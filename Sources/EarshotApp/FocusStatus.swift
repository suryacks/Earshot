import Foundation
import Intents

/// Whether a Focus is currently active.
///
/// Used to suppress the island's sneak peeks and battery alerts while the user
/// has asked not to be interrupted. Authorization is requested once; if it is
/// refused the app behaves as though no Focus is active, which fails toward
/// showing information rather than silently swallowing it.
@MainActor
enum FocusStatus {
    private static var authorized = false

    static func requestAuthorization() {
        INFocusStatusCenter.default.requestAuthorization { status in
            Task { @MainActor in authorized = (status == .authorized) }
        }
    }

    static var isFocused: Bool {
        guard authorized else { return false }
        return INFocusStatusCenter.default.focusStatus.isFocused ?? false
    }

    /// True when an interruption is acceptable right now.
    static var mayInterrupt: Bool {
        guard Settings.shared.respectFocus else { return true }
        return !isFocused
    }
}
