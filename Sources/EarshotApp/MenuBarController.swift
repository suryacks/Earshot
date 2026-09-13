import AppKit
import SwiftUI
import EarshotKit

/// The status item and its popover.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel
    private var eventMonitor: Any?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 420)
        popover.contentViewController = NSHostingController(rootView: DashboardView(model: model))

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.imagePosition = .imageLeading
        }
        render(nil)

        NotificationCenter.default.addObserver(
            forName: .earshotMenuBarStyleChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render(self?.model.primaryDevice) }
        }
    }

    /// Called whenever the device list changes.
    func update(devices: [DeviceState]) {
        render(model.primaryDevice)
    }

    private func render(_ device: DeviceState?) {
        guard let button = statusItem.button else { return }
        let symbol = device?.sfSymbol ?? "airpodspro"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Earshot")
        image?.isTemplate = true
        button.image = image

        if let level = device?.minimumBattery, Settings.shared.menuBarShowsPercent {
            button.title = " \(level)%"
            // Low battery is the one state worth breaking template colour for.
            let colour: NSColor = level <= Settings.shared.lowBatteryThreshold
                ? .systemRed : .labelColor
            button.attributedTitle = NSAttributedString(
                string: " \(level)%",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: colour,
                ])
        } else {
            button.title = ""
        }

        let name = device?.name ?? "Earshot"
        button.toolTip = device.map { "\($0.name) — \($0.displayBattery)" } ?? name
    }

    // Exposed for `--selftest`, which cannot inspect the menu bar from outside.
    var debugStatusItem: NSStatusItem? { statusItem }
    var debugPopover: NSPopover { popover }

    func openPopover() {
        guard !popover.isShown else { return }
        togglePopover()
    }

    func togglePopoverFromHotKey() {
        // A hot key can fire while another app is frontmost, so the app has to
        // come forward or the popover would appear behind it.
        NSApp.activate(ignoringOtherApps: true)
        togglePopover()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            model.refreshDevices()
            model.refreshAudio()
            model.refreshNowPlaying()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Without this the popover renders behind the frontmost app.
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
