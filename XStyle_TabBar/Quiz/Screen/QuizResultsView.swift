import SwiftUI

/// The end of a round: the score, a verdict, any new best, and the way
/// back or around again.
struct QuizResultsView: View {
    let kind: QuizKind
    let session: QuizSession

    @AppStorage private var bestScore: Int
    @State private var isNewBest = false
    @Environment(\.dismiss) private var dismiss

    init(kind: QuizKind, session: QuizSession) {
        self.kind = kind
        self.session = session
        _bestScore = AppStorage(wrappedValue: 0, kind.bestScoreKey)
    }

    var body: some View {
        VStack(spacing: 24) {
            QuizScoreRing(score: session.score, total: session.maxScore, tint: kind.tint)

            VStack(spacing: 8) {
                Text(headline)
                    .font(.title)
                    .bold()

                Text(summary)
                    .foregroundStyle(.secondary)

                if session.bestStreak > 1 {
                    Label("Best streak: \(session.bestStreak)", systemImage: "flame.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)

            if isNewBest {
                Label("New best!", systemImage: "trophy.fill")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(.yellow.opacity(0.3)), in: .capsule)
            }

            GlassEffectContainer {
                VStack(spacing: 12) {
                    Button(action: playAgain) {
                        Label("Play again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(kind.tint)

                    Button(action: close) {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
            }
        }
        .padding(.vertical)
        .onAppear(perform: recordBestScore)
    }

    private var summary: LocalizedStringResource {
        if session.maxScore == session.questionCount {
            "You got \(session.score) out of \(session.questionCount) right."
        } else {
            "You scored \(session.score) out of \(session.maxScore) points."
        }
    }

    private var headline: LocalizedStringResource {
        let fraction = Double(session.score) / Double(max(session.maxScore, 1))
        if fraction >= 0.8 {
            return "Pawsome!"
        } else if fraction >= 0.5 {
            return "Nicely done"
        } else {
            return "Keep sniffing around"
        }
    }

    private func recordBestScore() {
        guard session.score > bestScore else { return }
        bestScore = session.score
        isNewBest = true
    }

    private func playAgain() {
        isNewBest = false
        session.restart()
    }

    private func close() {
        dismiss()
    }
}
