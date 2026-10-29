import Testing
import CoreGraphics
@testable import XStyle_TabBar

@MainActor
struct TabQuickSwitchListTransitionTests {
    @Test("Moving replacement hides outgoing rows, moves one card, then reveals only the current generation")
    func movingStages() {
        var transition = visible(1)
        transition.request(2, style: .movingCard)
        let generation = transition.generation
        #expect(transition.stage == .moveFadeOut)
        #expect(transition.displayedID == 1)
        #expect(!transition.permitsVisibleRows)
        transition.complete(generation: generation)
        #expect(transition.stage == .moving)
        #expect(transition.displayedID == 2)
        #expect(!transition.permitsVisibleRows)
        transition.complete(generation: generation)
        #expect(transition.stage == .moveFadeIn)
        #expect(transition.permitsVisibleRows)
        transition.complete(generation: generation)
        #expect(transition.stage == .visible)
    }

    @Test("A newer target interrupts a moving card without resurrecting an obsolete completion")
    func retargetDuringMovement() {
        var transition = visible(1)
        transition.request(2, style: .movingCard)
        let oldGeneration = transition.generation
        transition.complete(generation: oldGeneration)
        #expect(transition.stage == .moving)
        transition.request(3, style: .movingCard)
        #expect(transition.stage == .moving)
        #expect(transition.displayedID == 3)
        let acceptedOldCompletion = transition.complete(generation: oldGeneration)
        #expect(!acceptedOldCompletion)
        #expect(transition.stage == .moving)
        transition.complete(generation: transition.generation)
        #expect(transition.stage == .moveFadeIn)
        #expect(transition.requestedID == 3)
    }

    @Test("Sequential replacement keeps the outgoing generation until its fade completes")
    func sequentialStages() {
        var transition = visible(1)
        transition.request(2, style: .sequentialFade)
        let oldGeneration = transition.generation
        #expect(transition.stage == .sequentialFadeOut)
        #expect(transition.displayedID == 1)
        #expect(!transition.permitsVisibleRows)
        transition.request(3, style: .sequentialFade)
        #expect(transition.displayedID == 1)
        let acceptedOldCompletion = transition.complete(generation: oldGeneration)
        #expect(!acceptedOldCompletion)
        transition.complete(generation: transition.generation)
        #expect(transition.stage == .sequentialFadeIn)
        #expect(transition.displayedID == 3)
        #expect(transition.permitsVisibleRows)
    }

    @Test("Immediate replacement has no intermediate selectable generation")
    func immediateReplacement() {
        var transition = visible(1)
        transition.request(2, style: .immediate)
        #expect(transition.stage == .visible)
        #expect(transition.requestedID == 2)
        #expect(transition.displayedID == 2)
        #expect(!transition.acceptsRows(presentationID: 1, contentOpacity: 1, hasPresentationLayer: true))
        #expect(transition.acceptsRows(presentationID: 2, contentOpacity: 1, hasPresentationLayer: false))
    }

    @Test("Reopening before collapse finishes always uses entrance behavior",
          arguments: TabQuickSwitchListSwitchStyle.allCases)
    func reopenInterruptsCollapse(_ style: TabQuickSwitchListSwitchStyle) {
        var transition = visible(1)
        transition.request(nil, style: style)
        let closingGeneration = transition.generation
        #expect(transition.stage == .closing)
        transition.request(2, style: style)
        #expect(transition.stage == .entrance)
        #expect(transition.displayedID == 2)
        let acceptedClosingCompletion = transition.complete(generation: closingGeneration)
        #expect(!acceptedClosingCompletion)
        #expect(transition.stage == .entrance)
    }

    @Test("An entrance cannot hit invisible model-layer rows before its first displayed frame")
    func entranceVisibilityGate() {
        var transition = TabQuickSwitchListTransition()
        transition.request(1, style: .movingCard)
        #expect(!transition.acceptsRows(presentationID: 1, contentOpacity: 1, hasPresentationLayer: false))
        #expect(!transition.acceptsRows(presentationID: 1, contentOpacity: 0, hasPresentationLayer: true))
        #expect(transition.acceptsRows(presentationID: 1, contentOpacity: 0.4, hasPresentationLayer: true))
        #expect(!transition.acceptsRows(presentationID: 2, contentOpacity: 1, hasPresentationLayer: true))
        transition.complete(generation: transition.generation)
        #expect(transition.acceptsRows(presentationID: 1, contentOpacity: 1, hasPresentationLayer: false))
    }

    @Test("Highlight and scroll updates do not restart an unchanged transition")
    func duplicateRequestDoesNotRestart() {
        var transition = visible(1)
        transition.request(2, style: .movingCard)
        let previous = transition
        let restarted = transition.request(2, style: .movingCard)
        #expect(!restarted)
        #expect(transition == previous)
    }

    @Test("Row hit testing clips rounded corners, card gaps, and scrolled-out rows")
    func snapshotHitsVisibleRows() {
        let snapshot = TabQuickSwitchListSnapshot(
            presentationID: 7, cardFrame: CGRect(x: 20, y: 300, width: 200, height: 100),
            rows: [.init(destination: .scan, frame: CGRect(x: 6, y: 6, width: 188, height: 44)),
                   .init(destination: .scanHistory, frame: CGRect(x: 6, y: 50, width: 188, height: 44)),
                   .init(destination: .homePage(.likes), frame: CGRect(x: 6, y: 94, width: 188, height: 44))],
            contentHeight: 144
        )
        #expect(snapshot.destination(at: CGPoint(x: 100, y: 20), scrollOffset: 0) == .scan)
        #expect(snapshot.destination(at: CGPoint(x: 100, y: 70), scrollOffset: 0) == .scanHistory)
        #expect(snapshot.destination(at: CGPoint(x: 100, y: 20), scrollOffset: 44) == .scanHistory)
        #expect(snapshot.destination(at: CGPoint(x: 100, y: 70), scrollOffset: 44) == .homePage(.likes))
        #expect(snapshot.destination(at: CGPoint(x: 100, y: 101), scrollOffset: 44) == nil)
        #expect(snapshot.destination(at: CGPoint(x: 7, y: 7), scrollOffset: 0) == nil)
        #expect(snapshot.destination(at: CGPoint(x: 2, y: 50), scrollOffset: 0) == nil)
        #expect(snapshot.destination(at: CGPoint(x: 100, y: 2), scrollOffset: 0) == nil)
    }

    @Test("Reused presentation layers cannot authorize a newly installed generation")
    func displayFenceRejectsUnrenderedGeneration() {
        var fence = TabQuickSwitchListDisplayFence()
        fence.install(1)
        fence.tick(at: 10, presentationID: 1)
        #expect(!fence.permits(1))
        fence.tick(at: 10.016, presentationID: 1)
        #expect(fence.permits(1))
        fence.install(2)
        #expect(!fence.permits(2))
        fence.tick(at: 10.032, presentationID: 1)
        #expect(!fence.permits(2))
        fence.tick(at: 10.048, presentationID: 2)
        #expect(!fence.permits(2))
        fence.tick(at: 10.064, presentationID: 2)
        #expect(fence.permits(2))
        #expect(!fence.permits(1))
    }

    @Test("Vertical card measurement stays in the space inward from either rail")
    func inwardWidthAndEntranceAnchor() {
        let area = CGRect(x: 16, y: 16, width: 358, height: 760)
        let left = CGRect(x: 8, y: 300, width: 64, height: 240)
        let right = CGRect(x: 318, y: 300, width: 64, height: 240)
        #expect(TabQuickSwitchListSnapshot.maximumCardWidth(area: area, bar: left, vertical: true) == 292)
        #expect(TabQuickSwitchListSnapshot.maximumCardWidth(area: area, bar: right, vertical: true) == 292)
        let tab = CGRect(x: 318, y: 350, width: 64, height: 60)
        let card = CGRect(x: 16, y: 300, width: 292, height: 200)
        #expect(TabQuickSwitchListSnapshot.entranceAnchor(tab: tab, card: card, bar: right, vertical: true)
                == CGPoint(x: 1, y: 0.4))
        #expect(TabQuickSwitchListSnapshot.entranceAnchor(tab: tab, card: card, bar: right, vertical: false).y == 1)
    }

    private func visible(_ id: UInt64) -> TabQuickSwitchListTransition {
        var transition = TabQuickSwitchListTransition()
        transition.request(id, style: .movingCard)
        transition.complete(generation: transition.generation)
        return transition
    }
}
