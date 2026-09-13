import Foundation
import EarshotKit

enum Format {
    static var useColor = isatty(fileno(stdout)) == 1

    static func c(_ s: String, _ code: String) -> String {
        useColor ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s
    }
    static func bold(_ s: String) -> String { c(s, "1") }
    static func dim(_ s: String) -> String { c(s, "2") }

    static func batteryColor(_ pct: Int) -> String {
        switch pct {
        case ..<20: return "31"   // red
        case ..<40: return "33"   // yellow
        default: return "32"      // green
        }
    }

    static func bar(_ pct: Int, width: Int = 10) -> String {
        let filled = max(0, min(width, Int((Double(pct) / 100.0 * Double(width)).rounded())))
        let s = String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
        return c(s, batteryColor(pct))
    }

    static func level(_ v: Int?) -> String {
        guard let v else { return dim("  —") }
        return c(String(format: "%3d%%", v), batteryColor(v))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// RSSI is roughly -30 (touching) to -100 (far). Mapped to 0...100.
    static func proximity(_ rssi: Int) -> Int {
        let clamped = max(-100, min(-30, rssi))
        return Int(Double(clamped + 100) / 70.0 * 100.0)
    }

    static func deviceLine(_ d: DeviceState) -> String {
        var parts: [String] = []
        let dot = d.isConnected ? c("●", "32") : dim("○")
        parts.append("\(dot) \(bold(d.name))")

        var levels: [String] = []
        if let s = d.single { levels.append("\(bar(s)) \(level(s))") }
        if let l = d.left { levels.append("L \(level(l))") }
        if let r = d.right { levels.append("R \(level(r))") }
        if let cs = d.caseBattery { levels.append("case \(level(cs))") }
        if levels.isEmpty { levels.append(dim("no battery data")) }
        parts.append(levels.joined(separator: "  "))

        var flags: [String] = []
        if d.isCharging { flags.append(c("⚡︎charging", "33")) }
        if d.batteryFromAdvert { flags.append(dim("via BLE")) }
        if !d.isPaired { flags.append(dim("unpaired")) }
        if let r = d.rssi { flags.append(dim("\(r) dBm")) }
        if !flags.isEmpty { parts.append(flags.joined(separator: " ")) }

        return parts.joined(separator: "   ")
    }
}
