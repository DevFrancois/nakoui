import SwiftUI

/// Everything under the board, in one glass container: the wrong-guess
/// note, the clue, and either the controls or, once the word is settled,
/// the fact and Next. The Hint button morphs into the clue card, and the
/// notes and fact card morph in and out.
struct WordWagPanel: View {
    let board: WordWagBoard
    let session: QuizSession
    let next: () -> Void

    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: WordWagMetrics.panelBlend) {
            VStack(spacing: QuizMetrics.sectionSpacing) {
                if board.status == .wrong {
                    WordWagWrongNote()
                        .glassEffectID("wrong", in: glassNamespace)
                }

                if board.usedHint {
                    WordWagClueCard(clue: board.puzzle.clue)
                        .glassEffectID("hint", in: glassNamespace)
                }

                if let outcome = session.outcome {
                    QuizFactCard(outcome: outcome, fact: board.puzzle.fact)
                        .glassEffectID("fact", in: glassNamespace)

                    QuizNextButton(tint: QuizKind.wordWag.tint, isLast: session.isLastQuestion, action: next)
                        .id(WordWagScrollTarget.next)
                } else {
                    WordWagControls(board: board, namespace: glassNamespace)
                }
            }
        }
    }
}
