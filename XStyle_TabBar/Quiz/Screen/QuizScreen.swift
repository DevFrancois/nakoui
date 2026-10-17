import SwiftUI

/// The frame every quiz shares: its ambient light, a glass status header with
/// progress and score, and the results once the round is over.
struct QuizScreen<Content: View>: View {
    let kind: QuizKind
    let session: QuizSession
    @ViewBuilder let content: Content

    var body: some View {
        // Scrolls so large text and short windows still reach every control.
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
        .safeAreaBar(edge: .top) {
            QuizStatusHeader(kind: kind, session: session)
                .frame(maxWidth: QuizMetrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
        }
    }
}
