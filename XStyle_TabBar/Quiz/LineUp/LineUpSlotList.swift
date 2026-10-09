import SwiftUI

/// The line itself: the numbered slots from top to bottom, between labels
/// naming each end, such as "Lightest" and "Heaviest".
struct LineUpSlotList: View {
    let round: LineUpRound
    let board: LineUpBoard
    /// How many slots, from the top, show their verdict so far.
    let revealedCount: Int
    let isLocked: Bool
    let tint: Color
    let glassNamespace: Namespace.ID
    let clear: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LineUpMetrics.rowSpacing) {
            Label(round.firstLabel, systemImage: round.firstSymbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(board.slots.indices, id: \.self) { slot in
                LineUpSlotRow(
                    position: slot + 1,
                    pet: board.pet(inSlot: slot),
                    mark: slot < revealedCount ? board.mark(forSlot: slot) : nil,
                    isNext: slot == board.nextSlot,
                    isLocked: isLocked,
                    tint: tint,
                    glassNamespace: glassNamespace
                ) {
                    clear(slot)
                }
            }

            Label(round.lastLabel, systemImage: round.lastSymbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
