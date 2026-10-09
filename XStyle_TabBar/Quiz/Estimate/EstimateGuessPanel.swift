import SwiftUI

/// The current guess, large, over the slider that sets it, on one glass panel.
struct EstimateGuessPanel: View {
    let question: EstimateQuestion
    @Binding var guess: Double
    let isLocked: Bool
    let tint: Color

    var body: some View {
        VStack(spacing: 12) {
            Text("\(Text(guess, format: .number.precision(.fractionLength(0)))) \(Text(question.unit))")
                .font(.largeTitle)
                .bold()
                .monospacedDigit()
                .contentTransition(.numericText(value: guess))
                .animation(.snappy, value: guess)

            Slider(value: $guess, in: question.range, step: question.step) {
                Text("Your guess")
            } minimumValueLabel: {
                Text(question.range.lowerBound, format: .number)
            } maximumValueLabel: {
                Text(question.range.upperBound, format: .number)
            }
            .tint(tint)
            .disabled(isLocked)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
    }
}
