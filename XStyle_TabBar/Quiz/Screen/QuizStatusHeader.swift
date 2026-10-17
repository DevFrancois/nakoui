import SwiftUI

/// Progress through the round and the score, as glass that merges
/// when the pieces sit close together.
struct QuizStatusHeader: View {
    let kind: QuizKind
    let session: QuizSession

    var body: some View {
        GlassEffectContainer {
            HStack {
                // An invisible copy of the badge mirrors its width, so the
                // progress sits centered at every text size.
                QuizScoreBadge(score: session.score)
                    .hidden()
                    .accessibilityHidden(true)

                Spacer(minLength: 0)

                QuizProgressCapsule(kind: kind, session: session)

                Spacer(minLength: 0)

                QuizScoreBadge(score: session.score)
            }
        }
        .padding(.horizontal)
    }
}
