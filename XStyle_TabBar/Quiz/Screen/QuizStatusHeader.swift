import SwiftUI

/// Progress through the round and the score, as glass that merges
/// when the pieces sit close together.
struct QuizStatusHeader: View {
    let kind: QuizKind
    let session: QuizSession

    var body: some View {
        GlassEffectContainer {
            HStack {
                QuizProgressCapsule(kind: kind, session: session)

                Spacer(minLength: 0)

                QuizScoreBadge(score: session.score)
            }
        }
        .padding(.horizontal)
    }
}
