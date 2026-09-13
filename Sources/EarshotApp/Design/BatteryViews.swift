import SwiftUI
import EarshotKit

/// A circular battery gauge.
struct BatteryRing: View {
    let level: Int?
    var charging: Bool = false
    var label: String?
    var size: CGFloat = 46
    var lineWidth: CGFloat?
    var onDark: Bool = false

    private var stroke: CGFloat { lineWidth ?? size * 0.105 }
    private var tint: Color { Theme.battery(level, charging: charging) }

    var body: some View {
        VStack(spacing: size * 0.11) {
            ZStack {
                Circle()
                    .stroke(onDark ? Color.white.opacity(0.13) : Color.primary.opacity(0.12),
                            lineWidth: stroke)

                if let level {
                    Circle()
                        .trim(from: 0, to: max(0.008, CGFloat(level) / 100))
                        .stroke(Theme.batteryGradient(level, charging: charging),
                                style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .glow(tint, radius: size * 0.14, active: charging)
                        .animation(Theme.value, value: level)
                }

                Group {
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: size * 0.30, weight: .bold))
                            .foregroundStyle(tint)
                    } else if let level {
                        Text("\(level)")
                            .font(.system(size: size * 0.30, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(onDark ? .white : .primary)
                            .animation(Theme.value, value: level)
                    } else {
                        // Never "0%": unknown and empty are different facts.
                        Text("—")
                            .font(.system(size: size * 0.30, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
            .frame(width: size, height: size)

            if let label {
                Text(label)
                    .font(.system(size: max(8, size * 0.20), weight: .medium))
                    .foregroundStyle(onDark ? Color.white.opacity(0.45) : Color.secondary)
            }
        }
    }
}

/// A horizontal capsule gauge, for tighter rows.
struct BatteryPill: View {
    let level: Int?
    var charging: Bool = false
    var label: String?
    var width: CGFloat = 46
    var onDark: Bool = true

    private var tint: Color { Theme.battery(level, charging: charging) }

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(onDark ? Color.white.opacity(0.12) : Color.primary.opacity(0.10))
                if let level {
                    Capsule()
                        .fill(Theme.battery(level, charging: charging))
                        .frame(width: max(4, width * CGFloat(level) / 100))
                        .glow(tint, radius: 4, active: charging)
                        .animation(Theme.value, value: level)
                }
            }
            .frame(width: width, height: 5)

            HStack(spacing: 2) {
                if let label {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(onDark ? Color.white.opacity(0.4) : Color.secondary)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(tint)
                }
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(onDark ? .white : .primary)
                    .animation(Theme.value, value: level)
            }
        }
    }
}

/// Left / right / case, or a single cell, depending on the device.
struct DeviceBatteries: View {
    let device: DeviceState
    var ringSize: CGFloat = 46
    var onDark: Bool = false

    var body: some View {
        HStack(spacing: ringSize * 0.30) {
            if let single = device.single {
                BatteryRing(level: single, charging: device.isCharging,
                            size: ringSize, onDark: onDark)
            } else if device.left == nil && device.right == nil && device.caseBattery == nil {
                BatteryRing(level: nil, label: "no data", size: ringSize, onDark: onDark)
            } else {
                if device.left != nil || device.right != nil {
                    BatteryRing(level: device.left, charging: device.leftCharging,
                                label: "Left", size: ringSize, onDark: onDark)
                    BatteryRing(level: device.right, charging: device.rightCharging,
                                label: "Right", size: ringSize, onDark: onDark)
                }
                if let c = device.caseBattery {
                    BatteryRing(level: c, charging: device.caseCharging,
                                label: "Case", size: ringSize, onDark: onDark)
                }
            }
        }
    }
}

extension DeviceState {
    var sfSymbol: String {
        switch kind {
        case .headphones:
            if let pid = productID, DeviceModel.lookup(pid).isSingleBattery { return "headphones" }
            return "airpodspro"
        case .keyboard: return "keyboard"
        case .mouse: return "magicmouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .gamepad: return "gamecontroller"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .watch: return "applewatch"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}
