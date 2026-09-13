import Foundation

/// Reads connected-device battery from `system_profiler SPBluetoothDataType`.
///
/// This is the authoritative source while a device is connected: it reports
/// per-side levels with explicit left/right labels, so it never suffers the
/// bud-swap ambiguity that BLE adverts have. It costs 200-500 ms per call,
/// so it is polled slowly and never on the main thread.
public enum SystemProfiler {

    public static func snapshot() -> [DeviceState] {
        guard let data = run() else { return [] }
        return parse(json: data)
    }

    static func run() -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        // Read before waiting: a full pipe buffer would deadlock the child.
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return out.isEmpty ? nil : out
    }

    /// Levels arrive as strings like `"86%"`.
    static func percent(_ any: Any?) -> Int? {
        guard let s = any as? String else { return nil }
        let digits = s.trimmingCharacters(in: CharacterSet(charactersIn: "% "))
        guard let v = Int(digits), (0...100).contains(v) else { return nil }
        return v
    }

    static func hex16(_ any: Any?) -> UInt16? {
        guard var s = any as? String else { return nil }
        s = s.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        return UInt16(s, radix: 16)
    }

    static func kind(from minorType: String?, productID: UInt16?) -> DeviceState.Kind {
        switch (minorType ?? "").lowercased() {
        case let s where s.contains("headphone"): return .headphones
        case let s where s.contains("keyboard"): return .keyboard
        case let s where s.contains("mouse"): return .mouse
        case let s where s.contains("trackpad"): return .trackpad
        case let s where s.contains("gamepad"), let s where s.contains("joystick"): return .gamepad
        case let s where s.contains("phone"): return .phone
        default: return productID != nil ? .headphones : .other
        }
    }

    static func parse(json: Data) -> [DeviceState] {
        guard
            let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let list = root["SPBluetoothDataType"] as? [[String: Any]],
            let top = list.first
        else { return [] }

        var out: [DeviceState] = []
        for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
            guard let entries = top[key] as? [[String: Any]] else { continue }
            for entry in entries {
                for (name, raw) in entry {
                    guard let f = raw as? [String: Any] else { continue }
                    out.append(device(name: name, fields: f, connected: connected))
                }
            }
        }
        return out
    }

    private static func device(name: String, fields f: [String: Any], connected: Bool) -> DeviceState {
        let address = f["device_address"] as? String
        var d = DeviceState(id: address ?? name, name: name)
        d.address = address
        d.isConnected = connected
        d.isPaired = true
        d.productID = hex16(f["device_productID"])
        d.left = percent(f["device_batteryLevelLeft"])
        d.right = percent(f["device_batteryLevelRight"])
        d.caseBattery = percent(f["device_batteryLevelCase"])
        d.single = percent(f["device_batteryLevelMain"]) ?? percent(f["device_batteryLevel"])
        d.firmware = f["device_firmwareVersion"] as? String
        d.serial = f["device_serialNumber"] as? String
        d.kind = kind(from: f["device_minorType"] as? String, productID: d.productID)
        if let r = f["device_rssi"] as? String, let v = Int(r) { d.rssi = v }
        if connected { d.lastSeen = Date() }
        return d
    }
}
