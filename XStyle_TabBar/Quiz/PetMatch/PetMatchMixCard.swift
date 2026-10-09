import SwiftUI

/// The runner-up, then every breed the answers leaned toward, as shares
/// that add up to 100%, like a DNA test for personality.
struct PetMatchMixCard: View {
    let runnerUp: PetMatchBreed
    let mix: [PetMatchMixShare]

    /// The biggest share, which fills a whole bar.
    private var leadingPercent: Int {
        max(mix.map(\.percent).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("Runner-up: \(Text(runnerUp.name).bold())")
                } icon: {
                    Image(systemName: "medal.fill")
                        .foregroundStyle(runnerUp.tint)
                }
                .font(.headline)

                Text(runnerUp.runnerUpNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Divider()

            Text("Your breed mix")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(mix) { share in
                PetMatchMixRow(share: share, barFraction: Double(share.percent) / Double(leadingPercent))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(in: .rect(cornerRadius: QuizMetrics.cardCornerRadius))
    }
}

#Preview {
    PetMatchMixCard(
        runnerUp: .beagle,
        mix: [
            PetMatchMixShare(breed: .goldenRetriever, percent: 45),
            PetMatchMixShare(breed: .beagle, percent: 30),
            PetMatchMixShare(breed: .greyhound, percent: 15),
            PetMatchMixShare(breed: .shibaInu, percent: 10)
        ]
    )
    .padding()
    .background(.pink.gradient)
}
