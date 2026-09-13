import Foundation

/// "When Zoom is frontmost, use the interface for input and AirPods for output."
///
/// Rules are matched against the frontmost app's bundle identifier. The app
/// target drives this from an NSWorkspace observer; the matching logic lives
/// here so it can be unit-tested without a running desktop.
public struct AppAudioRule: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var bundleID: String
    public var outputUID: String?
    public var inputUID: String?
    public var enabled: Bool = true

    public init(bundleID: String, outputUID: String? = nil, inputUID: String? = nil, enabled: Bool = true) {
        self.bundleID = bundleID
        self.outputUID = outputUID
        self.inputUID = inputUID
        self.enabled = enabled
    }
}

public struct AppAudioRuleSet: Codable, Sendable, Equatable {
    public var rules: [AppAudioRule] = []
    public init(rules: [AppAudioRule] = []) { self.rules = rules }

    public func rule(for bundleID: String) -> AppAudioRule? {
        rules.first { $0.enabled && $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
}

/// Applies rules as the frontmost app changes.
@MainActor
public final class AppAudioRuleEngine {
    public var ruleSet = AppAudioRuleSet()
    public var isEnabled = false
    /// Reports what was switched, for the HUD.
    public var onApplied: ((_ bundleID: String, _ output: String?, _ input: String?) -> Void)?

    private var lastAppliedBundleID: String?

    public init() {}

    /// Re-applying on every frontmost change would fight the user's manual
    /// choices, so a rule fires once per activation of that app.
    public func frontmostAppChanged(bundleID: String?) {
        guard isEnabled, let bundleID else { return }
        guard bundleID != lastAppliedBundleID else { return }
        guard let rule = ruleSet.rule(for: bundleID) else {
            lastAppliedBundleID = nil
            return
        }
        lastAppliedBundleID = bundleID

        var outName: String?
        var inName: String?
        if let uid = rule.outputUID, let d = AudioRouter.outputs().first(where: { $0.uid == uid }) {
            if AudioRouter.setDefaultOutput(d) { outName = d.name }
        }
        if let uid = rule.inputUID, let d = AudioRouter.inputs().first(where: { $0.uid == uid }) {
            if AudioRouter.setDefaultInput(d) { inName = d.name }
        }
        if outName != nil || inName != nil { onApplied?(bundleID, outName, inName) }
    }
}
