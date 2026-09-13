import SwiftUI
import ServiceManagement
import EarshotKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    @State private var showHUD = Settings.shared.showHUDOnLidOpen
    @State private var lowAlerts = Settings.shared.lowBatteryAlerts
    @State private var threshold = Double(Settings.shared.lowBatteryThreshold)
    @State private var menuPercent = Settings.shared.menuBarShowsPercent
    @State private var showNowPlaying = Settings.shared.showNowPlaying
    @State private var inputLock = Settings.shared.inputLockEnabled
    @State private var lockedUID = Settings.shared.inputLockUIDs.first ?? ""
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Earshot Settings").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group("General") {
                        Toggle("Show battery when the case opens", isOn: $showHUD)
                            .onChange(of: showHUD) { _, new in Settings.shared.showHUDOnLidOpen = new }
                        Toggle("Show percentage in the menu bar", isOn: $menuPercent)
                            .onChange(of: menuPercent) { _, new in
                                Settings.shared.menuBarShowsPercent = new
                                NotificationCenter.default.post(name: .earshotMenuBarStyleChanged, object: nil)
                            }
                        Toggle("Show Now Playing", isOn: $showNowPlaying)
                            .onChange(of: showNowPlaying) { _, new in
                                Settings.shared.showNowPlaying = new
                                model.refreshNowPlaying()
                            }
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, on in
                                do { try LoginItem.set(on) ; loginItemError = nil }
                                catch {
                                    loginItemError = error.localizedDescription
                                    launchAtLogin = LoginItem.isEnabled
                                }
                            }
                        if let loginItemError {
                            Text(loginItemError).font(.caption).foregroundStyle(.orange)
                        }
                    }

                    group("Battery alerts") {
                        Toggle("Warn me when a device runs low", isOn: $lowAlerts)
                            .onChange(of: lowAlerts) { _, new in Settings.shared.lowBatteryAlerts = new }
                        HStack {
                            Text("Threshold")
                            Slider(value: $threshold, in: 5...50, step: 5)
                                .onChange(of: threshold) { _, new in Settings.shared.lowBatteryThreshold = Int(new) }
                            Text("\(Int(threshold))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                        .disabled(!lowAlerts)
                    }

                    group("Audio Input Lock") {
                        Text("Stops macOS switching your microphone when a headset connects.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Keep my input device", isOn: $inputLock)
                            .onChange(of: inputLock) { _, new in
                                Settings.shared.inputLockEnabled = new
                                model.applyInputLockSetting()
                            }
                        Picker("Preferred input", selection: $lockedUID) {
                            Text("Current device").tag("")
                            ForEach(model.inputs) { Text($0.name).tag($0.uid) }
                        }
                        .disabled(!inputLock)
                        .onChange(of: lockedUID) { _, uid in
                            Settings.shared.inputLockUIDs = uid.isEmpty ? [] : [uid]
                            model.applyInputLockSetting()
                        }
                        if let blocked = model.lastBlockedInput {
                            Text("Last blocked: \(blocked)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    group("Bluetooth") {
                        LabeledContent("Status", value: statusText)
                        if model.bluetoothState == .unauthorized {
                            Text("Open System Settings › Privacy & Security › Bluetooth and enable Earshot, then relaunch.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 560)
    }

    private var statusText: String {
        switch model.bluetoothState {
        case .scanning: return "Scanning"
        case .unauthorized: return "Permission denied"
        case .poweredOff: return "Bluetooth is off"
        case .unsupported: return "Unsupported"
        case .idle: return "Idle"
        }
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}

extension Notification.Name {
    static let earshotMenuBarStyleChanged = Notification.Name("earshot.menuBarStyleChanged")
}

/// Launch at login via SMAppService.
///
/// Registration fails unless the app is signed and in a stable location, so
/// errors are surfaced to the user rather than silently swallowed - a toggle
/// that flips back with no explanation is worse than one that says why.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
