import SwiftUI

/// The face-down side: a tilted paw inside a dashed border, like the back of
/// a playing card. Decorative; the card's button carries its name.
struct PawPairsCardBack: View {
    var body: some View {
        Image(systemName: "pawprint.fill")
            .font(.title)
            .foregroundStyle(.white)
            .rotationEffect(.degrees(-15))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: QuizMetrics.answerCornerRadius - 6)
                    .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .padding(6)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    PawPairsCardBack()
        .frame(width: 110, height: 96)
        .glassEffect(PawPairsCardState.backGlass, in: .rect(cornerRadius: QuizMetrics.answerCornerRadius))
        .padding()
        .background(.indigo.gradient)
}
