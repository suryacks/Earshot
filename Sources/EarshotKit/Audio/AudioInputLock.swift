import Foundation
import CoreAudio

/// Keeps the system input on a device you chose.
///
/// macOS switches the default input whenever a headset with a microphone
/// connects, which silently downgrades call quality. This watches the default
/// input property and puts it back when something else moves it.
///
/// Up to two preferred devices are supported: the second is a fallback for when
/// the first is unplugged, so unplugging an interface does not strand you.
/// Trampoline for the CoreAudio listener.
///
/// Lives at file scope rather than as a static member so `deinit` - which is
/// nonisolated - can still reference it to unregister. CoreAudio invokes this
/// on an arbitrary thread, so the work hops to the main actor where all state
/// lives.
private let earshotInputListenerProc: AudioObjectPropertyListenerProc = { _, _, _, context in
    guard let context else { return noErr }
    let lock = Unmanaged<AudioInputLock>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { MainActor.assumeIsolated { lock.handleDefaultInputChanged() } }
    return noErr
}

@MainActor
public final class AudioInputLock {

    public private(set) var isEnabled = false
    /// Preferred inputs by UID, highest priority first.
    public var preferredUIDs: [String] = []
    /// Called when a switch was blocked, so the UI can say so.
    public var onBlocked: ((_ attempted: String, _ restored: String) -> Void)?

    private var listening = false
    /// Guards against reacting to our own corrective write.
    private var suppressUntil = Date.distantPast

    public init() {}

    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    public func enable(preferred: [AudioDevice]) {
        preferredUIDs = preferred.map(\.uid).filter { !$0.isEmpty }
        guard !preferredUIDs.isEmpty else { return }
        isEnabled = true
        applyPreferred()
        startListening()
    }

    public func disable() {
        isEnabled = false
        stopListening()
    }

    private func startListening() {
        guard !listening else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &address, earshotInputListenerProc, ctx)
        listening = (status == noErr)
    }

    private func stopListening() {
        guard listening else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &address, earshotInputListenerProc, ctx)
        listening = false
    }

    deinit {
        // Listener holds an unretained pointer to self; it must not outlive us.
        if listening {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject), &addr,
                earshotInputListenerProc, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    /// First preferred device that is currently present.
    private func target() -> AudioDevice? {
        let available = AudioRouter.inputs()
        for uid in preferredUIDs {
            if let match = available.first(where: { $0.uid == uid }) { return match }
        }
        return nil
    }

    @discardableResult
    private func applyPreferred() -> Bool {
        guard let want = target() else { return false }
        guard let current = AudioRouter.defaultInput() else { return false }
        guard current.uid != want.uid else { return true }
        suppressUntil = Date().addingTimeInterval(0.5)
        return AudioRouter.setDefaultInput(want)
    }

    fileprivate func handleDefaultInputChanged() {
        guard isEnabled, Date() >= suppressUntil else { return }
        guard let want = target(), let current = AudioRouter.defaultInput() else { return }
        guard current.uid != want.uid else { return }
        let attempted = current.name
        if applyPreferred() { onBlocked?(attempted, want.name) }
    }
}
