import SwiftUI

/// The mystery pet: a question mark in a glass circle that wiggles as each
/// clue arrives, then turns into a dog or a cat once the breed is settled.
struct MysteryPetPortrait: View {
    /// Set once the breed is settled.
    let species: PetSpecies?
    let clueCount: Int
    let tint: Color

    @ScaledMetric(relativeTo: .title) private var size = MysteryPetMetrics.portraitSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtitle: LocalizedStringResource {
        switch species {
        case .dog: "Woof! Mystery solved."
        case .cat: "Meow! Mystery solved."
        case nil: "Read my clues, then name my breed."
        }
    }

    /// The title moves under the portrait at accessibility sizes, where the
    /// scaled circle would leave it too little room beside it.
    private var layout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        } else {
            AnyLayout(HStackLayout(spacing: 16))
        }
    }

    var body: some View {
        layout {
            Image(systemName: species?.symbol ?? "questionmark")
                .font(.title)
                .bold()
                .foregroundStyle(species?.tint ?? tint)
                .contentTransition(.symbolEffect(.replace))
                // Holds still with Reduce Motion on.
                .symbolEffect(.wiggle, value: reduceMotion ? 0 : clueCount)
                .frame(width: size, height: size)
                .glassEffect(.regular.tint((species?.tint ?? tint).opacity(0.2)), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Who am I?")
                    .font(.title2)
                    .bold()

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(spacing: 24) {
        MysteryPetPortrait(species: nil, clueCount: 1, tint: .brown)
        MysteryPetPortrait(species: .dog, clueCount: 2, tint: .brown)
    }
    .padding()
    .background(.orange.gradient)
}
