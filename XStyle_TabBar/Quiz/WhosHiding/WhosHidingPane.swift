import SwiftUI

/// The frosted window the animal hides behind. Its glass clears a little at
/// each stage, then shrinks into a badge: "Who's that?" once fully clear,
/// and who it was once answered. VoiceOver reads it as one element saying
/// how clear it is.
struct WhosHidingPane: View {
    let round: WhosHidingRound
    let stage: WhosHidingStage
    let outcome: QuizOutcome?

    @ScaledMetric(relativeTo: .largeTitle) private var height = 220.0
    @ScaledMetric(relativeTo: .largeTitle) private var animalSize = 110.0
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRevealed: Bool {
        outcome != nil
    }

    /// Morphs the window into the badge, or fades between them with Reduce Motion on.
    private var glassTransition: GlassEffectTransition {
        reduceMotion ? .materialize : .matchedGeometry
    }

    var body: some View {
        ZStack {
            WhosHidingAnimal(
                symbol: round.symbol,
                tint: round.tint,
                stage: isRevealed ? .clear : stage,
                outcome: outcome,
                size: animalSize
            )
            // Sits a little high, leaving room for the badge.
            .padding(.bottom, animalSize * 0.3)

            GlassEffectContainer {
                ZStack(alignment: .bottom) {
                    if isRevealed {
                        WhosHidingBadge(title: round.reveal, systemImage: "sparkles", tint: round.tint)
                            .glassEffectID("window", in: glassNamespace)
                            .glassEffectTransition(glassTransition)
                            .padding(.bottom)
                    } else if stage == .clear {
                        WhosHidingBadge(title: "Who's that?", systemImage: "questionmark", tint: nil)
                            .glassEffectID("window", in: glassNamespace)
                            .glassEffectTransition(glassTransition)
                            .padding(.bottom)
                    } else {
                        Color.clear
                            .glassEffect(stage.glass, in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
                            .glassEffectID("window", in: glassNamespace)
                            .glassEffectTransition(glassTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !reduceMotion {
                WhosHidingSparkleBurst(trigger: outcome == .correct, tint: round.tint, radius: animalSize)
                    .padding(.bottom, animalSize * 0.3)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            ZStack {
                Rectangle()
                    .fill(.background.opacity(0.35))

                // The animal's color glows behind it once it's out.
                RadialGradient(
                    colors: [round.tint.opacity(isRevealed ? 0.4 : 0), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: height * 0.7
                )
            }
        }
        .clipShape(.rect(cornerRadius: QuizMetrics.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: QuizMetrics.cardCornerRadius)
                .strokeBorder(.white.opacity(0.3), lineWidth: 1)
        }
        .animation(.smooth, value: stage)
        .animation(reduceMotion ? .smooth : .bouncy, value: outcome)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Hidden animal"))
        .accessibilityValue(Text(isRevealed ? round.reveal : stage.accessibilityValue))
    }
}

#Preview {
    VStack {
        WhosHidingPane(round: WhosHidingRounds.all[3], stage: .misty, outcome: nil)
        WhosHidingPane(round: WhosHidingRounds.all[3], stage: .misty, outcome: .correct)
    }
    .padding()
    .background(.purple.gradient)
}
