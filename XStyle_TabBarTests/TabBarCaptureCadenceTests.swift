import Testing
@testable import XStyle_TabBar

struct TabBarCaptureCadenceTests {
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
