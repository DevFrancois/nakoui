import CoreFoundation
import Darwin

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
