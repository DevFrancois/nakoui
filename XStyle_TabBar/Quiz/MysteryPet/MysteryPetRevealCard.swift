import SwiftUI

/// The mystery pet steps out: a dog or a cat, its breed, how quickly it was
/// found and the points that earned, on glass tinted for its species.
struct MysteryPetRevealCard: View {
    let breed: MysteryPetBreed
    let outcome: QuizOutcome
    let cluesUsed: Int
    let tint: Color

    @ScaledMetric(relativeTo: .title) private var badgeSize = MysteryPetMetrics.revealBadgeSize
    @State private var bounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var earned: Int {
        outcome == .correct ? MysteryPetRounds.points(afterClues: cluesUsed) : 0
    }

    private var remark: LocalizedStringResource {
        if outcome != .correct {
            "It was me all along!"
        } else if cluesUsed == 1 {
            "Sniffed out from the very first clue!"
        } else if cluesUsed == 2 {
            "Tracked down in just two clues!"
        } else {
            "You found me!"
        }
    }

    private var pointsLabel: LocalizedStringResource {
        if earned > 0 {
            "+^[\(earned) point](inflect: true)"
        } else {
            "No points this time"
        }
    }

    /// The badge moves above the words at accessibility sizes, so the breed
    /// name gets the card's full width instead of breaking mid-word.
    private var layout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        } else {
            AnyLayout(HStackLayout(spacing: 16))
        }
    }

    var body: some View {
        layout {
            Image(systemName: breed.species.symbol)
                .font(.title)
                .foregroundStyle(breed.species.tint)
                .symbolEffect(.bounce, value: bounce)
                .frame(width: badgeSize, height: badgeSize)
                .background(breed.species.tint.quaternary, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(breed.species.title)
                    .font(.footnote)
                    .bold()
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Text(breed.name)
                    .font(.title2)
                    .bold()

                Text(remark)
                    .font(.subheadline)

                Label {
                    Text(pointsLabel)
                        .foregroundStyle(earned > 0 ? .primary : .secondary)
                } icon: {
                    Image(systemName: earned > 0 ? "pawprint.fill" : "pawprint")
                        .foregroundStyle(earned > 0 ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                }
                .font(.subheadline)
                .bold()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(
            .regular.tint(breed.species.tint.opacity(0.2)),
            in: .rect(cornerRadius: QuizMetrics.cardCornerRadius)
        )
        .accessibilityElement(children: .combine)
        .onAppear(perform: celebrate)
    }

    private func celebrate() {
        guard !reduceMotion else { return }
        bounce.toggle()
    }
}

#Preview {
    VStack {
        MysteryPetRevealCard(breed: MysteryPetRounds.all[0], outcome: .correct, cluesUsed: 1, tint: .brown)
        MysteryPetRevealCard(breed: MysteryPetRounds.all[1], outcome: .wrong, cluesUsed: 3, tint: .brown)
    }
    .padding()
    .background(.orange.gradient)
}
