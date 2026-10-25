import Testing
import CoreGraphics
@testable import XStyle_TabBar

@MainActor
struct TabQuickSwitchHoldTests {
    @Test("A hold opens once, at its deadline, and never before")
    func opensOnceAtDeadline() throws {
        var hold = TabQuickSwitchHold()
        let generation = hold.begin(at: 10, duration: 0.45)
        let deadline = try #require(hold.pending?.deadline)
        #expect(deadline == 10 + 0.45)
        let opensEarly = hold.fire(generation: generation, at: deadline.nextDown)
        #expect(!opensEarly)
        let opensOnTime = hold.fire(generation: generation, at: deadline)
        #expect(opensOnTime)
        #expect(hold.pending == nil)
        let opensAgain = hold.fire(generation: generation, at: 11)
        #expect(!opensAgain)
    }

    @Test("A cancelled or replaced hold's timer opens nothing")
    func staleTimersOpenNothing() {
        var hold = TabQuickSwitchHold()
        let first = hold.begin(at: 0, duration: 0.45)
        hold.cancel()
        let cancelledOpens = hold.fire(generation: first, at: 1)
        #expect(!cancelledOpens)

        let second = hold.begin(at: 2, duration: 0.45)
        let third = hold.begin(at: 3, duration: 0.45)
        #expect(second != third)
        let replacedOpens = hold.fire(generation: second, at: 4)
        #expect(!replacedOpens)
        let latestOpens = hold.fire(generation: third, at: 4)
        #expect(latestOpens)
    }
}

@MainActor
struct TabQuickSwitchHoldSettingTests {
    @Test("The stored hold time stays within the range the setting offers")
    func storedHoldTimeIsClamped() {
        let range = TabQuickSwitchSettings.holdDurationRange
        #expect(range.contains(TabQuickSwitchSettings.defaultHoldDuration))
        #expect(TabQuickSwitchSettings.clampedHoldDuration(0.3) == 0.3)
        #expect(TabQuickSwitchSettings.clampedHoldDuration(0) == range.lowerBound)
        #expect(TabQuickSwitchSettings.clampedHoldDuration(5) == range.upperBound)
        #expect(TabQuickSwitchSettings.clampedHoldDuration(.nan) == TabQuickSwitchSettings.defaultHoldDuration)
    }
}

@MainActor
struct TabQuickSwitchListScrollTests {
    private let viewport = CGRect(x: 40, y: 100, width: 200, height: 300)

    @Test("A list that fits never scrolls")
    func fittingListStays() {
        var scroll = TabQuickSwitchListScroll(viewport: viewport, contentHeight: viewport.height)
        #expect(scroll.maximumOffset == 0)
        #expect(scroll.velocity(at: CGPoint(x: viewport.midX, y: viewport.maxY - 1)) == 0)
        let scrolls = scroll.scroll(by: 50)
        #expect(!scrolls)
    }

    @Test("Resting near an edge with rows past it scrolls, faster nearer the edge; elsewhere nothing moves")
    func edgesScrollTowardsHiddenRows() {
        var scroll = TabQuickSwitchListScroll(viewport: viewport, contentHeight: viewport.height + 120)
        let band = TabQuickSwitchMetrics.listScrollBand
        let speed = TabQuickSwitchMetrics.listScrollSpeed
        #expect(scroll.maximumOffset == 120)
        // Nothing above yet: the top edge rests.
        #expect(scroll.velocity(at: CGPoint(x: viewport.midX, y: viewport.minY)) == 0)
        #expect(scroll.velocity(at: CGPoint(x: viewport.midX, y: viewport.maxY - band / 2)) == speed / 2)
        #expect(scroll.velocity(at: CGPoint(x: viewport.midX, y: viewport.midY)) == 0)
        // Only a finger on the card scrolls it.
        #expect(scroll.velocity(at: CGPoint(x: viewport.maxX + 1, y: viewport.maxY - 1)) == 0)
        #expect(scroll.velocity(at: CGPoint(x: viewport.midX, y: viewport.maxY + 1)) == 0)

        let scrollsToEnd = scroll.scroll(by: 500)
        #expect(scrollsToEnd)
        #expect(scroll.offset == 120)
        #expect(scroll.velocity(at: CGPoint(x: viewport.midX, y: viewport.maxY - 1)) == 0)
        #expect(scroll.velocity(at: CGPoint(x: viewport.midX, y: viewport.minY)) == -speed)
        let scrollsToStart = scroll.scroll(by: -500)
        #expect(scrollsToStart)
        #expect(scroll.offset == 0)
    }

    @Test("A new layout keeps the offset within its own range")
    func relayoutKeepsOffset() {
        var scroll = TabQuickSwitchListScroll(viewport: viewport, contentHeight: viewport.height + 120)
        scroll.scroll(by: 100)
        scroll.update(viewport: viewport, contentHeight: viewport.height + 150)
        #expect(scroll.offset == 100)
        scroll.update(viewport: viewport, contentHeight: viewport.height + 40)
        #expect(scroll.offset == 40)
    }
}
