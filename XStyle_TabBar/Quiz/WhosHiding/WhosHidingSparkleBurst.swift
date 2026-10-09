import SwiftUI

/// A ring of sparkles that bursts out from the animal when it's named,
/// then fades. Invisible at rest, so it can stay in place between bursts.
struct WhosHidingSparkleBurst: View {
    /// Bursts each time this changes.
    let trigger: Bool
    let tint: Color
    /// How far the sparkles fly from the center.
    let radius: Double

    private let count = 8

    var body: some View {
        KeyframeAnimator(initialValue: 0.0, trigger: trigger) { progress in
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "star.fill")
                        .font(index.isMultiple(of: 2) ? .title : .headline)
                        .foregroundStyle(index.isMultiple(of: 2) ? tint : .yellow)
                        .scaleEffect(0.4 + 0.8 * progress)
                        .offset(y: -radius * (0.35 + 0.65 * progress))
                        .rotationEffect(.degrees(360 / Double(count) * Double(index)))
                        // Fades in and back out over the burst.
                        .opacity(sin(progress * .pi))
                }
            }
        } keyframes: { _ in
            CubicKeyframe(1, duration: 0.9)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
