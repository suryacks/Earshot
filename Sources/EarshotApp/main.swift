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
    private var cancellables = Set<AnyCancellable>()
    private var urlHandler: URLSchemeHandler?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Notifier.shared.requestAuthorization()

        menuBar = MenuBarController(model: model)
        model.onLidOpened = { [weak self] device in
            self?.hud.show(device: device)
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
