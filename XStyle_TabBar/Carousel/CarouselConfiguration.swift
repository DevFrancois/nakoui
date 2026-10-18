import Foundation
import SwiftUI

/// The lights 3D cards reflect in front of them (`CarouselConfiguration.Card3D.lighting`).
public enum CarouselCardLighting: String, CaseIterable {
    /// A diagonal strip, a softer glow beside it and a small lamp.
    case streak
    /// A four-pane window, its bars dark across the reflection.
    case window
    /// Three tall, thin studio strips the cards sweep under as the wheel turns.
    case strips
    /// A bright sky over a dark floor, as glossy paper outdoors.
    case horizon
    /// A ring light's circle.
    case ring
    /// The streak and window seen through an iridescent film, its colours shifting across the screen.
    case holo
    /// No lights in front: only the edges catch the studio.
    case matte

    public var title: String {
        switch self {
        case .streak: return "Streak"
        case .window: return "Window"
        case .strips: return "Strips"
        case .horizon: return "Horizon"
        case .ring: return "Ring"
        case .holo: return "Holo"
        case .matte: return "Matte"
        }
    }
}

/// The laminated plastic's optical finish (`CarouselConfiguration.Card3D.material`).
public enum CarouselCardMaterial: String, CaseIterable {
    case clear, frosted, smoked, prismatic

    public var title: String {
        switch self {
        case .clear: return "Clear"
        case .frosted: return "Frosted"
        case .smoked: return "Smoked"
        case .prismatic: return "Prism"
        }
    }

    public var detail: String {
        switch self {
        case .clear: return "Polished clear plastic with crisp refraction and fine studio reflections."
        case .frosted: return "Soft satin reflections and misted clear edges, keeping the artwork sharp."
        case .smoked: return "Cool dark transparent edges with restrained glossy highlights."
        case .prismatic: return "Clear plastic with subtle spectral separation along its refracted edges."
        }
    }
}

/// The colored coating across the whole 3D card, including its printed faces.
public enum CarouselCardColorStyle: String, CaseIterable {
    case none, solid, linear, radial

    public var title: String {
        switch self {
        case .none: return "Off"
        case .solid: return "Solid"
        case .linear: return "Linear"
        case .radial: return "Radial"
        }
    }
}

/// A coating's three colors: solid uses the middle stop; gradients use all three.
public enum CarouselCardColorPalette: String, CaseIterable {
    case ocean, sunset, orchid, emerald

    public var title: String {
        switch self {
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .orchid: return "Orchid"
        case .emerald: return "Emerald"
        }
    }

    /// Shared by the debug swatches and renderer; the shader receives linear colors.
    internal var sRGBStops: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        switch self {
        case .ocean: return (SIMD3(0.06, 0.64, 0.90), SIMD3(0.19, 0.29, 0.90), SIMD3(0.47, 0.09, 0.81))
        case .sunset: return (SIMD3(0.99, 0.56, 0.08), SIMD3(0.97, 0.21, 0.25), SIMD3(0.62, 0.07, 0.55))
        case .orchid: return (SIMD3(0.91, 0.35, 0.71), SIMD3(0.57, 0.23, 0.90), SIMD3(0.23, 0.48, 0.92))
        case .emerald: return (SIMD3(0.07, 0.72, 0.62), SIMD3(0.09, 0.45, 0.44), SIMD3(0.54, 0.78, 0.15))
        }
    }
}

/// One sRGB coating color. Zero opacity leaves the artwork and refraction visible.
public struct CarouselCardColorStop: Equatable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double = 0.19, green: Double = 0.29, blue: Double = 0.90, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

/// Editable colors and placement for a 3D card's colored coating.
public struct CarouselCardColorGradient: Equatable, Codable {
    /// False uses the selected palette's RGB values, retaining these stops' opacities.
    public var usesCustomColors: Bool
    public var start: CarouselCardColorStop
    public var middle: CarouselCardColorStop
    public var end: CarouselCardColorStop
    /// Positions along the gradient's full extent, from 0 to 1.
    public var startLocation: Double
    public var endLocation: Double
    /// The middle stop's fraction between the start and end locations.
    public var middleLocation: Double
    /// Degrees clockwise from right in normalized card coordinates, whose y axis points down.
    public var linearAngle: Double
    /// Radial center in normalized card coordinates, from 0 to 1.
    public var radialCenterX: Double
    public var radialCenterY: Double
    /// Radial extent in half-card widths and heights; 1 reaches the centered card's edges.
    public var radialRadius: Double

    public init(usesCustomColors: Bool = false,
                start: CarouselCardColorStop = .init(red: 0.06, green: 0.64, blue: 0.90),
                middle: CarouselCardColorStop = .init(),
                end: CarouselCardColorStop = .init(red: 0.47, green: 0.09, blue: 0.81),
                startLocation: Double = 0, endLocation: Double = 1, middleLocation: Double = 0.5,
                linearAngle: Double = 45, radialCenterX: Double = 0.5, radialCenterY: Double = 0.5,
                radialRadius: Double = 1) {
        self.usesCustomColors = usesCustomColors
        self.start = start
        self.middle = middle
        self.end = end
        self.startLocation = startLocation
        self.endLocation = endLocation
        self.middleLocation = middleLocation
        self.linearAngle = linearAngle
        self.radialCenterX = radialCenterX
        self.radialCenterY = radialCenterY
        self.radialRadius = radialRadius
    }

    internal var validated: CarouselCardColorGradient {
        var result = self
        let defaults = CarouselCardColorGradient()
        func clamp(_ value: Double, _ low: Double, _ high: Double, _ fallback: Double) -> Double {
            value.isFinite ? min(high, max(low, value)) : fallback
        }
        func stop(_ value: CarouselCardColorStop, fallback: CarouselCardColorStop) -> CarouselCardColorStop {
            .init(red: clamp(value.red, 0, 1, fallback.red),
                  green: clamp(value.green, 0, 1, fallback.green),
                  blue: clamp(value.blue, 0, 1, fallback.blue),
                  opacity: clamp(value.opacity, 0, 1, fallback.opacity))
        }
        result.start = stop(start, fallback: defaults.start)
        result.middle = stop(middle, fallback: defaults.middle)
        result.end = stop(end, fallback: defaults.end)
        result.startLocation = clamp(startLocation, 0, 0.99, 0)
        result.endLocation = max(result.startLocation + 0.01, clamp(endLocation, 0.01, 1, 1))
        result.middleLocation = clamp(middleLocation, 0.05, 0.95, 0.5)
        result.linearAngle = clamp(linearAngle, -180, 180, 45)
        result.radialCenterX = clamp(radialCenterX, 0, 1, 0.5)
        result.radialCenterY = clamp(radialCenterY, 0, 1, 0.5)
        result.radialRadius = clamp(radialRadius, 0.05, 3, 1)
        return result
    }

    /// Hidden RGB values do not affect an unedited preset.
    internal var hasDefaultPlacementAndOpacity: Bool {
        start.opacity == 1 && middle.opacity == 1 && end.opacity == 1 &&
            startLocation == 0 && endLocation == 1 && middleLocation == 0.5 && linearAngle == 45 &&
            radialCenterX == 0.5 && radialCenterY == 0.5 && radialRadius == 1
    }
}

/// What a card turning over plays (`CarouselConfiguration.Haptics.style`).
public enum CarouselHapticStyle: String, CaseIterable {
    /// The FWTransition reference's pattern (`CarouselFlip.ahap`).
    case pattern
    /// A single tap.
    case tap
}

/// Metal's glass-inspired frame or Apple's native iOS 26 glass material.
public enum CarouselGlassStyle: String, CaseIterable {
    case metal, liquidGlass
}

/// Alternative touch catches and tap entrances, captured when a touch begins.
public enum CarouselTapSelectionMode: String, CaseIterable {
    case custom, reference, softCatch

    public var title: String {
        switch self {
        case .custom: return "Custom"
        case .reference: return "Reference"
        case .softCatch: return "Soft catch"
        }
    }
}

/// Standard Apple timing curves and springs evaluated by the native engine.
public enum CarouselAnimation: String, CaseIterable {
    case linear, easeIn, easeOut, easeInOut, spring, smooth, snappy, bouncy

    public var title: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In Out"
        case .spring: return "Spring"
        case .smooth: return "Smooth"
        case .snappy: return "Snappy"
        case .bouncy: return "Bouncy"
        }
    }

    public var isSpring: Bool {
        switch self {
        case .spring, .smooth, .snappy, .bouncy: return true
        case .linear, .easeIn, .easeOut, .easeInOut: return false
        }
    }

    fileprivate var curve: UnitCurve? {
        switch self {
        case .linear: return .linear
        case .easeIn: return .easeIn
        case .easeOut: return .easeOut
        case .easeInOut: return .easeInOut
        case .spring, .smooth, .snappy, .bouncy: return nil
        }
    }

    fileprivate var curveEndpointSlopes: (start: Double, end: Double) {
        // The degenerate ease control points have nonzero one-sided slopes,
        // although UnitCurve's exact-endpoint velocity can report another value.
        switch self {
        case .linear: return (1, 1)
        case .easeIn: return (0, Self.easeEndpointSlope)
        case .easeOut: return (Self.easeEndpointSlope, 0)
        case .easeInOut, .spring, .smooth, .snappy, .bouncy: return (0, 0)
        }
    }

    private static let easeEndpointSlope = UnitCurve.easeOut.velocity(at: 0.000_000_01)

    fileprivate func spring(duration: Double, bounce: Double) -> Spring? {
        switch self {
        case .spring: return Spring(duration: duration, bounce: bounce)
        case .smooth: return .smooth(duration: duration, extraBounce: 0)
        case .snappy: return .snappy(duration: duration, extraBounce: 0)
        case .bouncy: return .bouncy(duration: duration, extraBounce: 0)
        case .linear, .easeIn, .easeOut, .easeInOut: return nil
        }
    }
}

/// Live configuration. Updating this value never replaces textures or motion state.
public struct CarouselConfiguration: Equatable {
    public struct Transition: Equatable {
        public var travelDuration: Double
        public var animation: CarouselAnimation
        public var animationDuration: Double
        public var bounce: Double

        public init(travelDuration: Double = 0.6, animation: CarouselAnimation = .spring,
                    animationDuration: Double = 0.6, bounce: Double = 0.28) {
            self.travelDuration = travelDuration
            self.animation = animation
            self.animationDuration = animationDuration
            self.bounce = bounce
        }
    }

    public struct Layout: Equatable {
        public var cardScale: Double = 1
        public var wheelCurve: Double = 0.6
        public var sideScale: Double = 1
        /// Every card's width over its height: 4:5 by default. Images are aspect-filled.
        public var cardAspect: Double = 0.8
        public init() {}
    }

    public struct Spin: Equatable {
        public var automatic: Bool = true
        public var speed: Double = 0.25
        public var settlingTime: Double = 3
        /// Discrete navigation interval; zero disables it. Waits for an idle wheel.
        public var autoplayInterval: Double = 0
        /// Steady automatic spin requests the screen's maximum rate (120 Hz on ProMotion
        /// iPhones). False requests up to 60 fps. iOS manages power and thermal throttling.
        public var prefersMaximumFrameRate: Bool = true
        public init() {}
    }

    public struct Focus: Equatable {
        /// Pacing for horizontal gestures between selected cards, independent of tap selection.
        public struct HorizontalSwipe: Equatable {
            /// False restores the original drag sensitivity, selection timing and release momentum.
            /// Captured at touch-down so comparing modes never interrupts an active swipe.
            public var isEnabled: Bool
            /// Card progress per finger page; lower values need a longer drag. Validated to 0.35...1.
            public var dragSensitivity: Double
            /// Spring response for both travel and rotation after release, in seconds (0.35...1.5).
            public var animationDuration: Double
            /// Soft ceiling on inherited release momentum, in cards per second (0.25...3).
            /// This does not change whether a flick selects the next card.
            public var momentumLimit: Double
            /// Wave swipes: one swipe progress trails the finger on Wave's follow spring and, on
            /// release, keeps its speed into Wave's return spring (`animationDuration` response),
            /// with every card placed from it until rest. Overrides `isEnabled`; uses the
            /// sensitivity and momentum limit above. Captured at touch-down.
            public var followsWithSpring: Bool
            /// Tucked swipes: both cards travel `1 − tuckAmount` of today's page sideways, so they
            /// stay close while they turn instead of opening a gap, and the turn follows the swipe:
            /// toward the previous card both cards turn the mirror way of the next card. Start and
            /// end poses are unchanged. Captured at touch-down.
            public var tucks: Bool
            /// How much closer tucked swipes keep the cards, as a share of a page (0...0.7).
            public var tuckAmount: Double
            /// False: swiping between selected cards never shows them turning, exactly as with
            /// `rotatesOnSelection` off, and plays no turn haptic. Tap selection and deselection
            /// still turn. Captured at touch-down.
            public var turnsCards: Bool

            public init(dragSensitivity: Double = 0.7, animationDuration: Double = 0.8,
                        momentumLimit: Double = 1, isEnabled: Bool = true, followsWithSpring: Bool = false,
                        tucks: Bool = false, tuckAmount: Double = 0.45, turnsCards: Bool = true) {
                self.isEnabled = isEnabled
                self.dragSensitivity = dragSensitivity
                self.animationDuration = animationDuration
                self.momentumLimit = momentumLimit
                self.followsWithSpring = followsWithSpring
                self.tucks = tucks
                self.tuckAmount = tuckAmount
                self.turnsCards = turnsCards
            }

            internal var transition: Transition {
                Transition(travelDuration: animationDuration, animation: .spring,
                           animationDuration: animationDuration, bounce: 0.28)
            }

            internal var effectiveDragSensitivity: Double { isEnabled || followsWithSpring ? dragSensitivity : 1 }
        }

        /// Two fingers on the selected card scale and rotate it, resisting ever more past 75%
        /// and 125% and past 25° either way. Lifting any finger ends the pinch: the card springs
        /// back to focus and never dismisses.
        public struct Pinch: Equatable {
            public var isEnabled: Bool
            /// True (default) feels like a companion: the card trails the fingers on Wave's follow
            /// spring and floats back on its return spring. False keeps the card under the fingers
            /// and releases on the drag snap-back spring.
            public var followsWithSpring: Bool

            public init(isEnabled: Bool = true, followsWithSpring: Bool = true) {
                self.isEnabled = isEnabled
                self.followsWithSpring = followsWithSpring
            }
        }

        /// Captured at touch start. Reference uses fixed easing; Custom is the default.
        public var tapSelectionMode: CarouselTapSelectionMode = .custom
        /// Captured at touch start for Custom and Soft catch selections.
        /// Focused controller navigation captures it at dispatch.
        public var selection = Transition()
        /// Captured at touch-down for selected-card swipes in every tap-selection mode.
        public var horizontalSwipe = HorizontalSwipe()
        /// Captured at touch-down with the rest of the focus tuning.
        public var pinch = Pinch()
        /// Captured for background dismissal and throws in any direction, including release momentum.
        /// Focused controller navigation uses selection tuning instead.
        public var returnToWheel = Transition(travelDuration: 0.5, animationDuration: 0.5, bounce: 0.10)
        /// Compatibility alias for the return transition's custom spring bounce.
        public var cardReturnBounce: Double {
            get { returnToWheel.bounce }
            set { returnToWheel.bounce = newValue }
        }
        /// Bounce for an incomplete drag that returns to focus.
        public var cardSnapBackBounce: Double = 0.45
        /// Grab-point tilt while dragging a selected card in any direction.
        public var cardDragTilt: Double = 8
        /// Release projection time for selected-card browsing and dismissals.
        public var cardFlickBoost: Double = 0.20
        /// Captured at touch-down. Horizontal drags browse selected cards when true;
        /// false keeps horizontal and vertical drags dismissing to the wheel.
        public var swipesBetweenSelectedCards: Bool = false
        /// Selecting a card turns it to its back; false keeps the selected card facing forward.
        public var rotatesOnSelection: Bool = true
        /// A wheel card yields where it is pressed (that spot tilts into the screen on a Wave
        /// spring, released as it lifts) and a tap selection turns toward the tapped side.
        /// Captured at touch-down.
        public var physicalTap: Bool = false
        /// How far a physical tap tilts a card's edge into the screen, in degrees (0...35);
        /// the whole card also sinks by 5% per 20°.
        public var physicalTapTilt: Double = 20
        public init(rotatesOnSelection: Bool = true) {
            self.rotatesOnSelection = rotatesOnSelection
        }
    }

    public struct Glass: Equatable {
        /// The frame's material once `padding` adds one. Liquid Glass requires iOS 26;
        /// earlier systems draw the Metal frame instead.
        public var style: CarouselGlassStyle = .metal
        /// Uniform outer padding in UIKit points. The default zero draws plain cards
        /// without a frame in either style, which is the least work.
        public var padding: Double = 0
        public init(style: CarouselGlassStyle = .metal, padding: Double = 0) {
            self.style = style
            self.padding = padding
        }
    }

    /// Rendering choices do not alter card geometry, hit testing or motion.
    public struct Rendering: Equatable {
        /// Linear resolution while cards are dragged or animating interactively.
        /// Validated to 0.75...1; idle cards and gentle automatic spin stay sharp.
        public var motionScale: Double
        /// Avoid material samples for fragments completely hidden by nearer cards.
        public var skipHiddenShading: Bool
        /// Acquire drawables and schedule their command buffers off the touch thread.
        public var responsiveRendering: Bool
        /// Prepare every new feature video frame of one display refresh in a single
        /// command buffer instead of one per video. Pixels and ordering are unchanged.
        public var batchesVideoFrames: Bool
        /// Ask feature videos for their new frames on a background queue, ready for a later
        /// refresh, instead of waiting on the media server from the main thread.
        public var fetchesVideoFramesInBackground: Bool

        public init(motionScale: Double = 1, skipHiddenShading: Bool = false,
                    responsiveRendering: Bool = false, batchesVideoFrames: Bool = false,
                    fetchesVideoFramesInBackground: Bool = false) {
            self.motionScale = motionScale
            self.skipHiddenShading = skipHiddenShading
            self.responsiveRendering = responsiveRendering
            self.batchesVideoFrames = batchesVideoFrames
            self.fetchesVideoFramesInBackground = fetchesVideoFramesInBackground
        }
    }

    /// Cards drawn in the Metal styles as laminated plastic, after the onboarding project's
    /// cards: the image printed on a paper sheet sealed in clear plastic, with real
    /// thickness, a rounded edge and a margin of clear plastic around the paper, through
    /// which the carousel behind shows. A photo studio lights them; its gloss slides
    /// across the cards as the wheel turns, and a card turning over (with `cardBack`)
    /// shows its thickness. Liquid Glass cards stay flat.
    public struct Card3D: Equatable {
        public var isEnabled: Bool = false
        /// Thickness in millimetres of an 85.6 mm-wide card (a credit card is 0.76 mm),
        /// so it scales with each card's width.
        public var thickness: Double = 0.76
        /// The clear plastic from the paper's edge to the card's, in the same millimetres;
        /// never narrower than the rounded edge.
        public var margin: Double = 2
        /// The corners' radius, in the same millimetres of the image's width (2.91 is the
        /// flat cards' 0.034 × width); a frame's padding adds to it, as for flat cards.
        public var cornerRadius: Double = 2.91
        /// The rounded edge's radius as a share of the thickness: 0.5 rounds it fully.
        public var bevelFraction: Double = 0.5
        /// 0 rounds the edge as a circle; 1 flattens its profile into the faces.
        public var softness: Double = 0
        /// The studio's reflections on the plastic: 1 is physically based.
        public var highlight: Double = 1
        /// The plastic surface's roughness: low is glossy, high is satin.
        public var roughness: Double = 0.12
        /// The lights the cards reflect in front of them.
        public var lighting: CarouselCardLighting = .streak
        /// Those lights turned about the screen's centre, in degrees, clockwise.
        public var lightAngle: Double = 0
        /// How strongly the colours of nearby cards bleed into a card's edge, as Liquid
        /// Glass picks up what is around it; 0 turns it off.
        public var bleed: Double = 1
        /// How deep that bleed reaches into a card, and how far around it looks, in the
        /// same millimetres.
        public var bleedReach: Double = 12
        /// The depth of the rim’s soft light field between card surfaces, in millimetres.
        public var bleedDepth: Double = 12
        /// Layered studio reflections on the plastic. False preserves the original reflection.
        public var refinedReflections: Bool = true
        /// Refraction and light transmission through the clear margin and rounded edge.
        public var refractiveEdges: Bool = true
        /// The selected card's visible UI reflects in exposed clear rims; requires refractive edges.
        public var foregroundReflections: Bool = true
        /// Gentle directional shading of the paper sealed inside the plastic.
        public var paperShading: Bool = true
        /// Soft directional shadows that ground the laminated cards in the wheel.
        public var softShadows: Bool = true
        /// The plastic's finish. Clear preserves the established laminated material.
        public var material: CarouselCardMaterial = .clear
        /// A colored coating over the full card. None preserves the material's own color.
        public var colorStyle: CarouselCardColorStyle = .none
        /// Solid uses the palette's middle color; gradients use its three stops.
        public var colorPalette: CarouselCardColorPalette = .ocean
        /// The coating's strength, from 0 (unchanged) to 1 (strongest).
        public var colorStrength: Double = 0.38
        /// Editable coating stops, transparency and gradient placement.
        public var colorGradient = CarouselCardColorGradient()
        /// Resolve the rim’s displacement, blur and visibility in one shared 3D scene.
        /// Screen poses and the existing turn projection remain unchanged.
        public var sceneDepth: Bool = true
        /// Separation between wheel layers, in millimetres of the wheel card's 85.6 mm width.
        public var wheelLayerSpacing: Double = 4
        /// A fully selected card's lift above the wheel, in the same millimetres.
        public var selectionLift: Double = 24
        public init(isEnabled: Bool = false, thickness: Double = 0.76, margin: Double = 2,
                    cornerRadius: Double = 2.91, bevelFraction: Double = 0.5, softness: Double = 0,
                    highlight: Double = 1, roughness: Double = 0.12, lighting: CarouselCardLighting = .streak,
                    lightAngle: Double = 0, bleed: Double = 1, bleedReach: Double = 12,
                    refinedReflections: Bool = true, refractiveEdges: Bool = true,
                    paperShading: Bool = true, softShadows: Bool = true,
                    material: CarouselCardMaterial = .clear, colorStyle: CarouselCardColorStyle = .none,
                    colorPalette: CarouselCardColorPalette = .ocean, colorStrength: Double = 0.38,
                    colorGradient: CarouselCardColorGradient = .init(), foregroundReflections: Bool = true,
                    sceneDepth: Bool = true, wheelLayerSpacing: Double = 4, selectionLift: Double = 24, bleedDepth: Double = 12) {
            self.isEnabled = isEnabled
            self.thickness = thickness
            self.margin = margin
            self.cornerRadius = cornerRadius
            self.bevelFraction = bevelFraction
            self.softness = softness
            self.highlight = highlight
            self.roughness = roughness
            self.lighting = lighting
            self.lightAngle = lightAngle
            self.bleed = bleed
            self.bleedReach = bleedReach
            self.bleedDepth = bleedDepth
            self.refinedReflections = refinedReflections
            self.refractiveEdges = refractiveEdges
            self.foregroundReflections = foregroundReflections
            self.paperShading = paperShading
            self.softShadows = softShadows
            self.material = material
            self.colorStyle = colorStyle
            self.colorPalette = colorPalette
            self.colorStrength = colorStrength
            self.colorGradient = colorGradient
            self.sceneDepth = sceneDepth
            self.wheelLayerSpacing = wheelLayerSpacing
            self.selectionLift = selectionLift
        }
    }

    /// The haptic a change of selection plays as cards turn over (with `cardBack`).
    public struct Haptics: Equatable {
        public var isEnabled: Bool = true
        public var style: CarouselHapticStyle = .pattern
        public init(isEnabled: Bool = true, style: CarouselHapticStyle = .pattern) {
            self.isEnabled = isEnabled
            self.style = style
        }
    }

    public struct Entrance: Equatable {
        /// The wheel drops in from above the view on a bouncy spring when the carousel
        /// first appears, and again when its cards are replaced. Off shows it in place.
        public var isEnabled: Bool = true
        public init() {}
    }

    public var layout = Layout()
    public var spin = Spin()
    public var focus = Focus()
    public var glass = Glass()
    public var rendering = Rendering()
    public var entrance = Entrance()
    public var card3D = Card3D()
    public var haptics = Haptics()
    public init() {}

    /// Keep the requested style intact when running on an older OS.
    internal var effectiveGlassStyle: CarouselGlassStyle {
        if #available(iOS 26.0, *) { return glass.style }
        return .metal
    }

    /// System glass forms only the frame; without padding there is none to present.
    internal var usesNativeGlass: Bool {
        effectiveGlassStyle == .liquidGlass && glass.padding > 0
    }

    internal var validated: CarouselConfiguration {
        var result = self
        func clamp(_ value: Double, _ low: Double, _ high: Double, _ fallback: Double) -> Double {
            value.isFinite ? min(high, max(low, value)) : fallback
        }
        result.layout.cardScale = clamp(layout.cardScale, 0.5, 1.3, 1)
        result.layout.wheelCurve = clamp(layout.wheelCurve, 0, 1, 0.6)
        result.layout.sideScale = clamp(layout.sideScale, 0.1, 1, 1)
        result.layout.cardAspect = clamp(layout.cardAspect, 0.4, 1.25, 0.8)
        result.spin.speed = clamp(spin.speed, 0.05, 1, 0.25)
        result.spin.settlingTime = clamp(spin.settlingTime, 0.5, 6, 3)
        result.spin.autoplayInterval = clamp(spin.autoplayInterval, 0, 3600, 0)
        result.focus.selection.travelDuration = clamp(focus.selection.travelDuration, 0.1, 2, 0.6)
        result.focus.selection.animationDuration = clamp(focus.selection.animationDuration, 0.1, 2, 0.6)
        result.focus.selection.bounce = clamp(focus.selection.bounce, 0, 0.7, 0.28)
        result.focus.horizontalSwipe.dragSensitivity = clamp(focus.horizontalSwipe.dragSensitivity, 0.35, 1, 0.7)
        result.focus.horizontalSwipe.animationDuration = clamp(focus.horizontalSwipe.animationDuration, 0.35, 1.5, 0.8)
        result.focus.horizontalSwipe.momentumLimit = clamp(focus.horizontalSwipe.momentumLimit, 0.25, 3, 1)
        result.focus.horizontalSwipe.tuckAmount = clamp(focus.horizontalSwipe.tuckAmount, 0, 0.7, 0.45)
        result.focus.returnToWheel.travelDuration = clamp(focus.returnToWheel.travelDuration, 0.1, 2, 0.5)
        result.focus.returnToWheel.animationDuration = clamp(focus.returnToWheel.animationDuration, 0.1, 2, 0.5)
        result.focus.returnToWheel.bounce = clamp(focus.returnToWheel.bounce, 0, 0.7, 0.10)
        result.focus.cardSnapBackBounce = clamp(focus.cardSnapBackBounce, 0, 0.7, 0.45)
        result.focus.cardDragTilt = clamp(focus.cardDragTilt, 0, 20, 8)
        result.focus.physicalTapTilt = clamp(focus.physicalTapTilt, 0, 35, 20)
        result.focus.cardFlickBoost = clamp(focus.cardFlickBoost, 0, 0.5, 0.2)
        result.glass.padding = clamp(glass.padding, 0, 24, 0)
        result.rendering.motionScale = clamp(rendering.motionScale, 0.75, 1, 1)
        result.card3D.thickness = clamp(card3D.thickness, 0.2, 3, 0.76)
        result.card3D.margin = clamp(card3D.margin, 0, 5, 2)
        result.card3D.cornerRadius = clamp(card3D.cornerRadius, 0, 24, 2.91)
        result.card3D.bevelFraction = clamp(card3D.bevelFraction, 0, 0.5, 0.5)
        result.card3D.softness = clamp(card3D.softness, 0, 1, 0)
        result.card3D.highlight = clamp(card3D.highlight, 0, 2, 1)
        result.card3D.roughness = clamp(card3D.roughness, 0.03, 0.6, 0.12)
        result.card3D.lightAngle = clamp(card3D.lightAngle, -180, 180, 0)
        result.card3D.bleed = clamp(card3D.bleed, 0, 2, 1)
        result.card3D.bleedReach = clamp(card3D.bleedReach, 2, 40, 12)
        result.card3D.bleedDepth = clamp(card3D.bleedDepth, 2, 48, 12)
        result.card3D.colorStrength = clamp(card3D.colorStrength, 0, 1, 0.38)
        result.card3D.colorGradient = card3D.colorGradient.validated
        result.card3D.wheelLayerSpacing = clamp(card3D.wheelLayerSpacing, 0, 16, 4)
        result.card3D.selectionLift = clamp(card3D.selectionLift, 0, 85.6, 24)
        return result
    }
}

/// A scalar channel with a fixed target. Curves finish at their deadline;
/// Apple's springs retain momentum and may settle after their perceptual duration.
struct CarouselAnimationTrack: Equatable {
    private(set) var value: Double
    private(set) var velocity: Double
    var remainingDuration: Double { max(0, segmentDuration - elapsed) }

    private var target: Double
    private let spring: Spring?
    private let curve: UnitCurve?
    private let curveStartSlope: Double
    private let curveEndSlope: Double
    private let originalDuration: Double
    private var segmentDuration: Double
    private var elapsed: Double = 0
    private var initialResidual: Double
    private var initialVelocity: Double
    private var preservesMomentum: Bool

    init(value: Double, velocity: Double, target: Double, animation: CarouselAnimation,
         duration: Double, bounce: Double, preserveMomentum: Bool) {
        let safeValue = value.isFinite ? value : 0
        let safeTarget = target.isFinite ? target : safeValue
        let safeVelocity = velocity.isFinite ? velocity : 0
        let safeDuration = duration.isFinite ? max(0.01, duration) : 0.46
        let safeBounce = bounce.isFinite ? min(0.7, max(0, bounce)) : 0.28
        self.value = safeValue
        self.velocity = safeVelocity
        self.target = safeTarget
        spring = animation.spring(duration: safeDuration, bounce: safeBounce)
        curve = animation.curve
        let slopes = animation.curveEndpointSlopes
        curveStartSlope = slopes.start
        curveEndSlope = slopes.end
        originalDuration = safeDuration
        segmentDuration = safeDuration
        initialResidual = safeValue - safeTarget
        initialVelocity = safeVelocity
        preservesMomentum = preserveMomentum
        if let curve, !preserveMomentum {
            self.velocity = -initialResidual * curve.velocity(at: 0) / safeDuration
        }
    }

    mutating func advance(by seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        elapsed += seconds
        if let spring {
            spring.update(value: &value, velocity: &velocity, target: target, deltaTime: seconds)
        } else if let curve {
            guard elapsed < segmentDuration else {
                value = target
                velocity = 0
                return
            }
            let progress = elapsed / segmentDuration
            let sample = preservesMomentum ? momentumCurve(curve, at: progress) :
                (value: curve.value(at: progress), velocity: curve.velocity(at: progress))
            let curveValue = sample.value
            let curveVelocity = sample.velocity
            var residual = initialResidual * (1 - curveValue)
            var derivative = -initialResidual * curveVelocity
            if preservesMomentum {
                // Hermite corrections preserve the incoming velocity while
                // ending at the target with no residual velocity.
                let start = segmentDuration * initialVelocity + initialResidual * curveStartSlope
                let end = initialResidual * curveEndSlope
                let squared = progress * progress
                let cubed = squared * progress
                residual += start * (cubed - 2 * squared + progress) + end * (cubed - squared)
                derivative += start * (3 * squared - 4 * progress + 1) + end * (3 * squared - 2 * progress)
            }
            value = target + residual
            velocity = derivative / segmentDuration
        }
    }

    /// Tiny C1 endpoint patches remove UnitCurve's floating-point quantization
    /// from release velocities. Ordinary tap interpolation stays untouched.
    private func momentumCurve(_ curve: UnitCurve, at progress: Double) -> (value: Double, velocity: Double) {
        let edge = 0.001
        if progress < edge {
            return hermite(from: 0, startSlope: curveStartSlope,
                to: curve.value(at: edge), endSlope: curve.velocity(at: edge),
                interval: edge, progress: progress / edge)
        }
        if progress > 1 - edge {
            return hermite(from: curve.value(at: 1 - edge), startSlope: curve.velocity(at: 1 - edge),
                to: 1, endSlope: curveEndSlope,
                interval: edge, progress: (progress - (1 - edge)) / edge)
        }
        return (curve.value(at: progress), curve.velocity(at: progress))
    }

    private func hermite(from start: Double, startSlope: Double, to end: Double, endSlope: Double,
                         interval: Double, progress: Double) -> (value: Double, velocity: Double) {
        let squared = progress * progress
        let cubed = squared * progress
        let value = start * (2 * cubed - 3 * squared + 1) +
            startSlope * interval * (cubed - 2 * squared + progress) +
            end * (-2 * cubed + 3 * squared) + endSlope * interval * (cubed - squared)
        let velocity = (start * (6 * squared - 6 * progress) +
            end * (-6 * squared + 6 * progress)) / interval +
            startSlope * (3 * squared - 4 * progress + 1) + endSlope * (3 * squared - 2 * progress)
        return (value, velocity)
    }

    func isSettled(tolerance: Double, velocityTolerance: Double) -> Bool {
        if curve != nil && elapsed < segmentDuration { return false }
        return abs(value - target) <= tolerance && abs(velocity) <= velocityTolerance
    }

    /// Rebase from a displayed pose without restarting a curve's deadline or
    /// changing the spring's response. Retargeting a completed curve uses its
    /// original pace; a completed channel already at rest stays complete.
    mutating func reseed(value: Double, velocity: Double, target: Double,
                         preserveMomentum: Bool = true) {
        let safeValue = value.isFinite ? value : self.value
        let safeTarget = target.isFinite ? target : self.target
        let safeVelocity = velocity.isFinite ? velocity : 0
        if curve != nil {
            let remaining = remainingDuration
            if remaining > 0 {
                segmentDuration = remaining
                elapsed = 0
            } else if safeValue != safeTarget || safeVelocity != 0 {
                segmentDuration = originalDuration
                elapsed = 0
            }
        }
        self.value = safeValue
        self.velocity = safeVelocity
        self.target = safeTarget
        initialResidual = safeValue - safeTarget
        initialVelocity = safeVelocity
        preservesMomentum = preserveMomentum
        if let curve, !preserveMomentum {
            self.velocity = -initialResidual * curve.velocity(at: 0) / segmentDuration
        }
    }
}

/// Independent tuning for interactive text companions. No companion provider means no overlay.
public struct CarouselCompanionConfiguration: Equatable {
    public var isEnabled = true
    public var selectedCardsOnly = false
    public var isInteractive = true
    public var motionEnabled = true
    public var mass: Double = 1
    public var damping: Double = 0.68
    public var parallax: Double = 0.18

    public init() {}

    var validated: Self {
        var result = self
        result.mass = mass.isFinite ? min(3, max(0.5, mass)) : 1
        result.damping = damping.isFinite ? min(1, max(0.5, damping)) : 0.68
        result.parallax = parallax.isFinite ? min(0.3, max(0, parallax)) : 0.18
        return result
    }
}
