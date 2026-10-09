import SwiftUI

/// What the word is worth, as paw prints that empty when the hint or giving
/// up takes points away.
struct WordWagStakes: View {
    let points: Int

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<WordWagRounds.pointsPerWord, id: \.self) { index in
                    Image(systemName: index < points ? "pawprint.fill" : "pawprint")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .foregroundStyle(QuizKind.wordWag.tint)

            Text("^[\(points) point](inflect: true)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(points)))
        }
        .animation(.snappy, value: points)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Worth ^[\(points) point](inflect: true)"))
    }
}

#Preview {
    VStack {
        WordWagStakes(points: 2)
        WordWagStakes(points: 1)
        WordWagStakes(points: 0)
    }
}
