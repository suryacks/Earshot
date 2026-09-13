import SwiftUI
import EarshotKit

/// What the island is currently showing.
///
/// Ordered by how much room each needs, because the morph between them is the
/// whole effect: the shape is one continuous object that grows and shrinks,
/// never a window that appears.
enum NotchState: Equatable {
    /// Invisible, exactly the size of the physical notch.
    case idle
    /// A one-line announcement: connected, disconnected, route changed.
    case toast(NotchToast)
    /// The lid-open card: artwork plus per-cell battery, like the phone does.
    case device(DeviceState)
    /// Hovered: fully interactive.
    case expanded

    var size: CGSize {
        switch self {
        case .idle: return .zero                       // resolved from geometry
        case .toast: return CGSize(width: 320, height: 46)
        case .device: return CGSize(width: 340, height: 132)
        case .expanded: return CGSize(width: 468, height: 196)
        }
    }
}

struct NotchToast: Equatable {
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color = .white
    var device: DeviceState?
}

/// The island.
struct NotchView: View {
    @ObservedObject var model: AppModel
    let geometry: NotchGeometry
    let state: NotchState
    var onHover: (Bool) -> Void
    var onTap: () -> Void

    private var size: CGSize {
        state == .idle ? geometry.notchSize : state.size
    }

    /// On a notched Mac the top corners stay square so the island reads as the
    /// notch growing. On other Macs it is a free-floating pill.
    private var topRadius: CGFloat { geometry.hasNotch ? 0 : bottomRadius }

    private var bottomRadius: CGFloat {
        switch state {
        case .idle: return geometry.hasNotch ? 10 : 14
        case .toast: return 22
        case .device: return 28
        case .expanded: return 30
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                shape
                    .fill(Theme.islandFill)
                    .overlay(shape.strokeBorder(Theme.islandStroke, lineWidth: 0.7))
                    .shadow(color: state == .idle ? .clear : Theme.islandShadow,
                            radius: state == .idle ? 0 : 22, y: 10)

                content
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .clipped()
            }
            .frame(width: size.width, height: size.height)
            .contentShape(shape)
            .onHover { onHover($0) }
            .onTapGesture { onTap() }
            .animation(Theme.morph, value: size)
            .animation(Theme.morph, value: bottomRadius)

            Spacer(minLength: 0)
        }
        .padding(.top, geometry.topOffset)
        .frame(width: geometry.windowSize.width,
               height: geometry.windowSize.height,
               alignment: .top)
    }

    private var horizontalPadding: CGFloat {
        switch state {
        case .idle: return 0
        case .toast: return 16
        case .device: return 18
        case .expanded: return 20
        }
    }

    private var verticalPadding: CGFloat {
        switch state {
        case .idle, .toast: return 0
        case .device: return 14
        case .expanded: return 16
        }
    }

    private var shape: some InsettableShape {
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            Color.clear
        case .toast(let toast):
            ToastContent(toast: toast)
                .transition(.island)
        case .device(let device):
            NotchDeviceCard(device: device, model: model)
                .transition(.island)
        case .expanded:
            ExpandedContent(model: model)
                .transition(.island)
        }
    }

    /// Rect of the island inside the window, for click-through hit testing.
    var islandRect: CGRect {
        CGRect(x: (geometry.windowSize.width - size.width) / 2,
               y: geometry.topOffset,
               width: size.width,
               height: size.height)
    }
}

private extension AnyTransition {
    /// Content fades and settles rather than sliding, so it looks like it was
    /// revealed by the shape growing instead of animating independently.
    static var island: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                .animation(Theme.content.delay(0.04)),
            removal: .opacity.animation(.easeOut(duration: 0.12)))
    }
}

// MARK: - Lid-open card

/// The card the phone shows when you open a case: artwork on the left, a
/// battery gauge per cell on the right.
private struct NotchDeviceCard: View {
    let device: DeviceState
    @ObservedObject var model: AppModel
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                DeviceArt.view(for: device, size: 52, tint: .white)
                    .scaleEffect(appeared ? 1 : 0.82)
                    .opacity(appeared ? 1 : 0)
                    .animation(Theme.morph.delay(0.06), value: appeared)
                if device.caseBattery != nil {
                    CaseArt(size: 26, tint: .white.opacity(0.85), lit: device.caseCharging)
                        .opacity(appeared ? 1 : 0)
                        .animation(Theme.content.delay(0.12), value: appeared)
                }
            }
            .frame(width: 62)

            VStack(alignment: .leading, spacing: 10) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 14) {
                    if let single = device.single {
                        BatteryPill(level: single, charging: device.isCharging,
                                    width: 68, onDark: true)
                    } else {
                        if device.left != nil {
                            BatteryPill(level: device.left, charging: device.leftCharging,
                                        label: "L", width: 44)
                        }
                        if device.right != nil {
                            BatteryPill(level: device.right, charging: device.rightCharging,
                                        label: "R", width: 44)
                        }
                        if device.caseBattery != nil {
                            BatteryPill(level: device.caseBattery, charging: device.caseCharging,
                                        label: "Case", width: 44)
                        }
                    }
                }

                if !device.isConnected, device.address != nil {
                    Button {
                        model.toggleConnection(device)
                    } label: {
                        Text("Connect")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(PressableButtonStyle())
                } else if device.isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.battery(100))
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Toast

private struct ToastContent: View {
    let toast: NotchToast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(toast.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                if let subtitle = toast.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            if let d = toast.device {
                HStack(spacing: 8) {
                    if let s = d.single {
                        BatteryPill(level: s, charging: d.isCharging, width: 34)
                    } else {
                        if let l = d.left { BatteryPill(level: l, charging: d.leftCharging, label: "L", width: 28) }
                        if let r = d.right { BatteryPill(level: r, charging: d.rightCharging, label: "R", width: 28) }
                    }
                }
            }
        }
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    @ObservedObject var model: AppModel

    private var devices: [DeviceState] {
        // Only the user's own devices. The island is not a place to advertise
        // whatever is broadcasting in the room.
        model.devices.filter { $0.isPaired && ($0.minimumBattery != nil || $0.isConnected) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Devices")
                if devices.isEmpty {
                    Text("Nothing connected")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 2)
                } else {
                    ForEach(devices.prefix(3)) { device in
                        NotchDeviceRow(device: device, model: model)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Now Playing")
                NotchNowPlaying(model: model)
                Spacer(minLength: 0)
            }
            .frame(width: 176, alignment: .leading)
        }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.35))
    }
}

private struct NotchDeviceRow: View {
    let device: DeviceState
    @ObservedObject var model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            DeviceArt.view(for: device, size: 22, tint: .white.opacity(0.9))

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white).lineLimit(1)
                if device.isCompanionReport {
                    Text("via Shortcut")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.32))
                } else if device.batteryFromAdvert {
                    Text("nearby")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.32))
                }
            }
            Spacer(minLength: 4)

            HStack(spacing: 7) {
                if let s = device.single {
                    BatteryPill(level: s, charging: device.isCharging, width: 30)
                } else {
                    if let l = device.left { BatteryPill(level: l, charging: device.leftCharging, label: "L", width: 24) }
                    if let r = device.right { BatteryPill(level: r, charging: device.rightCharging, label: "R", width: 24) }
                    if let c = device.caseBattery { BatteryPill(level: c, charging: device.caseCharging, label: "C", width: 24) }
                }
            }

            if device.address != nil {
                Button { model.toggleConnection(device) } label: {
                    Image(systemName: device.isConnected ? "xmark.circle.fill" : "link.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.3))
                }
                .buttonStyle(PressableButtonStyle())
                .help(device.isConnected ? "Disconnect" : "Connect")
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 7)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(hovering ? 0.07 : 0)))
        .onHover { hovering = $0 }
        .animation(Theme.quick, value: hovering)
    }
}

private struct NotchNowPlaying: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let info = model.nowPlaying {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Artwork(url: info.artworkURL, playing: info.isPlaying)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white).lineLimit(1)
                        if let artist = info.artist {
                            Text(artist)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                    }
                }
                HStack(spacing: 14) {
                    control("backward.fill", 12) { model.mediaCommand(.previous) }
                    control(info.isPlaying ? "pause.fill" : "play.fill", 15) { model.mediaCommand(.playPause) }
                    control("forward.fill", 12) { model.mediaCommand(.next) }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            Text("Nothing playing")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                .padding(.top, 2)
        }
    }

    private func control(_ symbol: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private struct Artwork: View {
    let url: URL?
    let playing: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.1))
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "music.note")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: 42, height: 42)
        .scaleEffect(playing ? 1 : 0.93)
        .shadow(color: .black.opacity(0.4), radius: playing ? 6 : 2, y: 2)
        .animation(Theme.morph, value: playing)
    }
}
