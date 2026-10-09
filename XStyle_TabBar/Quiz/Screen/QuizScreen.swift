import SwiftUI

/// The frame every quiz shares: its ambient light, a glass top bar with
/// progress and score, the zoom from its card, and the results once the
/// round is over.
struct QuizScreen<Content: View>: View {
    let kind: QuizKind
    let session: QuizSession
    let namespace: Namespace.ID
    @ViewBuilder let content: Content

    var body: some View {
        // Scrolls so large text and short windows, such as iPhone Duo's
        // outer display, still reach every control.
        ScrollView {
            Group {
                if session.isFinished {
                    QuizResultsView(kind: kind, session: session)
                } else {
                    content
                }
            }
            .transition(.blurReplace)
            .padding()
            .frame(maxWidth: QuizMetrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(.smooth, value: session.isFinished)
        .sensoryFeedback(trigger: session.outcome) { _, outcome in
            outcome?.feedback
        }
        .background {
            AmbientGradientBackground(palettes: [kind.palette], progress: 0)
        }
        // Part of the page, not the navigation bar, so it follows the zoom.
        .safeAreaBar(edge: .top) {
            QuizTopBar(kind: kind, session: session)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationTransition(.zoom(sourceID: kind, in: namespace))
    }
}
