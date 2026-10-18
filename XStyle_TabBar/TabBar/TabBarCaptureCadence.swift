import CoreFoundation
import Darwin

/// A single clean tick is not evidence that an interaction or GPU producer has
/// stopped. Keep its display cadence through callback jitter and the final update.
nonisolated struct TabBarRenderActivity {
    private var activeUntil: CFTimeInterval = 0
    var isInteracting = false

    mutating func noteChange(at time: CFTimeInterval) {
        guard time.isFinite else { return }
        activeUntil = max(activeUntil, time + 0.25)
    }

    func isActive(at time: CFTimeInterval) -> Bool {
        isInteracting || time < activeUntil
    }
}

/// Idle checks run at a different clock/power state. Their measured cost must
/// not replace the active estimate and block the first capture of a new scroll.
/// Both histories retain their own deadline guard and bounded retry policy.
nonisolated struct TabBarCaptureSchedule {
    private var active = TabBarCaptureCadence()
    private var idle = TabBarCaptureCadence()
    private var motionPendingUntil: CFTimeInterval = 0
    private var lastCaptureTime: CFTimeInterval?

    /// Input can precede scrolling by hundreds of milliseconds. Classify the
    /// next capture from an actual offset change, independently of the render
    /// clock. Consume this signal even if the sampled pixels happen to match.
    mutating func noteUIMotion(at time: CFTimeInterval) {
        guard time.isFinite else { return }
        motionPendingUntil = time + 0.25
    }

    func hasUIMotion(at time: CFTimeInterval) -> Bool {
        time < motionPendingUntil
    }

    func estimatedDuration(isIdle: Bool) -> CFTimeInterval {
        isIdle ? idle.estimatedCaptureDuration : active.estimatedCaptureDuration
    }

    mutating func shouldCapture(at time: CFTimeInterval, deadline: CFTimeInterval,
                                isIdle: Bool, force: Bool = false) -> Bool {
        // Switching histories must not admit two captures on adjacent 120Hz
        // ticks. The shared rate limit applies even when the cost class changes.
        if let lastCaptureTime, time < lastCaptureTime { reset() }
        if !force, let lastCaptureTime, time - lastCaptureTime + 1.0 / 600 < 1.0 / 60 {
            return false
        }
        if isIdle { return idle.shouldCapture(at: time, deadline: deadline, force: force) }
        return active.shouldCapture(at: time, deadline: deadline, force: force)
    }

    mutating func recordCapture(duration: CFTimeInterval, at time: CFTimeInterval, isIdle: Bool) {
        guard duration.isFinite, duration >= 0, time.isFinite else { return }
        lastCaptureTime = time
        motionPendingUntil = 0
        if isIdle { idle.recordCapture(duration: duration, at: time) }
        else { active.recordCapture(duration: duration, at: time) }
    }

    mutating func reset() { self = Self() }
}

/// Separates the cost of producing nearby UI colors from the display's refresh
/// rate. This does not queue work: callers either capture now or reuse textures.
nonisolated struct TabBarCaptureCadence {
    private(set) var estimatedCaptureDuration: CFTimeInterval = 0.002
    private var averageDuration: CFTimeInterval = 0.002
    private var peakDuration: CFTimeInterval = 0.002
    private var lastCaptureTime: CFTimeInterval?
    private var firstDeferredTime: CFTimeInterval?

    private static let maximumRate: Double = 60
    // Bound average capture work while allowing a measured sub-frame capture
    // to follow the display. The deadline guard rejects work predicted to miss
    // presentation, with a small reserve for the rest of the frame.
    private static let cpuBudgetFraction: Double = 0.60
    private static let deadlineMargin: CFTimeInterval = 0.001
    private static let retryDelay: CFTimeInterval = 0.25

    var captureInterval: CFTimeInterval {
        max(1 / Self.maximumRate, estimatedCaptureDuration / Self.cpuBudgetFraction)
    }

    /// UI capture participates in UIKit's current update. Its submission
    /// deadline is distinct from a display link's presentation target, which
    /// can already be past when the simulator delivers the callback. Use the
    /// view-specific system deadline without inventing another frame of time.
    static func submissionDeadline(displayTarget: CFTimeInterval,
                                   uiCompletion: CFTimeInterval?) -> CFTimeInterval {
        guard let uiCompletion, uiCompletion.isFinite, uiCompletion > 0 else {
            return displayTarget
        }
        return uiCompletion
    }

    mutating func shouldCapture(at time: CFTimeInterval, deadline: CFTimeInterval,
                                force: Bool = false) -> Bool {
        guard time.isFinite else { return false }
        if let lastCaptureTime, time < lastCaptureTime { reset() }
        if force { return true }
        // Display callbacks arrive with small scheduling jitter. Requiring an
        // exact 16.667 ms gap would randomly halve a cheap capture's cadence.
        // This tolerance still rejects a second 120 Hz tick and does not relax
        // the cost budget for expensive captures.
        let tolerance = captureInterval <= 1 / Self.maximumRate ? 1.0 / 600 : 0.000_001
        if let lastCaptureTime, time - lastCaptureTime + tolerance < captureInterval {
            return false
        }
        if deadline.isFinite,
           deadline - time >= estimatedCaptureDuration + Self.deadlineMargin {
            return true
        }

        // A capture costing more than a display interval cannot meet any frame
        // deadline. Retry occasionally rather than freezing its colors forever.
        // The budget-derived interval may exceed 100 ms: enforcing a 10 Hz floor
        // could exceed the main-thread budget on slower devices.
        if firstDeferredTime == nil { firstDeferredTime = time }
        let reference = lastCaptureTime ?? firstDeferredTime ?? time
        return time - reference >= max(Self.retryDelay, captureInterval)
    }

    mutating func recordCapture(duration: CFTimeInterval, at time: CFTimeInterval) {
        guard duration.isFinite, duration >= 0, time.isFinite else { return }
        // Age history by elapsed time only after obtaining a new measurement.
        // Counting samples alone traps recovery at the 250ms retry cadence:
        // a stale expensive image keeps rejecting captures long after scrolling
        // has moved to cheap content. At a regular 60Hz this matches the original
        // weighting; slower samples replace old costs faster without weakening
        // the deadline check or assuming an unmeasured capture became cheaper.
        let elapsed = lastCaptureTime.map { time - $0 } ?? (1 / Self.maximumRate)
        let intervals = min(60, max(1, elapsed * Self.maximumRate))
        let averageRetention = pow(0.75, intervals)
        let peakRetention = pow(0.85, intervals)
        averageDuration = averageDuration * averageRetention + duration * (1 - averageRetention)
        peakDuration = max(duration, peakDuration * peakRetention)
        estimatedCaptureDuration = max(averageDuration, peakDuration)
        lastCaptureTime = time
        firstDeferredTime = nil
    }

    mutating func reset() {
        self = Self()
    }
}
