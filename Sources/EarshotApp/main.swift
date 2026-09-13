import AppKit
import Combine
import SwiftUI
import EarshotKit

/// Earshot runs as a menu bar agent: no Dock icon, no main window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var menuBar: MenuBarController?
    private let hud = HUDController()
    private lazy var notch = NotchController(model: model)
    private var cancellables = Set<AnyCancellable>()
    private var urlHandler: URLSchemeHandler?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Notifier.shared.requestAuthorization()

        FocusStatus.requestAuthorization()

        menuBar = MenuBarController(model: model)

        if Settings.shared.notchEnabled { notch.enable() }

        model.onLidOpened = { [weak self] device in
            guard let self, FocusStatus.mayInterrupt else { return }
            // The island is the nicer surface when it is available; the
            // free-floating HUD is the fallback for when it is switched off.
            if self.notch.isEnabled {
                self.notch.peek(NotchPeek(kind: .lidOpened,
                                          title: device.name,
                                          subtitle: nil,
                                          device: device,
                                          symbol: "airpodspro"))
            } else {
                self.hud.show(device: device)
            }
        }

        model.onDeviceConnected = { [weak self] device in
            guard let self, FocusStatus.mayInterrupt else { return }
            self.notch.peek(NotchPeek(kind: .connected,
                                      title: device.name,
                                      subtitle: "Connected",
                                      device: device,
                                      symbol: "checkmark.circle.fill"))
        }

        model.onDeviceDisconnected = { [weak self] device in
            guard let self, FocusStatus.mayInterrupt else { return }
            self.notch.peek(NotchPeek(kind: .disconnected,
                                      title: device.name,
                                      subtitle: "Disconnected",
                                      device: nil,
                                      symbol: "xmark.circle.fill"),
                            for: 2.0)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.notch.screenChanged() }
        }

        NotificationCenter.default.addObserver(
            forName: .earshotNotchSettingChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Settings.shared.notchEnabled { self.notch.enable() }
                else { self.notch.disable() }
            }
        }

        // The menu bar title follows whichever device is primary.
        model.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in self?.menuBar?.update(devices: devices) }
            .store(in: &cancellables)

        urlHandler = URLSchemeHandler(model: model)
        urlHandler?.onShowDashboard = { [weak self] in self?.menuBar?.openPopover() }
        hotKey = GlobalHotKey { [weak self] in
            MainActor.assumeIsolated { self?.menuBar?.togglePopoverFromHotKey() }
        }

        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

// Top-level code runs on the main thread but is not implicitly main-actor
// isolated here, so the hop is made explicit.
MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--selftest") {
        // Needs a connection to the window server for status item and panel
        // creation, but must not show a Dock icon or steal focus.
        NSApplication.shared.setActivationPolicy(.accessory)
        SelfTest.run()
    }
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    // The delegate is referenced weakly by NSApplication; without this it would
    // be deallocated immediately and the app would launch with no menu bar item.
    objc_setAssociatedObject(app, "earshot.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
