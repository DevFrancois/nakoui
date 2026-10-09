import SwiftUI

/// Back, progress through the round, and the score, as glass that merges
/// when the pieces sit close together.
struct QuizTopBar: View {
    let kind: QuizKind
    let session: QuizSession
    var showsScore = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassEffectContainer {
            HStack {
                Button("Back", systemImage: "chevron.backward", action: goBack)
                    .buttonStyle(GlassCircleButtonStyle())

                Spacer(minLength: 0)

                QuizProgressCapsule(kind: kind, session: session)

                Spacer(minLength: 0)

                if showsScore {
                    QuizScoreBadge(score: session.score)
                } else {
                    // Keeps the progress capsule centered.
                    Color.clear
                        .frame(width: TopMenuMetrics.minimumTapSize, height: TopMenuMetrics.minimumTapSize)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal)
    }

    private func goBack() {
        dismiss()
    }
}
