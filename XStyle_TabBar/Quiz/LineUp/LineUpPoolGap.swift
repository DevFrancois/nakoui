import SwiftUI

/// The spot a placed pet came from: a dashed outline the size of its chip,
/// so the other chips keep their places.
struct LineUpPoolGap: View {
    let pet: LineUpPet

    @ScaledMetric(relativeTo: .headline) private var minHeight = LineUpMetrics.chipHeight

    var body: some View {
        LineUpPetLabel(pet: pet)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .leading)
            .hidden()
            .background {
                RoundedRectangle(cornerRadius: QuizMetrics.answerCornerRadius)
                    .strokeBorder(.tertiary, style: LineUpMetrics.dashedOutline)
            }
            .accessibilityHidden(true)
    }
}
