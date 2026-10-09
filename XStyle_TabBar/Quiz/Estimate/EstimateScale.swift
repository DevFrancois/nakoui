import SwiftUI

/// The guess and the real answer as markers on the question's range.
struct EstimateScale: View {
    let question: EstimateQuestion
    let guess: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 8)

                EstimateMarkerLayout {
                    EstimateMarker(label: "You", systemImage: "person.fill", style: AnyShapeStyle(.secondary))
                        .layoutValue(key: EstimateMarkerPosition.self, value: question.fraction(of: guess))

                    EstimateMarker(label: "Answer", systemImage: "flag.fill", style: AnyShapeStyle(tint))
                        .layoutValue(key: EstimateMarkerPosition.self, value: question.fraction(of: question.answer))
                }
            }
            .padding(.horizontal)

            Text("The answer is \(Text(question.answer, format: .number)) \(Text(question.unit)).")
                .font(.headline)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
        .accessibilityElement(children: .combine)
    }
}
