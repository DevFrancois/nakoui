import SwiftUI

/// The end of the round. Emblems shuffle in a glass circle while the match
/// is sniffed out, then the circle grows into the breed's card and its
/// trait chips morph out of it, followed by the runner-up, the whole breed
/// mix, and ways to share, go again or leave. VoiceOver goes straight to
/// the match.
struct PetMatchResultsView: View {
    /// Fixed for this results screen, so "Take it again" clearing the tally
    /// can't change what's shown while the screen animates away.
    let result: PetMatchResult
    let takeAgain: () -> Void

    @State private var isRevealed = false
    @Namespace private var glassNamespace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var showsMatch: Bool {
        isRevealed || voiceOverEnabled
    }

    private var match: PetMatchBreed {
        result.match
    }

    private var shareMessage: String {
        String(localized: match.shareMessage)
    }

    /// Grows out of the sniffing circle, or materializes in place with Reduce Motion on.
    private var glassTransition: GlassEffectTransition {
        reduceMotion ? .materialize : .matchedGeometry
    }

    /// Rises in below the reveal, or fades in with Reduce Motion on.
    private var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    var body: some View {
        VStack(spacing: QuizMetrics.sectionSpacing) {
            GlassEffectContainer(spacing: QuizMetrics.sectionSpacing) {
                VStack(spacing: QuizMetrics.sectionSpacing) {
                    if showsMatch {
                        PetMatchHeroCard(breed: match)
                            .glassEffectID("match", in: glassNamespace)
                            .glassEffectTransition(glassTransition)

                        PetMatchTraitRow(traits: match.traits, tint: match.tint, namespace: glassNamespace)
                    } else {
                        PetMatchSniffingBadge()
                            .glassEffectID("match", in: glassNamespace)
                            .glassEffectTransition(glassTransition)
                            .padding(.top, 40)

                        Text("Sniffing out your match…")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if showsMatch {
                PetMatchMixCard(runnerUp: result.runnerUp, mix: result.mix)
                    .transition(revealTransition)

                // Default spacing, like the shared results, so the three
                // buttons stay apart rather than fusing across their gaps.
                GlassEffectContainer {
                    VStack(spacing: 12) {
                        ShareLink(item: shareMessage) {
                            Label("Share my match", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(match.tint)

                        Button(action: takeAgain) {
                            Label("Take it again", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)

                        Button(action: close) {
                            Text("Done")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    .controlSize(.large)
                }
                .transition(revealTransition)
            }
        }
        .padding(.vertical)
        .sensoryFeedback(.success, trigger: isRevealed)
        .task {
            await reveal()
        }
    }

    /// Holds the suspense for a moment, then shows the match.
    private func reveal() async {
        guard !showsMatch else { return }
        do {
            try await Task.sleep(for: PetMatchMetrics.sniffDuration)
        } catch {
            return
        }
        withAnimation(reduceMotion ? .smooth : .bouncy(duration: 0.7)) {
            isRevealed = true
        }
    }

    private func close() {
        dismiss()
    }
}

#Preview {
    ScrollView {
        PetMatchResultsView(
            result: PetMatchResult(
                match: .goldenRetriever,
                runnerUp: .beagle,
                mix: [
                    PetMatchMixShare(breed: .goldenRetriever, percent: 45),
                    PetMatchMixShare(breed: .beagle, percent: 30),
                    PetMatchMixShare(breed: .greyhound, percent: 15),
                    PetMatchMixShare(breed: .shibaInu, percent: 10)
                ]
            ),
            takeAgain: {}
        )
        .padding()
    }
    .background(.pink.gradient)
}
