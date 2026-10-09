import SwiftUI

/// Back, progress through the round, and the score, as glass that merges
/// when the pieces sit close together.
struct QuizTopBar: View {
    let kind: QuizKind
    let session: QuizSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassEffectContainer {
            HStack {
                Button("Back", systemImage: "chevron.backward", action: goBack)
                    .buttonStyle(GlassCircleButtonStyle())

                Spacer(minLength: 0)

                QuizProgressCapsule(kind: kind, session: session)

                Spacer(minLength: 0)

                QuizScoreBadge(score: session.score)
            }
        }
        .padding(.horizontal)
    }

    private func goBack() {
        dismiss()
    }
}
