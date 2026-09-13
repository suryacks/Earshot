import AppKit
import EarshotKit

/// Handles `earshot://` URLs.
///
/// This is the Shortcuts integration. A proper App Intents extension needs an
/// Xcode appex target, which a Swift Package cannot produce - but a URL scheme
/// works from Shortcuts' "Open URL" action, from AppleScript, from the shell,
/// and from other apps, with no extension at all.
///
///   earshot://dashboard
///   earshot://connect?name=AirPods
///   earshot://disconnect?name=AirPods
///   earshot://toggle?name=AirPods
///   earshot://output?name=MacBook%20Pro%20Speakers
///   earshot://input?name=Shure
///   earshot://inputlock?on=1
@MainActor
final class URLSchemeHandler: NSObject {
    private weak var model: AppModel?
    var onShowDashboard: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handle(event:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handle(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string)
        else { return }
        perform(url)
    }

    func perform(_ url: URL) {
        guard url.scheme?.lowercased() == "earshot", let model else { return }
        let action = (url.host ?? "").lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let name = items.first { $0.name == "name" }?.value
        let on = items.first { $0.name == "on" }?.value

        switch action {
        case "dashboard", "show":
            onShowDashboard?()

        case "connect", "disconnect", "toggle":
            guard let name, let device = model.devices.first(where: {
                $0.name.localizedCaseInsensitiveContains(name) && $0.address != nil
            }), let address = device.address else { return }
            switch action {
            case "connect": BluetoothControl.connect(address: address)
            case "disconnect": BluetoothControl.disconnect(address: address)
            default: BluetoothControl.toggle(address: address)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                model.refreshDevices(); model.refreshAudio()
            }

        case "output":
            guard let name, let d = AudioRouter.find(name, input: false) else { return }
            model.setOutput(d)

        case "input":
            guard let name, let d = AudioRouter.find(name, input: true) else { return }
            model.setInput(d)

        case "inputlock":
            // Absent `on` means toggle, which is the friendlier default for a
            // Shortcut bound to a key.
            let enable = on.map { ["1", "true", "yes", "on"].contains($0.lowercased()) }
                ?? !Settings.shared.inputLockEnabled
            Settings.shared.inputLockEnabled = enable
            model.applyInputLockSetting()

        default:
            break
        }
    }
}
