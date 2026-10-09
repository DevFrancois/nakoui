import SwiftUI

/// Hint, Shuffle and Give up as glass capsules in a row, or a column when
/// their titles don't fit side by side. They sit in the quiz's glass
/// container, so the Hint button morphs into its clue card. Giving up asks
/// first, since it forfeits the word's points.
struct WordWagControls: View {
    let board: WordWagBoard
    let namespace: Namespace.ID

    @State private var isConfirmingGiveUp = false

    var body: some View {
        WordWagControlsLayout(spacing: WordWagMetrics.controlSpacing) {
            if !board.usedHint {
                WordWagActionButton(title: "Hint", systemImage: "lightbulb.fill", cost: "−1", action: board.useHint)
                    .accessibilityHint(Text("Shows a clue, but the word is then worth one point less."))
                    .glassEffectID("hint", in: namespace)
            }

            WordWagActionButton(title: "Shuffle", systemImage: "shuffle", action: board.shuffle)
                .disabled(board.isTrayEmpty)
                .glassEffectID("shuffle", in: namespace)

            WordWagActionButton(title: "Give up", systemImage: "eye", action: confirmGiveUp)
                .glassEffectID("giveUp", in: namespace)
                .confirmationDialog(
                    "Give up on this word?",
                    isPresented: $isConfirmingGiveUp,
                    titleVisibility: .visible
                ) {
                    Button("Reveal the breed", role: .destructive, action: giveUp)
                } message: {
                    Text("You won't score any points for it.")
                }
        }
    }

    private func confirmGiveUp() {
        isConfirmingGiveUp = true
    }

    private func giveUp() {
        board.reveal()
    }
}

#Preview {
    @Previewable @Namespace var namespace

    GlassEffectContainer(spacing: WordWagMetrics.panelBlend) {
        WordWagControls(board: WordWagBoard(puzzle: WordWagRounds.all[0]), namespace: namespace)
    }
    .frame(width: 343)
    .padding()
    .background(.mint.gradient)
}
