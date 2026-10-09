import SwiftUI

/// A slot's number in a glass circle: clear while open, lit in the quiz's
/// color while it's the next to fill, in the placed pet's color so the two
/// blend into one docked piece, then green or red once checked.
struct LineUpSlotBadge: View {
    /// Counting from 1.
    let position: Int
    /// The placed pet's color; nil while the slot is open.
    let petTint: Color?
    let isNext: Bool
    /// Nil until this slot's verdict is revealed.
    let mark: LineUpMark?
    let tint: Color

    @ScaledMetric(relativeTo: .headline) private var size = TopMenuMetrics.minimumTapSize

    var body: some View {
        Text(position, format: .number)
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(petTint == nil && !isNext ? .secondary : .primary)
            .frame(width: size, height: size)
            .glassEffect(glass, in: .circle)
            .accessibilityHidden(true)
    }

    private var glass: Glass {
        if let mark {
            mark.choiceState.glass
        } else if let petTint {
            // Matches the pet's chip, so the blended shape reads as one.
            .regular.tint(petTint.opacity(0.15))
        } else if isNext {
            .regular.tint(tint.opacity(0.3))
        } else {
            .regular
        }
    }
}
