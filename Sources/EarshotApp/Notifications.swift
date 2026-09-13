import Foundation
import UserNotifications
import EarshotKit

/// Low-battery alerts.
///
/// Alerts latch: one notification per device per discharge cycle. Without this,
/// a device hovering at the threshold would notify on every poll, which is the
/// fastest way to get an app muted permanently.
@MainActor
final class Notifier {
    static let shared = Notifier()
    private var alerted = Set<String>()
    private var authorized = false

    private init() {}

    func requestAuthorization() {
        // Only a bundled, signed app can post notifications; in a raw CLI run
        // this fails harmlessly and alerts are simply skipped.
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                Task { @MainActor in self.authorized = granted }
            }
    }

    func evaluate(_ devices: [DeviceState]) {
        guard Settings.shared.lowBatteryAlerts else { return }
        let threshold = Settings.shared.lowBatteryThreshold

        for d in devices where d.isPaired {
            guard let level = d.minimumBattery else { continue }

            // Clear the latch once charging or comfortably above the threshold,
            // so the next real drain can alert again.
            if d.isCharging || level >= threshold + 10 {
                alerted.remove(d.id)
                continue
            }
            guard level <= threshold, !alerted.contains(d.id) else { continue }
            alerted.insert(d.id)
            post(title: "\(d.name) is at \(level)%",
                 body: d.caseBattery.map { "Case is at \($0)%." } ?? "Time to charge.")
        }
    }

    func post(title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
