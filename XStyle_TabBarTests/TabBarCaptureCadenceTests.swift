import Testing
@testable import XStyle_TabBar

struct TabBarCaptureCadenceTests {
    @Test("Changing capture histories cannot double the sampling rate")
    func modeChangesShareRateLimit() {
        var schedule = TabBarCaptureSchedule()
        schedule.recordCapture(duration: 0.002, at: 1, isIdle: true)
        let tooSoon = schedule.shouldCapture(at: 1 + 1.0 / 120, deadline: 1.03, isIdle: false)
        #expect(!tooSoon)
        let nextFrame = schedule.shouldCapture(at: 1 + 1.0 / 60, deadline: 1.03, isIdle: false)
        #expect(nextFrame)
    }

    @Test("A scroll signal is consumed by its capture and cannot classify later static checks")
    func motionDoesNotContaminateStaticHistory() {
        var schedule = TabBarCaptureSchedule()
        schedule.noteUIMotion(at: 1)
        #expect(schedule.hasUIMotion(at: 1.01))
        schedule.recordCapture(duration: 0.003, at: 1.01, isIdle: false)
        #expect(!schedule.hasUIMotion(at: 1.02))
        schedule.recordCapture(duration: 0.013, at: 1.05, isIdle: true)
        schedule.noteUIMotion(at: 2)
        #expect(schedule.hasUIMotion(at: 2.01))
        #expect(schedule.estimatedDuration(isIdle: false) == 0.003)
        #expect(!schedule.hasUIMotion(at: 2.3))
        schedule.reset()
        #expect(!schedule.hasUIMotion(at: 2.01))
    }

    @Test("Slow idle checks cannot starve the first active capture")
    func idleCostDoesNotDelayWake() {
        var schedule = TabBarCaptureSchedule()
        schedule.recordCapture(duration: 0.003, at: 1, isIdle: false)
        for sample in 0..<30 {
            schedule.recordCapture(duration: 0.013, at: 2 + Double(sample) / 30, isIdle: true)
        }
        #expect(schedule.estimatedDuration(isIdle: true) >= 0.013)
        #expect(schedule.estimatedDuration(isIdle: false) == 0.003)
        let admitted = schedule.shouldCapture(at: 3, deadline: 3.006, isIdle: false)
        #expect(admitted)
    }

    @Test("Idle transitions never erase a genuinely expensive active capture")
    func activeCostIsPreservedAcrossIdle() {
        var schedule = TabBarCaptureSchedule()
        schedule.recordCapture(duration: 0.012, at: 1, isIdle: false)
        schedule.recordCapture(duration: 0.001, at: 1.1, isIdle: true)
        let admitted = schedule.shouldCapture(at: 1.15, deadline: 1.156, isIdle: false)
        #expect(!admitted)
        #expect(schedule.estimatedDuration(isIdle: false) == 0.012)
    }

    @Test("Idle checks keep an expensive first active capture behind the retry delay")
    func idleChecksDelayOverDeadlineRetry() {
        var schedule = TabBarCaptureSchedule()
        schedule.recordCapture(duration: 0.012, at: 1, isIdle: false)
        for sample in 0...12 {
            schedule.recordCapture(duration: 0.001, at: 1.1 + Double(sample) / 30, isIdle: true)
        }
        // 6ms of headroom cannot fit a 12ms capture. The active history last
        // ran 520ms ago, but the latest capture was only 20ms ago.
        let tooSoon = schedule.shouldCapture(at: 1.52, deadline: 1.526, isIdle: false)
        #expect(!tooSoon)
        let retry = schedule.shouldCapture(at: 1.76, deadline: 1.766, isIdle: false)
        #expect(retry)
    }

    @Test("Clean ticks between producer frames do not lower the active display cadence")
    func producerActivitySurvivesCallbackGaps() {
        var activity = TabBarRenderActivity()
        for frame in 0..<120 {
            let time = 1 + Double(frame) / 60
            activity.noteChange(at: time)
            #expect(activity.isActive(at: time + 1.0 / 120))
        }
        #expect(!activity.isActive(at: 4))
    }

    @Test("A held interaction remains active, then settles after release")
    func interactionAndRelease() {
        var activity = TabBarRenderActivity()
        activity.isInteracting = true
        activity.noteChange(at: 1)
        #expect(activity.isActive(at: 10))
        activity.isInteracting = false
        activity.noteChange(at: 10)
        #expect(activity.isActive(at: 10.1))
        #expect(!activity.isActive(at: 10.3))
    }

    @Test("Rendering unchanged content cannot extend the activity hold")
    func unchangedFramesEventuallyIdle() {
        var activity = TabBarRenderActivity()
        activity.noteChange(at: 1)
        for frame in 0..<120 {
            _ = activity.isActive(at: 1 + Double(frame) / 120)
        }
        #expect(!activity.isActive(at: 2))
        activity.noteChange(at: 2)
        #expect(activity.isActive(at: 2))
    }

    @Test("A stale presentation target does not starve a valid UIKit update")
    func uiSubmissionDeadline() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.004, at: 1)
        let deadline = TabBarCaptureCadence.submissionDeadline(
            displayTarget: 1.0494, uiCompletion: 1.066)
        let canCapture = cadence.shouldCapture(at: 1.05, deadline: deadline)
        #expect(canCapture)
    }

    @Test("An exhausted UIKit update is respected even with a future presentation target")
    func expiredUIUpdateIsNotExtended() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.004, at: 1)
        let deadline = TabBarCaptureCadence.submissionDeadline(
            displayTarget: 1.066, uiCompletion: 1.049)
        #expect(deadline == 1.049)
        let canCapture = cadence.shouldCapture(at: 1.05, deadline: deadline)
        #expect(!canCapture)
    }

    @Test("Missing or invalid UIKit timing retains the display target without adding time")
    func missingUIUpdateUsesDisplayTarget() {
        for value: Double? in [nil, .nan, .infinity, 0, -1] {
            #expect(TabBarCaptureCadence.submissionDeadline(displayTarget: 1.05, uiCompletion: value) == 1.05)
        }
    }

    @Test("Small display callback jitter does not halve a cheap capture's refresh rate")
    func callbackJitter() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.001, at: 1)
        let earlyDisplayTick = cadence.shouldCapture(at: 1.0155, deadline: 1.032)
        #expect(earlyDisplayTick)
        let next120HzTick = cadence.shouldCapture(at: 1.0084, deadline: 1.017)
        #expect(!next120HzTick)
    }

    @Test("Cheap captures can follow 60 Hz without duplicating frames")
    func inexpensiveCaptureCadence() {
        var cadence = TabBarCaptureCadence()
        let captureDecision1 = cadence.shouldCapture(at: 1, deadline: 1.016)
        #expect(captureDecision1)
        cadence.recordCapture(duration: 0.001, at: 1)
        let captureDecision2 = !cadence.shouldCapture(at: 1, deadline: 1.016)
        #expect(captureDecision2)
        let captureDecision3 = !cadence.shouldCapture(at: 1.008, deadline: 1.024)
        #expect(captureDecision3)
        let captureDecision4 = cadence.shouldCapture(at: 1 + 1.0 / 60, deadline: 1.034)
        #expect(captureDecision4)
    }

    @Test("Capture cost, rather than display rate, bounds main-thread usage")
    func expensiveCapturesRespectBudget() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.040, at: 1)
        #expect(cadence.captureInterval >= 0.040 / 0.60)
        let captureDecision5 = !cadence.shouldCapture(at: 1.05, deadline: 1.2)
        #expect(captureDecision5)
        let captureDecision6 = cadence.shouldCapture(at: 1.23, deadline: 1.28)
        #expect(captureDecision6)
    }

    @Test("A capture waits when its estimated cost misses the frame deadline")
    func deadlineProtectsCurrentAnimation() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.008, at: 1)
        let captureDecision7 = !cadence.shouldCapture(at: 1.05, deadline: 1.058)
        #expect(captureDecision7)
        let captureDecision8 = cadence.shouldCapture(at: 1.05, deadline: 1.060)
        #expect(captureDecision8)
    }

    @Test("Over-budget capture retries without starving or spinning every frame")
    func expensiveCaptureDoesNotStarve() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.040, at: 1)
        let captureDecision9 = !cadence.shouldCapture(at: 1.23, deadline: 1.246)
        #expect(captureDecision9)
        let captureDecision10 = cadence.shouldCapture(at: 1.251, deadline: 1.267)
        #expect(captureDecision10)
        cadence.recordCapture(duration: 0.040, at: 1.251)
        let captureDecision11 = !cadence.shouldCapture(at: 1.267, deadline: 1.283)
        #expect(captureDecision11)
    }

    @Test("An initially exhausted deadline gets a bounded retry")
    func initialCaptureDoesNotStarve() {
        var cadence = TabBarCaptureCadence()
        let captureDecision12 = !cadence.shouldCapture(at: 1, deadline: 1)
        #expect(captureDecision12)
        let captureDecision13 = !cadence.shouldCapture(at: 1.1, deadline: 1.1)
        #expect(captureDecision13)
        let captureDecision14 = cadence.shouldCapture(at: 1.251, deadline: 1.251)
        #expect(captureDecision14)
    }

    @Test("Initial and layout-change captures may explicitly bypass the deadline")
    func forcedCapture() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.040, at: 1)
        let captureDecision15 = cadence.shouldCapture(at: 1.001, deadline: 1.001, force: true)
        #expect(captureDecision15)
    }

    @Test("One slow allocation does not permanently lower the sampling rate")
    func expensiveSpikeDecays() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.040, at: 1)
        for index in 1...40 {
            cadence.recordCapture(duration: 0.001, at: 1 + Double(index))
        }
        #expect(cadence.captureInterval == 1.0 / 60)
        #expect(cadence.estimatedCaptureDuration < 0.002)
    }

    @Test("A measured cheaper retry promptly restores capture on a 120Hz display")
    func expensiveImageRecovery() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.040, at: 1)
        let beforeRetry = cadence.shouldCapture(at: 1.20, deadline: 1.2065)
        #expect(!beforeRetry)
        let retry = cadence.shouldCapture(at: 1.25, deadline: 1.2565)
        #expect(retry)
        cadence.recordCapture(duration: 0.005, at: 1.25)
        #expect(cadence.estimatedCaptureDuration < 0.0051)
        let nextSample = cadence.shouldCapture(at: 1.25 + 1.0 / 60,
                                               deadline: 1.25 + 1.0 / 60 + 0.0065)
        #expect(nextSample)
    }

    @Test("Regular 60Hz samples preserve the existing cost weighting")
    func regularSampleWeighting() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.012, at: 1)
        cadence.recordCapture(duration: 0.005, at: 1 + 1.0 / 60)
        #expect(abs(cadence.estimatedCaptureDuration - 0.012 * 0.85) < 0.000_001)
    }

    @Test("Elapsed time without a cheaper measurement never relaxes the deadline")
    func expensiveCaptureStillNeedsTime() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.012, at: 1)
        for tick in 1...24 {
            let time = 1 + Double(tick) / 120
            let canCapture = cadence.shouldCapture(at: time, deadline: time + 0.0065)
            #expect(!canCapture)
        }
        #expect(cadence.estimatedCaptureDuration == 0.012)
        // Even after a retry, genuinely expensive work remains over deadline.
        cadence.recordCapture(duration: 0.012, at: 1.25)
        let afterRetry = cadence.shouldCapture(at: 1.30, deadline: 1.3065)
        #expect(!afterRetry)
        #expect(cadence.estimatedCaptureDuration == 0.012)
    }

    @Test("Reset clears both timing and obsolete performance estimates")
    func resetRestoresInitialCadence() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: 0.040, at: 10)
        cadence.reset()
        #expect(cadence.captureInterval == 1.0 / 60)
        let captureDecision16 = cadence.shouldCapture(at: 1, deadline: 1.016)
        #expect(captureDecision16)
    }

    @Test("Invalid timing never poisons future captures")
    func invalidTiming() {
        var cadence = TabBarCaptureCadence()
        cadence.recordCapture(duration: .nan, at: 1)
        cadence.recordCapture(duration: .infinity, at: 1)
        cadence.recordCapture(duration: -1, at: 1)
        cadence.recordCapture(duration: 1, at: .infinity)
        #expect(cadence.captureInterval == 1.0 / 60)
        let captureDecision17 = !cadence.shouldCapture(at: .nan, deadline: 1, force: true)
        #expect(captureDecision17)
        let captureDecision18 = !cadence.shouldCapture(at: 1, deadline: .nan)
        #expect(captureDecision18)
        let captureDecision19 = cadence.shouldCapture(at: 1, deadline: 1.016)
        #expect(captureDecision19)
    }
}
