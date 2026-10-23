import CoreGraphics
import Testing
@testable import XStyle_TabBar

@MainActor
struct ScanRevealTests {
    @Test("With Reduce Motion, live brackets fade in on the code instead of flying there")
    func liveBracketsWithReduceMotion() {
        let halfway = ScanRevealTimeline.reducedMotionFade / 2
        let live = ScanRevealTimeline.frame(at: halfway, freezeTime: nil, closeTime: nil, style: .liveBrackets, reduceMotion: true)
        #expect(live.bracketProgress == 1)
        #expect(live.bracketOpacity == 0.5)

        // The full reveal crossfades to its card instead, so its brackets stay hidden.
        let full = ScanRevealTimeline.frame(at: halfway, freezeTime: nil, closeTime: nil, style: .fullReveal, reduceMotion: true)
        #expect(full.bracketOpacity == 0)
    }

    @Test("Without Reduce Motion, both styles fly their brackets to the code")
    func bracketsFly() {
        for style in ScanRevealStyle.allCases {
            let frame = ScanRevealTimeline.frame(at: 0, freezeTime: nil, closeTime: nil, style: style, reduceMotion: false)
            #expect(frame.bracketProgress == 0)
            #expect(frame.bracketOpacity == 1)
        }
    }

    #if targetEnvironment(simulator)
    @Test("Live brackets open the result at once, then let the code go while the result stays open")
    func liveBracketsSequence() async throws {
        let model = ScannerModel()
        model.revealStyle = .liveBrackets
        model.updateScreen(size: CGSize(width: 386, height: 662), displayScale: 3)
        let run = Task { await model.run(preparePreview: { _ in }) }
        defer { run.cancel() }
        try #require(await eventually(within: 3) { model.isAiming })

        model.simulateScan()
        try #require(await eventually(within: 3) { model.revealedCode != nil })
        // The result opens with the reveal, not after it.
        #expect(model.scannedCode == model.revealedCode)
        #expect(model.reveal?.style == .liveBrackets)
        #expect(model.reveal?.frozen == nil)

        let holdAndClose = ScanRevealTimeline.liveHold + ScanRevealTimeline.closeDuration
        #expect(await eventually(within: holdAndClose + 1) { model.revealedCode == nil })
        #expect(model.reveal == nil)
        #expect(model.scannedCode != nil)
        // Scanning with the result open, the camera aims again.
        #expect(model.isAiming)
    }
    #endif

    private func eventually(within seconds: Double, _ condition: () -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
