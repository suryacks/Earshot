import Foundation
import CoreAudio

public struct AudioDevice: Sendable, Identifiable, Equatable, Codable {
    public let id: UInt32
    public let uid: String
    public let name: String
    public let hasOutput: Bool
    public let hasInput: Bool
    public let transport: String
}

/// Audio device enumeration and default-device switching via public CoreAudio.
public enum AudioRouter {

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func dataSize(_ obj: AudioObjectID, _ addr: inout AudioObjectPropertyAddress) -> UInt32 {
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr else { return 0 }
        return size
    }

    /// CoreAudio hands back a +1 CFString here, so it is taken as retained.
    /// Binding through `Unmanaged` avoids forming a raw pointer to an object
    /// reference, which is undefined behaviour.
    static func string(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &ref) { ptr -> OSStatus in
            AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }

    static func channelCount(_ obj: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        let size = dataSize(obj, &addr)
        guard size > 0 else { return 0 }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buf.deallocate() }
        var s = size
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &s, buf) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(buf.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    public static func devices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        let size = dataSize(AudioObjectID(kAudioObjectSystemObject), &addr)
        guard size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        var s = size
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &s, &ids) == noErr
        else { return [] }

        return ids.compactMap { id in
            guard let name = string(id, kAudioObjectPropertyName) else { return nil }
            var t: UInt32 = 0
            var ta = address(kAudioDevicePropertyTransportType)
            var ts = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(id, &ta, 0, nil, &ts, &t)
            let transport = withUnsafeBytes(of: t.bigEndian) {
                String(bytes: $0, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "?"
            }
            return AudioDevice(
                id: id,
                uid: string(id, kAudioDevicePropertyDeviceUID) ?? "",
                name: name,
                hasOutput: channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
                hasInput: channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0,
                transport: transport
            )
        }
    }

    public static func outputs() -> [AudioDevice] { devices().filter(\.hasOutput) }
    public static func inputs() -> [AudioDevice] { devices().filter(\.hasInput) }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDevice? {
        var addr = address(selector)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr
        else { return nil }
        return devices().first { $0.id == id }
    }

    public static func defaultOutput() -> AudioDevice? { defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) }
    public static func defaultInput() -> AudioDevice? { defaultDevice(kAudioHardwarePropertyDefaultInputDevice) }

    @discardableResult
    private static func setDefault(_ selector: AudioObjectPropertySelector, _ id: AudioDeviceID) -> Bool {
        var addr = address(selector)
        var value = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &value) == noErr
    }

    @discardableResult
    public static func setDefaultOutput(_ d: AudioDevice) -> Bool {
        setDefault(kAudioHardwarePropertyDefaultOutputDevice, d.id)
    }

    @discardableResult
    public static func setDefaultInput(_ d: AudioDevice) -> Bool {
        setDefault(kAudioHardwarePropertyDefaultInputDevice, d.id)
    }

    /// Exact name match first so "MacBook Pro Microphone" cannot be shadowed
    /// by a substring hit on another device.
    public static func find(_ query: String, input: Bool) -> AudioDevice? {
        let pool = input ? inputs() : outputs()
        let q = query.lowercased()
        return pool.first { $0.name.lowercased() == q }
            ?? pool.first { $0.uid.lowercased() == q }
            ?? pool.first { $0.name.lowercased().contains(q) }
    }
}
