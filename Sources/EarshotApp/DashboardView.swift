import SwiftUI
import EarshotKit

/// The menu bar popover.
struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var showingSettings = false
    @State private var showNearby = Settings.shared.showNearbyDevices

    private var paired: [DeviceState] { model.devices.filter(\.isPaired) }
    private var nearby: [DeviceState] { model.devices.filter { !$0.isPaired } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let np = model.nowPlaying, Settings.shared.showNowPlaying {
                        NowPlayingCard(info: np, model: model)
                    }

                    if model.devices.isEmpty {
                        EmptyStateView(state: model.bluetoothState)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(paired) { DeviceCard(device: $0, model: model) }
                        }

                        if showNearby, !nearby.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader("Nearby", trailing: "not yours")
                                ForEach(nearby) { DeviceCard(device: $0, model: model) }
                            }
                        } else if !nearby.isEmpty {
                            Button {
                                withAnimation(Theme.morph) {
                                    showNearby = true
                                    Settings.shared.showNearbyDevices = true
                                }
                            } label: {
                                Label("\(nearby.count) nearby device\(nearby.count == 1 ? "" : "s")",
                                      systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }

                    AudioCard(model: model)
                }
                .padding(14)
            }
            .frame(maxHeight: 480)

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 348)
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model, isPresented: $showingSettings)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Earshot")
                .font(.system(size: 13, weight: .semibold))

            if model.bluetoothState == .unauthorized {
                Label("No Bluetooth access", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .help("Grant Bluetooth permission in System Settings › Privacy & Security › Bluetooth.")
            } else if model.bluetoothState == .poweredOff {
                Label("Bluetooth off", systemImage: "bolt.horizontal.circle")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(Theme.quick) { model.refreshDevices(); model.refreshAudio() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(PressableButtonStyle())
            .help("Refresh now")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { showingSettings = true }
                .buttonStyle(.borderless)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}

private struct SectionHeader: View {
    let title: String
    var trailing: String?
    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(0.6)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 9))
            }
        }
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Device

struct DeviceCard: View {
    let device: DeviceState
    @ObservedObject var model: AppModel
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DeviceArt.view(for: device, size: 28, tint: .primary.opacity(0.85))

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    HStack(spacing: 5) {
                        if device.isConnected {
                            StatusChip(text: "Connected", color: Theme.battery(100))
                        }
                        if device.isCompanionReport {
                            Text("via Shortcut").font(.system(size: 9)).foregroundStyle(.tertiary)
                        } else if device.batteryFromAdvert {
                            Text("over the air").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)

                if device.isPaired, device.address != nil {
                    Button(device.isConnected ? "Disconnect" : "Connect") {
                        model.toggleConnection(device)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                    .opacity(hovering ? 1 : 0.55)
                }
            }

            DeviceBatteries(device: device, ringSize: 42)
                .padding(.leading, 2)

            if let eta = model.timeToEmpty(device), !device.isCharging {
                Label("≈\(formatted(eta)) left at this rate", systemImage: "clock")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(Theme.quick, value: hovering)
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds), h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

private struct StatusChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }
}

// MARK: - Now Playing

private struct NowPlayingCard: View {
    let info: NowPlayingInfo
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                if let url = info.artworkURL {
                    AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                        placeholder: { Image(systemName: "music.note").foregroundStyle(.secondary) }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let artist = info.artist {
                    Text(artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                mediaButton("backward.fill", 11) { model.mediaCommand(.previous) }
                mediaButton(info.isPlaying ? "pause.fill" : "play.fill", 14) { model.mediaCommand(.playPause) }
                mediaButton("forward.fill", 11) { model.mediaCommand(.next) }
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.04)))
    }

    private func mediaButton(_ symbol: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size))
                .frame(width: 22, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(.primary)
    }
}

// MARK: - Audio

private struct AudioCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader("Audio")

            row(icon: "speaker.wave.2.fill", label: "Output",
                selection: Binding(
                    get: { model.defaultOutputID ?? 0 },
                    set: { id in
                        if let d = model.outputs.first(where: { $0.id == id }) { model.setOutput(d) }
                    }),
                options: model.outputs, disabled: false)

            row(icon: model.inputLockActive ? "lock.fill" : "mic.fill", label: "Input",
                selection: Binding(
                    get: { model.defaultInputID ?? 0 },
                    set: { id in
                        if let d = model.inputs.first(where: { $0.id == id }) { model.setInput(d) }
                    }),
                options: model.inputs, disabled: model.inputLockActive)

            if model.inputLockActive {
                Label("Input locked — change it in Settings", systemImage: "lock.fill")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    private func row(icon: String, label: String,
                     selection: Binding<UInt32>, options: [AudioDevice],
                     disabled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
            Picker(label, selection: selection) {
                ForEach(options) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(disabled)
        }
        .font(.system(size: 12))
    }
}

private struct EmptyStateView: View {
    let state: BLEScanner.State

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: state == .unauthorized ? "lock.shield" : "airpodspro")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(state == .unauthorized ? "Bluetooth permission needed" : "No devices yet")
                .font(.system(size: 12, weight: .medium))
            Text(state == .unauthorized
                 ? "Enable Earshot under System Settings › Privacy & Security › Bluetooth, then relaunch."
                 : "Open your AirPods case nearby and they'll appear here.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
