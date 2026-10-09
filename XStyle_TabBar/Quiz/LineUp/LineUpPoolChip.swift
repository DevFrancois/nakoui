import SwiftUI

/// A pet waiting in the pool, as an interactive glass chip. Tapping it
/// sends it to the next open slot.
struct LineUpPoolChip: View {
    let pet: LineUpPet
    /// Where the pet will go, counting from 1.
    let nextPosition: Int
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var minHeight = LineUpMetrics.chipHeight

    var body: some View {
        Button(action: action) {
            LineUpPetLabel(pet: pet)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .leading)
                .contentShape(.rect(cornerRadius: QuizMetrics.answerCornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        .glassEffect(
            .regular.tint(pet.tint.opacity(0.15)).interactive(),
            in: .rect(cornerRadius: QuizMetrics.answerCornerRadius)
        )
        .accessibilityHint(Text("Places it at position \(nextPosition)."))
    }
}
