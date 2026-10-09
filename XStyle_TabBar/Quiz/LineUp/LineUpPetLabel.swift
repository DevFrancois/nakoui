import SwiftUI

/// A pet's symbol and name, with its value underneath once revealed.
struct LineUpPetLabel: View {
    let pet: LineUpPet
    var showsValue = false

    @ScaledMetric(relativeTo: .title3) private var iconWidth = 32.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStacked: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    /// The symbol beside the name, or above it at accessibility sizes, so a
    /// long name such as "Chihuahua" keeps the chip's full width rather than
    /// breaking mid-word. A layout rather than `Label`, which can't stack.
    private var layout: AnyLayout {
        isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        layout {
            Image(systemName: pet.symbol)
                .font(.title3)
                .foregroundStyle(pet.tint)
                .frame(width: iconWidth, alignment: isStacked ? .leading : .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name)
                    .font(.headline)

                if showsValue {
                    Text(pet.value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .multilineTextAlignment(.leading)
        }
    }
}
