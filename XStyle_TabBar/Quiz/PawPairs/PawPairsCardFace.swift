import SwiftUI

/// A card's glass and whichever side is showing, turned about its vertical
/// axis. It's animatable, so the sides swap at the moment the card is
/// edge-on, and the front is turned the right way round. With `turns` off,
/// for Reduce Motion, the sides crossfade in place instead.
@Animatable
struct PawPairsCardFace: View {
    /// 0 when face down, 180 when face up.
    var angle: Double
    @AnimatableIgnored var card: PawPairsCard
    @AnimatableIgnored var state: PawPairsCardState
    @AnimatableIgnored var isReviewing: Bool
    @AnimatableIgnored var turns: Bool

    var body: some View {
        ZStack {
            if showsFront {
                PawPairsCardFront(card: card, state: state, isReviewing: isReviewing)
                    .transition(turns ? .identity : .opacity)
            } else {
                PawPairsCardBack()
                    .transition(turns ? .identity : .opacity)
            }
        }
        .contentShape(.rect(cornerRadius: QuizMetrics.answerCornerRadius))
        .glassEffect(
            showsFront ? state.frontGlass : PawPairsCardState.backGlass,
            in: .rect(cornerRadius: QuizMetrics.answerCornerRadius)
        )
        .rotation3DEffect(.degrees(shownAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }

    private var showsFront: Bool {
        turns ? angle >= 90 : state.isFaceUp
    }

    /// Past halfway the front shows, turned back by half a turn so its
    /// text reads normally.
    private var shownAngle: Double {
        guard turns else { return 0 }
        return showsFront ? angle - 180 : angle
    }
}
