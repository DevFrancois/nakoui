import SwiftUI

/// The pets still to place, as glass chips in shuffled spots they keep: a
/// placed pet leaves a dashed gap, so the others don't jump around. Each
/// chip shares its glass ID with its slot, so the glass flows between them.
struct LineUpPool: View {
    let board: LineUpBoard
    let glassNamespace: Namespace.ID
    let focus: AccessibilityFocusState<LineUpFocus?>.Binding
    let place: (LineUpPet) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LineUpGridLayout(columns: dynamicTypeSize.isAccessibilitySize ? 1 : 2, spacing: LineUpMetrics.rowSpacing) {
            ForEach(board.pool) { pet in
                if board.isPlaced(pet) {
                    LineUpPoolGap(pet: pet)
                } else {
                    LineUpPoolChip(pet: pet, nextPosition: (board.nextSlot ?? 0) + 1) {
                        place(pet)
                    }
                    .glassEffectID(pet.id, in: glassNamespace)
                    .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
                    .accessibilityFocused(focus, equals: .pet(pet.id))
                }
            }
        }
    }
}
