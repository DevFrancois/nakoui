import SwiftUI

/// The question's four mood tiles, two a row, or one a row at accessibility
/// text sizes. A grid rather than a lazy one, so tiles in a row share its
/// height. Tiles keep their glass, by position, from question to question,
/// so a pick melts back to idle as the next one arrives.
struct PetMatchMoodGrid: View {
    let question: PetMatchQuestion
    let pick: PetMatchAnswer?
    /// The glass namespace of the surrounding `GlassEffectContainer`.
    let namespace: Namespace.ID
    let choose: (PetMatchAnswer) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    /// The position of the first answer in each row.
    private var rowStarts: [Int] {
        Array(stride(from: 0, to: question.answers.count, by: columnCount))
    }

    var body: some View {
        Grid(horizontalSpacing: PetMatchMetrics.tileSpacing, verticalSpacing: PetMatchMetrics.tileSpacing) {
            ForEach(rowStarts, id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + columnCount, question.answers.count), id: \.self) { index in
                        PetMatchMoodTile(
                            answer: question.answers[index],
                            tint: PetMatchMetrics.tileTint(at: index),
                            state: state(of: question.answers[index])
                        ) {
                            choose(question.answers[index])
                        }
                        .glassEffectID(index, in: namespace)
                    }
                }
            }
        }
    }

    private func state(of answer: PetMatchAnswer) -> PetMatchTileState {
        guard let pick else { return .idle }
        return pick.id == answer.id ? .picked : .passed
    }
}

#Preview {
    @Previewable @Namespace var namespace
    let question = PetMatchRounds.all[2]

    GlassEffectContainer(spacing: PetMatchMetrics.tileSpacing) {
        PetMatchMoodGrid(question: question, pick: question.answers[1], namespace: namespace) { _ in }
    }
    .padding()
    .background(.pink.gradient)
}
