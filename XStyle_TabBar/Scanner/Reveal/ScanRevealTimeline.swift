import SwiftUI

/// The reveal's choreography as pure functions of time, measured frame by
/// frame from Apple's Code Scanner at 60 fps. Times are seconds since the
/// code was detected.
///
/// Live phase: the brackets fly from the viewfinder onto the code and track
/// it. At `freeze` the frame stops; from there on, times run from when the
/// frozen frame actually arrived, so a slow freeze delays rather than skips.
nonisolated enum ScanRevealTimeline {
    static let freeze = 0.28
    /// The brackets have all but landed by now.
    static let bracketFlightDuration = 0.4
    static let blurDuration = 0.10
    static let liftStart = 0.58
    static let liftDuration = 0.45
    static let bracketFadeDuration = 0.05
    static let bloomStart = 1.13
    static let iconStart = 1.47
    /// When nothing moves any more.
    static let settleTime = 1.75
    static let closeDuration = 0.3

    static let bracketSpring = Spring(duration: 0.24, bounce: 0)
    /// About 8% overshoot, peaking 0.1 s in.
    static let iconSpring = Spring(duration: 0.16, bounce: 0.37)

    /// - Parameters:
    ///   - time: Seconds since detection.
    ///   - freezeTime: Seconds since detection when the frozen frame arrived,
    ///     or nil while still live.
    ///   - closeTime: Seconds since the result closed, or nil.
    static func frame(at time: Double, freezeTime: Double?, closeTime: Double?, reduceMotion: Bool) -> ScanRevealFrame {
        var frame = ScanRevealFrame()
        if let closeTime {
            frame.overlayOpacity = 1 - UnitCurve.easeOut.value(at: progress(closeTime, from: 0, over: closeDuration))
        }
        if reduceMotion {
            frame.bracketOpacity = 0
        } else {
            frame.bracketProgress = CGFloat(bracketSpring.value(target: 1.0, time: max(time, 0)))
        }
        guard let freezeTime else { return frame }

        // Frozen-phase clock: `freeze` at the moment the frame arrived.
        let t = time - freezeTime + freeze
        frame.isFrozen = true
        frame.blur = UnitCurve.easeOut.value(at: progress(t, from: freeze, over: blurDuration))

        if reduceMotion {
            // A crossfade straight to the result, with no motion.
            frame.lift = 1
            frame.patchOpacity = 0
            frame.bloomTime = .infinity
            frame.cardOpacity = progress(t, from: freeze, over: 0.2)
            frame.iconScale = 1
            frame.iconOpacity = frame.cardOpacity
            return frame
        }

        frame.bracketOpacity = 1 - progress(t, from: liftStart, over: bracketFadeDuration)
        frame.lift = CGFloat(UnitCurve.easeInOut.value(at: progress(t, from: liftStart, over: liftDuration)))
        if t >= bloomStart {
            frame.bloomTime = t - bloomStart
        }
        if t >= iconStart {
            frame.iconScale = CGFloat(iconSpring.value(target: 1.0, time: t - iconStart))
        }
        return frame
    }

    /// Seconds since detection when the reveal has played out and fades back
    /// to the live camera, over `closeDuration`.
    static func fadeTime(freezeTime: Double, reduceMotion: Bool) -> Double {
        freezeTime - freeze + (reduceMotion ? 0.6 : settleTime)
    }

    private static func progress(_ t: Double, from start: Double, over duration: Double) -> Double {
        min(max((t - start) / duration, 0), 1)
    }
}
