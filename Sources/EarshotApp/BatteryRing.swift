import SwiftUI
import EarshotKit

/// Shared battery visual. One implementation so the HUD, dashboard and menu
/// never disagree about what "low" looks like.
struct BatteryRing: View {
    let level: Int?
    let charging: Bool
    var label: String?
    var size: CGFloat = 46

    private var color: Color {
        guard let level else { return .secondary }
        if charging { return .green }
        switch level {
        case ..<20: return .red
        case ..<40: return .orange
        default: return .green
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: size * 0.11)
                if let level {
                    Circle()
                        .trim(from: 0, to: CGFloat(level) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.35), value: level)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundStyle(.green)
                } else if let level {
                    Text("\(level)")
                        .font(.system(size: size * 0.3, weight: .medium, design: .rounded))
                        .monospacedDigit()
                } else {
                    // An em dash, never "0%": unknown and empty are different
                    // facts and must not look the same.
                    Text("—").font(.system(size: size * 0.3)).foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)

            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The battery cluster for one device: either one ring, or left/right/case.
struct DeviceBatteries: View {
    let device: DeviceState
    var ringSize: CGFloat = 46

    var body: some View {
        HStack(spacing: 14) {
            if let single = device.single {
                BatteryRing(level: single, charging: device.isCharging, size: ringSize)
            } else if device.left == nil && device.right == nil && device.caseBattery == nil {
                BatteryRing(level: nil, charging: false, label: "no data", size: ringSize)
            } else {
                if device.left != nil || device.right != nil {
                    BatteryRing(level: device.left, charging: device.leftCharging,
                                label: "Left", size: ringSize)
                    BatteryRing(level: device.right, charging: device.rightCharging,
                                label: "Right", size: ringSize)
                }
                if let c = device.caseBattery {
                    BatteryRing(level: c, charging: device.caseCharging,
                                label: "Case", size: ringSize)
                }
            }
        }
    }
}

extension DeviceState {
    var sfSymbol: String {
        switch kind {
        case .headphones:
            if let pid = productID, DeviceModel.lookup(pid).isSingleBattery {
                return "headphones"
            }
            return "airpodspro"
        case .keyboard: return "keyboard"
        case .mouse: return "magicmouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .gamepad: return "gamecontroller"
        case .phone: return "iphone"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}
