import SwiftUI

/// The match's traits as glass chips: side by side when they fit, stacked
/// when they don't. Each chip has its own glass ID, so the chips morph out
/// of the hero card as it's revealed.
struct PetMatchTraitRow: View {
    let traits: [PetMatchTrait]
    let tint: Color
    let namespace: Namespace.ID

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(traits) { trait in
                    PetMatchTraitChip(trait: trait, tint: tint)
                        .glassEffectID(trait.id, in: namespace)
                }
            }

            VStack(spacing: 8) {
                ForEach(traits) { trait in
                    PetMatchTraitChip(trait: trait, tint: tint)
                        .glassEffectID(trait.id, in: namespace)
                }
            }
        }
    }
}
