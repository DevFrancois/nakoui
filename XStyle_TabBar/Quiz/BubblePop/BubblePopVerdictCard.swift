import SwiftUI

/// How the round went: the verdict with a symbol and words, the matches
/// missed and the wrong pops by name, and a fun fact, on glass tinted by the
/// outcome.
struct BubblePopVerdictCard: View {
    let ending: BubblePopEnding
    let missed: [LocalizedStringResource]
    let wrong: [LocalizedStringResource]
    let fact: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(ending.title, systemImage: ending.symbol)
                .font(.headline)
                .foregroundStyle(ending.outcome.tint)

            if !missed.isEmpty {
                Label("Missed: \(Self.list(missed))", systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            }

            if !wrong.isEmpty {
                Label("Wrong pops: \(Self.list(wrong))", systemImage: "xmark.circle")
                    .font(.subheadline)
            }

            Text(fact)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(
            .regular.tint(ending.outcome.tint.opacity(0.15)),
            in: .rect(cornerRadius: QuizMetrics.cardCornerRadius)
        )
        .accessibilityElement(children: .combine)
    }

    /// The words as a list in the reader's language, such as "Corgi and Sheltie".
    private static func list(_ words: [LocalizedStringResource]) -> String {
        words.map { String(localized: $0) }.formatted()
    }
}

#Preview {
    BubblePopVerdictCard(
        ending: .cleared,
        missed: [],
        wrong: ["Beagle"],
        fact: "The Sphynx isn't truly hairless: many have a fine, barely visible down that makes their skin feel like a peach."
    )
    .padding()
    .background(.cyan.gradient)
}
