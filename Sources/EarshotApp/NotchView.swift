import SwiftUI
import EarshotKit

enum NotchState: Equatable {
    case idle
    case peek(NotchPeek)
    case expanded
}

/// A brief message the island slides out to show, then retracts.
struct NotchPeek: Equatable {
    enum Kind: Equatable { case lidOpened, connected, disconnected, lowBattery, audioRoute }
    var kind: Kind
    var title: String
    var subtitle: String?
    var device: DeviceState?
    var symbol: String
}

/// The island. Renders all three states and animates between them.
struct NotchView: View {
    @ObservedObject var model: AppModel
    let geometry: NotchGeometry
    let state: NotchState
    var onHover: (Bool) -> Void
    var onCollapse: () -> Void

    // One spring for every transition, so the island always feels like the
    // same physical object rather than several different animations.
    private var spring: Animation { .spring(response: 0.38, dampingFraction: 0.78) }

    private var size: CGSize {
        switch state {
        case .idle: return geometry.notchSize
        case .peek: return NotchGeometry.peekSize
        case .expanded: return NotchGeometry.expandedSize
        }
    }

    /// Square off the top corners on a notched Mac so the island reads as an
    /// extension of the notch instead of a floating pill.
    private var topRadius: CGFloat { geometry.hasNotch ? 0 : 14 }
    private var bottomRadius: CGFloat {
        switch state {
        case .idle: return geometry.hasNotch ? 10 : 14
        case .peek: return 18
        case .expanded: return 24
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                shape
                    .fill(.black)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(state == .idle ? 0 : 0.45),
                            radius: state == .idle ? 0 : 18, y: 8)

                content
                    .padding(.horizontal, state == .expanded ? 18 : 12)
                    .padding(.vertical, state == .expanded ? 14 : 0)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            // Scoped to the island, not the transparent window around it, or
            // the whole top of the screen would behave as a hover target.
            .onHover { onHover($0) }
            .animation(spring, value: size)
            .animation(spring, value: state)
            Spacer(minLength: 0)
        }
        .padding(.top, geometry.topOffset)
        .frame(width: geometry.windowSize.width,
               height: geometry.windowSize.height,
               alignment: .top)
    }

    /// The island's rect inside the window, used for click-through hit testing.
    var islandRect: CGRect {
        CGRect(x: (geometry.windowSize.width - size.width) / 2,
               y: geometry.topOffset,
               width: size.width,
               height: size.height)
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
        case .peek(let peek):
            PeekContent(peek: peek)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: -6)),
                    removal: .opacity))
        case .expanded:
            ExpandedContent(model: model, onCollapse: onCollapse)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }
}

private struct PeekContent: View {
    let peek: NotchPeek

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: peek.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 1) {
                Text(peek.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle = peek.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            if let device = peek.device {
                HStack(spacing: 6) {
                    if let single = device.single {
                        MiniBattery(level: single, charging: device.isCharging, label: nil)
                    } else {
                        if let l = device.left {
                            MiniBattery(level: l, charging: device.leftCharging, label: "L")
                        }
                        if let r = device.right {
                            MiniBattery(level: r, charging: device.rightCharging, label: "R")
                        }
                        if let c = device.caseBattery {
                            MiniBattery(level: c, charging: device.caseCharging, label: "C")
                        }
                    }
                }
            }
        }
    }
}

struct MiniBattery: View {
    let level: Int
    let charging: Bool
    let label: String?

    private var color: Color {
        if charging { return .green }
        switch level {
        case ..<20: return .red
        case ..<40: return .orange
        default: return .white
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
            }
            Text("\(level)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4), value: level)
        }
    }
}

private struct ExpandedContent: View {
    @ObservedObject var model: AppModel
    var onCollapse: () -> Void

    private var devices: [DeviceState] {
        // Only the user's own devices: the island is not a place to advertise
        // strangers' AirPods.
        model.devices.filter { $0.isPaired && ($0.minimumBattery != nil || $0.isConnected) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Devices")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))

                if devices.isEmpty {
                    Text("Nothing connected")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    ForEach(devices.prefix(3)) { device in
                        NotchDeviceRow(device: device, model: model)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 8) {
                Text("Now Playing")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                NotchNowPlaying(model: model)
                Spacer(minLength: 0)
            }
            .frame(width: 178, alignment: .leading)
        }
    }
}

private struct NotchDeviceRow: View {
    let device: DeviceState
    @ObservedObject var model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.sfSymbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if device.isCompanionReport {
                    Text("via Shortcut")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if let single = device.single {
                    MiniBattery(level: single, charging: device.isCharging, label: nil)
                } else {
                    if let l = device.left { MiniBattery(level: l, charging: device.leftCharging, label: "L") }
                    if let r = device.right { MiniBattery(level: r, charging: device.rightCharging, label: "R") }
                    if let c = device.caseBattery { MiniBattery(level: c, charging: device.caseCharging, label: "C") }
                }
            }

            if device.address != nil {
                Button {
                    model.toggleConnection(device)
                } label: {
                    Image(systemName: device.isConnected ? "xmark.circle.fill" : "link.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.35))
                }
                .buttonStyle(.plain)
                .help(device.isConnected ? "Disconnect" : "Connect")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(hovering ? 0.08 : 0))
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct NotchNowPlaying: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let info = model.nowPlaying {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ArtworkView(url: info.artworkURL, playing: info.isPlaying)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let artist = info.artist {
                            Text(artist)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                }
                HStack(spacing: 16) {
                    control("backward.fill") { model.mediaCommand(.previous) }
                    control(info.isPlaying ? "pause.fill" : "play.fill") { model.mediaCommand(.playPause) }
                    control("forward.fill") { model.mediaCommand(.next) }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            Text("Nothing playing")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func control(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ArtworkView: View {
    let url: URL?
    let playing: Bool
    @State private var spin = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.1))
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: 40, height: 40)
        .scaleEffect(playing ? 1.0 : 0.94)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: playing)
    }
}
