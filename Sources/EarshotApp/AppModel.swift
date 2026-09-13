import SwiftUI
import AppKit
import EarshotKit

/// Observable state for every view in the app.
///
/// Holds the one `DeviceRegistry` instance; views never touch Bluetooth or
/// CoreAudio directly, so there is a single place where state can change.
@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [DeviceState] = []
    @Published var outputs: [AudioDevice] = []
    @Published var inputs: [AudioDevice] = []
    @Published var defaultOutputID: UInt32?
    @Published var defaultInputID: UInt32?
    @Published var nowPlaying: NowPlayingInfo?
    @Published var bluetoothState: BLEScanner.State = .idle
    @Published var inputLockActive = false
    @Published var lastBlockedInput: String?

    let store = BatteryStore()
    private lazy var registry = DeviceRegistry(store: store)
    private let inputLock = AudioInputLock()
    private let ruleEngine = AppAudioRuleEngine()
    private let nowPlayingResolver = NowPlayingResolver()
    private var audioTimer: Timer?
    private var nowPlayingTimer: Timer?

    var onLidOpened: ((DeviceState) -> Void)?
    var onDeviceConnected: ((DeviceState) -> Void)?
    var onDeviceDisconnected: ((DeviceState) -> Void)?
    /// Previous connection state per device, for detecting transitions.
    private var connectionState: [String: Bool] = [:]
    private var seededConnectionState = false

    func start() {
        registry.onChange = { [weak self] devices in
            guard let self else { return }
            self.devices = devices
            self.detectConnectionChanges(devices)
            Notifier.shared.evaluate(devices)
        }
        registry.onScannerStateChange = { [weak self] state in
            self?.bluetoothState = state
        }
        registry.onLidOpened = { [weak self] device in
            guard Settings.shared.showHUDOnLidOpen else { return }
            self?.onLidOpened?(device)
        }
        registry.start(pollInterval: 20)

        refreshAudio()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAudio() }
        }

        refreshNowPlaying()
        nowPlayingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNowPlaying() }
        }

        inputLock.onBlocked = { [weak self] attempted, restored in
            self?.lastBlockedInput = attempted
            Notifier.shared.post(title: "Audio Input Lock",
                                 body: "Blocked a switch to \(attempted). Still using \(restored).")
        }
        applyInputLockSetting()

        ruleEngine.ruleSet = Settings.shared.appRules
        ruleEngine.isEnabled = Settings.shared.appRulesEnabled
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.ruleEngine.frontmostAppChanged(bundleID: app?.bundleIdentifier)
            }
        }

        store?.prune()
        store?.purgeUnpairedDevices()
    }

    func stop() {
        audioTimer?.invalidate()
        nowPlayingTimer?.invalidate()
        registry.stop()
    }

    /// Emits connect/disconnect events by diffing against the last snapshot.
    ///
    /// The first snapshot only seeds the baseline: without that, every device
    /// already connected at launch would fire a "connected" animation.
    private func detectConnectionChanges(_ devices: [DeviceState]) {
        defer {
            connectionState = Dictionary(devices.map { ($0.id, $0.isConnected) },
                                         uniquingKeysWith: { a, _ in a })
            seededConnectionState = true
        }
        guard seededConnectionState else { return }
        for d in devices where d.isPaired {
            guard let was = connectionState[d.id], was != d.isConnected else { continue }
            if d.isConnected { onDeviceConnected?(d) } else { onDeviceDisconnected?(d) }
        }
    }

    func refreshDevices() { registry.refreshProfiled() }

    var companionDirectory: String { registry.companionDirectory }
    var companionConfigured: Bool { registry.companionConfigured }
    @discardableResult
    func createCompanionDirectory() -> Bool { registry.createCompanionDirectory() }

    func refreshAudio() {
        outputs = AudioRouter.outputs()
        inputs = AudioRouter.inputs()
        defaultOutputID = AudioRouter.defaultOutput()?.id
        defaultInputID = AudioRouter.defaultInput()?.id
    }

    func mediaCommand(_ command: MediaControl.Command) {
        guard MediaControl.send(command, using: nowPlayingResolver) else { return }
        // Give the player a beat to settle before re-reading, or the UI shows
        // the pre-command state and looks unresponsive.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    func refreshNowPlaying() {
        guard Settings.shared.showNowPlaying else { nowPlaying = nil; return }
        nowPlaying = nowPlayingResolver.fetch()
    }

    // MARK: - Actions

    func toggleConnection(_ device: DeviceState) {
        guard let address = device.address else { return }
        BluetoothControl.toggle(address: address)
        // The stack takes a moment to settle; re-read rather than guess.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refreshDevices()
            self?.refreshAudio()
        }
    }

    func setOutput(_ device: AudioDevice) {
        AudioRouter.setDefaultOutput(device)
        refreshAudio()
    }

    func setInput(_ device: AudioDevice) {
        AudioRouter.setDefaultInput(device)
        refreshAudio()
    }

    func applyInputLockSetting() {
        let settings = Settings.shared
        guard settings.inputLockEnabled else {
            inputLock.disable()
            inputLockActive = false
            return
        }
        let preferred = settings.inputLockUIDs.compactMap { uid in
            AudioRouter.inputs().first { $0.uid == uid }
        }
        // With nothing chosen, lock to whatever is current: that is what the
        // user was using when they switched the feature on.
        let targets = preferred.isEmpty ? [AudioRouter.defaultInput()].compactMap { $0 } : preferred
        guard !targets.isEmpty else {
            inputLockActive = false
            return
        }
        if preferred.isEmpty { settings.inputLockUIDs = targets.map(\.uid) }
        inputLock.enable(preferred: targets)
        inputLockActive = true
    }

    func setAppRules(_ set: AppAudioRuleSet) {
        Settings.shared.appRules = set
        ruleEngine.ruleSet = set
    }

    func setAppRulesEnabled(_ on: Bool) {
        Settings.shared.appRulesEnabled = on
        ruleEngine.isEnabled = on
    }

    var primaryDevice: DeviceState? {
        devices.first { $0.isConnected && $0.kind == .headphones }
            ?? devices.first { $0.isConnected }
            ?? devices.first { $0.isPaired && $0.minimumBattery != nil }
    }

    func timeToEmpty(_ device: DeviceState) -> TimeInterval? {
        store?.timeToEmpty(deviceID: device.id)
    }
}
