import SwiftUI
import Combine
import UIKit
import Metal

/// Native iOS controller. Navigation follows the current focused state.
@MainActor
public final class CardCarouselController: ObservableObject {
    weak var engine: CarouselEngine?
    var wake: (() -> Void)?

    public init() {}
    public var index: Int { engine?.index ?? 0 }
    public func next() { engine?.next(); wake?() }
    public func prev() { engine?.prev(); wake?() }
    public func show(_ index: Int) { engine?.navigate(to: index); wake?() }
    /// Drops the wheel in from the top again, as when the carousel first appears. A debug
    /// aid for the demo: it does not first return a selected or returning card to the wheel.
    func replayEntrance() { engine?.beginEntrance(); wake?() }
}

/// Cards supplied as views instead of images. Each card is drawn once as a still picture
/// (`isLive == false`) for the wheel and for every move; once the selected card settles,
/// its live view (`isLive == true`) plays over it. Live views never receive touches.
struct CarouselCards {
    enum Content {
        case swiftUI((Int, Bool) -> AnyView)
        case uiKit((Int, Bool) -> UIView)
    }

    var count: Int
    var id: String
    var content: Content

    /// Texture keys: stable across sizes, distinct per kind and identifier.
    var names: [String] {
        let kind: String
        switch content {
        case .swiftUI: kind = "swiftui"
        case .uiKit: kind = "uikit"
        }
        return (0..<max(0, count)).map { "carousel.\(kind).\(id).\($0)" }
    }

    /// The still picture for one card at its selected size.
    @MainActor
    func poster(index: Int, size: CGSize, scale: CGFloat) -> CGImage? {
        switch content {
        case .swiftUI(let make):
            let renderer = ImageRenderer(content: make(index, false).frame(width: size.width, height: size.height))
            renderer.scale = scale
            renderer.proposedSize = ProposedViewSize(size)
            return renderer.cgImage
        case .uiKit(let make):
            let view = make(index, false)
            view.frame = CGRect(origin: .zero, size: size)
            view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.preferredRange = .standard
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                view.layer.render(in: context.cgContext)
            }.cgImage
        }
    }

    /// The live view for one card, and the hosting controller that must stay alive with it.
    @MainActor
    func liveView(index: Int, size: CGSize) -> (view: UIView, owner: AnyObject?) {
        switch content {
        case .swiftUI(let make):
            let host = UIHostingController(rootView: AnyView(make(index, true)
                .frame(width: size.width, height: size.height)))
            host.view.backgroundColor = .clear
            return (host.view, host)
        case .uiKit(let make):
            return (make(index, true), nil)
        }
    }
}

/// SwiftUI entry point backed by a UIKit MTKView.
public struct CardCarousel: UIViewRepresentable {
    public var images: [String]
    public var configuration: CarouselConfiguration
    public var controller: CardCarouselController?
    public var onReady: (() -> Void)?
    public var onIndexChange: ((Int) -> Void)?
    private var hostIsActive = true
    var itemLayouts: [CarouselCardLayout] = []
    var featureMedia: ((Int) -> CarouselFeatureMedia?)?
    var companionContent: ((Int) -> CarouselCompanionContent?)?
    var companionConfiguration = CarouselCompanionConfiguration()
    var holdIntervals: [Double] = []
    var cards: CarouselCards?
    var back: ((Int) -> AnyView)?
    var backVideo: ((Int) -> URL?)?
    var renderTextureReceiver: ((MTLTexture, MTLCommandBuffer, UIView) -> Void)?
    var renderTextureUnavailable: ((UIView) -> Void)?

    public init(images: [String], configuration: CarouselConfiguration = .init(),
                controller: CardCarouselController? = nil, onReady: (() -> Void)? = nil,
                onIndexChange: ((Int) -> Void)? = nil) {
        self.images = images
        self.configuration = configuration
        self.controller = controller
        self.onReady = onReady
        self.onIndexChange = onIndexChange
    }

    /// Cards built in SwiftUI. `isLive` is false for the still picture shown on the wheel
    /// and while moving, true for the animating view over the settled selected card. Both
    /// must lay out identically; change `id` to redraw the stills.
    public init<Card: View>(count: Int, id: String = "", configuration: CarouselConfiguration = .init(),
                            controller: CardCarouselController? = nil, onReady: (() -> Void)? = nil,
                            onIndexChange: ((Int) -> Void)? = nil,
                            @ViewBuilder card: @escaping (_ index: Int, _ isLive: Bool) -> Card) {
        self.init(images: [], configuration: configuration, controller: controller,
                  onReady: onReady, onIndexChange: onIndexChange)
        cards = CarouselCards(count: count, id: id, content: .swiftUI { AnyView(card($0, $1)) })
    }

    /// Cards built from UIKit views, with the same still and live roles as the SwiftUI form.
    /// The still is drawn with `CALayer.render(in:)`; the live view is shown as is.
    public init(count: Int, id: String = "", configuration: CarouselConfiguration = .init(),
                controller: CardCarouselController? = nil, onReady: (() -> Void)? = nil,
                onIndexChange: ((Int) -> Void)? = nil,
                uiCard: @escaping (_ index: Int, _ isLive: Bool) -> UIView) {
        self.init(images: [], configuration: configuration, controller: controller,
                  onReady: onReady, onIndexChange: onIndexChange)
        cards = CarouselCards(count: count, id: id, content: .uiKit(uiCard))
    }

    /// A back face for each card. A card then turns about its vertical axis as it leaves the
    /// wheel, keeping its size and shape: selected, it shows `back(index)`. The turn follows
    /// the card, so selecting, swiping between selected cards and returning all turn it. A
    /// tap on the selected card or beside it sends it back. The back takes no touches.
    public func cardBack<Back: View>(@ViewBuilder _ back: @escaping (_ index: Int) -> Back) -> CardCarousel {
        var carousel = self
        carousel.back = { AnyView(back($0)) }
        return carousel
    }

    /// A video for each card's back (nil for none), played where the `cardBack` view puts a
    /// `CarouselBackVideo`: muted and looping, from its first frame once the selected card
    /// shows its back, paused when it turns away or the app is inactive. One player serves
    /// all cards; each file is loaded once.
    public func cardBackVideo(_ video: @escaping (_ index: Int) -> URL?) -> CardCarousel {
        var carousel = self
        carousel.backVideo = video
        return carousel
    }

    /// Optional item proportions; the wheel retains its common slot spacing.
    public func cardLayouts(_ layouts: [CarouselCardLayout]) -> CardCarousel {
        var result = self
        result.itemLayouts = layouts
        return result
    }

    /// Prepared feature media plays on either face using the carousel's shared player.
    public func cardFeatureMedia(_ media: @escaping (Int) -> CarouselFeatureMedia?) -> CardCarousel {
        var result = self
        result.featureMedia = media
        return result
    }

    public func cardAutoplayIntervals(_ intervals: [Double]) -> CardCarousel {
        var result = self
        result.holdIntervals = intervals
        return result
    }

    /// Stops the display clock and media while a retained tab is not selected.
    /// The existing cards, playback position and gesture state stay owned here.
    public func isActive(_ isActive: Bool) -> CardCarousel {
        var result = self
        result.hostIsActive = isActive
        return result
    }

    /// Shares the current Metal scene, including moving cards and prepared video frames,
    /// without reading pixels back to the CPU. The callback runs synchronously on main
    /// after the scene is encoded, before its command buffer is committed.
    ///
    /// Append sampling work to the supplied command buffer and end every encoder before
    /// returning. Do not commit it, present its drawables, or retain the source texture
    /// for later GPU reads: its pooled storage is reused after this submission completes.
    /// To display a derived reflection later, render into your own texture here and wait
    /// for successful command-buffer completion before consuming that result.
    ///
    /// The source view supplies coordinates: capture its bounds converted to the shared
    /// window during this callback. The texture covers those bounds, with its origin at
    /// the top left. Native UIKit overlays are not captured; native-glass mode exports
    /// the cards' Metal imagery. `onUnavailable` clears retained results when the source
    /// is hidden, offscreen, inactive, detached, stopped, or this callback is removed.
    /// Disconnect an old consumer explicitly before replacing it with a different one;
    /// SwiftUI closure updates do not carry a comparable consumer identity.
    public func onRenderTexture(
        _ receive: @escaping (MTLTexture, MTLCommandBuffer, UIView) -> Void,
        onUnavailable: ((UIView) -> Void)? = nil
    ) -> CardCarousel {
        var result = self
        result.renderTextureReceiver = receive
        result.renderTextureUnavailable = onUnavailable
        return result
    }

    /// Text companions have their own playful gestures and never navigate the cards.
    public func cardCompanion(configuration: CarouselCompanionConfiguration = .init(),
                              content: @escaping (Int) -> CarouselCompanionContent?) -> CardCarousel {
        var result = self
        result.companionContent = content
        result.companionConfiguration = configuration
        return result
    }

    public func makeUIView(context: Context) -> CarouselMetalView {
        let view = CarouselMetalView(images: cards?.names ?? images, configuration: configuration)
        view.isHostActive = hostIsActive
        view.update(images: images, cards: cards, back: back, backVideo: backVideo,
                    layouts: itemLayouts, featureMedia: featureMedia, holdIntervals: holdIntervals,
                    companions: companionContent, companionConfiguration: companionConfiguration,
                    configuration: configuration,
                    controller: controller, onReady: onReady, onIndexChange: onIndexChange,
                    onRenderTexture: renderTextureReceiver, onTextureUnavailable: renderTextureUnavailable)
        return view
    }

    public func updateUIView(_ view: CarouselMetalView, context: Context) {
        view.isHostActive = hostIsActive
        view.update(images: images, cards: cards, back: back, backVideo: backVideo,
                    layouts: itemLayouts, featureMedia: featureMedia, holdIntervals: holdIntervals,
                    companions: companionContent, companionConfiguration: companionConfiguration,
                    configuration: configuration,
                    controller: controller, onReady: onReady, onIndexChange: onIndexChange,
                    onRenderTexture: renderTextureReceiver, onTextureUnavailable: renderTextureUnavailable)
    }

    public static func dismantleUIView(_ view: CarouselMetalView, coordinator: ()) { view.stop() }
}
