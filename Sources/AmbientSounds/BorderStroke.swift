import SwiftUI

// MARK: - BorderStroke
//
// SwiftUI animated border stroke effect.
// A glowing comet that continuously rides the border of a rounded shape.
// Uses a fixed-stop AngularGradient that only rotates — no stop clamping,
// so there's zero discontinuity / size-jump at any position.
// Zero external dependencies.

struct BorderStroke<Content: View>: View {

    // MARK: – Config

    /// Must match the child view's corner radius.
    var borderRadius: CGFloat = 9
    /// Border stroke width.
    var lineWidth: CGFloat = 2.0
    /// Glow intensity (0 = off, 1 = full).
    var strength: CGFloat = 0.85
    /// Seconds per full revolution.
    var duration: Double = 18
    /// Bright leading-edge colour of the animated stroke.
    var strokeColor: Color = .white
    /// Fading tail colour — pair with the artwork accent for best results.
    var trailColor: Color = .clear
    /// Freeze / hide the animated stroke when false.
    var active: Bool = true

    @ViewBuilder var content: () -> Content

    // MARK: – Body

    var body: some View {
        content()
            .overlay {
                if active {
                    TimelineView(.animation) { timeline in
                        strokeOverlay(date: timeline.date)
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                }
            }
    }

    // MARK: – Stroke layer

    @ViewBuilder
    private func strokeOverlay(date: Date) -> some View {
        let seconds  = date.timeIntervalSinceReferenceDate
        let progress = CGFloat(seconds.truncatingRemainder(dividingBy: duration) / duration)

        // Slow blink: sine wave with period 3.5 s, ±6 % swing → opacity 0.88 – 1.00
        let blinkPeriod = 3.5
        let blinkRaw    = sin(seconds * (2 * .pi) / blinkPeriod)  // −1 … +1
        let blink       = CGFloat(0.94 + blinkRaw * 0.06)         // 0.88 … 1.00

        ZStack {
            // ── Soft outer glow ────────────────────────────────────────
            RoundedRectangle(cornerRadius: borderRadius)
                .stroke(gradient(progress: progress, glowOnly: true),
                        lineWidth: lineWidth * 4)
                .blur(radius: 5)
                .opacity(Double(strength) * 0.65 * Double(blink))

            // ── Sharp stroke line ─────────────────────────────────────
            RoundedRectangle(cornerRadius: borderRadius)
                .stroke(gradient(progress: progress, glowOnly: false),
                        lineWidth: lineWidth)
                .opacity(Double(strength) * Double(blink))
        }
        .allowsHitTesting(false)
    }

    // MARK: – Gradient
    //
    // Key insight: gradient STOPS are fixed (0…1), only the rotation angles
    // advance with progress. This means there are NO clamped stop positions
    // and zero jump/shrink at any point in the revolution.
    //
    // location 1.0 always = head (bright tip)   → sits at endAngle
    // location 0.0       = start of transparent → sits at startAngle
    // The gradient sweeps exactly 360°, so startAngle = endAngle − 360°.

    private func gradient(progress: CGFloat, glowOnly: Bool) -> AngularGradient {
        // Tail covers this fraction of the full circle (0.45 = 45% ≈ 162°)
        let tailFraction = 0.45

        let tipOpacity   = glowOnly ? 0.55 : 1.0
        let trailOpacity = glowOnly ? 0.25 : 0.55

        let stops = Gradient(stops: [
            // ── Transparent majority (behind the tail) ────────────────
            .init(color: .clear,                                   location: 0.00),
            .init(color: .clear,                                   location: 1 - tailFraction),
            // ── Tail fades in from trailColor ─────────────────────────
            .init(color: trailColor.opacity(0),                    location: 1 - tailFraction),
            .init(color: trailColor.opacity(trailOpacity * 0.6),   location: 1 - tailFraction * 0.55),
            .init(color: trailColor.opacity(trailOpacity),         location: 1 - tailFraction * 0.18),
            // ── Bright head ───────────────────────────────────────────
            .init(color: strokeColor.opacity(tipOpacity * 0.85),   location: 0.97),
            .init(color: strokeColor.opacity(tipOpacity),          location: 1.00),
        ])

        // Head angle: progress 0 → top (−90°), advances clockwise
        let headDeg = Double(progress) * 360.0 - 90.0

        return AngularGradient(
            gradient: stops,
            center: .center,
            startAngle: .degrees(headDeg - 360), // location 0.0 — one full turn behind
            endAngle:   .degrees(headDeg)         // location 1.0 — the bright head
        )
    }
}

// MARK: - Convenience modifier

extension View {
    /// Wraps the view with an animated border stroke glow.
    func borderStroke(
        borderRadius: CGFloat = 9,
        lineWidth: CGFloat = 2.0,
        strength: CGFloat = 0.85,
        duration: Double = 12,
        color: Color = .white,
        trailColor: Color = .clear,
        active: Bool = true
    ) -> some View {
        BorderStroke(
            borderRadius: borderRadius,
            lineWidth: lineWidth,
            strength: strength,
            duration: duration,
            strokeColor: color,
            trailColor: trailColor,
            active: active
        ) { self }
    }
}
