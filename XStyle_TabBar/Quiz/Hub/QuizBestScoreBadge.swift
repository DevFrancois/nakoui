import SwiftUI

/// The best score so far for a quiz, once one exists.
struct QuizBestScoreBadge: View {
    let kind: QuizKind

    @AppStorage private var bestScore: Int

    init(kind: QuizKind) {
        self.kind = kind
        _bestScore = AppStorage(wrappedValue: 0, kind.bestScoreKey)
    }

    var body: some View {
        if bestScore > 0 {
            Label("Best \(bestScore)/\(kind.maxScore)", systemImage: "trophy.fill")
                .font(.footnote)
                .bold()
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.yellow.quaternary, in: .capsule)
        }
    }
}
