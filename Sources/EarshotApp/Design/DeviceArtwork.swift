import SwiftUI
import EarshotKit

/// Original vector artwork for the device types Earshot knows about.
///
/// Drawn rather than shipped as images: Apple's product renders are
/// copyrighted, and an open-source app cannot redistribute them. These are
/// deliberately stylised silhouettes - recognisable at 24pt, not pretending to
/// be photographs.
enum DeviceArt {

    @ViewBuilder
    static func view(for device: DeviceState, size: CGFloat, tint: Color = .white) -> some View {
        let model = device.productID.map { DeviceModel.lookup($0) }

        switch device.kind {
        case .headphones where model?.isSingleBattery == true:
            OverEarArt(size: size, tint: tint)
        case .headphones:
            BudsPairArt(size: size, tint: tint, isPro: isProStyle(model))
        case .phone:
            SlabArt(size: size, tint: tint, aspect: 0.48, cornerScale: 0.16)
        case .tablet:
            SlabArt(size: size, tint: tint, aspect: 0.72, cornerScale: 0.10)
        case .watch:
            WatchArt(size: size, tint: tint)
        case .keyboard, .mouse, .trackpad, .gamepad, .other:
            Image(systemName: device.sfSymbol)
                .font(.system(size: size * 0.62, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }

    /// Pro-style buds have a short, wide stem; the original AirPods have a
    /// long thin one. Everything from AirPods Pro onward uses the short stem.
    private static func isProStyle(_ model: DeviceModel?) -> Bool {
        guard let id = model?.id else { return true }
        return !(id == 0x2002 || id == 0x200F)
    }
}

/// One earbud, stem down.
struct BudArt: View {
    var size: CGFloat
    var tint: Color = .white
    var isPro: Bool = true
    /// Mirrors the stem so a pair leans away from centre, as a real pair does.
    var flipped: Bool = false

    var body: some View {
        let w = size
        let h = size * 1.55
        let bulbH = h * (isPro ? 0.50 : 0.44)
        let stemW = w * (isPro ? 0.40 : 0.26)
        let stemH = h - bulbH * 0.62

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: stemW * 0.5, style: .continuous)
                .fill(tint)
                .frame(width: stemW, height: stemH)
                .offset(x: w * (isPro ? 0.10 : 0.06) * (flipped ? -1 : 1),
                        y: bulbH * 0.58)

            Ellipse()
                .fill(tint)
                .frame(width: w, height: bulbH)
        }
        .frame(width: w, height: h)
        .scaleEffect(x: flipped ? -1 : 1, y: 1)
    }
}

/// A pair of buds, angled slightly apart.
struct BudsPairArt: View {
    var size: CGFloat
    var tint: Color = .white
    var isPro: Bool = true

    var body: some View {
        let bud = size * 0.40
        HStack(spacing: size * 0.06) {
            BudArt(size: bud, tint: tint, isPro: isPro, flipped: true)
                .rotationEffect(.degrees(-8))
            BudArt(size: bud, tint: tint, isPro: isPro)
                .rotationEffect(.degrees(8))
        }
        .frame(width: size, height: size)
    }
}

/// A charging case: rounded, wider than tall, with a seam and status light.
struct CaseArt: View {
    var size: CGFloat
    var tint: Color = .white
    var lit: Bool = false

    var body: some View {
        let w = size * 0.86
        let h = size * 0.70

        ZStack {
            RoundedRectangle(cornerRadius: h * 0.34, style: .continuous)
                .fill(tint)
                .frame(width: w, height: h)

            // Lid seam, punched out so it reads on any background.
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(width: w * 0.78, height: max(0.7, size * 0.028))
                .offset(y: -h * 0.16)

            Circle()
                .fill(lit ? Theme.battery(nil, charging: true) : Color.black.opacity(0.45))
                .frame(width: size * 0.09, height: size * 0.09)
                .offset(y: h * 0.20)
                .glow(Theme.battery(nil, charging: true), radius: 4, active: lit)
        }
        .frame(width: size, height: size)
    }
}

/// Over-ear headphones: headband plus two cups.
struct OverEarArt: View {
    var size: CGFloat
    var tint: Color = .white

    var body: some View {
        let s = size
        ZStack {
            // Headband: an arc, not a full ring.
            Circle()
                .trim(from: 0.56, to: 0.94)
                .stroke(tint, style: StrokeStyle(lineWidth: s * 0.10, lineCap: .round))
                .frame(width: s * 0.74, height: s * 0.74)
                .offset(y: -s * 0.02)

            HStack(spacing: s * 0.44) {
                cup(s)
                cup(s)
            }
            .offset(y: s * 0.16)
        }
        .frame(width: s, height: s)
    }

    private func cup(_ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: s * 0.09, style: .continuous)
            .fill(tint)
            .frame(width: s * 0.20, height: s * 0.30)
    }
}

/// iPhone / iPad silhouette.
struct SlabArt: View {
    var size: CGFloat
    var tint: Color = .white
    var aspect: CGFloat
    var cornerScale: CGFloat

    var body: some View {
        let h = size * 0.82
        let w = h * aspect
        RoundedRectangle(cornerRadius: w * cornerScale, style: .continuous)
            .stroke(tint, lineWidth: max(1, size * 0.055))
            .frame(width: w, height: h)
            .overlay(
                Capsule()
                    .fill(tint)
                    .frame(width: w * 0.30, height: max(1, size * 0.035))
                    .offset(y: -h * 0.40)
            )
            .frame(width: size, height: size)
    }
}

struct WatchArt: View {
    var size: CGFloat
    var tint: Color = .white

    var body: some View {
        let h = size * 0.50
        let w = h * 0.82
        ZStack {
            // Band, behind the case.
            Capsule()
                .fill(tint.opacity(0.45))
                .frame(width: w * 0.62, height: size * 0.80)
            RoundedRectangle(cornerRadius: w * 0.30, style: .continuous)
                .fill(tint)
                .frame(width: w, height: h)
        }
        .frame(width: size, height: size)
    }
}
