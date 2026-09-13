import SwiftUI
import EarshotKit

/// The popover shown from the menu bar.
struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let np = model.nowPlaying, Settings.shared.showNowPlaying {
                        NowPlayingRow(info: np)
                        Divider()
                    }
                    deviceSection
                    Divider()
                    AudioRoutingSection(model: model)
                }
                .padding(14)
            }
            .frame(maxHeight: 460)
            Divider()
            footer
        }
        .frame(width: 340)
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model, isPresented: $showingSettings)
        }
    }

    private var header: some View {
        HStack {
            Text("Earshot").font(.system(size: 13, weight: .semibold))
            Spacer()
            if model.bluetoothState == .unauthorized {
                Label("No Bluetooth access", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Grant Bluetooth permission in System Settings › Privacy & Security › Bluetooth.")
            } else if model.bluetoothState == .poweredOff {
                Label("Bluetooth off", systemImage: "bolt.horizontal.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { model.refreshDevices(); model.refreshAudio() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var paired: [DeviceState] { model.devices.filter(\.isPaired) }
    private var nearby: [DeviceState] {
        Settings.shared.showNearbyDevices ? model.devices.filter { !$0.isPaired } : []
    }
    private var hiddenNearbyCount: Int {
        Settings.shared.showNearbyDevices ? 0 : model.devices.filter { !$0.isPaired }.count
    }

    @ViewBuilder
    private var deviceSection: some View {
        if model.devices.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No devices yet").font(.system(size: 12, weight: .medium))
                Text(model.bluetoothState == .unauthorized
                     ? "Earshot needs Bluetooth permission to see your devices."
                     : "Open your AirPods case nearby and they will appear here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(paired) { device in
                DeviceRow(device: device, model: model)
            }
            if !nearby.isEmpty {
                Text("Nearby")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(nearby) { device in
                    DeviceRow(device: device, model: model)
                }
            } else if hiddenNearbyCount > 0 {
                Button {
                    Settings.shared.showNearbyDevices = true
                    model.objectWillChange.send()
                } label: {
                    Label("Show \(hiddenNearbyCount) nearby device\(hiddenNearbyCount == 1 ? "" : "s")",
                          systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { showingSettings = true }
                .buttonStyle(.borderless)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct DeviceRow: View {
    let device: DeviceState
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: device.sfSymbol).foregroundStyle(.secondary)
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if device.isConnected {
                    Text("Connected")
                        .font(.system(size: 10))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.green.opacity(0.18), in: Capsule())
                        .foregroundStyle(.green)
                }
                Spacer()
                if device.isPaired, device.address != nil {
                    Button(device.isConnected ? "Disconnect" : "Connect") {
                        model.toggleConnection(device)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
            }
            DeviceBatteries(device: device, ringSize: 40)
            if let eta = model.timeToEmpty(device), !device.isCharging {
                Text("≈\(formatted(eta)) remaining at the current drain rate")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if device.batteryFromAdvert {
                Text("Battery reported over Bluetooth LE")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds), h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

struct NowPlayingRow: View {
    let info: NowPlayingInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: info.isPlaying ? "waveform" : "pause.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let artist = info.artist {
                    Text(artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
    }
}

struct AudioRoutingSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio").font(.caption).foregroundStyle(.secondary)

            Picker("Output", selection: Binding(
                get: { model.defaultOutputID ?? 0 },
                set: { id in
                    if let d = model.outputs.first(where: { $0.id == id }) { model.setOutput(d) }
                })) {
                ForEach(model.outputs) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)

            Picker("Input", selection: Binding(
                get: { model.defaultInputID ?? 0 },
                set: { id in
                    if let d = model.inputs.first(where: { $0.id == id }) { model.setInput(d) }
                })) {
                ForEach(model.inputs) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)
            .disabled(model.inputLockActive)
            .help(model.inputLockActive
                  ? "Audio Input Lock is on. Turn it off in Settings to change the input."
                  : "")

            if model.inputLockActive {
                Label("Input locked", systemImage: "lock.fill")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
    }
}
