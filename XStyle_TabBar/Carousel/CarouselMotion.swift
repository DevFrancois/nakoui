import CoreGraphics
import Foundation

/// Exact damped oscillator integration. Response is one undamped period;
/// damping 1 is critical. Each step preserves both position and velocity.
struct CarouselSpring: Equatable {
    var value: Double
    var velocity: Double = 0
    var response: Double
    var damping: Double

    mutating func advance(by seconds: Double, target: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        let omega = 2 * Double.pi / max(0.01, response)
        let zeta = min(1, max(0.05, damping))
        let offset = value - target
        let envelope = exp(-zeta * omega * seconds)
        if zeta < 0.999999 {
            let frequency = omega * sqrt(1 - zeta * zeta)
            let a = offset
            let b = (velocity + zeta * omega * offset) / frequency
            let cosine = cos(frequency * seconds), sine = sin(frequency * seconds)
            value = target + envelope * (a * cosine + b * sine)
            velocity = envelope * ((frequency * b - zeta * omega * a) * cosine -
                                   (frequency * a + zeta * omega * b) * sine)
        } else {
            let b = velocity + omega * offset
            let displacement = offset + b * seconds
            value = target + envelope * displacement
            velocity = envelope * (b - omega * displacement)
        }
    }

    func isSettled(at target: Double, tolerance: Double = 0.001,
                   velocityTolerance: Double = 0.01) -> Bool {
        abs(value - target) <= tolerance && abs(velocity) <= velocityTolerance
    }
}

struct CarouselPoseVelocity: Equatable {
    var x: Double = 0
    var y: Double = 0
    var height: Double = 0
    var angle: Double = 0
    var promotion: Double = 0
    var turn: Double = 0
}

/// Touch-down identity and tuning survive the presentation queue draining.
/// The view replaces only the frame with the last genuinely displayed snapshot.
struct CarouselTapCapture {
    var frame: CarouselFrame
    let hitIndex: Int?
    let tuning: CarouselConfiguration.Focus
}

enum CarouselAnimationActivity: Equatable {
    case idle
    case automatic
    case interactive
}

/// Native motion state. UIKit feeds timestamped touch samples;
/// the display link advances this model and Metal consumes its immutable frame.
final class CarouselEngine {
    /// Optional item geometry changes without replacing content, focus or wheel position.
    var cardLayouts: [CarouselCardLayout] = [] {
        didSet { if cardLayouts != oldValue { rebaseLayout() } }
    }
    /// Per-item resting holds for feature presentations; empty retains legacy autoplay.
    var autoplayIntervals: [Double] = [] {
        didSet { if autoplayIntervals != oldValue { resetAutoplayHold() } }
    }
    /// A companion owns input independently of card gestures. Pause unattended
    /// advancement (timed holds or continuous spin) without taking over card input.
    var autoplaySuspended = false {
        didSet { if autoplaySuspended != oldValue { resetAutoplayHold() } }
    }
    var isInteracting: Bool { gesture != nil || scrollReleaseAt != nil }
    /// Two or more fingers are scaling and rotating the selected card.
    var isPinching: Bool {
        if case .focus(let held)? = gesture { return held.pinch != nil }
        return false
    }
    var activeMediaIndex: Int? {
        guard count > 0 else { return nil }
        return focusedIndex ?? CarouselGeometry.wrappedIndex(Int(wheelPosition.rounded()), count: count)
    }

    func resetAutoplayHold() { autoplayElapsed = 0 }

    private func aspect(for index: Int) -> Double {
        itemLayout(for: index)?.aspectRatio ?? settings.layout.cardAspect
    }

    private func itemLayout(for index: Int) -> CarouselCardLayout? {
        guard cardLayouts.indices.contains(index) else { return nil }
        return cardLayouts[index].validated(fallbackAspect: settings.layout.cardAspect)
    }

    func focusedPose(for index: Int) -> CarouselPose {
        CarouselGeometry.focusedPose(size: size, glass: settings.glass, aspect: aspect(for: index))
    }

    private var autoplayInterval: Double {
        let index = CarouselGeometry.wrappedIndex(Int(wheelPosition.rounded()), count: count)
        if autoplayIntervals.indices.contains(index) {
            let hold = autoplayIntervals[index]
            if hold.isFinite, hold > 0 { return min(3600, hold) }
        }
        return settings.spin.autoplayInterval
    }

    var configuration: CarouselConfiguration {
        get { settings }
        set {
            let old = settings
            settings = newValue.validated
            if old.layout != settings.layout || old.glass.padding != settings.glass.padding {
                rebaseLayout(refocus: old.glass.padding != settings.glass.padding)
            }
            if old.spin.automatic != settings.spin.automatic, focusedIndex == nil, gesture == nil {
                wheelMode = .free
                wheelTarget = nil
                wheelTransition = nil
            }
            if old.spin.autoplayInterval != settings.spin.autoplayInterval { autoplayElapsed = 0 }
        }
    }

    var size: CGSize = .zero {
        didSet { if size != oldValue { rebaseLayout() } }
    }
    private(set) var count: Int
    private(set) var wheelPosition: Double = 0
    private(set) var wheelVelocity: Double = 0
    private(set) var spinDirection: Int = 1
    private(set) var focusedIndex: Int? {
        // With back faces every change of selection turns cards over: play its haptic.
        didSet { if rotatesSelectedCard, focusedIndex != oldValue, !silentSelection { onFlip?() } }
    }
    var returningIndices: [Int] { bodies.values.filter { $0.motion == .returning }.map(\.index).sorted() }
    /// The selected card once it rests at its focused pose: the only card that may show live content.
    var settledFocusedIndex: Int? {
        guard let index = focusedIndex, bodies[index]?.motion == .focused else { return nil }
        return index
    }
    /// Where a settled selected card rests.
    var focusedPose: CarouselPose { focusedPose(for: focusedIndex ?? activeMediaIndex ?? 0) }
    var index: Int {
        CarouselGeometry.wrappedIndex(Int((displayedFrame?.position ?? wheelPosition).rounded()), count: count)
    }
    var onIndexChange: ((Int) -> Void)?
    /// Assigned by the view after presentation, never just submission. Touches
    /// hit-test what the user saw. Fenced wheel catches also resume its motion;
    /// focused and promoted touches continue the newer simulated motion already
    /// queued for display instead of stepping back to it.
    var displayedFrame: CarouselFrame? {
        didSet {
            if displayedFrame != nil {
                usesDisplayedReporting = true
                publishIndex()
            }
        }
    }

    /// Set by the view when cards have a back face. Availability stays independent of
    /// whether selection rotates the card, so its back can be shown again without reset.
    var flipsEnabled = false {
        didSet {
            if flipsEnabled && !oldValue { enableTurnsForExistingCards() }
        }
    }
    /// Selection turns an available back with the card's lift, without changing its motion.
    var rotatesSelectedCard: Bool { flipsEnabled && settings.focus.rotatesOnSelection }
    /// Called when the selection changes while cards have back faces, as cards turn.
    var onFlip: (() -> Void)?
    /// Called when a swipe between selected cards changes the selection without showing a
    /// turn (Rotate selected off, or swipes that do not turn cards), as the swipe commits.
    var onSwipeSelection: (() -> Void)?
    /// True while the selected card shows its back face.
    var isFlipped: Bool {
        guard rotatesSelectedCard, let focusedIndex, let body = bodies[focusedIndex], !body.turnHidden else { return false }
        return cos(body.pose.turn) < 0
    }

    var needsAnimation: Bool {
        guard count > 0, size.width > 0, size.height > 0 else { return false }
        if isEntering { return true }
        if count > 1, case .wheel(let held)? = gesture, !held.isDragging,
           held.tuning.tapSelectionMode == .softCatch, held.initialVelocity != 0,
           held.brakingElapsed < Self.catchDuration {
            return true
        }
        if case .focus(let held)? = gesture, let brake = held.brake,
           brake.elapsed < Self.catchDuration {
            return true
        }
        if case .focus(let held)? = gesture, held.pinch?.isFollowing == true { return true }
        if swipeSettle != nil { return true }
        if presses.values.contains(where: { !$0.isAtRest }) { return true }
        if case .focus(let held)? = gesture, let follow = held.swipeFollow,
           !follow.isSettled(at: held.targetProgress, distance: 0.000_5, speed: 0.005) { return true }
        if scrollReleaseAt != nil || wheelMode == .centering { return true }
        // Auto-off free motion still needs one frame to choose a centering target.
        if wheelMode == .free && count > 1 && !(settings.spin.automatic && autoplaySuspended) { return true }
        if bodies.values.contains(where: { $0.motion == .spring || $0.motion == .returning }) { return true }
        return !dim.isSettled(at: focusedIndex == nil ? 0 : 1)
    }

    /// Steady unattended motion needs fewer frames than a catch or transition.
    /// This is a pacing hint; it never changes whether simulation must advance.
    var animationActivity: CarouselAnimationActivity {
        guard needsAnimation else { return .idle }
        if gesture == nil, scrollReleaseAt == nil, wheelMode == .free, !isEntering,
           focusedIndex == nil, bodies.isEmpty, settings.spin.automatic,
           dim.isSettled(at: 0) {
            let target = Double(spinDirection) * settings.spin.speed
            if abs(wheelVelocity - target) <= 0.05 { return .automatic }
        }
        return .interactive
    }

    /// True while the wheel is still dropping in.
    var isEntering: Bool { entrance != nil }

    /// Starts every visible card fully above the view. They fall left to right, each
    /// `entranceStagger` after its neighbour, on the same bouncy spring, and swing from
    /// `entranceSwing` into their resting tilt. Touches stay live; auto-spin ramps up meanwhile.
    func beginEntrance() {
        guard count > 0, size.width > 0, size.height > 0 else { return }
        let padding = settings.glass.padding
        let visible = CarouselGeometry.wheelIndices(position: wheelPosition, count: count, direction: stackDirection)
            .map { ($0, CarouselGeometry.wheelPose(index: $0, position: wheelPosition, count: count, size: size,
                                                   layout: settings.layout, glass: settings.glass, cardLayout: itemLayout(for: $0))) }
            .filter { $0.1.opacity > 0.001 }
        // Measured with the start tilt, which lowers one corner of each card.
        let lowest = visible.map { card -> Double in
            var start = card.1
            start.angle += Self.entranceSwing
            return Double(CarouselGeometry.outerBounds(pose: start, padding: padding).maxY)
        }.max() ?? 0
        var delays: [Int: Double] = [:]
        for (rank, card) in visible.sorted(by: { $0.1.x < $1.1.x }).enumerated() {
            delays[card.0] = Double(rank) * Self.entranceStagger
        }
        // A card that comes into view during the drop follows the last one.
        entrance = Entrance(drop: lowest + 24, delays: delays,
                            lateDelay: Double(visible.count) * Self.entranceStagger)
    }

    /// The host may schedule one idle wake-up for legacy autoplay while the
    /// display link sleeps. Pauses do not count toward this interval.
    var autoplayDelay: Double? {
        guard canAutoplay, autoplayInterval > 0 else { return nil }
        return max(0, autoplayInterval - autoplayElapsed)
    }

    private enum WheelMode { case free, held, centering, resting }
    private enum BodyMotion { case held, spring, focused, returning }
    private enum ReturnMotion { case configured, horizontal }
    private struct Body {
        var index: Int
        var pose: CarouselPose
        var velocity = CarouselPoseVelocity()
        /// The front orientation this selection came from, retained through catches.
        var selectionFrontTurn: Double = 0
        /// A physical tap's side: the selection turns +π (right edge away) or −π from its front.
        /// 0 keeps the default.
        var flipSide: Double = 0
        /// Drawn unturned, as with rotation off: a card swiped while swipes do not turn cards.
        /// Cleared when a tap selects it or it is deselected, so those still turn.
        var turnHidden = false
        var motion: BodyMotion = .held
        var response: Double = 0.46
        var damping: Double = 0.72
        // Captured at transition start; live controls never retune an active card.
        var transition: CarouselPoseTransition?
        var returnMotion: ReturnMotion = .configured
        var returnPose = CarouselPose(x: 0, y: 0, height: 0, promotion: 0)
        var returnVelocity = CarouselPoseVelocity()
        var target: CarouselPose?
        var slotVelocity = CarouselPoseVelocity()
        var relativeSlot: Double = 0
        var order: Int = 0
    }
    private struct WheelGesture {
        var start: CGPoint
        var startedAt: Double
        var position: Double
        var spacing: Double
        var hitIndex: Int?
        var originPose: CarouselPose?
        var tuning: CarouselConfiguration.Focus
        var initialVelocity: Double
        var brakingElapsed: Double = 0
        var isDragging = false
        var dragOrigin: CGPoint?
        var estimator = CarouselVelocityEstimator()
        var distance: Double = 0
        /// Where a physical tap pressed the card, card-local ±1 (+x right, +y down).
        var lever: CGPoint?
    }
    private struct FocusSample {
        var time: Double
        var point: CGPoint
        var wheelPosition: Double?
        var poses: [Int: CarouselPose]
        /// The finger's swipe progress, for a Wave swipe's release speed.
        var targetProgress: Double
    }
    private struct Correction {
        var pose: CarouselPose
        var presence: Double
        /// A returning neighbor keeps its caught offset while a swipe reverses.
        var slotOffset: CarouselPose? = nil
    }
    private struct FocusGesture {
        var index: Int
        var slot: Double
        var position: Double
        var pageWidth: Double
        var origin: CarouselPose
        var start: CGPoint
        var point: CGPoint
        var lever: CGPoint
        var grabPadding: Double
        var tuning: CarouselConfiguration.Focus
        var resumeResponse: Double
        var resumeDamping: Double
        var resumeTransition: CarouselPoseTransition?
        var resumeWheelTransition: CarouselAnimationTrack?
        var resumesHorizontalHandoff = false
        var startedAt: Double
        var lastTime: Double
        var background: Bool
        var axis: CarouselGestureAxis?
        var axisOrigin: CGPoint?
        var dx: Double = 0
        var dy: Double = 0
        var progress: Double = 0
        /// Where the finger puts a swipe's progress. A Wave swipe's shown `progress`
        /// trails it on `swipeFollow`; otherwise they are equal.
        var targetProgress: Double = 0
        var swipeFollow: CarouselWaveValue?
        var neighbor: Int?
        var neighborDirection: Int?
        var corrections: [Int: Correction] = [:]
        // A caught neighbor may overshoot its front. Keep its chosen back winding
        // through reversals instead of choosing another half-turn at the front.
        var focusedTurns: [Int: Double] = [:]
        var distance: Double = 0
        var samples: [FocusSample] = []
        // Deferred catch: running animations continue until the axis is decided,
        // a hold outlasts `focusCatchDelay`, or the touch selects another card.
        var hitPose: CarouselPose?
        var caught = false
        var pendingElapsed: Double = 0
        var driving = false
        var wheelHeld = true
        var brake: FocusBrake?
        /// Set once a second finger joins; the gesture then never dismisses.
        var pinch: CardPinch?
    }
    /// A held card and the wheel decelerate from their caught on-screen velocity,
    /// the same quadratic brake as a soft wheel catch.
    private struct FocusBrake {
        var pose: CarouselPose
        var velocity: CarouselPoseVelocity
        var position: Double
        var wheelVelocity: Double
        var elapsed: Double = 0
    }
    /// Fingers scaling and rotating the selected card around their centroid, with the
    /// companion's Wave manipulation. The x/y/scale/angle values are what is shown: glued,
    /// they take the target directly; otherwise they trail it on Wave's follow spring.
    private struct CardPinch {
        static let follow = CarouselWaveSpring(response: 0.26, damping: 0.8)
        var manipulation = CarouselManipulation()
        var points: [CGPoint]
        /// The focused pose the offset and scale are measured from.
        var rest: CarouselPose
        /// Promotion, turn and shape stay as they were caught until release.
        var held: CarouselPose
        var follows: Bool
        var x: CarouselWaveValue
        var y: CarouselWaveValue
        var scale: CarouselWaveValue
        var angle: CarouselWaveValue

        var targetCenter: CGPoint {
            CGPoint(x: rest.x + Double(manipulation.offset.x), y: rest.y + Double(manipulation.offset.y))
        }

        var target: CarouselPose {
            var pose = held
            pose.x = Double(targetCenter.x)
            pose.y = Double(targetCenter.y)
            pose.height = rest.height * manipulation.scale
            pose.angle = manipulation.rotation
            return pose
        }

        var followPose: CarouselPose {
            var pose = held
            pose.x = x.value
            pose.y = y.value
            pose.height = rest.height * scale.value
            pose.angle = angle.value
            return pose
        }

        var followVelocity: CarouselPoseVelocity {
            CarouselPoseVelocity(x: x.velocity, y: y.velocity, height: rest.height * scale.velocity,
                                 angle: angle.velocity)
        }

        var isFollowing: Bool {
            let target = target
            return !(x.isSettled(at: target.x) && y.isSettled(at: target.y) &&
                scale.isSettled(at: manipulation.scale, distance: 0.001, speed: 0.005) &&
                angle.isSettled(at: target.angle, distance: 0.001, speed: 0.01))
        }

        /// Glued channels take the target at once.
        mutating func snapGlued() {
            guard !follows else { return }
            let target = target
            x.snap(to: target.x)
            y.snap(to: target.y)
            scale.snap(to: manipulation.scale)
            angle.snap(to: target.angle)
        }

        mutating func advanceFollow(by seconds: Double) {
            guard follows else { snapGlued(); return }
            let target = target
            x.advance(by: seconds, target: target.x, spring: Self.follow)
            y.advance(by: seconds, target: target.y, spring: Self.follow)
            scale.advance(by: seconds, target: manipulation.scale, spring: Self.follow)
            angle.advance(by: seconds, target: target.angle, spring: Self.follow)
            if x.isSettled(at: target.x) { x.snap(to: target.x) }
            if y.isSettled(at: target.y) { y.snap(to: target.y) }
            if scale.isSettled(at: manipulation.scale, distance: 0.001, speed: 0.005) { scale.snap(to: manipulation.scale) }
            if angle.isSettled(at: target.angle, distance: 0.001, speed: 0.01) { angle.snap(to: target.angle) }
        }
    }
    /// A released Wave swipe: its progress keeps the drag's speed into Wave's return spring
    /// and keeps placing every card through the drag's mapping until rest.
    private struct SwipeSettle {
        var held: FocusGesture
        var progress: CarouselWaveValue
        var target: Double
        var spring: CarouselWaveSpring
        var destination: Int
        /// The side the swipe pages toward; progress never crosses to the other neighbour.
        var side: Double
    }
    /// A wheel card pressed where the finger landed: the spot tilts into the screen on a
    /// quick Wave spring while held, then springs back out once released.
    private struct CardPress {
        /// The press at touch-down; a resting finger deepens it (`depth`).
        var baseX: Double
        var baseY: Double
        /// The share of its size the whole card sinks while pressed.
        var baseSink: Double
        var heldTime: Double = 0
        var x = CarouselWaveValue(value: 0)
        var y = CarouselWaveValue(value: 0)
        var sink = CarouselWaveValue(value: 0)
        var pressed = true

        var depth: Double { CarouselEngine.pressDepth(after: heldTime) }
        var targetX: Double { pressed ? baseX * depth : 0 }
        var targetY: Double { pressed ? baseY * depth : 0 }
        var targetSink: Double { pressed ? baseSink * depth : 0 }

        /// A held press keeps sinking, so it is never at rest.
        var isAtRest: Bool {
            !pressed && x.isSettled(at: 0, distance: 0.000_5, speed: 0.005) &&
                y.isSettled(at: 0, distance: 0.000_5, speed: 0.005) &&
                sink.isSettled(at: 0, distance: 0.000_1, speed: 0.001)
        }
    }
    private enum Gesture { case wheel(WheelGesture), focus(FocusGesture) }

    private var settings: CarouselConfiguration
    private var wheelMode: WheelMode = .free
    private var wheelTarget: Double?
    private var wheelResponse = 0.42
    private var wheelDamping = 0.78
    private var wheelTransition: CarouselAnimationTrack?
    private var wheelCenteringIsHandoff = false
    private var focusSlot: Double = 0
    private var bodies: [Int: Body] = [:]
    private var sequence = 0
    private var gesture: Gesture?
    private var swipeSettle: SwipeSettle?
    private var presses: [Int: CardPress] = [:]
    /// A selection changed by a swipe that does not turn cards plays no turn haptic.
    private var silentSelection = false
    private var dim = CarouselSpring(value: 0, response: 0.30, damping: 1)
    /// The drop-in entrance. Each card follows the onboarding landing wheel's spring
    /// (response 0.5, damping 0.65: about 7% overshoot, settled near 0.85 s) after its delay.
    private struct Entrance {
        var drop: Double
        var elapsed: Double = 0
        var delays: [Int: Double]
        /// For cards that come into view during the drop: they fall after the last one.
        var lateDelay: Double
    }
    private var entrance: Entrance?
    /// Time between neighbouring cards starting to fall, left to right.
    static let entranceStagger = 0.06
    /// Cards start this far from their resting tilt (counter-clockwise) and swing into it.
    static let entranceSwing = -7 * Double.pi / 180
    private var clock: Double = 0
    private var scrollReleaseAt: Double?
    private var autoplayElapsed: Double = 0
    private var reportedIndex: Int?
    private var usesDisplayedReporting = false
    /// Wheel cards stack by travel: +1 while the position increases (cards move left and
    /// arrive from the right). Arriving cards are drawn above the cards they pass.
    private(set) var stackDirection = 1
    /// A centering spring keeps the direction it set out in, so its overshoot never
    /// reverses the stacking.
    private var centeringDirection: Int?
    /// Below this wheel speed (cards per second) the stacking direction is kept.
    static let stackReversalSpeed = 0.15
    /// A physical tap sinks the whole card by this share of its size per 20° of tilt.
    static let pressSink = 0.05
    /// Taps nearer the middle than this share of the half-width keep the default flip side.
    static let flipSideDeadZone = 0.15
    /// The companion's springs: it follows on 0.26/0.8 and lets go on 0.8/0.68.
    private static let pressYield = CarouselWaveSpring(response: 0.26, damping: 0.8)
    private static let pressRelease = CarouselWaveSpring(response: 0.8, damping: 0.68)
    /// A resting finger keeps pressing at this rate (per second of the touch-down press),
    /// through the companion's soft limit: ever more slowly, with no ceiling.
    private static let pressGrowth = 0.6
    private static let pressSoftness = 0.4

    static func pressDepth(after heldTime: Double) -> Double {
        1 + CarouselManipulation.soften(pressGrowth * max(0, heldTime), limits: 0...0, softness: pressSoftness)
    }
    private static let catchDuration = 0.08
    /// A focused touch that has not chosen an axis by then starts a soft catch.
    /// Longer than a fast swipe needs to travel the 8-point axis lock.
    private static let focusCatchDelay = 0.05
    private static let wheelDragThreshold = 6.0

    init(count: Int, configuration: CarouselConfiguration) {
        self.count = max(0, count)
        settings = configuration.validated
        if count <= 1 || !settings.spin.automatic { wheelMode = .resting }
    }

    func replaceImages(count: Int) {
        self.count = max(0, count)
        gesture = nil
        swipeSettle = nil
        presses.removeAll()
        focusedIndex = nil
        bodies.removeAll()
        displayedFrame = nil
        reportedIndex = nil
        dim.value = 0
        dim.velocity = 0
        wheelTarget = nil
        wheelTransition = nil
        scrollReleaseAt = nil
        autoplayElapsed = 0
        wheelPosition = count > 0 ? Double(CarouselGeometry.wrappedIndex(index, count: count)) : 0
        if count <= 1 { wheelVelocity = 0 }
        wheelMode = count <= 1 ? .resting : .free
        stackDirection = spinDirection
        centeringDirection = nil
        entrance = nil
    }

    func advance(by seconds: Double) {
        guard seconds.isFinite, seconds > 0, count > 0 else { return }
        // A deferred catch lands exactly at its delay, independent of frame rate.
        if case .focus(let held)? = gesture, !held.caught, !held.background {
            let remaining = Self.focusCatchDelay - held.pendingElapsed
            if remaining > 0, seconds > remaining {
                advance(by: remaining)
                advance(by: seconds - remaining)
                return
            }
        }
        clock += seconds
        var wheelSeconds = seconds
        if let deadline = scrollReleaseAt, clock >= deadline {
            wheelSeconds = min(seconds, max(0, clock - deadline))
            scrollReleaseAt = nil
            wheelVelocity = 0 // OS scroll momentum was already delivered as movement.
            wheelMode = .free
        }
        advanceFocusBrake(by: seconds)
        advanceWheel(by: wheelSeconds)
        advancePinchFollow(by: seconds)
        advanceSwipeFollow(by: seconds)
        advanceSwipeSettle(by: seconds)
        advancePresses(by: seconds)
        advanceBodies(by: seconds)
        advancePendingFocus(by: seconds)
        let dimTarget = focusedIndex == nil ? 0.0 : 1.0
        dim.advance(by: seconds, target: dimTarget)
        if var current = entrance {
            current.elapsed += seconds
            entrance = current
            // Done once the last falling card is half a point from rest, like the onboarding
            // wheel's 0.1% snap. A card that came into view late is the last one.
            let lateCardShown = CarouselGeometry.wheelIndices(position: wheelPosition, count: count,
                                                              direction: stackDirection).contains {
                current.delays[$0] == nil && CarouselGeometry.wheelPose(index: $0, position: wheelPosition,
                    count: count, size: size, layout: settings.layout, glass: settings.glass, cardLayout: itemLayout(for: $0)).opacity > 0.001
            }
            let last = entranceShare(delay: lateCardShown ? current.lateDelay : current.delays.values.max() ?? 0)
            if abs(last.share) * current.drop <= 0.5, abs(last.rate) * current.drop <= 5 {
                entrance = nil
            }
        }
        if dim.isSettled(at: dimTarget) { dim.value = dimTarget; dim.velocity = 0 }
        if canAutoplay && autoplayInterval > 0 {
            autoplayElapsed += seconds
            if autoplayElapsed >= autoplayInterval { autoplayElapsed = 0; next() }
        } else {
            autoplayElapsed = 0
        }
        updateStackDirection()
        publishIndex()
    }

    /// Idle timer wake, kept separate from animation time so a sleeping display
    /// link never integrates elapsed wall time or advances springs on resume.
    func advanceAutoplay(by seconds: Double) {
        guard seconds.isFinite, seconds > 0, canAutoplay else { return }
        autoplayElapsed += seconds
        if autoplayInterval > 0 && autoplayElapsed >= autoplayInterval {
            autoplayElapsed = 0
            next()
        }
    }

    func frame() -> CarouselFrame {
        var wheel: [CarouselRenderedCard] = []
        let sorted = CarouselGeometry.wheelIndices(position: wheelPosition, count: count, direction: stackDirection)
        var wheelDepthKeys: [Int: Double] = [:]
        if settings.card3D.isEnabled && settings.card3D.sceneDepth && !settings.usesNativeGlass {
            wheelDepthKeys = Dictionary(uniqueKeysWithValues: sorted.map { ($0, stackKey($0)) })
            for (index, body) in bodies {
                wheelDepthKeys[index] = body.motion == .returning ? returningSceneKey(body) : stackKey(index)
            }
        }
        if count > 0 {
            for index in sorted where bodies[index] == nil {
                let pose = wheelPose(index)
                if pose.opacity > 0.001 { wheel.append(CarouselRenderedCard(index: index, pose: pose)) }
            }
        }
        // Paging keeps the original owner until release; its neighbor leads after halfway.
        // A released Wave swipe keeps the same order until it rests.
        var swipeOwner: Int?
        var swipeNeighbor: Int?
        var neighborIsInFront = false
        if case .focus(let held)? = gesture, pagesHorizontally(held) {
            swipeOwner = held.index
            swipeNeighbor = held.neighbor
            neighborIsInFront = abs(held.progress) > 0.5
        } else if let settle = swipeSettle {
            swipeOwner = settle.held.index
            swipeNeighbor = settle.held.neighbor
            neighborIsInFront = abs(settle.held.progress) > 0.5
        }
        func rank(_ index: Int) -> Int {
            if index == swipeNeighbor { return neighborIsInFront ? 3 : 1 }
            if index == swipeOwner { return 2 }
            return index == focusedIndex ? 2 : 0
        }
        var promoted = bodies.values.sorted {
            if rank($0.index) != rank($1.index) { return rank($0.index) < rank($1.index) }
            return $0.order < $1.order
        }.compactMap { body -> CarouselRenderedCard? in
            var pose = body.pose
            pose.aspect = aspect(for: body.index)
            pose.height = max(0, pose.height)
            // Keep the spring's overshoot for rotation and scene elevation. Only
            // opacity is a bounded blend; clipping the pose stops the flip early.
            pose.promotion = pose.promotion.isFinite ? max(0, pose.promotion) : 0
            let opacityPromotion = min(1, pose.promotion)
            pose.opacity = wheelPose(body.index).opacity * (1 - opacityPromotion) + opacityPromotion
            guard pose.height > 0, pose.opacity > 0.001 else { return nil }
            // Both faces are the same card: turning changes neither its size nor its shape.
            let frontRemainder = body.pose.turn.remainder(dividingBy: 2 * .pi)
            let restingFront = abs(frontRemainder) < 0.0005 && abs(body.velocity.turn) < 0.01
            pose.turn = rotatesSelectedCard && !body.turnHidden && body.pose.turn.isFinite && !restingFront ?
                body.pose.turn : 0
            // A docking card joins the wheel below the cards ahead of it in travel order.
            let key = stackKey(body.index)
            let occluders = wheel.filter { stackKey($0.index) > key + 0.0001 }.map(\.index)
            return CarouselRenderedCard(index: body.index, pose: pose, occluderIndices: occluders,
                                        occlusion: wheelOcclusion(pose, index: body.index))
        }
        if !presses.isEmpty {
            for card in wheel.indices { applyPress(to: &wheel[card]) }
            for card in promoted.indices { applyPress(to: &promoted[card]) }
        }
        let displayed = CarouselFrame(size: size, wheel: wheel, promoted: promoted,
                             scrimOpacity: min(1, max(0, dim.value)) * 0.35,
                             position: wheelPosition, wheelVelocity: wheelVelocity,
                             poseVelocities: Dictionary(uniqueKeysWithValues: (wheel + promoted).map {
                                 ($0.index, presentationVelocity(for: $0.index) ?? CarouselPoseVelocity())
                             }), wheelCardWidth: CarouselGeometry.cardHeight(size: size, layout: settings.layout) * settings.layout.cardAspect,
                             wheelDepthKeys: wheelDepthKeys,
                             glass: .init(style: settings.effectiveGlassStyle, padding: settings.glass.padding),
                             card3D: settings.card3D)
        return CarouselGeometry.applyingSceneDepth(to: displayed)
    }

    private func stackKey(_ index: Int) -> Double {
        CarouselGeometry.stackKey(index, position: wheelPosition, count: count, direction: stackDirection)
    }

    /// A retained return crosses the loop seam without its screen pose jumping.
    /// Inverting that pose's wheel curve keeps its optical docking layer continuous,
    /// and reaches the exact wrapped wheel layer when the return residual settles.
    /// The wrapped return-slot state remains untouched for its existing motion re-seed.
    private func returningSceneKey(_ body: Body) -> Double {
        guard count > 1 else { return stackKey(body.index) }
        let spacing = CarouselGeometry.spacing(size: size, layout: settings.layout, glass: settings.glass)
        let x = body.pose.x - Double(size.width) / 2
        guard spacing.isFinite, spacing > 0, x.isFinite else { return stackKey(body.index) }
        let step = settings.layout.wheelCurve * .pi / 6
        let offset = step < 0.00001 ? x / spacing : asin(min(1, max(-1, x * step / spacing))) / step
        guard offset.isFinite else { return stackKey(body.index) }
        return min(2, max(-2, offset)) * Double(stackDirection < 0 ? -1 : 1)
    }

    /// How much the wheel cards ahead of a card off the wheel cover it: fully on its slot,
    /// not at all once it is lifted past 0.35 or half a slot width away.
    private func wheelOcclusion(_ pose: CarouselPose, index: Int) -> Double {
        let slot = wheelPose(index)
        let distance = hypot(pose.x - slot.x, pose.y - slot.y) /
            max(1, Double(slot.outerSize(padding: settings.glass.padding).width))
        return (1 - CarouselGeometry.smoothstep(0, 0.35, min(1, max(0, pose.promotion)))) *
            (1 - CarouselGeometry.smoothstep(0, 0.45, distance))
    }

    /// A card lifting off or docking onto the wheel while still partly covered by it. Its
    /// occluders depend on the stacking direction, so the direction holds until it is clear.
    private func isPartlyCoveredByWheel(_ body: Body) -> Bool {
        wheelOcclusion(body.pose, index: body.index) > 0
    }

    /// Follows the wheel's travel with a dead band, so jitter, braking and a centering
    /// overshoot keep the order. A reversal flips the wheel's stacking in one frame.
    private func updateStackDirection() {
        guard count > 1, !bodies.values.contains(where: isPartlyCoveredByWheel) else { return }
        if wheelMode == .centering {
            if let direction = centeringDirection { stackDirection = direction }
            return
        }
        if abs(wheelVelocity) >= Self.stackReversalSpeed {
            stackDirection = wheelVelocity < 0 ? -1 : 1
        } else if wheelMode == .free, gesture == nil, settings.spin.automatic {
            stackDirection = spinDirection
        }
    }

    func presentationPose(for index: Int) -> CarouselPose? {
        guard index >= 0, index < count else { return nil }
        guard var pose = bodies[index]?.pose else { return wheelPose(index) }
        pose.aspect = aspect(for: index)
        return pose
    }

    func presentationVelocity(for index: Int) -> CarouselPoseVelocity? {
        guard index >= 0, index < count else { return nil }
        return bodies[index]?.velocity ?? wheelPoseVelocity(index)
    }

    func navigate(to index: Int) {
        guard count > 0 else { return }
        let normalized = CarouselGeometry.wrappedIndex(index, count: count)
        let slot = CarouselGeometry.nearestPosition(for: normalized,
            from: displayedFrame?.position ?? wheelPosition, count: count)
        navigate(to: normalized, slot: slot)
    }

    func next() {
        guard count > 0 else { return }
        if let focusedIndex {
            navigate(to: CarouselGeometry.wrappedIndex(focusedIndex + 1, count: count), slot: focusSlot + (count > 1 ? 1 : 0))
        } else {
            let slot = wheelPosition.rounded() + (count > 1 ? 1 : 0)
            navigate(to: CarouselGeometry.wrappedIndex(Int(slot), count: count), slot: slot)
        }
    }

    func prev() {
        guard count > 0 else { return }
        if let focusedIndex {
            navigate(to: CarouselGeometry.wrappedIndex(focusedIndex - 1, count: count), slot: focusSlot - (count > 1 ? 1 : 0))
        } else {
            let slot = wheelPosition.rounded() - (count > 1 ? 1 : 0)
            navigate(to: CarouselGeometry.wrappedIndex(Int(slot), count: count), slot: slot)
        }
    }

    func captureTap(at point: CGPoint) -> CarouselTapCapture? {
        guard focusedIndex == nil else { return nil }
        let visible = displayedFrame ?? frame()
        let hit = CarouselGeometry.hitTest(point, frame: visible)
        guard !visible.promoted.contains(where: { $0.index == hit }) else { return nil }
        return CarouselTapCapture(frame: visible, hitIndex: hit, tuning: settings.focus)
    }

    func touchBegan(at point: CGPoint, time: Double, capture: CarouselTapCapture? = nil) {
        guard count > 0, size.width > 0, size.height > 0, time.isFinite else { return }
        // A cancelled Wave swipe starts settling; either way, hand any settle over first.
        if gesture != nil { cancelCurrentGesture() }
        handOffSwipeSettle()
        scrollReleaseAt = nil
        autoplayElapsed = 0
        let tapCapture = capture ?? captureTap(at: point)
        let visible = tapCapture?.frame ?? displayedFrame ?? frame()
        let hit = tapCapture.map(\.hitIndex) ?? CarouselGeometry.hitTest(point, frame: visible)
        let promotedHit = hit.flatMap { index in visible.promoted.last(where: { $0.index == index }) }
        if focusedIndex != nil {
            // Identity and grip come from the displayed frame. Motion is not rewound:
            // frames already submitted after it reach the screen regardless, so the
            // deferred catch continues from the simulated state instead.
            beginFocusGesture(at: point, time: time, hit: promotedHit, visible: visible)
            return
        } else {
            // With nothing selected, a card still returning to the wheel acts like a docked
            // one: the touch holds the wheel, a drag in any direction moves the wheel, and
            // only a quick tap selects the card, so it cannot be thrown again and again.
            // The view does not fence such touches, so they continue from the simulated
            // state instead of the displayed one.
            if promotedHit == nil { catchDisplayedPoses(visible) }
            wheelMode = .held
            wheelTarget = nil
            wheelTransition = nil
            let tuning = tapCapture?.tuning ?? settings.focus
            let initialVelocity = promotedHit == nil ? visible.wheelVelocity : wheelVelocity
            wheelVelocity = tuning.tapSelectionMode == .softCatch ? initialVelocity : 0
            var held = WheelGesture(start: point, startedAt: time, position: wheelPosition,
                                    spacing: max(1, CarouselGeometry.spacing(size: size, layout: settings.layout, glass: settings.glass)),
                                    hitIndex: hit,
                                    originPose: hit.flatMap { index in
                                        visible.wheel.first(where: { $0.index == index })?.pose
                                    }, tuning: tuning, initialVelocity: initialVelocity)
            held.estimator.add(point, at: time)
            if tuning.physicalTap, let index = hit,
               let shown = promotedHit?.pose ?? visible.wheel.first(where: { $0.index == index })?.pose {
                let lever = CarouselInput.lever(at: point, pose: shown, padding: visible.glass.padding, limit: 1)
                held.lever = lever
                beginPress(index, lever: lever, tilt: tuning.physicalTapTilt * .pi / 180)
            }
            gesture = .wheel(held)
        }
        // Catching the wheel changes its attachment speed immediately. Preserve
        // other cards' absolute momentum when re-seeding their residual springs.
        rebaseReturningAttachments()
    }

    func touchMoved(at point: CGPoint, time: Double) {
        guard time.isFinite, let current = gesture else { return }
        switch current {
        case .wheel(var held):
            let dx = Double(point.x - held.start.x), dy = Double(point.y - held.start.y)
            held.distance = max(held.distance, hypot(dx, dy))
            held.estimator.add(point, at: time)
            if !held.isDragging, held.distance >= Self.wheelDragThreshold {
                held.isDragging = true
                releasePresses()
                held.position = wheelPosition
                let distance = max(Self.wheelDragThreshold, hypot(dx, dy))
                held.dragOrigin = CGPoint(x: held.start.x + dx * Self.wheelDragThreshold / distance,
                                          y: held.start.y + dy * Self.wheelDragThreshold / distance)
            }
            if count > 1, held.isDragging, let origin = held.dragOrigin {
                wheelPosition = held.position - Double(point.x - origin.x) / held.spacing
                wheelVelocity = max(-8, min(8, -Double(held.estimator.velocity(at: time, cap: .infinity).x) / held.spacing))
            }
            gesture = .wheel(held)
        case .focus(var held):
            guard time >= held.lastTime else { return }
            // A pinch follows its fingers through `pinchMoved` only.
            if held.pinch != nil { return }
            held.point = point
            held.dx = Double(point.x - held.start.x)
            held.dy = Double(point.y - held.start.y)
            held.distance = max(held.distance, hypot(held.dx, held.dy))
            if held.axis == nil,
               let axis = CarouselGestureDecision.axis(for: CGPoint(x: held.dx, y: held.dy)) {
                held.axis = axis
                held.axisOrigin = point
                // A dismissed card on its way back responds only to a tap; dragging
                // it does nothing instead of grabbing and throwing it again.
                if let focused = focusedIndex, held.index != focused, isDismissedReturn(held.index) {
                    held.background = true
                }
                // A page takes over on the first movement after axis lock. Free drags
                // grip immediately, preserving the dismissal gesture when paging is off.
                if !held.background, !pagesHorizontally(held) { takeOverFocusGesture(&held) }
            } else if !held.background, held.axis != nil, !held.driving, point != held.axisOrigin {
                takeOverFocusGesture(&held)
            }
            let delta = time - held.lastTime
            let previous = wheelPosition
            if !held.background, held.driving { updateHeldCard(&held, seconds: delta) }
            if held.driving, pagesHorizontally(held), held.swipeFollow == nil, delta > 0 {
                wheelVelocity = (wheelPosition - previous) / delta
            }
            held.lastTime = time
            addSample(to: &held, at: time)
            gesture = .focus(held)
        }
        updateStackDirection()
        publishIndex()
    }

    func touchEnded(at point: CGPoint, time: Double, cancelled: Bool) {
        guard gesture != nil else { return }
        if cancelled { cancelCurrentGesture(); return }
        // A final stationary sample correctly removes stale velocity after a hold.
        touchMoved(at: point, time: time)
        guard let latest = gesture else { return }
        gesture = nil
        switch latest {
        case .wheel(let held):
            releasePresses()
            let tapped = CarouselGestureDecision.isQuickTap(distance: held.distance, duration: time - held.startedAt)
            if tapped, let index = held.hitIndex {
                promote(index, from: held)
            } else {
                wheelVelocity = count > 1 && held.isDragging ?
                    max(-8, min(8, -Double(held.estimator.velocity(at: time, cap: .infinity).x) / held.spacing)) : 0
                if abs(wheelVelocity) > 0.05 { spinDirection = wheelVelocity < 0 ? -1 : 1 }
                wheelMode = count > 1 ? .free : .resting
            }
        case .focus(let held):
            finishFocusGesture(held, at: time)
        }
        updateStackDirection()
        publishIndex()
    }

    /// A second finger joins a selected-card touch. `points` lists every finger in
    /// arrival order. Refused while paging, for other cards, or with pinching disabled;
    /// the view then keeps ignoring the extra finger.
    func beginPinch(points: [CGPoint], time: Double) -> Bool {
        guard points.count > 1, time.isFinite, case .focus(var held)? = gesture, held.pinch == nil,
              held.tuning.pinch.isEnabled, let focused = focusedIndex, held.index == focused,
              !pagesHorizontally(held) else { return false }
        if held.background {
            // Fingers placed around the card still take it when their centroid is on it.
            let visible = displayedFrame ?? frame()
            guard CarouselGeometry.hitTest(CarouselTouchGeometry.centroid(points), frame: visible) == focused
            else { return false }
            held.background = false
        }
        if !held.caught { catchFocusGesture(&held, brake: false) }
        held.driving = true
        held.position = wheelPosition
        held.slot = focusSlot
        // Release rates measure the gesture, not the animation it interrupted.
        for sample in held.samples.indices {
            held.samples[sample].poses[held.index] = nil
            held.samples[sample].wheelPosition = nil
        }
        let body = bodyFor(held.index)
        let rest = focusedPose(for: held.index)
        let pose = body.pose
        let restHeight = max(1, rest.height)
        var pinch = CardPinch(points: points, rest: rest, held: pose, follows: held.tuning.pinch.followsWithSpring,
                              x: CarouselWaveValue(value: pose.x, velocity: body.velocity.x),
                              y: CarouselWaveValue(value: pose.y, velocity: body.velocity.y),
                              scale: CarouselWaveValue(value: pose.height / restHeight,
                                                       velocity: body.velocity.height / restHeight),
                              angle: CarouselWaveValue(value: pose.angle, velocity: body.velocity.angle))
        pinch.rest.height = restHeight
        pinch.manipulation.begin(offset: CGPoint(x: pose.x - rest.x, y: pose.y - rest.y),
                                 scale: pose.height / restHeight, rotation: pose.angle,
                                 position: CGPoint(x: pose.x, y: pose.y), at: time)
        held.pinch = pinch
        held.point = CarouselTouchGeometry.centroid(points)
        held.lastTime = max(held.lastTime, time)
        addSample(to: &held, at: time)
        gesture = .focus(held)
        return true
    }

    /// Every pinching finger's location, in the same order. A finger joining re-measures
    /// from the new set without moving the card. Lifting any finger ends the pinch: the
    /// view then calls `touchEnded`, and the card springs back to rest.
    func pinchMoved(points: [CGPoint], time: Double) {
        guard time.isFinite, points.count > 1, case .focus(var held)? = gesture, var pinch = held.pinch,
              time >= held.lastTime else { return }
        if points.count == pinch.points.count {
            // The companion's exact step: scale and rotate around the fingers, then follow them.
            let delta = CarouselTouchGeometry.delta(from: pinch.points, to: points)
            pinch.manipulation.apply(translation: delta.translation, scaleFactor: delta.scale,
                                     rotationDelta: delta.rotation, pivot: CarouselTouchGeometry.centroid(pinch.points),
                                     center: pinch.targetCenter)
        }
        pinch.points = points
        pinch.snapGlued()
        pinch.manipulation.record(position: pinch.targetCenter, at: time)
        held.pinch = pinch
        held.point = CarouselTouchGeometry.centroid(points)
        if !pinch.follows {
            var body = bodyFor(held.index)
            drive(&body, to: pinch.followPose, seconds: time - held.lastTime)
            bodies[held.index] = body
        }
        held.lastTime = time
        addSample(to: &held, at: time)
        gesture = .focus(held)
        updateStackDirection()
        publishIndex()
    }

    /// Scroll-wheel/trackpad momentum is direct input. No synthetic extra fling
    /// is added after the operating system's event burst finishes.
    func scroll(by delta: CGPoint, time: Double) {
        guard focusedIndex == nil, gesture == nil, count > 1 else { return }
        let spacing = max(1, CarouselGeometry.spacing(size: size, layout: settings.layout, glass: settings.glass))
        wheelPosition -= Double(delta.x) / spacing
        wheelVelocity = 0
        wheelMode = .held
        wheelTarget = nil
        wheelTransition = nil
        scrollReleaseAt = clock + 0.13
        autoplayElapsed = 0
        if abs(delta.x) / spacing > 0.0001 { spinDirection = delta.x > 0 ? -1 : 1 }
        // Scrolling zeroes the velocity; a deliberate scroll against the order reverses it,
        // unless a card is still partly covered by the wheel.
        if abs(delta.x) / spacing >= 0.001, !bodies.values.contains(where: isPartlyCoveredByWheel) {
            stackDirection = delta.x > 0 ? -1 : 1
        }
        publishIndex()
    }

    private var canAutoplay: Bool {
        count > 1 && !settings.spin.automatic && !autoplaySuspended && focusedIndex == nil && gesture == nil &&
            bodies.isEmpty && wheelMode == .resting && scrollReleaseAt == nil && !isEntering
    }

    private func advanceWheel(by seconds: Double) {
        guard count > 1 else { wheelPosition = 0; wheelVelocity = 0; wheelMode = .resting; return }
        switch wheelMode {
        case .held:
            if case .wheel(var held)? = gesture, !held.isDragging,
               held.tuning.tapSelectionMode == .softCatch {
                held.brakingElapsed = min(Self.catchDuration, held.brakingElapsed + seconds)
                let time = held.brakingElapsed
                let duration = Self.catchDuration
                let remaining = max(0, 1 - time / duration)
                // The velocity and its derivative reach zero together. Integrate
                // this quadratic brake exactly, independently of frame rate.
                wheelPosition = held.position + held.initialVelocity *
                    (time - time * time / duration + time * time * time / (3 * duration * duration))
                wheelVelocity = held.initialVelocity * remaining * remaining
                gesture = .wheel(held)
            }
        case .resting:
            break
        case .centering:
            guard let target = wheelTarget else { wheelMode = .free; return }
            if var transition = wheelTransition {
                transition.advance(by: seconds)
                wheelPosition = transition.value
                wheelVelocity = transition.velocity
                wheelTransition = transition
                if transition.isSettled(tolerance: 0.0001, velocityTolerance: 0.001) {
                    wheelPosition = target
                    wheelVelocity = 0
                    wheelTarget = nil
                    wheelTransition = nil
                    wheelMode = focusedIndex == nil && settings.spin.automatic ? .free : .resting
                }
                return
            }
            var spring = CarouselSpring(value: wheelPosition, velocity: wheelVelocity,
                                        response: wheelResponse, damping: wheelDamping)
            spring.advance(by: seconds, target: target)
            wheelPosition = spring.value
            wheelVelocity = spring.velocity
            if spring.isSettled(at: target, tolerance: 0.0001, velocityTolerance: 0.001) {
                wheelPosition = target
                wheelVelocity = 0
                wheelTarget = nil
                wheelMode = focusedIndex == nil && settings.spin.automatic ? .free : .resting
            }
        case .free:
            guard focusedIndex == nil else { wheelVelocity = 0; wheelMode = .resting; return }
            // Keep the anchor and momentum while a companion is held/settling.
            // Resume from this state on the same clock, with no elapsed-time catch-up.
            guard !(settings.spin.automatic && autoplaySuspended) else { return }
            let target = settings.spin.automatic ? Double(spinDirection) * settings.spin.speed : 0
            let rate = log(20) / settings.spin.settlingTime
            let decay = exp(-rate * seconds)
            wheelPosition += target * seconds + (wheelVelocity - target) * (1 - decay) / rate
            wheelVelocity = target + (wheelVelocity - target) * decay
            if !settings.spin.automatic && abs(wheelVelocity) < 0.05 {
                centerWheel(at: wheelPosition.rounded(), response: 0.42, damping: 1)
            }
        }
    }

    private func advanceBodies(by seconds: Double) {
        for index in Array(bodies.keys) {
            guard var body = bodies[index] else { continue }
            if body.motion == .spring {
                var target = focusedTarget(for: body.index, near: body.pose.turn)
                target.angle = nearestAngle(target.angle, to: body.pose.angle)
                let next: (pose: CarouselPose, velocity: CarouselPoseVelocity, settled: Bool)
                if var transition = body.transition {
                    next = transition.advance(by: seconds)
                    body.transition = transition
                } else {
                    next = stepPose(body.pose, velocity: body.velocity, toward: target,
                                    response: body.response, damping: body.damping, seconds: seconds)
                }
                body.pose = next.pose
                body.velocity = next.velocity
                if next.settled {
                    body.motion = .focused
                    body.transition = nil
                }
            } else if body.motion == .returning, let oldTarget = body.target {
                var target = wheelPose(index)
                target.turn = oldTarget.turn
                target.angle = nearestAngle(target.angle, to: oldTarget.angle)
                let relative = CarouselGeometry.relative(index, position: wheelPosition, count: count)
                let crossedSeam = abs(relative - body.relativeSlot) > Double(count) / 2
                let targetVelocity = wheelPoseVelocity(index)
                if crossedSeam {
                    // Past the seam the wheel shows this card on its far side. A card that
                    // is offscreen or faint there (under 15% visible) docks instead of
                    // re-seeding a residual that would fly it across the screen as a ghost.
                    // Two-card decks retain visible returns at their side-slot seam. Once
                    // fully invisible, they dock too: a tiny centering bounce must not
                    // create another screen-wide residual for a card no longer drawn.
                    let promotion = min(1, max(0, body.pose.promotion))
                    let opacity = target.opacity * (1 - promotion) + promotion
                    let previousOpacity = oldTarget.opacity * (1 - promotion) + promotion
                    let onscreen = CarouselGeometry.outerBounds(pose: body.pose, padding: settings.glass.padding)
                        .intersects(CGRect(origin: .zero, size: size))
                    if (count == 2 && opacity <= 0.001 && previousOpacity <= 0.001) ||
                       (count > 2 && (!onscreen || opacity < 0.15)) {
                        bodies.removeValue(forKey: index)
                        continue
                    }
                    reseedReturn(&body, target: target, slotVelocity: targetVelocity)
                }
                let next: (pose: CarouselPose, velocity: CarouselPoseVelocity, settled: Bool)
                if body.returnMotion == .horizontal, body.transition == nil {
                    next = stepPose(body.returnPose, velocity: body.returnVelocity, toward: zeroPose,
                                    response: 0.42, damping: 0.78, seconds: seconds)
                } else if var transition = body.transition {
                    next = transition.advance(by: seconds)
                    body.transition = transition
                } else {
                    continue
                }
                if body.returnMotion == .horizontal {
                    body.returnPose = next.pose
                    body.returnVelocity = next.velocity
                }
                body.pose = add(target, next.pose)
                body.velocity = add(targetVelocity, next.velocity)
                body.target = target
                body.slotVelocity = targetVelocity
                body.relativeSlot = relative
                if next.settled { bodies.removeValue(forKey: index); continue }
            }
            bodies[index] = body
        }
    }

    private func navigate(to index: Int, slot: Double) {
        handOffSwipeSettle()
        // Controller calls are not fenced either: continue from the simulated state
        // the queued frames end on rather than stepping back to the displayed one.
        if focusedIndex != nil, bodies[index] == nil { bodies[index] = bodyFor(index) }
        gesture = nil
        scrollReleaseAt = nil
        autoplayElapsed = 0
        if focusedIndex != nil {
            settleFocus(index, slot: slot, response: 0.42, damping: 0.78, velocity: wheelVelocity,
                        horizontalReturns: true, handoffConfiguration: handoffConfiguration(for: settings.focus))
        } else {
            centerWheel(at: slot, response: 0.42, damping: 0.78)
        }
        rebaseReturningAttachments()
    }

    private func centerWheel(at slot: Double, response: Double, damping: Double) {
        wheelCenteringIsHandoff = false
        wheelTransition = nil
        wheelTarget = slot
        wheelResponse = response
        wheelDamping = damping
        wheelMode = .centering
        captureCenteringDirection(toward: slot)
    }

    private func captureCenteringDirection(toward slot: Double) {
        let travel = slot - wheelPosition
        centeringDirection = abs(travel) > 0.05 ? (travel < 0 ? -1 : 1) : nil
        updateStackDirection()
    }

    private func centerWheel(at slot: Double, configuration: CarouselConfiguration.Transition,
                             preserveMomentum: Bool, continuation: CarouselAnimationTrack? = nil) {
        wheelCenteringIsHandoff = false
        var transition = continuation ?? CarouselAnimationTrack(value: wheelPosition, velocity: wheelVelocity,
            target: slot, animation: configuration.animation, duration: configuration.travelDuration,
            bounce: configuration.bounce, preserveMomentum: preserveMomentum)
        if continuation != nil {
            transition.reseed(value: wheelPosition, velocity: wheelVelocity, target: slot)
        }
        wheelTransition = transition
        wheelTarget = slot
        wheelMode = .centering
        captureCenteringDirection(toward: slot)
    }

    private func promote(_ index: Int, from held: WheelGesture) {
        guard count > 0 else { return }
        let mode = held.tuning.tapSelectionMode
        let configuration = mode == .reference ?
            CarouselConfiguration.Transition(travelDuration: 0.20, animation: .easeInOut,
                                            animationDuration: 0.20, bounce: 0) : held.tuning.selection
        let preserveMomentum = mode == .softCatch
        if !preserveMomentum { wheelVelocity = 0 }
        focusedIndex = index
        focusSlot = CarouselGeometry.nearestPosition(for: index, from: wheelPosition, count: count)
        var body = bodyFor(index)
        body.turnHidden = false
        // A physical tap turns the card toward the side it was pressed.
        if held.tuning.physicalTap, let lever = held.lever, abs(Double(lever.x)) >= Self.flipSideDeadZone {
            body.flipSide = lever.x > 0 ? 1 : -1
        } else {
            body.flipSide = 0
        }
        if var origin = held.originPose {
            // Promotion and wheel centering share one caught origin. Soft catch
            // adds the slot's actual braking travel rather than a stale frame.
            origin.turn = rotatesSelectedCard ? nearestAngle(origin.turn, to: body.pose.turn) : body.pose.turn
            body.pose = add(origin, subtract(wheelPose(index), wheelPose(index, position: held.position)))
        }
        if body.motion == .returning, let target = body.target { body.selectionFrontTurn = target.turn }
        let turnVelocity = body.velocity.turn
        body.velocity = preserveMomentum ? liftVelocity(index) : CarouselPoseVelocity()
        if preserveMomentum { body.velocity.turn = turnVelocity }
        body.order = nextOrder()
        body.motion = .spring
        body.transition = CarouselPoseTransition(pose: body.pose, velocity: body.velocity,
            toward: focusedTarget(for: body.index, near: body.pose.turn, side: body.flipSide), configuration: configuration,
            preserveMomentum: preserveMomentum)
        body.target = nil
        bodies[index] = body
        let wheelConfiguration = mode == .reference ?
            CarouselConfiguration.Transition(travelDuration: 0.30, animation: .easeInOut,
                                            animationDuration: 0.30, bounce: 0) : configuration
        centerWheel(at: focusSlot, configuration: wheelConfiguration, preserveMomentum: preserveMomentum)
    }

    private func beginFocusGesture(at point: CGPoint, time: Double, hit: CarouselRenderedCard?, visible: CarouselFrame) {
        var hit = hit
        var forwarded = false
        if hit == nil, let focused = focusedIndex, let body = bodies[focused],
           bodies.values.contains(where: { $0.motion == .returning && $0.returnMotion == .horizontal }),
           CarouselGeometry.contains(point, pose: focusedPose(for: focused),
                                     frame: visible) {
            // During a handoff the gap between the cards, or the space the focused card
            // has not reached yet, belongs to it: a tap there must not dismiss focus.
            hit = CarouselRenderedCard(index: focused, pose: body.pose)
            forwarded = true
        }
        guard let index = hit?.index ?? focusedIndex else { return }
        // Touch-down records identity, grip and tuning only. The catch itself waits
        // for the axis, a hold, or a release that selects another card, so a quick
        // follow-up swipe never stalls a running handoff or centering wheel.
        let grabPadding = visible.glass.padding
        let origin = hit?.pose ?? bodyFor(index).pose
        var held = FocusGesture(index: index, slot: focusSlot, position: wheelPosition,
                                pageWidth: max(1, Double(focusedPose(for: index).outerSize(padding: settings.glass.padding).width) + 20),
                                origin: origin, start: point, point: point,
                                lever: hit == nil ? .zero : CarouselInput.lever(at: point, pose: origin, padding: grabPadding,
                                                                                limit: forwarded ? .infinity : 1),
                                grabPadding: grabPadding,
                                tuning: settings.focus, resumeResponse: 0.46, resumeDamping: 0.72,
                                resumeTransition: nil, resumeWheelTransition: nil,
                                startedAt: time, lastTime: time, background: hit == nil)
        held.hitPose = hit?.pose
        addSample(to: &held, at: time)
        gesture = .focus(held)
    }

    /// Holds the touched card and the wheel from their current simulated state.
    /// `brake` decelerates both from their current velocity instead of stopping them.
    private func catchFocusGesture(_ held: inout FocusGesture, brake: Bool, holdWheel: Bool = true) {
        let index = held.index
        let wasFocused = focusedIndex
        focusedIndex = index
        focusSlot = CarouselGeometry.nearestPosition(for: index, from: wheelPosition, count: count)
        let resumeWheelTransition = wheelTransition
        let resumesHorizontalHandoff = wheelMode == .centering && wheelCenteringIsHandoff
        let wheelSpeed = wheelVelocity
        held.wheelHeld = holdWheel
        if holdWheel {
            wheelTarget = nil
            wheelTransition = nil
            wheelMode = .held
            wheelVelocity = 0
        } else if count > 1, wheelTarget != focusSlot, abs(wheelPosition - focusSlot) > 0.0001 {
            // A card drag leaves the wheel centering, retargeted to the touched card.
            centerWheel(at: focusSlot, response: 0.42, damping: 0.78)
        }
        var body = bodyFor(index)
        // A newly selected card turns again; a swipe that takes over hides it once more.
        if wasFocused != index { body.turnHidden = false }
        let response = body.motion == .spring ? body.response : 0.46
        let damping = body.motion == .spring ? body.damping : 0.72
        let resumeTransition = body.motion == .spring ? body.transition : nil
        let speed = body.velocity
        if body.motion == .returning, let target = body.target { body.selectionFrontTurn = target.turn }
        body.velocity = CarouselPoseVelocity()
        body.motion = .held
        body.target = nil
        body.order = nextOrder()
        bodies[index] = body
        for other in Array(bodies.keys) where other != index {
            if bodies[other]?.motion != .returning { startReturn(other, configuration: held.tuning.returnToWheel) }
        }
        held.caught = true
        held.slot = focusSlot
        held.resumeResponse = response
        held.resumeDamping = damping
        held.resumeTransition = resumeTransition
        held.resumeWheelTransition = resumeWheelTransition
        held.resumesHorizontalHandoff = resumesHorizontalHandoff
        if wasFocused != index {
            held.resumeTransition = CarouselPoseTransition(pose: body.pose, velocity: CarouselPoseVelocity(),
                toward: focusedTarget(for: body.index, near: body.pose.turn), configuration: held.tuning.selection,
                preserveMomentum: true)
            held.resumeWheelTransition = nil
            held.resumesHorizontalHandoff = false
        }
        if brake {
            held.brake = FocusBrake(pose: body.pose, velocity: speed, position: wheelPosition, wheelVelocity: wheelSpeed)
            // Returning cards keep docking onto the decelerating slot.
            wheelVelocity = count > 1 ? wheelSpeed : 0
        }
        // Catching the wheel changes its attachment speed immediately. Preserve
        // other cards' absolute momentum when re-seeding their residual springs.
        rebaseReturningAttachments()
    }

    /// The swipe or drag takes over from the then-current pose and wheel position.
    private func takeOverFocusGesture(_ held: inout FocusGesture) {
        let swipe = pagesHorizontally(held)
        let hidesTurn = swipe && !held.tuning.horizontalSwipe.turnsCards
        if !held.caught {
            silentSelection = hidesTurn
            catchFocusGesture(&held, brake: false, holdWheel: swipe)
            silentSelection = false
        }
        if hidesTurn { bodies[held.index]?.turnHidden = true }
        if swipe {
            held.brake = nil
            // A Wave swipe's shown progress starts at rest where the finger takes over.
            if held.tuning.horizontalSwipe.followsWithSpring { held.swipeFollow = CarouselWaveValue(value: 0) }
        }
        held.driving = true
        held.position = wheelPosition
        held.slot = focusSlot
        guard let owner = bodies[held.index] else { return }
        // Release rates measure the gesture, not the animation it interrupted.
        for sample in held.samples.indices {
            held.samples[sample].poses[held.index] = nil
            held.samples[sample].wheelPosition = nil
        }
        if !swipe {
            // Tilt starts from the card as it is now, never the touched frame.
            held.origin = owner.pose
            if let hitPose = held.hitPose,
               hypot(owner.pose.x - hitPose.x, owner.pose.y - hitPose.y) > 1 ||
               abs(owner.pose.height - hitPose.height) > 0.5 || abs(owner.pose.angle - hitPose.angle) > 0.001 {
                // The card moved on after the frame the user touched. Grip the spot where the
                // finger landed on the card as it is now (drags follow from the lock point),
                // so the card neither snaps back nor slides under the finger.
                held.lever = CarouselInput.lever(at: held.start, pose: owner.pose, padding: held.grabPadding,
                                                 limit: .infinity)
            }
        }
        if swipe {
            held.focusedTurns[held.index] = focusedTarget(for: held.index, near: owner.pose.turn).turn
            // Measured against the lock point, so the finger's next step moves the card.
            held.corrections[held.index] = Correction(
                pose: subtract(owner.pose, horizontalPose(held.index, presence: 1, shift: 0,
                                                            focusedTurn: held.focusedTurns[held.index])), presence: 1)
        }
    }

    private func isSettlingInFocus(_ index: Int) -> Bool {
        guard let body = bodies[index] else { return false }
        if body.motion == .focused { return true }
        let target = focusedPose(for: index)
        return body.motion == .spring && abs(body.pose.x - target.x) < 6 && abs(body.pose.y - target.y) < 6 &&
            abs(body.pose.height - target.height) < 6 && body.pose.promotion > 0.97
    }

    private func isReturning(_ index: Int) -> Bool {
        guard let body = bodies[index] else { return true }
        return body.motion == .returning
    }

    /// A card sent back by a dismissal rather than leaving through a handoff.
    private func isDismissedReturn(_ index: Int) -> Bool {
        guard let body = bodies[index] else { return true }
        return body.motion == .returning && body.returnMotion == .configured
    }

    private func advancePendingFocus(by seconds: Double) {
        guard case .focus(var held)? = gesture, !held.caught, !held.background else { return }
        held.pendingElapsed += seconds
        // A returning card keeps going under a resting finger. A release can catch
        // it (a quick tap for a dismissed card); either drag axis can catch a
        // card leaving through controller navigation.
        let leaving = focusedIndex.map { held.index != $0 && isReturning(held.index) } ?? false
        // A selected card in its last few points of settling finishes under a resting
        // finger: braking that bounce and resuming it on release reads as a stutter.
        let settling = held.index == focusedIndex && isSettlingInFocus(held.index)
        if !leaving, !settling, held.pendingElapsed >= Self.focusCatchDelay - 0.000_000_1 {
            catchFocusGesture(&held, brake: true)
        }
        gesture = .focus(held)
    }

    private func advanceFocusBrake(by seconds: Double) {
        guard case .focus(var held)? = gesture, var brake = held.brake,
              brake.elapsed < Self.catchDuration else { return }
        let duration = Self.catchDuration
        brake.elapsed = min(duration, brake.elapsed + seconds)
        let t = brake.elapsed
        let travel = t - t * t / duration + t * t * t / (3 * duration * duration)
        let remaining = (1 - t / duration) * (1 - t / duration)
        // A card drag that started from a hold lets the wheel finish braking.
        if count > 1 {
            wheelPosition = brake.position + brake.wheelVelocity * travel
            wheelVelocity = brake.wheelVelocity * remaining
        }
        if !held.driving, var body = bodies[held.index] {
            body.pose = add(brake.pose, multiply(brake.velocity, by: travel))
            body.velocity = multiply(brake.velocity, by: remaining)
            bodies[held.index] = body
        }
        held.brake = brake
        gesture = .focus(held)
    }

    /// Wave's follow spring carries a pinched card toward its fingers' target.
    private func advancePinchFollow(by seconds: Double) {
        guard case .focus(var held)? = gesture, var pinch = held.pinch, pinch.follows || pinch.isFollowing
        else { return }
        pinch.advanceFollow(by: seconds)
        held.pinch = pinch
        var body = bodyFor(held.index)
        body.pose = pinch.followPose
        body.velocity = pinch.followVelocity
        body.motion = .held
        body.transition = nil
        body.target = nil
        bodies[held.index] = body
        gesture = .focus(held)
    }

    /// A pinch always ends back in focus: on the drag snap-back spring when the card
    /// followed the fingers directly, or the companion's return spring after Wave's follow.
    private func settlePinch(_ held: FocusGesture, carriesVelocity: Bool) {
        guard let pinch = held.pinch else { return }
        if var body = bodies[held.index] {
            if carriesVelocity {
                // Wave's follow throws like a companion; a glued card like a card drag.
                let release = pinch.manipulation.releaseVelocity(positionCap: pinch.follows ? 2_000 : 4_000,
                                                                 scaleCap: 3, rotationCap: 12)
                body.velocity = CarouselPoseVelocity(x: Double(release.position.x), y: Double(release.position.y),
                    height: release.scale * pinch.rest.height, angle: release.rotation)
            } else {
                body.velocity = CarouselPoseVelocity()
            }
            bodies[held.index] = body
        }
        settleFocus(held.index, slot: held.slot, response: pinch.follows ? 0.8 : 0.40,
                    damping: pinch.follows ? 0.68 : 1 - held.tuning.cardSnapBackBounce,
                    velocity: held.wheelHeld && held.brake == nil ? 0 : wheelVelocity,
                    returnConfiguration: held.tuning.returnToWheel)
    }

    /// A Wave swipe's shown progress trails the finger on Wave's follow spring; every card
    /// and the wheel are placed from it through the drag's own mapping.
    private func advanceSwipeFollow(by seconds: Double) {
        guard case .focus(var held)? = gesture, held.driving, pagesHorizontally(held),
              var follow = held.swipeFollow else { return }
        follow.advance(by: seconds, target: held.targetProgress, spring: CardPinch.follow)
        if follow.isSettled(at: held.targetProgress, distance: 0.000_5, speed: 0.005) {
            follow.snap(to: held.targetProgress)
        }
        held.swipeFollow = follow
        held.progress = follow.value
        let previous = wheelPosition
        updateHeldSwipe(&held, seconds: seconds)
        wheelVelocity = (wheelPosition - previous) / seconds
        gesture = .focus(held)
    }

    /// Releases a Wave swipe toward `direction` (0 returns to the held card). Selection moves
    /// now, as for any committed swipe; the cards keep following the swipe's mapping.
    private func startSwipeSettle(_ held: FocusGesture, direction: Int, velocity: Double) {
        let destination = CarouselGeometry.wrappedIndex(held.index + direction, count: count)
        if destination != focusedIndex { swipeChangedSelection(held.tuning) }
        keepSwipeOwnerFront(held, direction: direction)
        let side = direction != 0 ? Double(direction) : (held.progress > 0 ? 1 : held.progress < 0 ? -1 : 0)
        gesture = nil
        silentSelection = !held.tuning.horizontalSwipe.turnsCards
        focusedIndex = destination
        silentSelection = false
        focusSlot = held.slot + Double(direction)
        wheelMode = .held
        wheelTarget = nil
        wheelTransition = nil
        autoplayElapsed = 0
        swipeSettle = SwipeSettle(held: held, progress: CarouselWaveValue(value: held.progress, velocity: velocity),
            target: Double(direction),
            spring: CarouselWaveSpring(response: held.tuning.horizontalSwipe.animationDuration, damping: 0.68),
            destination: destination, side: side)
    }

    private func advanceSwipeSettle(by seconds: Double) {
        guard var settle = swipeSettle else { return }
        settle.progress.advance(by: seconds, target: settle.target, spring: settle.spring)
        let rested = settle.progress.isSettled(at: settle.target, distance: 0.000_5, speed: 0.005)
        if rested { settle.progress.snap(to: settle.target) }
        // Overshoot past the next card carries on; the swipe never shows the other neighbour.
        settle.held.progress = settle.side * max(0, settle.side * settle.progress.value)
        let previous = wheelPosition
        updateHeldSwipe(&settle.held, seconds: seconds)
        // Landing snaps the last fraction of a millimetre into place: not motion to hand on,
        // which would carry the wheel past its slot toward the other neighbour.
        wheelVelocity = rested ? 0 : (wheelPosition - previous) / seconds
        swipeSettle = settle
        if rested { handOffSwipeSettle() }
    }

    /// Hands a released Wave swipe to the ordinary focus and return motion with each card's
    /// current pose and speed: at rest it lands exactly, and any other change (a touch,
    /// navigation, a layout change) continues from the swipe without a jump.
    private func handOffSwipeSettle() {
        guard let settle = swipeSettle else { return }
        swipeSettle = nil
        preserveHorizontalStacking(settle.held)
        settleFocus(settle.destination, slot: focusSlot, response: 0.42, damping: 0.78, velocity: wheelVelocity,
                    horizontalReturns: true, handoffConfiguration: swipeConfiguration(for: settle.held.tuning))
        rebaseReturningAttachments()
    }

    /// Where a swipe's selection change shows no turn, it still gets its own haptic.
    private func swipeChangedSelection(_ tuning: CarouselConfiguration.Focus) {
        if !rotatesSelectedCard || !tuning.horizontalSwipe.turnsCards { onSwipeSelection?() }
    }

    private func pagesHorizontally(_ held: FocusGesture) -> Bool {
        held.tuning.swipesBetweenSelectedCards && held.axis == .horizontal && count > 1
    }

    private func updateHeldCard(_ held: inout FocusGesture, seconds: Double) {
        if pagesHorizontally(held) {
            let dx = Double(held.point.x - (held.axisOrigin ?? held.start).x)
            held.targetProgress = CarouselGestureDecision.resistedProgress(
                -dx / held.pageWidth * held.tuning.horizontalSwipe.effectiveDragSensitivity)
            // A Wave swipe's cards follow on display ticks (`advanceSwipeFollow`).
            guard held.swipeFollow == nil else { return }
            held.progress = held.targetProgress
            updateHeldSwipe(&held, seconds: seconds)
            return
        }
        var body = bodyFor(held.index)
        // The drag starts where the axis locked: the card does not replay the finger's
        // travel through the 8-point slop, so it does not jump. A held card keeps its
        // size; only a card caught below full promotion is raised to it.
        let lock = held.axisOrigin ?? held.start
        let dx = Double(held.point.x - lock.x), dy = Double(held.point.y - lock.y)
        let distance = hypot(dx, dy)
        let grip = CGPoint(x: min(1, max(-1, Double(held.lever.x))), y: min(1, max(-1, Double(held.lever.y))))
        let torque = (Double(grip.x) * dy - Double(grip.y) * dx) / 220
        let angle = held.origin.angle + min(1, max(-1, torque)) * held.tuning.cardDragTilt * .pi / 180
        let height = held.origin.height
        let promotion = held.origin.promotion + (1 - held.origin.promotion) * CarouselGeometry.smoothstep(0, 24, distance)
        let anchor = CGPoint(x: held.start.x + held.point.x - lock.x, y: held.start.y + held.point.y - lock.y)
        var pose = CarouselPose(x: 0, y: 0, height: height, angle: angle, promotion: promotion,
                                aspect: aspect(for: held.index))
        let turnTarget = focusedTarget(for: held.index, near: held.origin.turn).turn
        pose.turn = held.origin.turn + (turnTarget - held.origin.turn) * CarouselGeometry.smoothstep(0, 24, distance)
        let offset = CarouselInput.anchorOffset(lever: held.lever, pose: pose, padding: held.grabPadding)
        pose.x = Double(anchor.x - offset.x)
        pose.y = Double(anchor.y - offset.y)
        drive(&body, to: pose, seconds: seconds)
        bodies[held.index] = body
    }

    private func updateHeldSwipe(_ held: inout FocusGesture, seconds: Double) {
        let progress = held.progress
        // Retain the caught wheel position, then complete any unfinished tap
        // centering as the drag reaches its neighbouring slot.
        wheelPosition = held.position + progress +
            (held.slot - held.position) * CarouselGeometry.smoothstep(0, 1, abs(progress))
        let fraction = min(1, abs(progress))
        let outgoing = cos(fraction * .pi / 2)
        let incoming = sin(fraction * .pi / 2)
        var owner = bodyFor(held.index)
        let shift = swipeShift(held)
        let side = progress > 0 ? 1 : progress < 0 ? -1 : 0
        let ownerBase = horizontalPose(held.index, presence: outgoing, shift: -progress * shift,
                                       focusedTurn: held.focusedTurns[held.index],
                                       slotTurn: swipeOwnerFront(held, direction: side))
        if held.corrections[held.index] == nil {
            held.corrections[held.index] = Correction(pose: subtract(owner.pose, ownerBase), presence: outgoing)
        }
        drive(&owner, to: corrected(ownerBase, with: held.corrections[held.index], presence: outgoing), seconds: seconds)
        bodies[held.index] = owner

        guard progress != 0 else {
            if let previous = held.neighbor { releaseSwipeNeighbor(previous, tuning: held.tuning, pageWidth: held.pageWidth) }
            held.neighbor = nil
            held.neighborDirection = nil
            return
        }
        let direction = progress > 0 ? 1 : -1
        let neighborIndex = CarouselGeometry.wrappedIndex(held.index + direction, count: count)
        let changed = held.neighbor != neighborIndex || held.neighborDirection != direction
        if let previous = held.neighbor, changed, previous != neighborIndex {
            releaseSwipeNeighbor(previous, tuning: held.tuning, pageWidth: held.pageWidth)
        }
        let existed = bodies[neighborIndex] != nil
        var neighbor = bodyFor(neighborIndex)
        if changed, neighbor.motion == .returning, let target = neighbor.target {
            neighbor.selectionFrontTurn = target.turn
        }
        if !held.tuning.horizontalSwipe.turnsCards { neighbor.turnHidden = true }
        bodies[neighborIndex] = neighbor
        if changed {
            held.focusedTurns[neighborIndex] = held.tuning.horizontalSwipe.tucks ?
                swipeSlotPose(neighborIndex).turn + Double(direction) * .pi :
                focusedTarget(for: neighborIndex, near: neighbor.pose.turn).turn
        }
        // Presence saturates at one page, but the shifted target continues
        // moving under the rubber-band resistance rather than sticking at zero.
        let base = horizontalPose(neighborIndex, presence: incoming,
                                  shift: (Double(direction) - progress) * shift,
                                  focusedTurn: held.focusedTurns[neighborIndex])
        let slot = swipeSlotPose(neighborIndex)
        if changed {
            // A returning neighbor may already have samples from its previous
            // animation. Its release must inherit only this swipe's driven motion.
            if held.tuning.horizontalSwipe.isEnabled {
                for sample in held.samples.indices { held.samples[sample].poses[neighborIndex] = nil }
            }
            held.corrections[neighborIndex] = existed ?
                Correction(pose: subtract(neighbor.pose, base), presence: incoming,
                           slotOffset: subtract(neighbor.pose, slot)) :
                Correction(pose: zeroPose, presence: incoming)
        }
        drive(&neighbor, to: corrected(base, with: held.corrections[neighborIndex], presence: incoming, slot: slot),
              seconds: seconds)
        bodies[neighborIndex] = neighbor
        held.neighbor = neighborIndex
        held.neighborDirection = direction
    }

    /// Sideways travel per unit of swipe progress: a page, less the tuck when tucked.
    private func swipeShift(_ held: FocusGesture) -> Double {
        let swipe = held.tuning.horizontalSwipe
        return held.pageWidth * (swipe.tucks ? 1 - swipe.tuckAmount : 1)
    }

    /// A tucked swipe turns the way it travels: toward the next card the old card turns back
    /// to its front one way and the new card over the other way; toward the previous card
    /// both mirror. Returns the owner's front for `direction`, or nil to keep its own.
    private func swipeOwnerFront(_ held: FocusGesture, direction: Int) -> Double? {
        guard held.tuning.horizontalSwipe.tucks, direction != 0,
              let back = held.focusedTurns[held.index] else { return nil }
        return back - Double(direction) * .pi
    }

    /// A committed tucked swipe leaves the old card with the front it turned to, so its
    /// return to the wheel never unwinds an extra half-turn.
    private func keepSwipeOwnerFront(_ held: FocusGesture, direction: Int) {
        guard let front = swipeOwnerFront(held, direction: direction) else { return }
        bodies[held.index]?.selectionFrontTurn = front
    }

    private func swipeSlotPose(_ index: Int) -> CarouselPose {
        var slot = wheelPose(index)
        slot.turn = bodies[index]?.selectionFrontTurn ?? 0
        return slot
    }

    /// `slotTurn` overrides the front the card turns to, for a tucked swipe's mirrored turn.
    private func horizontalPose(_ index: Int, presence: Double, shift: Double,
                                focusedTurn: Double?, slotTurn: Double? = nil) -> CarouselPose {
        var slot = swipeSlotPose(index)
        if let slotTurn { slot.turn = slotTurn }
        var target = focusedTarget(for: index, near: bodies[index]?.pose.turn ?? slot.turn)
        if let focusedTurn { target.turn = focusedTurn }
        target.x += shift
        target.angle = nearestAngle(target.angle, to: slot.angle)
        return interpolate(slot, target, amount: presence)
    }

    private func corrected(_ pose: CarouselPose, with correction: Correction?, presence: Double,
                           slot: CarouselPose? = nil) -> CarouselPose {
        guard let correction else { return pose }
        let weight: Double
        if abs(presence - correction.presence) < 0.000_000_001 { weight = 1 }
        else if presence > correction.presence { weight = (1 - presence) / max(0.000_001, 1 - correction.presence) }
        else if let offset = correction.slotOffset, let slot {
            // A re-picked returning card would lose its correction within a sample or two
            // near zero presence, and that snap fed fast back-and-forth swipes. It keeps the
            // correction instead, each channel clamped between its slot and where it was.
            let held = add(pose, correction.pose)
            func keep(_ value: Double, _ slot: Double, _ offset: Double) -> Double {
                slot + min(max(0, offset), max(min(0, offset), value - slot))
            }
            return CarouselPose(x: keep(held.x, slot.x, offset.x), y: keep(held.y, slot.y, offset.y),
                                height: keep(held.height, slot.height, offset.height),
                                angle: keep(held.angle, slot.angle, offset.angle),
                                promotion: keep(held.promotion, slot.promotion, offset.promotion),
                                opacity: held.opacity, aspect: held.aspect,
                                turn: keep(held.turn, slot.turn, offset.turn))
        }
        else { weight = presence / max(0.000_001, correction.presence) }
        return add(pose, multiply(correction.pose, by: min(1, max(0, weight))))
    }

    /// Renumbers bodies in their drawn stacking before a horizontal gesture ends, so
    /// cards that drop to the shared rank keep the order they were shown in.
    private func preserveHorizontalStacking(_ held: FocusGesture) {
        let neighbor = held.neighbor
        let neighborIsInFront = abs(held.progress) > 0.5
        func rank(_ index: Int) -> Int {
            if index == neighbor { return neighborIsInFront ? 3 : 1 }
            return index == held.index ? 2 : 0
        }
        let stacked = bodies.values.sorted {
            rank($0.index) != rank($1.index) ? rank($0.index) < rank($1.index) : $0.order < $1.order
        }
        for body in stacked { bodies[body.index]?.order = nextOrder() }
    }

    private func finishFocusGesture(_ held: FocusGesture, at time: Double) {
        var held = held
        resolveDeferredCatch(&held)
        if held.pinch != nil {
            settlePinch(held, carriesVelocity: true)
            return
        }
        if held.background {
            if CarouselGestureDecision.isQuickTap(distance: held.distance, duration: time - held.startedAt) {
                dismiss(tuning: held.tuning)
            } else if held.caught {
                restore(held)
            }
            return
        }
        // Cards with back content keep tap-to-dismiss even when selection rotation is off.
        if flipsEnabled, held.index == focusedIndex, held.axis == nil,
           CarouselGestureDecision.isQuickTap(distance: held.distance, duration: time - held.startedAt) {
            dismiss(tuning: held.tuning)
            return
        }
        guard held.caught else { return }
        guard held.axis != nil else { restore(held); return }
        let fingerVelocity = CarouselInput.capped(CGPoint(x: sampleRate(held, time: time) { Double($0.point.x) },
                                                        y: sampleRate(held, time: time) { Double($0.point.y) }), magnitude: 4_000)
        if pagesHorizontally(held), held.swipeFollow != nil {
            // A Wave swipe commits on the finger's own intent, then its shown progress keeps
            // the finger's speed, softly limited, into Wave's return spring.
            let fingerDirection = CarouselGestureDecision.horizontalDirection(progress: -held.targetProgress,
                velocity: Double(fingerVelocity.x), pageWidth: held.pageWidth, projection: held.tuning.cardFlickBoost)
            let rate = sampleRate(held, time: time) { $0.targetProgress }
            let momentum = CarouselInput.swipeMomentumScale(speed: rate,
                limit: held.tuning.horizontalSwipe.momentumLimit)
            startSwipeSettle(held, direction: -(fingerDirection ?? 0), velocity: rate * momentum)
            return
        }
        if pagesHorizontally(held) {
            // Gesture intent retains the finger's unscaled flick projection. Only the momentum
            // handed to the animation is softened; a short flick can still commit a full page.
            let gentler = held.tuning.horizontalSwipe.isEnabled
            let fingerDirection = CarouselGestureDecision.horizontalDirection(progress: -held.progress,
                velocity: Double(fingerVelocity.x), pageWidth: held.pageWidth, projection: held.tuning.cardFlickBoost)
            let direction = -(fingerDirection ?? 0)
            let destination = CarouselGeometry.wrappedIndex(held.index + direction, count: count)
            keepSwipeOwnerFront(held, direction: direction)
            preserveHorizontalStacking(held)
            let configuration = swipeConfiguration(for: held.tuning)
            // The wheel inherits its own displayed motion since the catch, keeping only
            // motion toward its destination slot like every carried channel.
            let releaseVelocity = Double(fingerVelocity.x)
            let destinationSlot = held.slot + Double(direction)
            let wheelRate = gentler ?
                approachRate(sampleRate(held, time: time) { $0.wheelPosition },
                             remaining: destinationSlot - wheelPosition, duration: configuration?.travelDuration) :
                -releaseVelocity / held.pageWidth
            let indices = [held.index, held.neighbor].compactMap { $0 }
            var rates: [Int: CarouselPoseVelocity] = [:]
            for index in indices {
                func rate(_ read: KeyPath<CarouselPose, Double>) -> Double {
                    sampleRate(held, time: time) { $0.poses[index]?[keyPath: read] }
                }
                rates[index] = CarouselPoseVelocity(x: rate(\.x), y: rate(\.y), height: rate(\.height),
                                                    promotion: rate(\.promotion), turn: rate(\.turn))
            }
            var momentum = 1.0
            if gentler {
                var speed = abs(wheelRate)
                for rate in rates.values {
                    speed = max(speed, abs(rate.x) / held.pageWidth, abs(rate.turn) / .pi, abs(rate.promotion))
                }
                momentum = CarouselInput.swipeMomentumScale(speed: speed,
                    limit: held.tuning.horizontalSwipe.momentumLimit)
            }
            for index in indices {
                guard let body = bodies[index], let rate = rates[index] else { continue }
                let target = index == destination ? focusedTarget(for: body.index, near: body.pose.turn) : swipeSlotPose(index)
                func carried(_ read: KeyPath<CarouselPose, Double>, _ rate: Double, duration: Double?) -> Double {
                    approachRate(rate, remaining: target[keyPath: read] - body.pose[keyPath: read], duration: duration) * momentum
                }
                bodies[index]?.velocity = CarouselPoseVelocity(
                    x: gentler ? carried(\.x, rate.x, duration: configuration?.travelDuration) : releaseVelocity,
                    y: carried(\.y, rate.y, duration: configuration?.travelDuration),
                    height: carried(\.height, rate.height, duration: configuration?.animationDuration),
                    promotion: carried(\.promotion, rate.promotion, duration: configuration?.animationDuration),
                    turn: carried(\.turn, rate.turn, duration: configuration?.animationDuration))
            }
            if bodies[destination] == nil {
                var incoming = bodyFor(destination)
                incoming.velocity = CarouselPoseVelocity(x: -wheelRate * swipeShift(held) * momentum)
                bodies[destination] = incoming
            }
            if destination != focusedIndex { swipeChangedSelection(held.tuning) }
            silentSelection = !held.tuning.horizontalSwipe.turnsCards
            settleFocus(destination, slot: destinationSlot, response: 0.42, damping: 0.78,
                        velocity: wheelRate * momentum, horizontalReturns: true,
                        handoffConfiguration: configuration)
            silentSelection = false
            rebaseReturningAttachments()
            return
        }
        for index in Array(bodies.keys) {
            guard var body = bodies[index], body.motion == .held else { continue }
            body.velocity = CarouselPoseVelocity(
                x: sampleRate(held, time: time) { $0.poses[index]?.x },
                y: sampleRate(held, time: time) { $0.poses[index]?.y },
                height: sampleRate(held, time: time) { $0.poses[index]?.height },
                angle: sampleRate(held, time: time) { $0.poses[index]?.angle },
                promotion: sampleRate(held, time: time) { $0.poses[index]?.promotion },
                turn: sampleRate(held, time: time) { $0.poses[index]?.turn })
            let center = CarouselInput.capped(CGPoint(x: body.velocity.x, y: body.velocity.y), magnitude: 4_000)
            body.velocity.x = Double(center.x)
            body.velocity.y = Double(center.y)
            bodies[index] = body
        }
        if var owner = bodies[held.index] {
            let grip = CGPoint(x: min(1, max(-1, Double(held.lever.x))), y: min(1, max(-1, Double(held.lever.y))))
            owner.velocity.angle = (Double(grip.x) * Double(fingerVelocity.y) -
                                    Double(grip.y) * Double(fingerVelocity.x)) * 0.1 * .pi / 180
            let gripVelocity = CarouselInput.capped(CGPoint(
                x: sampleRate(held, time: time) { sample in
                    guard let pose = sample.poses[held.index] else { return nil }
                    return pose.x + Double(CarouselInput.anchorOffset(lever: held.lever, pose: pose, padding: held.grabPadding).x)
                },
                y: sampleRate(held, time: time) { sample in
                    guard let pose = sample.poses[held.index] else { return nil }
                    return pose.y + Double(CarouselInput.anchorOffset(lever: held.lever, pose: pose, padding: held.grabPadding).y)
                }), magnitude: 4_000)
            let center = CarouselInput.centerVelocity(anchorVelocity: gripVelocity, lever: held.lever,
                                                     pose: owner.pose, heightVelocity: owner.velocity.height,
                                                     angularVelocity: owner.velocity.angle, padding: held.grabPadding)
            owner.velocity.x = Double(center.x)
            owner.velocity.y = Double(center.y)
            bodies[held.index] = owner
        }
        if CarouselGestureDecision.shouldDismiss(
                    displacement: CGPoint(x: held.dx, y: held.dy), velocity: fingerVelocity,
                    projection: held.tuning.cardFlickBoost) {
            let projectedX = held.dx + Double(fingerVelocity.x) * held.tuning.cardFlickBoost
            let projectedY = held.dy + Double(fingerVelocity.y) * held.tuning.cardFlickBoost
            let turnDirection = abs(projectedX) > abs(projectedY) ? (projectedX > 0 ? 1 : -1) : nil
            dismiss(tuning: held.tuning, turnDirection: turnDirection)
        } else {
            settleFocus(held.index, slot: held.slot, response: 0.40,
                        damping: 1 - held.tuning.cardSnapBackBounce,
                        velocity: held.wheelHeld && held.brake == nil ? 0 : wheelVelocity,
                        returnConfiguration: held.tuning.returnToWheel)
        }
    }

    private func settleFocus(_ index: Int, slot: Double, response: Double, damping: Double, velocity: Double,
                             selectionTransition: CarouselPoseTransition? = nil,
                             wheelContinuation: CarouselAnimationTrack? = nil,
                             returnConfiguration: CarouselConfiguration.Transition? = nil,
                             horizontalReturns: Bool = false,
                             handoffConfiguration: CarouselConfiguration.Transition? = nil) {
        focusedIndex = index
        focusSlot = slot
        gesture = nil
        wheelVelocity = velocity
        var selected = bodyFor(index)
        if var transition = selectionTransition {
            transition.reseed(pose: selected.pose, velocity: selected.velocity,
                              toward: focusedTarget(for: selected.index, near: selected.pose.turn))
            selected.transition = transition
            centerWheel(at: slot, configuration: transition.configuration,
                        preserveMomentum: true, continuation: wheelContinuation)
        } else if let configuration = handoffConfiguration {
            selected.transition = CarouselPoseTransition(pose: selected.pose, velocity: selected.velocity,
                toward: focusedTarget(for: selected.index, near: selected.pose.turn),
                configuration: configuration, preserveMomentum: true)
            centerWheel(at: slot, configuration: configuration, preserveMomentum: true)
        } else {
            selected.transition = nil
            centerWheel(at: slot, response: response, damping: damping)
        }
        wheelCenteringIsHandoff = horizontalReturns
        selected.motion = .spring
        selected.response = response
        selected.damping = damping
        selected.target = nil
        selected.order = nextOrder()
        bodies[index] = selected
        for other in Array(bodies.keys) where other != index {
            if bodies[other]?.motion != .returning {
                if horizontalReturns { startHorizontalReturn(other, configuration: handoffConfiguration) }
                else { startReturn(other, configuration: returnConfiguration ?? settings.focus.returnToWheel) }
            }
        }
    }

    private func dismiss(tuning: CarouselConfiguration.Focus, turnDirection: Int? = nil) {
        handOffSwipeSettle()
        guard let dismissedIndex = focusedIndex else { return }
        focusedIndex = nil
        gesture = nil
        if wheelMode == .centering, wheelTransition == nil || wheelCenteringIsHandoff, count > 1 {
            // Dismissed by a deferred touch during a handoff: the wheel finishes its
            // captured centering with momentum, then automatic spin resumes from rest.
            // A tap-selection centering stops as before.
            if !settings.spin.automatic {
                centerWheel(at: focusSlot, configuration: tuning.returnToWheel, preserveMomentum: true)
            }
        } else {
            wheelVelocity = 0
            wheelTarget = nil
            wheelTransition = nil
            wheelMode = settings.spin.automatic && count > 1 ? .free : .resting
            if !settings.spin.automatic {
                centerWheel(at: focusSlot, configuration: tuning.returnToWheel, preserveMomentum: true)
            }
        }
        for index in Array(bodies.keys) {
            if bodies[index]?.motion != .returning {
                startReturn(index, configuration: tuning.returnToWheel,
                            turnDirection: index == dismissedIndex ? turnDirection : nil)
            }
        }
        autoplayElapsed = 0
    }

    private func restore(_ held: FocusGesture) {
        if held.pinch != nil {
            settlePinch(held, carriesVelocity: false)
            return
        }
        for index in Array(bodies.keys) where bodies[index]?.motion == .held {
            bodies[index]?.velocity = CarouselPoseVelocity()
        }
        if held.axis == nil {
            // A release during the catch brake resumes from the remaining motion.
            var wheelSpeed = 0.0
            if let brake = held.brake {
                let remaining = max(0, 1 - brake.elapsed / Self.catchDuration)
                bodies[held.index]?.velocity = multiply(brake.velocity, by: remaining * remaining)
                wheelSpeed = count > 1 ? brake.wheelVelocity * remaining * remaining : 0
            }
            settleFocus(held.index, slot: held.slot, response: held.resumeResponse,
                        damping: held.resumeDamping, velocity: wheelSpeed,
                        selectionTransition: held.resumeTransition,
                        wheelContinuation: held.resumeWheelTransition,
                        returnConfiguration: held.tuning.returnToWheel,
                        horizontalReturns: held.resumesHorizontalHandoff,
                        handoffConfiguration: held.resumesHorizontalHandoff ? held.resumeTransition?.configuration : nil)
        } else if pagesHorizontally(held), held.swipeFollow != nil {
            startSwipeSettle(held, direction: 0, velocity: 0)
        } else if pagesHorizontally(held) {
            preserveHorizontalStacking(held)
            settleFocus(held.index, slot: held.slot, response: 0.42, damping: 0.78, velocity: 0,
                        horizontalReturns: true, handoffConfiguration: swipeConfiguration(for: held.tuning))
            rebaseReturningAttachments()
        } else {
            settleFocus(held.index, slot: held.slot, response: 0.40,
                        damping: 1 - held.tuning.cardSnapBackBounce,
                        velocity: held.wheelHeld && held.brake == nil ? 0 : wheelVelocity,
                        returnConfiguration: held.tuning.returnToWheel)
        }
    }

    private func cancelCurrentGesture() {
        guard let current = gesture else { return }
        gesture = nil
        switch current {
        case .wheel:
            releasePresses()
            wheelVelocity = 0
            wheelMode = count > 1 ? .free : .resting
        case .focus(var held):
            resolveDeferredCatch(&held)
            if held.caught { restore(held) }
        }
    }

    /// Ending a touch before its deferred catch. A locked axis takes over first;
    /// the focused card otherwise keeps its motion untouched, while another
    /// promoted card (one returning to the wheel) is caught with its momentum so
    /// the release selects it, as an immediate catch would have.
    private func resolveDeferredCatch(_ held: inout FocusGesture) {
        guard !held.background else { return }
        if held.axis != nil, !held.driving { takeOverFocusGesture(&held) }
        if !held.caught, held.index != focusedIndex, !isDismissedReturn(held.index) ||
            CarouselGestureDecision.isQuickTap(distance: held.distance, duration: held.lastTime - held.startedAt) {
            catchFocusGesture(&held, brake: true)
        }
    }

    /// A card resting at its front turns to the side a physical tap chose (`flipSide`);
    /// otherwise, and once turning, to the nearest back.
    private func focusedTarget(for index: Int, near turn: Double, side: Double? = nil) -> CarouselPose {
        var pose = focusedPose(for: index)
        if flipsEnabled {
            let side = side ?? bodies[index]?.flipSide ?? 0
            let front = (turn / (2 * .pi)).rounded() * 2 * .pi
            pose.turn = side != 0 && abs(turn - front) < 0.01 ? front + side * .pi : nearestAngle(.pi, to: turn)
        }
        return pose
    }

    /// `tilt` is the edge's tilt in radians; the whole card sinks in proportion to it.
    private func beginPress(_ index: Int, lever: CGPoint, tilt: Double) {
        var press = CardPress(baseX: Double(lever.y) * tilt, baseY: Double(lever.x) * tilt,
                              baseSink: Self.pressSink * tilt / (20 * .pi / 180))
        if let current = presses[index] {
            press.x = current.x
            press.y = current.y
            press.sink = current.sink
        }
        presses[index] = press
    }

    /// A tap quicker than the yield still dips: what is left of the press becomes inward
    /// speed. Otherwise the release keeps the press's own speed, as a companion does.
    private func releasePresses() {
        for index in Array(presses.keys) {
            guard var press = presses[index], press.pressed else { continue }
            let target = (x: press.targetX, y: press.targetY, sink: press.targetSink)
            press.pressed = false
            if abs(press.x.value) < 0.7 * abs(target.x) { press.x.velocity += (target.x - press.x.value) * 8 }
            if abs(press.y.value) < 0.7 * abs(target.y) { press.y.velocity += (target.y - press.y.value) * 8 }
            if press.sink.value < 0.7 * target.sink { press.sink.velocity += (target.sink - press.sink.value) * 8 }
            presses[index] = press
        }
    }

    private func advancePresses(by seconds: Double) {
        for index in Array(presses.keys) {
            guard var press = presses[index] else { continue }
            let spring = press.pressed ? Self.pressYield : Self.pressRelease
            // The held target keeps growing: follow it in the springs' own 1/240 s substeps,
            // so the press is the same at every display rate.
            let duration = min(seconds, 0.1)
            let steps = max(1, Int(ceil(duration * 240 - 0.000_001)))
            let dt = duration / Double(steps)
            for _ in 0..<steps {
                if press.pressed { press.heldTime += dt }
                press.x.advance(by: dt, target: press.targetX, spring: spring)
                press.y.advance(by: dt, target: press.targetY, spring: spring)
                press.sink.advance(by: dt, target: press.targetSink, spring: spring)
            }
            presses[index] = !press.pressed && press.isAtRest ? nil : press
        }
    }

    private func applyPress(to card: inout CarouselRenderedCard) {
        guard let press = presses[card.index] else { return }
        card.pose.tiltX = press.x.value
        card.pose.tiltY = press.y.value
        card.pose.height *= 1 - press.sink.value
    }

    /// Adding back content to an already displayed card keeps the previous
    /// availability behavior, without changing position or restarting its timing.
    private func enableTurnsForExistingCards() {
        handOffSwipeSettle()
        for index in Array(bodies.keys) {
            guard var body = bodies[index] else { continue }
            body.pose.turn = .pi * body.pose.promotion
            body.velocity.turn = .pi * body.velocity.promotion
            body.selectionFrontTurn = 0
            if body.motion == .returning, var target = body.target {
                target.turn = 0
                reseedReturn(&body, target: target, slotVelocity: body.slotVelocity)
            } else if body.motion == .spring {
                body.transition?.reseed(pose: body.pose, velocity: body.velocity,
                                       toward: focusedTarget(for: body.index, near: body.pose.turn))
            }
            bodies[index] = body
        }
        if case .focus(var held)? = gesture {
            held.origin.turn = .pi * held.origin.promotion
            if var pinch = held.pinch {
                pinch.held.turn = .pi * pinch.held.promotion
                held.pinch = pinch
            }
            if var brake = held.brake {
                brake.pose.turn = .pi * brake.pose.promotion
                brake.velocity.turn = .pi * brake.velocity.promotion
                held.brake = brake
            }
            for sample in held.samples.indices {
                for index in Array(held.samples[sample].poses.keys) {
                    if var pose = held.samples[sample].poses[index] {
                        pose.turn = .pi * pose.promotion
                        held.samples[sample].poses[index] = pose
                    }
                }
            }
            gesture = .focus(held)
        }
    }

    private func frontTurn(from turn: Double, direction: Int?, original: Double) -> Double {
        guard flipsEnabled, turn.isFinite else { return 0 }
        let revolution = 2 * Double.pi
        if let direction {
            return (direction > 0 ? ceil(turn / revolution) : floor(turn / revolution)) * revolution
        }
        // A tap or vertical throw reverses the selection's half-turn as before.
        return original
    }

    private func bodyFor(_ index: Int) -> Body {
        if let body = bodies[index] { return body }
        return Body(index: index, pose: wheelPose(index), velocity: liftVelocity(index), order: nextOrder())
    }

    private func nextOrder() -> Int { sequence += 1; return sequence }

    private func drive(_ body: inout Body, to pose: CarouselPose, seconds: Double) {
        if seconds > 0 { body.velocity = velocity(from: body.pose, to: pose, seconds: seconds) }
        body.pose = pose
        body.motion = .held
        body.transition = nil
        body.target = nil
    }

    private func startReturn(_ index: Int, configuration: CarouselConfiguration.Transition, turnDirection: Int? = nil) {
        guard var body = bodies[index] else { return }
        // Deselection turns the card back to its front, whatever a swipe hid.
        body.turnHidden = false
        body.flipSide = 0
        body.motion = .returning
        body.returnMotion = .configured
        var target = wheelPose(index)
        target.turn = frontTurn(from: body.pose.turn, direction: turnDirection, original: body.selectionFrontTurn)
        target.angle = nearestAngle(target.angle, to: body.pose.angle)
        body.target = target
        body.slotVelocity = wheelPoseVelocity(index)
        body.transition = CarouselPoseTransition(pose: subtract(body.pose, target),
            velocity: subtract(body.velocity, body.slotVelocity), toward: zeroPose,
            configuration: configuration, preserveMomentum: true)
        body.relativeSlot = CarouselGeometry.relative(index, position: wheelPosition, count: count)
        bodies[index] = body
    }

    /// Controller navigation retains the selection timing and Reference behavior.
    /// Touch-driven browsing uses its independently captured swipe settings.
    private func handoffConfiguration(for tuning: CarouselConfiguration.Focus) -> CarouselConfiguration.Transition? {
        tuning.tapSelectionMode == .reference ? nil : tuning.selection
    }

    private func swipeConfiguration(for tuning: CarouselConfiguration.Focus) -> CarouselConfiguration.Transition? {
        tuning.horizontalSwipe.isEnabled || tuning.horizontalSwipe.followsWithSpring ?
            tuning.horizontalSwipe.transition : handoffConfiguration(for: tuning)
    }

    /// Keep only motion toward the target, bounded by the channel's duration.
    /// Reference retains half the original 0.42-second spring's natural rate.
    private func approachRate(_ rate: Double, remaining: Double, duration: Double? = nil) -> Double {
        guard rate * remaining > 0 else { return 0 }
        let limit = Double.pi / (duration ?? 0.42) * remaining
        return rate > 0 ? min(rate, limit) : max(rate, limit)
    }

    /// A held swipe that changes sides lets its neighbour go mid-gesture. The card returns
    /// from where it was drawn with the release path's capped rates, taken relative to its
    /// moving slot, and starts upright relative to it: a one-sample velocity from a fast
    /// back-and-forth can no longer overshoot it past its slot or feed the next crossing.
    private func releaseSwipeNeighbor(_ index: Int, tuning: CarouselConfiguration.Focus, pageWidth: Double) {
        let configuration = swipeConfiguration(for: tuning)
        startHorizontalReturn(index, configuration: configuration)
        guard var body = bodies[index] else { return }
        let offset = body.returnPose, rate = body.returnVelocity
        let speed = max(abs(rate.x) / pageWidth, abs(rate.turn) / .pi, abs(rate.promotion))
        let momentum = tuning.horizontalSwipe.isEnabled || tuning.horizontalSwipe.followsWithSpring ?
            CarouselInput.swipeMomentumScale(speed: speed, limit: tuning.horizontalSwipe.momentumLimit) : 1
        body.returnVelocity = CarouselPoseVelocity(
            x: approachRate(rate.x, remaining: -offset.x, duration: configuration?.travelDuration) * momentum,
            y: approachRate(rate.y, remaining: -offset.y, duration: configuration?.travelDuration) * momentum,
            height: approachRate(rate.height, remaining: -offset.height, duration: configuration?.animationDuration) * momentum,
            angle: 0,
            promotion: approachRate(rate.promotion, remaining: -offset.promotion, duration: configuration?.animationDuration) * momentum,
            turn: approachRate(rate.turn, remaining: -offset.turn, duration: configuration?.animationDuration) * momentum)
        body.transition?.reseed(pose: offset, velocity: body.returnVelocity, toward: zeroPose)
        // Later re-seeds rebuild the offset velocity from the screen velocity.
        body.velocity = add(body.slotVelocity, body.returnVelocity)
        bodies[index] = body
    }

    private func startHorizontalReturn(_ index: Int, configuration: CarouselConfiguration.Transition? = nil) {
        guard var body = bodies[index] else { return }
        body.flipSide = 0
        body.motion = .returning
        body.returnMotion = .horizontal
        body.transition = nil
        var target = wheelPose(index)
        target.turn = frontTurn(from: body.pose.turn, direction: nil, original: body.selectionFrontTurn)
        target.angle = nearestAngle(target.angle, to: body.pose.angle)
        reseedReturn(&body, target: target, slotVelocity: wheelPoseVelocity(index))
        if let configuration {
            body.transition = CarouselPoseTransition(pose: body.returnPose, velocity: body.returnVelocity,
                toward: zeroPose, configuration: configuration, preserveMomentum: true)
        }
        bodies[index] = body
    }

    private func reseedReturn(_ body: inout Body, target: CarouselPose, slotVelocity: CarouselPoseVelocity) {
        let residual = subtract(body.pose, target)
        let residualVelocity = subtract(body.velocity, slotVelocity)
        if body.returnMotion == .horizontal {
            body.returnPose = residual
            body.returnVelocity = residualVelocity
        }
        body.transition?.reseed(pose: residual, velocity: residualVelocity, toward: zeroPose)
        body.target = target
        body.slotVelocity = slotVelocity
        body.relativeSlot = CarouselGeometry.relative(body.index, position: wheelPosition, count: count)
    }

    /// Every wheel slot comes from here, so the entrance moves drawing, hit testing,
    /// accessibility and docking cards together.
    private func wheelPose(_ index: Int, position: Double? = nil) -> CarouselPose {
        var pose = CarouselGeometry.wheelPose(index: index, position: position ?? wheelPosition, count: count,
                                              size: size, layout: settings.layout, glass: settings.glass, cardLayout: itemLayout(for: index))
        if let entrance {
            let fall = entranceShare(delay: entrance.delays[index] ?? entrance.lateDelay)
            pose.y -= entrance.drop * fall.share
            pose.angle += Self.entranceSwing * fall.share
        }
        return pose
    }

    private func wheelPoseVelocity(_ index: Int) -> CarouselPoseVelocity {
        var velocity = spinPoseVelocity(index)
        if let entrance {
            let fall = entranceShare(delay: entrance.delays[index] ?? entrance.lateDelay)
            velocity.y -= entrance.drop * fall.rate
            velocity.angle += Self.entranceSwing * fall.rate
        }
        return velocity
    }

    /// A card lifted off the wheel keeps the wheel's motion but not the entrance's fall,
    /// which can reach thousands of points per second and would plunge the card.
    private func liftVelocity(_ index: Int) -> CarouselPoseVelocity {
        spinPoseVelocity(index)
    }

    /// The share of the drop a card still has to fall (1 before it starts, 0 at rest,
    /// below 0 while it overshoots) and its rate per second.
    private func entranceShare(delay: Double) -> (share: Double, rate: Double) {
        guard let entrance else { return (0, 0) }
        let time = entrance.elapsed - delay
        guard time > 0 else { return (1, 0) }
        var spring = CarouselSpring(value: 1, response: 0.5, damping: 0.65)
        spring.advance(by: time, target: 0)
        return (spring.value, spring.velocity)
    }

    private func spinPoseVelocity(_ index: Int) -> CarouselPoseVelocity {
        guard abs(wheelVelocity) > 0, count > 1 else { return CarouselPoseVelocity() }
        let interval = 0.0001
        let before = wheelPose(index, position: wheelPosition - wheelVelocity * interval)
        var after = wheelPose(index, position: wheelPosition + wheelVelocity * interval)
        guard hypot(after.x - before.x, after.y - before.y) <
            max(1, focusedPose(for: index).height) else {
            return CarouselPoseVelocity()
        }
        after.angle = nearestAngle(after.angle, to: before.angle)
        return velocity(from: before, to: after, seconds: 2 * interval)
    }

    private func rebaseLayout(refocus: Bool = true) {
        handOffSwipeSettle()
        for index in Array(bodies.keys) {
            guard var body = bodies[index] else { continue }
            if body.motion == .returning {
                var target = wheelPose(index)
                target.turn = body.target?.turn ?? body.selectionFrontTurn
                target.angle = nearestAngle(target.angle, to: body.pose.angle)
                reseedReturn(&body, target: target, slotVelocity: wheelPoseVelocity(index))
            } else if refocus {
                if body.motion == .focused {
                    body.motion = .spring
                    body.response = 0.42
                    body.damping = 0.78
                    body.transition = nil
                } else if body.motion == .spring {
                    body.transition?.reseed(pose: body.pose, velocity: body.velocity,
                                           toward: focusedTarget(for: body.index, near: body.pose.turn))
                }
            }
            bodies[index] = body
        }
        rebaseHeldSwipe()
    }

    private func rebaseHeldSwipe() {
        guard case .focus(var held)? = gesture, pagesHorizontally(held) else { return }
        held.pageWidth = max(1, Double(focusedPose(for: held.index)
            .outerSize(padding: settings.glass.padding).width) + 20)
        // Invert rubber-banding so the same current progress survives a new page
        // width. The next sample starts from this exact finger/card alignment.
        // A Wave swipe keeps its finger target; the shown progress keeps its cards.
        let targetProgress = held.swipeFollow == nil ? held.progress : held.targetProgress
        let targetMagnitude = abs(targetProgress)
        let magnitude = abs(held.progress)
        let excess = max(0, targetMagnitude - 1)
        let raw = targetMagnitude <= 1 ? targetMagnitude : 1 + excess / max(0.000_001, 1 - 3 * excess)
        let signed = targetProgress < 0 ? -raw : raw
        held.axisOrigin = CGPoint(x: held.point.x + signed * held.pageWidth / held.tuning.horizontalSwipe.effectiveDragSensitivity,
                                 y: (held.axisOrigin ?? held.start).y)
        let fraction = min(1, magnitude)
        let outgoing = cos(fraction * .pi / 2), incoming = sin(fraction * .pi / 2)
        if let owner = bodies[held.index] {
            let base = horizontalPose(held.index, presence: outgoing, shift: -held.progress * swipeShift(held),
                                      focusedTurn: held.focusedTurns[held.index],
                                      slotTurn: swipeOwnerFront(held, direction: held.progress > 0 ? 1 : held.progress < 0 ? -1 : 0))
            held.corrections[held.index] = Correction(pose: subtract(owner.pose, base), presence: outgoing)
        }
        if let neighbor = held.neighbor, let body = bodies[neighbor], let direction = held.neighborDirection {
            let base = horizontalPose(neighbor, presence: incoming,
                                      shift: (Double(direction) - held.progress) * swipeShift(held),
                                      focusedTurn: held.focusedTurns[neighbor])
            held.corrections[neighbor] = Correction(pose: subtract(body.pose, base), presence: incoming,
                                                    slotOffset: subtract(body.pose, swipeSlotPose(neighbor)))
        }
        gesture = .focus(held)
    }

    private func catchDisplayedPoses(_ visible: CarouselFrame) {
        guard displayedFrame != nil else { return }
        wheelPosition = visible.position
        wheelVelocity = visible.wheelVelocity
        let shown = Dictionary(uniqueKeysWithValues: (visible.wheel + visible.promoted).map { ($0.index, $0.pose) })
        for card in visible.promoted where bodies[card.index] == nil {
            var body = bodyFor(card.index)
            body.motion = .returning
            body.pose = card.pose
            if flipsEnabled && !rotatesSelectedCard { body.pose.turn = .pi * body.pose.promotion }
            if let velocity = visible.poseVelocities[card.index] { body.velocity = velocity }
            bodies[card.index] = body
            startReturn(card.index, configuration: settings.focus.returnToWheel)
        }
        for index in Array(bodies.keys) {
            guard var body = bodies[index], let pose = shown[index] else { continue }
            let retainedTurn = body.pose.turn
            body.pose = pose
            body.pose.turn = rotatesSelectedCard ? nearestAngle(pose.turn, to: retainedTurn) : retainedTurn
            if let velocity = visible.poseVelocities[index] { body.velocity = velocity }
            if body.motion == .spring {
                body.transition?.reseed(pose: body.pose, velocity: body.velocity,
                                       toward: focusedTarget(for: body.index, near: body.pose.turn))
            }
            if body.motion == .focused { body.motion = .spring }
            bodies[index] = body
        }
        // Keep the same visible stacking order before raising a caught card.
        for card in visible.promoted { bodies[card.index]?.order = nextOrder() }
    }

    private func rebaseReturningAttachments() {
        for index in Array(bodies.keys) {
            guard var body = bodies[index], body.motion == .returning else { continue }
            var target = wheelPose(index)
            target.turn = body.target?.turn ?? body.selectionFrontTurn
            target.angle = nearestAngle(target.angle, to: body.pose.angle)
            reseedReturn(&body, target: target, slotVelocity: wheelPoseVelocity(index))
            bodies[index] = body
        }
    }

    private func addSample(to held: inout FocusGesture, at time: Double) {
        let sample = FocusSample(time: time, point: held.point, wheelPosition: wheelPosition,
                                 poses: bodies.mapValues(\.pose), targetProgress: held.targetProgress)
        if held.samples.last?.time == time { held.samples[held.samples.count - 1] = sample }
        else { held.samples.append(sample) }
        while held.samples.count > 2 && held.samples[1].time <= time - 0.1 { held.samples.removeFirst() }
    }

    private func sampleRate(_ held: FocusGesture, time: Double, read: (FocusSample) -> Double?) -> Double {
        CarouselInput.rate(held.samples.compactMap { sample in read(sample).map { (sample.time, $0) } }, at: time)
    }

    private func publishIndex() {
        guard count > 0, !usesDisplayedReporting || displayedFrame != nil else { return }
        let current = index
        guard reportedIndex != current else { return }
        reportedIndex = current
        if Thread.isMainThread { onIndexChange?(current) }
        else if let onIndexChange { DispatchQueue.main.async { onIndexChange(current) } }
    }
}

/// Parallel movement and appearance tracks. Returns evaluate these in the live
/// slot's coordinate frame, while selections target the fixed focused pose.
private struct CarouselPoseTransition {
    let configuration: CarouselConfiguration.Transition
    private var target: CarouselPose
    private var x: CarouselAnimationTrack
    private var y: CarouselAnimationTrack
    private var height: CarouselAnimationTrack
    private var angle: CarouselAnimationTrack
    private var promotion: CarouselAnimationTrack
    private var turn: CarouselAnimationTrack

    init(pose: CarouselPose, velocity: CarouselPoseVelocity, toward target: CarouselPose,
         configuration: CarouselConfiguration.Transition, preserveMomentum: Bool) {
        self.configuration = configuration
        var target = target
        target.angle = nearestAngle(target.angle, to: pose.angle)
        self.target = target
        func track(_ value: Double, _ velocity: Double, _ target: Double, _ duration: Double) -> CarouselAnimationTrack {
            CarouselAnimationTrack(value: value, velocity: velocity, target: target,
                animation: configuration.animation, duration: duration, bounce: configuration.bounce,
                preserveMomentum: preserveMomentum)
        }
        x = track(pose.x, velocity.x, target.x, configuration.travelDuration)
        y = track(pose.y, velocity.y, target.y, configuration.travelDuration)
        height = track(pose.height, velocity.height, target.height, configuration.animationDuration)
        angle = track(pose.angle, velocity.angle, target.angle, configuration.animationDuration)
        promotion = track(pose.promotion, velocity.promotion, target.promotion, configuration.animationDuration)
        turn = track(pose.turn, velocity.turn, target.turn, configuration.animationDuration)
    }

    mutating func reseed(pose: CarouselPose, velocity: CarouselPoseVelocity, toward target: CarouselPose) {
        var target = target
        target.angle = nearestAngle(target.angle, to: pose.angle)
        self.target = target
        x.reseed(value: pose.x, velocity: velocity.x, target: target.x)
        y.reseed(value: pose.y, velocity: velocity.y, target: target.y)
        height.reseed(value: pose.height, velocity: velocity.height, target: target.height)
        angle.reseed(value: pose.angle, velocity: velocity.angle, target: target.angle)
        promotion.reseed(value: pose.promotion, velocity: velocity.promotion, target: target.promotion)
        turn.reseed(value: pose.turn, velocity: velocity.turn, target: target.turn)
    }

    mutating func advance(by seconds: Double) -> (pose: CarouselPose, velocity: CarouselPoseVelocity, settled: Bool) {
        x.advance(by: seconds)
        y.advance(by: seconds)
        height.advance(by: seconds)
        angle.advance(by: seconds)
        promotion.advance(by: seconds)
        turn.advance(by: seconds)
        let settled = x.isSettled(tolerance: 0.25, velocityTolerance: 2) &&
            y.isSettled(tolerance: 0.25, velocityTolerance: 2) &&
            height.isSettled(tolerance: 0.25, velocityTolerance: 2) &&
            angle.isSettled(tolerance: 0.001, velocityTolerance: 0.01) &&
            promotion.isSettled(tolerance: 0.001, velocityTolerance: 0.01) &&
            turn.isSettled(tolerance: 0.001, velocityTolerance: 0.01)
        if settled { return (target, CarouselPoseVelocity(), true) }
        return (CarouselPose(x: x.value, y: y.value, height: height.value,
                             angle: angle.value, promotion: promotion.value, aspect: target.aspect, turn: turn.value),
                CarouselPoseVelocity(x: x.velocity, y: y.velocity, height: height.velocity,
                                     angle: angle.velocity, promotion: promotion.velocity, turn: turn.velocity), false)
    }
}

private var zeroPose: CarouselPose { CarouselPose(x: 0, y: 0, height: 0, promotion: 0, opacity: 0) }
private func nearestAngle(_ angle: Double, to reference: Double) -> Double {
    reference + atan2(sin(angle - reference), cos(angle - reference))
}
private func subtract(_ a: CarouselPose, _ b: CarouselPose) -> CarouselPose {
    CarouselPose(x: a.x - b.x, y: a.y - b.y, height: a.height - b.height,
                 angle: a.angle - b.angle, promotion: a.promotion - b.promotion, aspect: a.aspect, turn: a.turn - b.turn)
}
private func add(_ a: CarouselPose, _ b: CarouselPose) -> CarouselPose {
    CarouselPose(x: a.x + b.x, y: a.y + b.y, height: a.height + b.height,
                 angle: a.angle + b.angle, promotion: a.promotion + b.promotion, aspect: a.aspect, turn: a.turn + b.turn)
}
private func multiply(_ pose: CarouselPose, by amount: Double) -> CarouselPose {
    CarouselPose(x: pose.x * amount, y: pose.y * amount, height: pose.height * amount,
                 angle: pose.angle * amount, promotion: pose.promotion * amount, aspect: pose.aspect,
                 turn: pose.turn * amount)
}
private func interpolate(_ a: CarouselPose, _ b: CarouselPose, amount: Double) -> CarouselPose {
    add(a, multiply(subtract(b, a), by: amount))
}
private func multiply(_ velocity: CarouselPoseVelocity, by amount: Double) -> CarouselPoseVelocity {
    CarouselPoseVelocity(x: velocity.x * amount, y: velocity.y * amount, height: velocity.height * amount,
                         angle: velocity.angle * amount, promotion: velocity.promotion * amount, turn: velocity.turn * amount)
}
private func add(_ pose: CarouselPose, _ velocity: CarouselPoseVelocity) -> CarouselPose {
    CarouselPose(x: pose.x + velocity.x, y: pose.y + velocity.y, height: pose.height + velocity.height,
                 angle: pose.angle + velocity.angle, promotion: pose.promotion + velocity.promotion,
                 aspect: pose.aspect, turn: pose.turn + velocity.turn)
}
private func subtract(_ a: CarouselPoseVelocity, _ b: CarouselPoseVelocity) -> CarouselPoseVelocity {
    CarouselPoseVelocity(x: a.x - b.x, y: a.y - b.y, height: a.height - b.height,
                         angle: a.angle - b.angle, promotion: a.promotion - b.promotion, turn: a.turn - b.turn)
}
private func add(_ a: CarouselPoseVelocity, _ b: CarouselPoseVelocity) -> CarouselPoseVelocity {
    CarouselPoseVelocity(x: a.x + b.x, y: a.y + b.y, height: a.height + b.height,
                         angle: a.angle + b.angle, promotion: a.promotion + b.promotion, turn: a.turn + b.turn)
}
private func velocity(from a: CarouselPose, to b: CarouselPose, seconds: Double) -> CarouselPoseVelocity {
    let inverse = 1 / max(0.000001, seconds)
    return CarouselPoseVelocity(x: (b.x - a.x) * inverse, y: (b.y - a.y) * inverse,
                                height: (b.height - a.height) * inverse, angle: (b.angle - a.angle) * inverse,
                                promotion: (b.promotion - a.promotion) * inverse, turn: (b.turn - a.turn) * inverse)
}
private func stepPose(_ pose: CarouselPose, velocity: CarouselPoseVelocity, toward target: CarouselPose,
                      response: Double, damping: Double, seconds: Double) -> (pose: CarouselPose, velocity: CarouselPoseVelocity, settled: Bool) {
    var x = CarouselSpring(value: pose.x, velocity: velocity.x, response: response, damping: damping)
    var y = CarouselSpring(value: pose.y, velocity: velocity.y, response: response, damping: damping)
    var height = CarouselSpring(value: pose.height, velocity: velocity.height, response: response, damping: damping)
    var angle = CarouselSpring(value: pose.angle, velocity: velocity.angle, response: response, damping: damping)
    var promotion = CarouselSpring(value: pose.promotion, velocity: velocity.promotion, response: response, damping: damping)
    x.advance(by: seconds, target: target.x)
    y.advance(by: seconds, target: target.y)
    height.advance(by: seconds, target: target.height)
    angle.advance(by: seconds, target: target.angle)
    var turn = CarouselSpring(value: pose.turn, velocity: velocity.turn, response: response, damping: damping)
    promotion.advance(by: seconds, target: target.promotion)
    turn.advance(by: seconds, target: target.turn)
    let settled = x.isSettled(at: target.x, tolerance: 0.25, velocityTolerance: 2) &&
        y.isSettled(at: target.y, tolerance: 0.25, velocityTolerance: 2) &&
        height.isSettled(at: target.height, tolerance: 0.25, velocityTolerance: 2) &&
        angle.isSettled(at: target.angle) && promotion.isSettled(at: target.promotion) && turn.isSettled(at: target.turn)
    if settled { return (target, CarouselPoseVelocity(), true) }
    return (CarouselPose(x: x.value, y: y.value, height: height.value, angle: angle.value, promotion: promotion.value,
                         aspect: target.aspect, turn: turn.value),
            CarouselPoseVelocity(x: x.velocity, y: y.velocity, height: height.velocity,
                                 angle: angle.velocity, promotion: promotion.velocity, turn: turn.velocity), false)
}
