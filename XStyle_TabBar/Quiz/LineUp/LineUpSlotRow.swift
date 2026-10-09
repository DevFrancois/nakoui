import SwiftUI

/// One numbered place in the line: a glass number beside the pet placed
/// there, which blends into it, or beside a dashed outline while it's open.
struct LineUpSlotRow: View {
    /// Counting from 1.
    let position: Int
    let pet: LineUpPet?
    /// Nil until this slot's verdict is revealed.
    let mark: LineUpMark?
    let isNext: Bool
    let isLocked: Bool
    let tint: Color
    let glassNamespace: Namespace.ID
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The number beside its pet, or docked above it at accessibility sizes,
    /// so long names keep the row's full width.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LineUpMetrics.badgeGap))
            : AnyLayout(HStackLayout(spacing: LineUpMetrics.badgeGap))
    }

    var body: some View {
        layout {
            LineUpSlotBadge(position: position, petTint: pet?.tint, isNext: isNext, mark: mark, tint: tint)
                .dynamicTypeSize(...LineUpMetrics.largestBadgeTypeSize)

            if let pet {
                LineUpSlotChip(pet: pet, position: position, mark: mark, isLocked: isLocked, action: action)
                    .glassEffectID(pet.id, in: glassNamespace)
                    .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
            } else {
                LineUpEmptySlot(position: position, isNext: isNext, tint: tint)
            }
        }
    }
}
