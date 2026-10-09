import Foundation

extension ArticleBackdrop {
    /// How the image's averaged colors are toned for one appearance, in HSB
    /// terms: each keeps its hue, takes a set brightness, and loses saturation.
    struct Tone {
        let lightBrightness: Float
        let lightSaturationScale: Float
        let maximumLightSaturation: Float
        let baseBrightness: Float
        let baseSaturationScale: Float
        let maximumBaseSaturation: Float

        /// Deep colors under light text, matched to the reference design.
        static let dark = Tone(
            lightBrightness: 0.23,
            lightSaturationScale: 0.8,
            maximumLightSaturation: 0.5,
            baseBrightness: 0.17,
            baseSaturationScale: 0.25,
            maximumBaseSaturation: 0.15
        )

        /// The image's own hues washed toward white, under dark text. The base
        /// stays close to white so body text keeps its contrast.
        static let light = Tone(
            lightBrightness: 0.94,
            lightSaturationScale: 0.6,
            maximumLightSaturation: 0.3,
            baseBrightness: 0.97,
            baseSaturationScale: 0.2,
            maximumBaseSaturation: 0.07
        )
    }
}
