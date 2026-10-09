import SwiftUI

/// How the line-up went, how many pets landed in place, and a fun fact, on
/// glass tinted by the verdict. The verdict carries a symbol and words, not
/// just a color.
struct LineUpVerdictCard: View {
    let points: Int
    let total: Int
    let fact: LocalizedStringResource

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var verdict: LineUpVerdict {
        LineUpVerdict(points: points, total: total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(verdict.title, systemImage: verdict.symbol)
                .font(.headline)
                .foregroundStyle(verdict.tint)
                .symbolEffect(.breathe, isActive: verdict == .perfect)
                .symbolEffectsRemoved(reduceMotion)

            Text("\(points) of \(total) in the right place", comment: "Line 'Em Up verdict: how many pets were in their right slot, out of how many in the line.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(fact)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(
            .regular.tint(verdict.tint.opacity(0.15)),
            in: .rect(cornerRadius: QuizMetrics.cardCornerRadius)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack {
        LineUpVerdictCard(points: 4, total: 4, fact: "The oldest cat on record, Creme Puff, lived to 38.")
        LineUpVerdictCard(points: 1, total: 4, fact: "The oldest cat on record, Creme Puff, lived to 38.")
    }
    .padding()
    .background(.blue.gradient)
}
