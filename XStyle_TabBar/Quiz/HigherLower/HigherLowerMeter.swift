import SwiftUI

/// How far the challenger's value has climbed. The mark in the middle, under
/// the known pet's symbol, is the known value, so a fill that passes it means
/// higher. Decorative: the card's text carries the same information.
struct HigherLowerMeter: View {
    let fraction: Double
    let tint: Color
    /// The known pet's symbol, shown over the mark.
    let markSymbol: String

    @ScaledMetric(relativeTo: .body) private var height = HigherLowerMetrics.meterHeight

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: markSymbol)
                .font(.footnote)
                .foregroundStyle(.secondary)

            ZStack {
                Group {
                    Capsule()
                        .fill(.quaternary)

                    HigherLowerMeterFill(fraction: fraction)
                        .fill(tint.gradient)
                        .flipsForRightToLeftLayoutDirection(true)
                }
                .frame(height: height)

                Capsule()
                    .fill(.primary)
                    .frame(width: HigherLowerMetrics.meterMarkWidth)
            }
            .frame(height: height * 2)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 24) {
        HigherLowerMeter(fraction: 0, tint: .orange, markSymbol: "dog.fill")
        HigherLowerMeter(fraction: 0.3, tint: .purple, markSymbol: "dog.fill")
        HigherLowerMeter(fraction: 0.8, tint: .orange, markSymbol: "cat.fill")
    }
    .padding()
}
