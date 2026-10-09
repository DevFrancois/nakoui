import SwiftUI

/// A tile's two moves: a shake on each wrong guess, and on each solve a
/// hop, wag and squash that starts after `hopDelay`, so the tiles ripple
/// along the word. Both wait for the last tile to land. Reduce Motion
/// turns both off; the tiles' tint still shows the result.
struct WordWagTileMotion: ViewModifier {
    let wrongGuesses: Int
    let solves: Int
    let hopDelay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let delay = hopDelay

        content
            .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : wrongGuesses) { content, shake in
                content.offset(x: shake)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0, duration: WordWagMetrics.landingPause)
                    CubicKeyframe(-12, duration: 0.07)
                    CubicKeyframe(10, duration: 0.08)
                    CubicKeyframe(-7, duration: 0.08)
                    CubicKeyframe(4, duration: 0.07)
                    CubicKeyframe(0, duration: 0.07)
                }
            }
            .keyframeAnimator(initialValue: WordWagHop(), trigger: reduceMotion ? 0 : solves) { content, hop in
                content
                    .scaleEffect(hop.scale)
                    .rotationEffect(.degrees(hop.tilt))
                    .offset(y: hop.lift)
            } keyframes: { _ in
                KeyframeTrack(\.lift) {
                    LinearKeyframe(0, duration: delay)
                    SpringKeyframe(-20, duration: 0.18, spring: .snappy)
                    SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                }
                KeyframeTrack(\.tilt) {
                    LinearKeyframe(0, duration: delay)
                    CubicKeyframe(-9, duration: 0.1)
                    CubicKeyframe(9, duration: 0.14)
                    CubicKeyframe(-5, duration: 0.12)
                    CubicKeyframe(0, duration: 0.12)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: delay)
                    SpringKeyframe(1.12, duration: 0.18, spring: .snappy)
                    SpringKeyframe(1, duration: 0.45, spring: .bouncy)
                }
            }
    }
}

extension View {
    func wordWagTileMotion(wrongGuesses: Int, solves: Int, hopDelay: Double) -> some View {
        modifier(WordWagTileMotion(wrongGuesses: wrongGuesses, solves: solves, hopDelay: hopDelay))
    }
}
