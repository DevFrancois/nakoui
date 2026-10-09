import SwiftUI

/// One breed's share of the answers: its emblem, name and percent over a bar.
struct PetMatchMixRow: View {
    let share: PetMatchMixShare
    /// The bar's length relative to the biggest share, from 0 to 1.
    let barFraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(share.breed.name)
                } icon: {
                    Image(systemName: share.breed.symbol)
                        .foregroundStyle(share.breed.tint)
                }

                Spacer(minLength: 8)

                Text(share.fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            PetMatchMixBar(fraction: barFraction, tint: share.breed.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(share.breed.name))
        .accessibilityValue(Text(share.fraction, format: .percent.precision(.fractionLength(0))))
    }
}
