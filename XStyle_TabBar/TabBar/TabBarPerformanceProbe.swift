#if DEBUG
import Foundation
import Metal
import QuartzCore

/// Opt-in diagnostics. Scalar snapshots never retain capture frames or textures.
/// Presentation timestamps come from the drawable, not command scheduling.
@MainActor
final class TabBarPerformanceProbe {
    typealias Frame = TabBarUITextureCapture.Frame
    static let shared = TabBarPerformanceProbe()
    let isEnabled = ProcessInfo.processInfo.environment["TABBAR_METRICS"] == "1"
        || ProcessInfo.processInfo.environment["TABBAR_LATENCY"] == "1"
    private var presentationKind: String {
        #if targetEnvironment(simulator)
        "scheduled"
        #else
        "actual"
        #endif
    }

    private nonisolated struct Revision: Sendable {
        var number: UInt64 = 0
        var time: CFTimeInterval = 0
    }

    private nonisolated struct Encoded: Sendable {
        let settings: Revision
        let scene: Revision
        let current: Revision
        let previous: Revision
        let blend: Double
        let gesture: UInt64
    }

    private struct Lag {
        var sum: Double = 0
        var maximum: Double = 0
        var count = 0
        mutating func add(_ seconds: Double) {
            guard seconds.isFinite, seconds >= 0 else { return }
            sum += seconds; maximum = max(maximum, seconds); count += 1
        }
        var meanMS: Double { sum * 1000 / Double(max(1, count)) }
        var maximumMS: Double { maximum * 1000 }
    }

    private struct Counters {
        var checks = 0, changed = 0, reused = 0
        var deferred = 0, tightHeadroom = 0
        var settings = 0, delivered = 0, published = 0
        var presented = 0, skipped = 0
        var uiPresented = 0, settingsPresented = 0, scenePresented = 0
        var uiAge = Lag(), uiLag = Lag(), settingsLag = Lag(), sceneLag = Lag()
    }

    private struct Wake {
        let id: UInt64
        let input: CFTimeInterval
        let observedInput: Bool
        var isHorizontal = false
        var motion: CFTimeInterval?
        var firstCheck: CFTimeInterval?
        var firstChanged: Revision?
        var firstPresented: CFTimeInterval?
        var fullyPresented: CFTimeInterval?
        var checks = 0, changed = 0, reused = 0
        var deferredBeforeChanged = 0, tightBeforeChanged = 0
        var firstDeferred: CFTimeInterval?
        var deferredEstimateMax: Double = 0
        var deferredHeadroomMin = Double.infinity
        var precedingSlowCapture: SlowCapture?
    }

    private struct SlowCapture {
        let time: CFTimeInterval
        let duration: CFTimeInterval
        let reason: String
        let changed: Bool
    }

    private var counters = Counters()
    private var settings = Revision(), scene = Revision()
    private var uiRevision: UInt64 = 0
    // Capture target times identify frames without keeping their GPU leases alive.
    private var captures: [CFTimeInterval: Revision] = [:]
    private var latestPresentedUI: UInt64 = 0
    private var latestPresentedSettings: UInt64 = 0
    private var latestPresentedScene: UInt64 = 0
    private var gesture: UInt64 = 0
    private var wake: Wake?
    private var isHorizontalTracking = false
    private var lastSlowMovingCapture: SlowCapture?

    func captureMeasured(duration: CFTimeInterval, isIdle: Bool, reason: String, changed: Bool) {
        guard isEnabled, !isIdle, duration > 0.006 else { return }
        lastSlowMovingCapture = SlowCapture(time: CACurrentMediaTime(), duration: duration,
                                           reason: reason, changed: changed)
    }

    func settingsChanged() {
        guard isEnabled else { return }
        settings = Revision(number: settings.number &+ 1, time: CACurrentMediaTime())
        counters.settings += 1
    }

    func sceneDelivered() {
        guard isEnabled else { return }
        counters.delivered += 1
    }

    func scenePublished() {
        guard isEnabled else { return }
        scene = Revision(number: scene.number &+ 1, time: CACurrentMediaTime())
        counters.published += 1
    }

    func uiCaptured(_ frame: Frame, changed: Bool) {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        counters.checks += 1
        if changed {
            counters.changed += 1
            uiRevision &+= 1
            captures[frame.captureTime] = Revision(number: uiRevision, time: now)
            if captures.count > 8, let oldest = captures.keys.min() { captures.removeValue(forKey: oldest) }
        } else { counters.reused += 1 }
        guard var value = wake, value.motion != nil else { return }
        value.checks += 1
        if value.firstCheck == nil { value.firstCheck = now }
        if changed {
            value.changed += 1
            if value.firstChanged == nil { value.firstChanged = captures[frame.captureTime] }
        } else { value.reused += 1 }
        wake = value
    }

    /// Optional call immediately before the CPU capture, after cadence admission.
    func captureAttemptBegan() {
        guard isEnabled, wake?.motion != nil, wake?.firstCheck == nil else { return }
        wake?.firstCheck = CACurrentMediaTime()
    }

    /// A denied cadence check; insufficient headroom is an observation, not a
    /// claim that the deadline rather than the rate limit caused the denial.
    func captureDeferred(estimatedDuration: CFTimeInterval, headroom: CFTimeInterval) {
        guard isEnabled else { return }
        counters.deferred += 1
        let tight = headroom.isFinite && estimatedDuration.isFinite
            && headroom < estimatedDuration + 0.001
        if tight { counters.tightHeadroom += 1 }
        guard var value = wake, value.motion != nil, value.firstChanged == nil else { return }
        value.deferredBeforeChanged += 1
        if tight { value.tightBeforeChanged += 1 }
        if value.firstDeferred == nil { value.firstDeferred = CACurrentMediaTime() }
        if estimatedDuration.isFinite { value.deferredEstimateMax = max(value.deferredEstimateMax, estimatedDuration) }
        if headroom.isFinite { value.deferredHeadroomMin = min(value.deferredHeadroomMin, headroom) }
        wake = value
    }

    /// `at` is UITouch.timestamp, in the host monotonic clock's seconds.
    func interactionBegan(at time: CFTimeInterval) {
        guard isEnabled else { return }
        if wake?.motion != nil { finishWake(status: "interrupted") }
        gesture &+= 1
        let now = CACurrentMediaTime()
        let validTouchTime = time.isFinite && time > 0 && abs(now - time) < 2
        wake = Wake(id: gesture, input: validTouchTime ? time : now, observedInput: validTouchTime)
    }

    func scrollPhaseChanged(isTracking: Bool, isIdle: Bool) {
        guard isEnabled else { return }
        if isTracking {
            if wake == nil, !isHorizontalTracking {
                gesture &+= 1
                wake = Wake(id: gesture, input: CACurrentMediaTime(), observedInput: false)
            }
            isHorizontalTracking = true
            wake?.isHorizontal = true
        } else if isIdle {
            isHorizontalTracking = false
            if wake?.motion == nil { wake = nil }
        }
    }

    func sourceMoved(from oldOffset: CGFloat, to newOffset: CGFloat) {
        guard isEnabled, oldOffset.isFinite, newOffset.isFinite,
              abs(newOffset - oldOffset) > 0.01,
              wake?.isHorizontal == true, wake?.motion == nil else { return }
        wake?.motion = CACurrentMediaTime()
        wake?.precedingSlowCapture = lastSlowMovingCapture
    }

    /// Call only for a successfully encoded frame, before presenting the drawable.
    @discardableResult
    func trackPresentation(drawable: CAMetalDrawable, current: Frame?, previous: Frame?,
                           targetTime: CFTimeInterval) -> (() -> Void)? {
        guard isEnabled else { return nil }
        let previous = previous ?? current
        let duration = min(1.0 / 30, max(1.0 / 120,
            (current?.captureTime ?? 0) - (previous?.captureTime ?? 0)))
        let blend = current === previous ? 1 : min(1, max(0,
            (targetTime - (current?.captureTime ?? 0)) / duration))
        let encoded = Encoded(settings: settings, scene: scene,
            current: current.flatMap { captures[$0.captureTime] } ?? Revision(),
            previous: previous.flatMap { captures[$0.captureTime] } ?? Revision(),
            blend: blend, gesture: wake?.id ?? 0)
        #if targetEnvironment(simulator)
        // Simulator Metal does not expose actual drawable presentation callbacks.
        // The caller invokes this scalar-only snapshot after scheduling present.
        return { [weak self] in self?.didPresent(encoded, at: CACurrentMediaTime()) }
        #else
        drawable.addPresentedHandler { [weak self] presented in
            let time = presented.presentedTime
            DispatchQueue.main.async { [weak self] in self?.didPresent(encoded, at: time) }
        }
        return nil
        #endif
    }

    private func didPresent(_ encoded: Encoded, at time: CFTimeInterval) {
        guard time.isFinite, time > 0 else { counters.skipped += 1; return }
        counters.presented += 1
        let visibleUI = encoded.blend > 0 ? encoded.current : encoded.previous
        if visibleUI.number > 0 { counters.uiAge.add(time - visibleUI.time) }
        if visibleUI.number > latestPresentedUI {
            latestPresentedUI = visibleUI.number
            counters.uiPresented += 1
            counters.uiLag.add(time - visibleUI.time)
        }
        if encoded.settings.number > latestPresentedSettings {
            latestPresentedSettings = encoded.settings.number
            counters.settingsPresented += 1
            counters.settingsLag.add(time - encoded.settings.time)
        }
        if encoded.scene.number > latestPresentedScene {
            latestPresentedScene = encoded.scene.number
            counters.scenePresented += 1
            counters.sceneLag.add(time - encoded.scene.time)
        }
        guard var value = wake, value.id == encoded.gesture,
              let first = value.firstChanged else { return }
        let currentIsFresh = encoded.current.number >= first.number
        let previousIsFresh = encoded.previous.number >= first.number
        let hasFreshPixels = (encoded.blend > 0 && currentIsFresh)
            || (encoded.blend < 1 && previousIsFresh)
        if hasFreshPixels, value.firstPresented == nil { value.firstPresented = time }
        // The initial changed capture is fully represented when all contributing
        // samples postdate motion, even if subsequent moving captures replaced it.
        let allPixelsFresh = (encoded.blend >= 1 && currentIsFresh)
            || (encoded.blend <= 0 && previousIsFresh)
            || (currentIsFresh && previousIsFresh)
        if allPixelsFresh, value.fullyPresented == nil { value.fullyPresented = time }
        wake = value
        if value.firstPresented != nil, value.fullyPresented != nil { finishWake(status: "presented") }
    }

    private func finishWake(status: String) {
        guard let value = wake, let motion = value.motion else { wake = nil; return }
        if let slow = value.precedingSlowCapture {
            print(String(format: "TABBAR_WAKE_HISTORY id=%llu slowAgeMS=%.3f slowCostMS=%.3f reason=%@ changed=%d",
                         value.id, (motion - slow.time) * 1000, slow.duration * 1000,
                         slow.reason, slow.changed ? 1 : 0))
        }
        func milliseconds(_ end: Double?, since start: Double) -> Double {
            end.map { ($0 - start) * 1000 } ?? -1
        }
        print(String(format: "TABBAR_WAKE id=%llu status=%@ presentationKind=%@ inputKind=%@ inputTime=%.6f motionTime=%.6f inputToMotionMS=%.3f inputToPresentMS=%.3f motionToCheckMS=%.3f motionToChangedMS=%.3f motionToPresentMS=%.3f changedToPresentMS=%.3f motionToFullMS=%.3f checks=%d changed=%d reused=%d deferredBeforeChanged=%d tightBeforeChanged=%d motionToDeferredMS=%.3f deferredEstimateMaxMS=%.3f deferredHeadroomMinMS=%.3f",
            value.id, status, presentationKind, value.observedInput ? "touch" : "scrollPhase", value.input, motion,
            (motion - value.input) * 1000, milliseconds(value.firstPresented, since: value.input),
            milliseconds(value.firstCheck, since: motion), milliseconds(value.firstChanged?.time, since: motion),
            milliseconds(value.firstPresented, since: motion),
            milliseconds(value.firstPresented, since: value.firstChanged?.time ?? motion),
            milliseconds(value.fullyPresented, since: motion), value.checks, value.changed, value.reused,
            value.deferredBeforeChanged, value.tightBeforeChanged,
            milliseconds(value.firstDeferred, since: motion), value.deferredEstimateMax * 1000,
            value.deferredHeadroomMin.isFinite ? value.deferredHeadroomMin * 1000 : -1.0))
        wake = nil
    }

    /// Called alongside the existing two-second metrics report. No per-frame I/O.
    func report(elapsed: Double) {
        guard isEnabled, elapsed.isFinite, elapsed > 0 else { return }
        if let value = wake, let motion = value.motion, CACurrentMediaTime() - motion > 5 {
            finishWake(status: "timeout")
        }
        let c = counters
        func rate(_ count: Int) -> Double { Double(count) / elapsed }
        print(String(format: "TABBAR_FRESHNESS presentationKind=%@ uiChecks=%.2f uiChanged=%.2f uiReused=%.2f uiPresented=%.2f settingsChanged=%.2f settingsPresented=%.2f sceneDelivered=%.2f scenePublished=%.2f scenePresented=%.2f presented=%.2f skipped=%d uiDeferred=%.2f uiTightHeadroom=%.2f uiAgeMeanMS=%.3f uiAgeMaxMS=%.3f uiLagMeanMS=%.3f uiLagMaxMS=%.3f settingsLagMeanMS=%.3f settingsLagMaxMS=%.3f sceneLagMeanMS=%.3f sceneLagMaxMS=%.3f",
            presentationKind, rate(c.checks), rate(c.changed), rate(c.reused), rate(c.uiPresented),
            rate(c.settings), rate(c.settingsPresented), rate(c.delivered), rate(c.published),
            rate(c.scenePresented), rate(c.presented), c.skipped, rate(c.deferred), rate(c.tightHeadroom),
            c.uiAge.meanMS, c.uiAge.maximumMS, c.uiLag.meanMS, c.uiLag.maximumMS,
            c.settingsLag.meanMS, c.settingsLag.maximumMS, c.sceneLag.meanMS, c.sceneLag.maximumMS))
        counters = Counters()
    }
}
#endif
