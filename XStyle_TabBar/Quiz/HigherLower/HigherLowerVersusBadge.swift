import SwiftUI

/// "VS" on a glass capsule straddling the two cards. Once the answer is out,
/// it stretches to show how many times bigger the larger value is, and takes
/// the verdict's tint so it melts into the settled challenger card.
struct HigherLowerVersusBadge: View {
    /// Nil until the round is settled.
    let ratio: Double?
    let tint: Color

    @ScaledMetric(relativeTo: .headline) private var size = HigherLowerMetrics.versusSize

    var body: some View {
        // One container, so a single glass capsule resizes around the swap.
        ZStack {
            if let ratio {
                Text("\(ratio, format: .number.precision(.fractionLength(0...1)))×")
                    .transition(.blurReplace)
                    .accessibilityLabel(Text("About \(ratio, format: .number.precision(.fractionLength(0...1))) times as much"))
            } else {
                Text("VS")
                    .transition(.blurReplace)
                    .accessibilityLabel(Text("versus"))
            }
        }
        .font(.headline)
        .fontDesign(.rounded)
        .bold()
        .monospacedDigit()
        .padding(.horizontal, 12)
        .frame(minWidth: size, minHeight: size)
        .glassEffect(.regular.tint(tint.opacity(0.25)), in: .capsule)
    }
}

#Preview {
    HStack {
        HigherLowerVersusBadge(ratio: nil, tint: QuizKind.higherLower.tint)
        HigherLowerVersusBadge(ratio: 3, tint: .green)
        HigherLowerVersusBadge(ratio: 3.57, tint: .red)
    }
    .padding()
    .background(.teal.gradient)
}
