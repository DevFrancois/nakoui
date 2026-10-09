import SwiftUI

/// The mystery pet's clues so far as a stack of glass speech bubbles, then
/// the button for another clue beside the points meter. Each new clue morphs
/// out of that button; once the breed is settled, the button and meter melt
/// away and the rest of the clues join the stack.
struct MysteryPetClueBoard: View {
    let breed: MysteryPetBreed
    let cluesUsed: Int
    /// The clue the pet is still "typing", if any.
    let typingClue: Int?
    let isAnswered: Bool
    let tint: Color
    let askForClue: () -> Void

    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Every clue once the breed is settled, otherwise the ones asked for.
    private var shownClues: Int {
        isAnswered ? breed.clues.count : cluesUsed
    }

    var body: some View {
        GlassEffectContainer(spacing: MysteryPetMetrics.glassSpacing) {
            VStack(spacing: MysteryPetMetrics.clueSpacing) {
                ForEach(0..<shownClues, id: \.self) { index in
                    MysteryPetClueCard(
                        number: index + 1,
                        text: breed.clues[index],
                        state: state(of: index),
                        tint: tint
                    )
                    .glassEffectID(MysteryPetGlassID.clue(index), in: glassNamespace)
                }

                if !isAnswered {
                    // Side by side when they fit; stacked in narrow windows
                    // and at large text sizes.
                    MysteryPetControlsLayout(spacing: MysteryPetMetrics.clueSpacing) {
                        MysteryPetClueControls(
                            cluesUsed: cluesUsed,
                            clueCount: breed.clues.count,
                            tint: tint,
                            glassNamespace: glassNamespace,
                            askForClue: askForClue
                        )
                    }
                }
            }
            // With Reduce Motion on, glass fades in and out where it stands
            // instead of travelling out of the button.
            .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
        }
    }

    private func state(of index: Int) -> MysteryPetClueState {
        if index == typingClue {
            .typing
        } else if index >= cluesUsed {
            .extra
        } else if index == cluesUsed - 1 && !isAnswered {
            .latest
        } else {
            .earlier
        }
    }
}
