import Foundation

/// One audio device as Earshot understands it, merged from every source.
public struct DeviceState: Sendable, Identifiable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case headphones, keyboard, mouse, trackpad, gamepad, phone, other
    }

    /// Stable across launches: the Bluetooth address when we know it,
    /// otherwise the BLE peripheral identifier for this session.
    public var id: String
    public var name: String
    public var address: String?
    public var productID: UInt16?
    public var kind: Kind = .other
    public var isConnected: Bool = false
    public var isPaired: Bool = false

    public var left: Int?
    public var right: Int?
    public var caseBattery: Int?
    /// Devices with one cell (AirPods Max, Magic Mouse) report here instead.
    public var single: Int?

    public var leftCharging = false
    public var rightCharging = false
    public var caseCharging = false
    public var leftInEar = false
    public var rightInEar = false

    public var rssi: Int?
    public var lastSeen: Date = .distantPast
    public var firmware: String?
    public var serial: String?
    /// True when battery came from a BLE advert rather than a live connection.
    public var batteryFromAdvert = false

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// Lowest cell, which is what actually decides when the device dies.
    public var minimumBattery: Int? {
        [left, right, single].compactMap { $0 }.min()
    }

    public var isCharging: Bool { leftCharging || rightCharging || caseCharging }

    public var displayBattery: String {
        if let s = single { return "\(s)%" }
        let l = left.map { "\($0)%" } ?? "—"
        let r = right.map { "\($0)%" } ?? "—"
        if left == nil && right == nil { return "—" }
        return left == right ? l : "\(l) / \(r)"
    }
}
