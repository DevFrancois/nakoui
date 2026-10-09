import SwiftUI

/// One of the match's traits on a glass capsule tinted with the breed's color.
struct PetMatchTraitChip: View {
    let trait: PetMatchTrait
    let tint: Color

    var body: some View {
        Label {
            Text(trait.title)
        } icon: {
            Image(systemName: trait.symbol)
                .foregroundStyle(tint)
        }
        .font(.subheadline)
        .bold()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(tint.opacity(0.2)), in: .capsule)
    }
}
