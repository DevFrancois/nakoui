#if DEBUG
import SwiftUI

/// Temporary Search destination for exercising moving-card and video reflections.
struct CarouselDebugView: View {
    let isActive: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabBarReflectionSource) private var reflections

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                Text("Search")
                    .font(.largeTitle.bold())
                Text("Carousel preview")
                    .font(.title3.weight(.semibold))
                Text("Drag or tap a card. Videos play as the wheel moves.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.black)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            CardCarousel(images: CarouselDebugMedia.cards.map(\.posterName), configuration: configuration)
                .cardLayouts(CarouselDebugMedia.cards.map(\.layout))
                .cardFeatureMedia { CarouselDebugMedia.cards[$0].media }
                .isActive(isActive && scenePhase == .active)
                .onRenderTexture { texture, commandBuffer, view in
                    reflections?.render(texture: texture, commandBuffer: commandBuffer, view: view)
                } onUnavailable: { view in
                    reflections?.remove(view: view)
                }
                // Keep moving content close to either the bottom or side menu.
                .frame(height: min(geometry.size.height, max(300, min(440, geometry.size.width * 0.85))))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityIdentifier("search.carouselPreview")
        }
        .background(Color(white: 242.0 / 255))
    }

    private var configuration: CarouselConfiguration {
        var value = CarouselConfiguration()
        value.layout.cardScale = 0.95
        value.layout.cardAspect = 1.25
        value.layout.wheelCurve = 0.18
        value.spin.automatic = !reduceMotion
        value.spin.speed = 0.25
        value.spin.prefersMaximumFrameRate = true
        value.entrance.isEnabled = !reduceMotion
        value.focus.swipesBetweenSelectedCards = true
        value.focus.physicalTap = true
        value.glass = .init(style: .metal, padding: 0)
        value.card3D.isEnabled = true
        value.card3D.thickness = 2
        value.card3D.margin = 4
        value.card3D.highlight = 2
        value.card3D.bleed = 1.35
        value.card3D.bleedReach = 12
        value.rendering = .init(motionScale: 0.8, skipHiddenShading: true,
                                responsiveRendering: true, batchesVideoFrames: true,
                                fetchesVideoFramesInBackground: true)
        return value
    }
}

private enum CarouselDebugMedia {
    struct Card {
        let posterName: String
        let layout: CarouselCardLayout
        let crop: CGRect
        let videoURL: URL?

        init(_ name: String, aspect: Double, width: Double = 1, crop: CGRect) {
            posterName = name
            layout = .init(aspectRatio: aspect, relativeWidth: width)
            self.crop = crop
            videoURL = Bundle.main.url(forResource: name, withExtension: "mov", subdirectory: "Videos")
                ?? Bundle.main.url(forResource: name, withExtension: "mov")
        }

        var media: CarouselFeatureMedia? {
            videoURL.map { .init(url: $0, normalizedCrop: crop, aspectRatio: layout.aspectRatio) }
        }
    }

    // Original Carousel crop coordinates keep video and poster geometry identical.
    static let cards: [Card] = [
        .init("hark-mexico-city", aspect: 1.6253968253968254,
              crop: CGRect(x: 0.059172661870503594, y: 0.06978260869565217,
                           width: 0.8816546762589927, height: 0.8195323114809783)),
        .init("hark-home-insurance", aspect: 1.8351254480286738,
              crop: CGRect(x: 0.059172661870503594, y: 0.0775748502994012,
                           width: 0.8816546762589927, height: 0.7997625842065867)),
        .init("hark-spending", aspect: 0.8309572301425662, width: 0.796875,
              crop: CGRect(x: -0.00028132992327365726, y: 0.0014042553191489363,
                           width: 0.9982352941176471, height: 0.9993857425949103))
    ]
}
#endif
