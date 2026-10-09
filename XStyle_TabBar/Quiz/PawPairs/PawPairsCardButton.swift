import SwiftUI

/// A card as a button: it flips when tapped, hops when matched and shakes
/// on a miss. VoiceOver hears "Card 4, face down" or the card's word, with
/// its result as the value. With Reduce Motion, the sides crossfade and the
/// hop and shake are left out; the tints and badges still tell the story.
struct PawPairsCardButton: View {
    let card: PawPairsCard
    let state: PawPairsCardState
    let isReviewing: Bool
    /// How often this card has been part of a miss; each new one shakes it.
    let misses: Int
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            PawPairsCardFace(
                angle: state.isFaceUp ? 180 : 0,
                card: card,
                state: state,
                isReviewing: isReviewing,
                turns: !reduceMotion
            )
        }
        .buttonStyle(PassthroughButtonStyle())
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : PawPairsMetrics.flipAnimation, value: state)
        .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : misses) { content, offset in
            content.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                // Waits for the card to land face up first.
                LinearKeyframe(0, duration: 0.4)
                CubicKeyframe(-8, duration: 0.06)
                CubicKeyframe(8, duration: 0.08)
                CubicKeyframe(-6, duration: 0.08)
                CubicKeyframe(4, duration: 0.07)
                CubicKeyframe(0, duration: 0.06)
            }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: !reduceMotion && state == .matched) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1, duration: 0.3)
                SpringKeyframe(1.1, duration: 0.15, spring: .snappy)
                SpringKeyframe(1, duration: 0.4, spring: .bouncy)
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(Text(state.accessibilityValue))
        .accessibilityInputLabels([inputLabel])
    }

    private var label: Text {
        if state.isFaceUp {
            Text(card.face.text)
        } else {
            Text("Card \(card.number), face down")
        }
    }

    /// A short name for Voice Control, such as "Tap Card 4", which its
    /// "Show names" overlay also puts on the face-down cards.
    private var inputLabel: Text {
        if state.isFaceUp {
            Text(card.face.text)
        } else {
            Text("Card \(card.number)")
        }
    }
}

#Preview {
    @Previewable @State var isUp = false
    let card = PawPairsCard(pairID: 0, face: PawPairsFace("Shiba Inu", symbol: "dog.fill"), number: 4, boardIndex: 0)

    PawPairsCardButton(card: card, state: isUp ? .faceUp : .faceDown, isReviewing: false, misses: 0) {
        isUp.toggle()
    }
    .frame(width: 110, height: 96)
    .padding()
    .background(.indigo.gradient)
}
