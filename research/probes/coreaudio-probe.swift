// coreaudio-probe.swift — lists audio devices; checks default in/out are settable.
// Build: swiftc -O coreaudio-probe.swift -o coreaudio-probe && ./coreaudio-probe
// 'settable: true' on input is what makes Audio Input Lock possible.

import CoreAudio
import Foundation
var size: UInt32 = 0
var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
let n = Int(size) / MemoryLayout<AudioDeviceID>.size
var ids = [AudioDeviceID](repeating: 0, count: n)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
print("CoreAudio devices: \(n)")
for id in ids {
    var nameRef: CFString = "" as CFString
    var s = UInt32(MemoryLayout<CFString>.size)
    var na = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(id, &na, 0, nil, &s, &nameRef)
    var ts: UInt32 = 0
    var ta = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var tsz = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &ta, 0, nil, &tsz, &ts)
    let t = withUnsafeBytes(of: ts.bigEndian) { String(bytes: $0, encoding: .ascii) ?? "?" }
    print("  [\(id)] \(nameRef as String)  transport=\(t)")
}
// can we WRITE the default output device?
var da = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var settable: DarwinBoolean = false
AudioObjectIsPropertySettable(AudioObjectID(kAudioObjectSystemObject), &da, &settable)
print("default OUTPUT device settable: \(settable.boolValue)  <- audio routing")
var ia = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
AudioObjectIsPropertySettable(AudioObjectID(kAudioObjectSystemObject), &ia, &settable)
print("default INPUT  device settable: \(settable.boolValue)  <- Audio Input Lock")
