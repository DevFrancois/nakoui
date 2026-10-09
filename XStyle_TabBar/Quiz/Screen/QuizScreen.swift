import SwiftUI

/// The frame every quiz shares: its ambient light, a glass top bar with
/// progress and score, the zoom from its card, and the results once the
/// round is over. Formats with their own ending, such as a personality
/// match, pass custom `results`.
struct QuizScreen<Content: View, Results: View>: View {
    let kind: QuizKind
    let session: QuizSession
    let namespace: Namespace.ID
    /// False for unscored formats, which hide the score badge.
    var showsScore = true
    @ViewBuilder let content: Content
    @ViewBuilder let results: Results

    var body: some View {
        // Scrolls so large text and short windows, such as iPhone Duo's
        // outer display, still reach every control.
        ScrollView {
            Group {
                if session.isFinished {
                    results
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
            QuizTopBar(kind: kind, session: session, showsScore: showsScore)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationTransition(.zoom(sourceID: kind, in: namespace))
    }
}

extension QuizScreen where Results == QuizResultsView {
    /// A scored quiz that ends on the shared results screen.
    init(
        kind: QuizKind,
        session: QuizSession,
        namespace: Namespace.ID,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            kind: kind,
            session: session,
            namespace: namespace,
            content: content,
            results: { QuizResultsView(kind: kind, session: session) }
        )
    }
}
