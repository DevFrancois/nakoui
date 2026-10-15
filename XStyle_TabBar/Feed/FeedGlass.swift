import SwiftUI

/// A For you card's color fill and its glass, which the debug dials can turn
/// white, switch to another material, or fade.
struct FeedGlass: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color
    /// How strongly the tint fills the card.
    let tintOpacity: Double

    // Release builds have no dials, so they ignore any values a debug build
    // left stored.
    #if DEBUG
    @AppStorage(FeedGlassTuning.materialKey) private var material = FeedGlassTuning.defaultMaterial
    @AppStorage(FeedGlassTuning.strengthKey) private var strength = FeedGlassTuning.defaultStrength
    @AppStorage(FeedGlassTuning.whiteFillKey) private var whiteFill = FeedGlassTuning.defaultWhiteFill
    #else
    private let material = FeedGlassTuning.defaultMaterial
    private let strength = FeedGlassTuning.defaultStrength
    private let whiteFill = FeedGlassTuning.defaultWhiteFill
    #endif

    func body(content: Content) -> some View {
        let card = content
            // The colour is a fill, not a glass tint: the snapshot iOS takes
            // for the app switcher drops glass rendering, tint included.
            .background(
                whiteFill ? AnyShapeStyle(.white) : AnyShapeStyle(tint.opacity(tintOpacity)),
                in: .rect(cornerRadius: cornerRadius)
            )

        Group {
            if let glass = material.glass, strength == 1 {
                // Full strength, the default: the card itself is glass, so
                // its text gets the glass's legibility treatment.
                card.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
            } else {
                // Faded: a separate glass layer behind the card.
                card.background {
                    if let glass = material.glass {
                        Color.clear
                            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
                            .opacity(strength)
                    }
                }
            }
        }
        // On white, the text and glass read as in light mode, so the card
        // stays legible in dark mode too.
        .environment(\.colorScheme, whiteFill ? .light : colorScheme)
    }

    @Environment(\.colorScheme) private var colorScheme
}
