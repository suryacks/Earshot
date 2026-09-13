import Foundation
import EarshotKit

/// User preferences, persisted in UserDefaults.
///
/// Defaults are chosen so a fresh install is useful and quiet: the HUD and
/// low-battery alerts are on, everything that changes system state (input
/// lock, per-app rules) is off until the user asks for it.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private enum Key {
        static let showHUD = "showHUDOnLidOpen"
        static let lowBatteryAlerts = "lowBatteryAlerts"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let menuBarShowsPercent = "menuBarShowsPercent"
        static let inputLockEnabled = "inputLockEnabled"
        static let inputLockUIDs = "inputLockUIDs"
        static let appRules = "appAudioRules"
        static let appRulesEnabled = "appAudioRulesEnabled"
        static let showNowPlaying = "showNowPlaying"
        static let showNearbyDevices = "showNearbyDevices"
        static let notchEnabled = "notchEnabled"
        static let notchSneakPeek = "notchSneakPeek"
        static let respectFocus = "respectFocus"
    }

    private init() {
        d.register(defaults: [
            Key.showHUD: true,
            Key.lowBatteryAlerts: true,
            Key.lowBatteryThreshold: 20,
            Key.menuBarShowsPercent: true,
            Key.inputLockEnabled: false,
            Key.appRulesEnabled: false,
            Key.showNowPlaying: true,
            // Off by default: a café full of strangers' AirPods is noise, not
            // information. Turn it on only when you want to connect to something.
            Key.showNearbyDevices: false,
            Key.notchEnabled: true,
            Key.notchSneakPeek: true,
            Key.respectFocus: true,
        ])
    }

    var showHUDOnLidOpen: Bool {
        get { d.bool(forKey: Key.showHUD) }
        set { d.set(newValue, forKey: Key.showHUD) }
    }
    var lowBatteryAlerts: Bool {
        get { d.bool(forKey: Key.lowBatteryAlerts) }
        set { d.set(newValue, forKey: Key.lowBatteryAlerts) }
    }
    /// Clamped: a threshold of 0 or 100 would either never fire or fire always.
    var lowBatteryThreshold: Int {
        get { min(50, max(5, d.integer(forKey: Key.lowBatteryThreshold))) }
        set { d.set(min(50, max(5, newValue)), forKey: Key.lowBatteryThreshold) }
    }
    var menuBarShowsPercent: Bool {
        get { d.bool(forKey: Key.menuBarShowsPercent) }
        set { d.set(newValue, forKey: Key.menuBarShowsPercent) }
    }
    var showNowPlaying: Bool {
        get { d.bool(forKey: Key.showNowPlaying) }
        set { d.set(newValue, forKey: Key.showNowPlaying) }
    }
    /// Whether to list Apple devices that are broadcasting nearby but are not
    /// paired with this Mac.
    var showNearbyDevices: Bool {
        get { d.bool(forKey: Key.showNearbyDevices) }
        set { d.set(newValue, forKey: Key.showNearbyDevices) }
    }
    var notchEnabled: Bool {
        get { d.bool(forKey: Key.notchEnabled) }
        set { d.set(newValue, forKey: Key.notchEnabled) }
    }
    var notchSneakPeek: Bool {
        get { d.bool(forKey: Key.notchSneakPeek) }
        set { d.set(newValue, forKey: Key.notchSneakPeek) }
    }
    var respectFocus: Bool {
        get { d.bool(forKey: Key.respectFocus) }
        set { d.set(newValue, forKey: Key.respectFocus) }
    }
    var inputLockEnabled: Bool {
        get { d.bool(forKey: Key.inputLockEnabled) }
        set { d.set(newValue, forKey: Key.inputLockEnabled) }
    }
    var inputLockUIDs: [String] {
        get { d.stringArray(forKey: Key.inputLockUIDs) ?? [] }
        set { d.set(Array(newValue.prefix(2)), forKey: Key.inputLockUIDs) }
    }
    var appRulesEnabled: Bool {
        get { d.bool(forKey: Key.appRulesEnabled) }
        set { d.set(newValue, forKey: Key.appRulesEnabled) }
    }
    var appRules: AppAudioRuleSet {
        get {
            guard let data = d.data(forKey: Key.appRules),
                  let set = try? JSONDecoder().decode(AppAudioRuleSet.self, from: data)
            else { return AppAudioRuleSet() }
            return set
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            d.set(data, forKey: Key.appRules)
        }
    }
}
