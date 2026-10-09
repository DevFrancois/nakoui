import SwiftUI

/// The button for another clue and the points meter, as siblings, so the
/// clue board's layout can set them side by side or stacked. Their glass
/// shares the board's namespace, so a new clue morphs out of the button.
struct MysteryPetClueControls: View {
    let cluesUsed: Int
    let clueCount: Int
    let tint: Color
    let glassNamespace: Namespace.ID
    let askForClue: () -> Void

    private var worth: Int {
        MysteryPetRounds.points(afterClues: cluesUsed)
    }

    var body: some View {
        if cluesUsed < clueCount {
            MysteryPetMoreCluesButton(
                worthNow: worth,
                worthAfter: MysteryPetRounds.points(afterClues: cluesUsed + 1),
                tint: tint,
                action: askForClue
            )
            .glassEffectID(MysteryPetGlassID.moreClues, in: glassNamespace)
        }

        MysteryPetPointsMeter(points: worth, tint: tint)
            .glassEffectID(MysteryPetGlassID.meter, in: glassNamespace)
    }
}
