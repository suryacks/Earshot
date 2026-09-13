import SwiftUI

/// One place for motion and colour, so every surface feels like the same object.
///
/// The springs matter more than the colours here. Apple's own island uses a
/// single, slightly under-damped spring for geometry and a faster, tighter one
/// for content; mixing timing curves across a morph is what makes a custom HUD
/// read as "not quite right" even when the layout is correct.
enum Theme {

    // MARK: - Motion

    /// Geometry: size, corner radius, position. Deliberately a touch bouncy.
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.74)
    /// Content appearing inside a shape that is already moving.
    static let content = Animation.spring(response: 0.28, dampingFraction: 0.86)
    /// Small state flips: hover, button presses.
    static let quick = Animation.spring(response: 0.22, dampingFraction: 0.9)
    /// Battery values, which should glide rather than snap.
    static let value = Animation.spring(response: 0.55, dampingFraction: 0.85)

    // MARK: - Colour

    static func battery(_ level: Int?, charging: Bool = false) -> Color {
        if charging { return Color(red: 0.28, green: 0.85, blue: 0.42) }
        guard let level else { return Color.white.opacity(0.28) }
        switch level {
        case ..<15: return Color(red: 1.0, green: 0.27, blue: 0.27)
        case ..<30: return Color(red: 1.0, green: 0.62, blue: 0.14)
        default: return Color(red: 0.30, green: 0.86, blue: 0.46)
        }
    }

    /// Rings read as flat at a small size with a single fill; a slight sweep
    /// gives them dimension without looking decorative.
    static func batteryGradient(_ level: Int?, charging: Bool = false) -> AngularGradient {
        let base = battery(level, charging: charging)
        return AngularGradient(
            colors: [base.opacity(0.75), base, base.opacity(0.95)],
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270))
    }

    // MARK: - Surfaces

    /// The island's fill. A flat black reads as a hole punched in the screen;
    /// the faint vertical lift makes it read as a surface sitting on top.
    static var islandFill: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.09), Color(white: 0.03)],
            startPoint: .top, endPoint: .bottom)
    }

    static var islandStroke: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
            startPoint: .top, endPoint: .bottom)
    }

    static let islandShadow = Color.black.opacity(0.5)
}

/// Scales and dims while pressed. AppKit buttons give no feedback inside a
/// custom HUD, which makes the island feel dead until you notice something
/// changed elsewhere.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// A soft glow behind charging indicators.
struct GlowModifier: ViewModifier {
    let color: Color
    var radius: CGFloat = 6
    var active: Bool = true

    func body(content: Content) -> some View {
        content
            .shadow(color: active ? color.opacity(0.55) : .clear, radius: radius)
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 6, active: Bool = true) -> some View {
        modifier(GlowModifier(color: color, radius: radius, active: active))
    }
}
