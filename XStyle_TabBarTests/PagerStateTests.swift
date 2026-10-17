import SwiftUI
import Testing
@testable import XStyle_TabBar

@MainActor
struct PagerStateTests {
    @Test("Dragging holds the highlight until native paging commits")
    func highlightsDestinationBeforeItBecomesTheSettledPage() {
        let pager = makePager()
        beginDrag(pager)
        pager.update(geometry(0.7))
        pager.receive(target(.videos, for: pager))

        #expect(pager.selectedTab == .bookmarks)
        #expect(pager.highlightedTab == .bookmarks)

        setPhase(pager, .decelerating, at: 0.7)
        #expect(pager.highlightedTab == .videos)
        #expect(pager.selectedTab == .bookmarks)

        setPhase(pager, .idle, at: 1)
        #expect(pager.selectedTab == .videos)
        #expect(pager.highlightedTab == .videos)
        #expect(pager.isAtRest)
    }

    @Test("A destination delivered after deceleration begins still commits")
    func acceptsDestinationDuringDeceleration() {
        let pager = makePager()
        beginDrag(pager)
        setPhase(pager, .decelerating, at: 0.6)
        pager.receive(target(.videos, for: pager))

        #expect(pager.highlightedTab == .videos)
        #expect(pager.selectedTab == .bookmarks)
    }

    @Test("A cancelled swipe never selects the page it briefly exposed")
    func cancellationReturnsToTheOriginalPage() {
        let pager = makePager()
        beginDrag(pager)
        pager.update(geometry(0.65))
        pager.receive(target(.bookmarks, for: pager))
        setPhase(pager, .decelerating, at: 0.65)
        setPhase(pager, .idle, at: 0)

        #expect(pager.selectedTab == .bookmarks)
        #expect(pager.highlightedTab == .bookmarks)
        #expect(pager.isAtRest)
    }

    @Test("At rest the actual page reconciles a missing destination callback")
    func settledGeometryIsTheFinalAuthority() {
        let pager = makePager()
        beginDrag(pager)
        let lateTarget = target(.articles, for: pager)
        setPhase(pager, .decelerating, at: 0.8)
        setPhase(pager, .idle, at: 1)
        pager.receive(lateTarget)

        #expect(pager.selectedTab == .videos)
        #expect(pager.highlightedTab == .videos)
    }

    @Test("Reversing an active swipe invalidates its old destination")
    func reversalRejectsThePreviousGesture() {
        let pager = makePager()
        beginDrag(pager)
        pager.receive(target(.videos, for: pager))
        let staleTarget = target(.articles, for: pager)
        setPhase(pager, .decelerating, at: 0.7)

        setPhase(pager, .tracking, at: 0.7)
        let newGestureID = pager.gestureID
        setPhase(pager, .interacting, at: 0.6)
        #expect(pager.gestureID == newGestureID)
        #expect(pager.gestureID != staleTarget.gestureID)

        pager.receive(staleTarget)
        #expect(pager.highlightedTab == .videos)

        pager.receive(target(.bookmarks, for: pager))
        setPhase(pager, .decelerating, at: 0.3)
        #expect(pager.highlightedTab == .bookmarks)
        setPhase(pager, .idle, at: 0)
        #expect(pager.selectedTab == .bookmarks)
    }

    @Test("Resizing retains the committed page and rejects old-width targets")
    func resizeWaitsForTheNewPageBoundary() {
        let pager = makePager()
        beginDrag(pager)
        pager.receive(target(.videos, for: pager))
        let staleTarget = target(.articles, for: pager)
        setPhase(pager, .decelerating, at: 0.7)

        pager.update(PagerGeometry(offset: 280, width: 736))
        #expect(pager.viewportWidth == 736)
        #expect(pager.gestureID != staleTarget.gestureID)
        #expect(pager.selectedTab == .bookmarks)
        #expect(!pager.isAtRest)

        pager.receive(staleTarget)
        pager.receive(PagerTarget(index: AppTab.articles.index, width: 400, gestureID: pager.gestureID))
        #expect(pager.highlightedTab == .videos)

        pager.update(PagerGeometry(offset: 736, width: 736))
        pager.scrollPhaseDidChange(from: .decelerating, to: .idle, geometry: PagerGeometry(offset: 736, width: 736))
        #expect(pager.selectedTab == .videos)
        #expect(pager.highlightedTab == .videos)
        #expect(pager.isAtRest)
    }

    @Test("Invalid target indices and unrelated viewport widths are ignored")
    func rejectsInvalidNativeReports() {
        let pager = makePager()
        beginDrag(pager)
        setPhase(pager, .decelerating, at: 0.5)
        pager.receive(PagerTarget(index: -1, width: 400, gestureID: pager.gestureID))
        pager.receive(PagerTarget(index: 5, width: 400, gestureID: pager.gestureID))
        pager.receive(PagerTarget(index: 1, width: 300, gestureID: pager.gestureID))

        #expect(pager.highlightedTab == .bookmarks)
    }

    @Test("A resize during a distant jump retains its destination until aligned")
    func resizedTapCompletesOnTheNewViewport() {
        let pager = makePager()
        pager.select(.quizz)
        setPhase(pager, .animating, at: 1.5)
        pager.update(PagerGeometry(offset: 600, width: 736))

        #expect(pager.selectedTab == .bookmarks)
        #expect(pager.highlightedTab == .quizz)
        #expect(pager.tapTransition?.destination == .quizz)

        pager.scrollPhaseDidChange(from: .animating, to: .idle, geometry: PagerGeometry(offset: 600, width: 736))
        #expect(pager.tapTransition?.destination == .quizz)
        #expect(!pager.isAtRest)

        pager.update(PagerGeometry(offset: 4 * 736, width: 736))
        #expect(pager.selectedTab == .quizz)
        #expect(pager.highlightedTab == .quizz)
        #expect(pager.tapTransition == nil)
        #expect(pager.isAtRest)
    }

    @Test("Only the latest queued distant tap runs after the active jump")
    func distantTapsKeepOnlyTheLatestQueuedDestination() {
        let pager = makePager()
        pager.select(.quizz)
        #expect(pager.tapTransition?.source == .bookmarks)
        #expect(pager.tapTransition?.destination == .quizz)
        #expect(pager.highlightedTab == .quizz)
        #expect(pager.selectedTab == .bookmarks)

        setPhase(pager, .animating, at: 0)
        pager.select(.articles)
        pager.select(.likes)
        #expect(pager.pendingTab == .likes)
        #expect(pager.highlightedTab == .quizz)

        setPhase(pager, .idle, at: 4)
        #expect(pager.selectedTab == .quizz)
        #expect(pager.tapTransition?.source == .quizz)
        #expect(pager.tapTransition?.destination == .likes)
        #expect(pager.highlightedTab == .likes)
        #expect(pager.pendingTab == nil)

        setPhase(pager, .animating, at: 4)
        setPhase(pager, .idle, at: 3)
        #expect(pager.selectedTab == .likes)
        #expect(pager.tapTransition == nil)
        #expect(pager.isAtRest)
    }

    @Test("A fractional width change is used for layout and distant-jump completion")
    func fractionalResizeKeepsTheViewportAndDestinationAligned() {
        let pager = makePager()
        pager.update(PagerGeometry(offset: 0, width: 400.5))
        #expect(pager.viewportWidth == 400.5)

        pager.select(.quizz)
        pager.update(PagerGeometry(offset: 1_602, width: 400.5))

        #expect(pager.progress == 4)
        #expect(pager.selectedTab == .quizz)
        #expect(pager.highlightedTab == .quizz)
        #expect(pager.tapTransition == nil)
        #expect(pager.isAtRest)
    }

    @Test("A tap queued during a swipe starts at the actual landing page")
    func queuedTapUsesTheSettledSource() {
        let pager = makePager()
        beginDrag(pager)
        pager.select(.quizz)
        pager.select(.articles)
        #expect(pager.tapTransition == nil)

        pager.receive(target(.videos, for: pager))
        setPhase(pager, .decelerating, at: 0.7)
        setPhase(pager, .idle, at: 1)

        #expect(pager.selectedTab == .videos)
        #expect(pager.tapTransition?.source == .videos)
        #expect(pager.tapTransition?.destination == .articles)
        #expect(pager.pendingTab == nil)
    }

    @Test("Repeating the destination clears the queue without another jump")
    func tappingTheCurrentDestinationDoesNotLeavePendingWork() {
        let pager = makePager()
        pager.select(.quizz)
        setPhase(pager, .animating, at: 0)
        pager.select(.quizz)
        setPhase(pager, .idle, at: 4)

        #expect(pager.selectedTab == .quizz)
        #expect(pager.pendingTab == nil)
        #expect(pager.tapTransition == nil)
        #expect(pager.isAtRest)
    }

    @Test("A tap made before layout waits for a usable viewport")
    func deferredLayoutKeepsTheRequestedDestination() {
        let pager = PagerState()
        pager.select(.articles)
        pager.update(PagerGeometry(offset: 0, width: 0))
        #expect(pager.tapTransition == nil)
        #expect(pager.pendingTab == .articles)

        pager.update(geometry(0))
        #expect(pager.tapTransition?.destination == .articles)
        #expect(pager.pendingTab == nil)
    }

    @Test("Reduce Motion preserves selection and completion without animated phases")
    func reducedMotionCanCompleteThroughGeometryAlone() {
        let pager = makePager()
        pager.setReduceMotion(true)
        pager.select(.quizz)
        pager.update(geometry(4))

        #expect(pager.highlightedTab == .quizz)
        #expect(pager.selectedTab == .quizz)
        #expect(pager.tapTransition == nil)
        #expect(pager.isAtRest)
    }

    private func makePager() -> PagerState {
        let pager = PagerState()
        pager.update(geometry(0))
        return pager
    }

    private func geometry(_ progress: CGFloat) -> PagerGeometry {
        PagerGeometry(offset: progress * 400, width: 400)
    }

    private func beginDrag(_ pager: PagerState) {
        setPhase(pager, .tracking, at: 0)
        setPhase(pager, .interacting, at: 0)
    }

    private func setPhase(_ pager: PagerState, _ phase: ScrollPhase, at progress: CGFloat) {
        pager.scrollPhaseDidChange(from: pager.phase, to: phase, geometry: geometry(progress))
    }

    private func target(_ tab: AppTab, for pager: PagerState) -> PagerTarget {
        PagerTarget(index: tab.index, width: pager.viewportWidth, gestureID: pager.gestureID)
    }
}
