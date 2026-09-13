import AppKit
import SwiftUI
import EarshotKit

/// Headless smoke test: `Earshot --selftest`.
///
/// Exercises the real objects - status item, popover, HUD panel, registry,
/// CoreAudio - and reports what came back, then exits non-zero if anything
/// essential is missing. Exists because the menu bar cannot be asserted on
/// from a terminal, and "the process did not crash" is not the same as
/// "the app works".
@MainActor
enum SelfTest {
    static func run() -> Never {
        var failures: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("  \(ok ? "✅" : "❌") \(name)\(detail.isEmpty ? "" : ": \(detail)")")
            if !ok { failures.append(name) }
        }

        print("Earshot self-test\n")

        print("Menu bar")
        let model = AppModel()
        let menuBar = MenuBarController(model: model)
        let item = menuBar.debugStatusItem
        check("status item created", item != nil)
        check("status item has a button", item?.button != nil)
        check("button shows an icon", item?.button?.image != nil,
              item?.button?.image?.name() ?? "")

        print("\nPopover")
        check("popover has content", menuBar.debugPopover.contentViewController != nil)
        let hosted = menuBar.debugPopover.contentViewController?.view
        hosted?.layoutSubtreeIfNeeded()
        check("dashboard lays out", (hosted?.fittingSize.width ?? 0) > 0,
              "\(Int(hosted?.fittingSize.width ?? 0))×\(Int(hosted?.fittingSize.height ?? 0))")

        print("\nAudio (CoreAudio)")
        let outputs = AudioRouter.outputs()
        let inputs = AudioRouter.inputs()
        check("outputs found", !outputs.isEmpty, "\(outputs.count)")
        check("inputs found", !inputs.isEmpty, "\(inputs.count)")
        check("default output readable", AudioRouter.defaultOutput() != nil,
              AudioRouter.defaultOutput()?.name ?? "none")
        check("default input readable", AudioRouter.defaultInput() != nil,
              AudioRouter.defaultInput()?.name ?? "none")

        print("\nBluetooth (IOBluetooth)")
        let paired = BluetoothControl.pairedDevices()
        check("paired devices enumerated", !paired.isEmpty, "\(paired.count)")

        print("\nDevice registry (live, 6s scan)")
        model.start()
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        check("bluetooth authorized", model.bluetoothState != .unauthorized,
              String(describing: model.bluetoothState))
        check("devices discovered", !model.devices.isEmpty, "\(model.devices.count)")
        let withBattery = model.devices.filter { $0.minimumBattery != nil }
        check("battery data present", !withBattery.isEmpty, "\(withBattery.count) device(s)")
        for d in model.devices.prefix(6) {
            let src = d.batteryFromAdvert ? "BLE" : (d.isConnected ? "profiler" : "-")
            print("     • \(d.name) — \(d.displayBattery) [\(src)]")
        }

        print("\nHUD")
        if let device = model.primaryDevice ?? model.devices.first {
            let hud = HUDController()
            hud.show(device: device, for: 0.6)
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.4))
            check("HUD panel visible", hud.debugPanel?.isVisible == true)
            check("HUD has content", (hud.debugPanel?.contentView?.fittingSize.width ?? 0) > 0)
            hud.hide()
        } else {
            check("HUD", false, "no device to render")
        }

        print("\nNotch island")
        let notch = NotchController(model: model)
        notch.enable()
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.3))
        check("island window created", notch.isEnabled)
        if let device = model.primaryDevice ?? model.devices.first {
            notch.peek(NotchPeek(kind: .lidOpened, title: device.name, subtitle: "Self-test",
                                 device: device, symbol: "airpodspro"), for: 0.5)
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.4))
            check("sneak peek rendered", true)
        }
        if let geo = NotchGeometry.current() {
            check("screen geometry read", geo.notchSize.width > 0,
                  "\(geo.hasNotch ? "notch" : "no notch") \(Int(geo.notchSize.width))×\(Int(geo.notchSize.height))")
        }
        notch.disable()

        print("\nCompanion devices (iPhone/iPad/Watch)")
        let mobileStore = MobileDeviceStore()
        check("drop folder present", mobileStore.directoryExists, mobileStore.directoryPath)
        let reports = mobileStore.read()
        check("companion reports readable", true, "\(reports.count) report(s)")
        for r in reports { print("     • \(r.name) — \(r.displayBattery)") }

        print("\nNow Playing")
        let np = NowPlayingResolver().fetch()
        check("resolver ran", true, np.map { "\($0.summary) via \($0.app)" } ?? "nothing playing")
        check("artwork available", true, np?.artworkURL?.absoluteString ?? "none")

        model.stop()
        print("\n\(failures.isEmpty ? "All checks passed." : "FAILED: \(failures.joined(separator: ", "))")")
        exit(failures.isEmpty ? 0 : 1)
    }
}
