import Foundation

/// A decoded Apple proximity-pairing advertisement (manufacturer message `0x07`).
///
/// Only the first nine payload bytes are plaintext; the remainder is encrypted
/// and deliberately ignored. Layout and confidence notes: `docs/PROTOCOL.md`.
public struct ProximityMessage: Sendable, Equatable {
    public let model: DeviceModel
    /// Battery of the bud physically in the left ear, 0...100. `nil` = not reported.
    public let leftBattery: Int?
    public let rightBattery: Int?
    public let caseBattery: Int?
    /// Devices with one cell (AirPods Max, most Beats) report here, and leave
    /// `leftBattery`/`rightBattery`/`caseBattery` nil.
    public let single: Int?
    public let leftCharging: Bool
    public let rightCharging: Bool
    public let caseCharging: Bool
    public let leftInEar: Bool
    public let rightInEar: Bool
    /// Increments each time the lid opens. Drives the HUD trigger.
    public let lidCounter: Int
    public let lidOpen: Bool
    /// True when both buds sit in a closed case, so the pair reads as one unit.
    public let bothInCase: Bool
    public let rawStatus: UInt8
    public let rawPayload: Data

    public static let appleCompanyID: UInt16 = 0x004C
    public static let messageType: UInt8 = 0x07

    /// Battery nibbles encode tens of a percent; `0x0F` means "not reported".
    /// A missing reading must stay `nil` — rendering it as 0% would tell the
    /// user their buds are dead when they simply aren't broadcasting.
    static func battery(_ nibble: UInt8) -> Int? {
        nibble <= 10 ? Int(nibble) * 10 : nil
    }

    /// Parses raw `CBAdvertisementDataManufacturerDataKey` bytes.
    /// Returns `nil` for anything that is not an Apple `0x07` message.
    public static func parse(manufacturerData data: Data) -> ProximityMessage? {
        let b = [UInt8](data)
        // company id (2, little-endian) + type + length
        guard b.count >= 4 else { return nil }
        let company = UInt16(b[0]) | (UInt16(b[1]) << 8)
        guard company == appleCompanyID, b[2] == messageType else { return nil }

        let declared = Int(b[3])
        let payload = Array(b.dropFirst(4))
        // Trust the shorter of declared/actual so a truncated frame can't over-read.
        let usable = min(declared, payload.count)
        // Both observed variants (25- and 17-byte) share this 9-byte prefix.
        guard usable >= 9 else { return nil }
        let p = Array(payload.prefix(usable))

        let modelID = UInt16(p[1]) | (UInt16(p[2]) << 8)
        let msgModel = DeviceModel.lookup(modelID)
        let status = p[3]
        let batteryByte = p[4]
        let caseByte = p[5]
        let lidByte = p[6]

        // Bit 0x02 of status indicates which physical bud is broadcasting, which
        // decides whether the high nibble is the left or the right bud. It flips
        // when you wear a single bud, so the labels swap without this check.
        let flipped = (status & 0x02) == 0
        let hi = ProximityMessage.battery(batteryByte >> 4)
        let lo = ProximityMessage.battery(batteryByte & 0x0F)
        var left = flipped ? hi : lo
        var right = flipped ? lo : hi
        var single: Int? = nil

        // Single-cell devices still populate the two nibbles, but only one of
        // them is real - reporting both produced nonsense like "L 0% R 100%".
        // The low nibble is the live one; the high nibble reads 0 and would
        // otherwise render as a flat battery.
        if msgModel.isSingleBattery {
            single = lo ?? hi
            left = nil
            right = nil
        }

        let charge = caseByte >> 4
        let leftCharging = (charge & 0b0001) != 0
        let rightCharging = (charge & 0b0010) != 0
        let caseCharging = (charge & 0b0100) != 0

        let inEarPrimary = (status & 0x08) != 0
        let inEarSecondary = (status & 0x04) != 0
        let leftInEar = flipped ? inEarPrimary : inEarSecondary
        let rightInEar = flipped ? inEarSecondary : inEarPrimary

        return ProximityMessage(
            model: msgModel,
            leftBattery: left,
            rightBattery: right,
            // A device with no case must never claim a case level.
            caseBattery: msgModel.hasCase ? ProximityMessage.battery(caseByte & 0x0F) : nil,
            single: single,
            leftCharging: leftCharging,
            rightCharging: rightCharging,
            caseCharging: caseCharging,
            leftInEar: leftInEar,
            rightInEar: rightInEar,
            lidCounter: Int(lidByte & 0x0F),
            lidOpen: (lidByte & 0x08) == 0,
            bothInCase: (status & 0x04) == 0 && (status & 0x08) == 0,
            rawStatus: status,
            rawPayload: Data(p)
        )
    }

    /// Convenience for tests and fixtures: parse a hex string of the full
    /// manufacturer payload *including* the `4C 00` company id.
    public static func parse(hex: String) -> ProximityMessage? {
        guard let d = Data(hexString: hex) else { return nil }
        return parse(manufacturerData: d)
    }
}

extension Data {
    public init?(hexString: String) {
        let s = hexString.filter { !$0.isWhitespace }
        guard s.count % 2 == 0 else { return nil }
        var out = Data(capacity: s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let byte = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(byte)
            i = j
        }
        self = out
    }

    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
