import CoreGraphics
import Observation
import Testing
@testable import XStyle_TabBar

@MainActor
struct ScannerSheetTests {
    /// A 402 × 874 pt iPhone whose bottom safe area holds the tab bar's toolbar.
    private let canvas = PaneCanvas(size: CGSize(width: 402, height: 874), safeAreaTop: 62, safeAreaBottom: 96)
    private let metrics = SheetMetrics.floating

    private func paneLayout(
        sheetTop: CGFloat, footerHeight: CGFloat = 0, mode: ViewportMode = .resizing
    ) throws -> PaneLayout {
        try #require(PaneLayout(
            sheetTop: sheetTop, canvas: canvas, sideInset: metrics.paneSideInset,
            tops: metrics.tops(for: canvas), footerHeight: footerHeight, mode: mode
        ))
    }

    private func paneFrame(sheetTop: CGFloat, footerHeight: CGFloat = 0) throws -> CGRect {
        try paneLayout(sheetTop: sheetTop, footerHeight: footerHeight).paneFrame
    }

    private func sheet(at detent: SheetDetent) -> SheetController {
        let sheet = SheetController(initialDetent: detent)
        sheet.updateCanvas(canvas)
        return sheet
    }

    private func release(_ sheet: SheetController, afterDraggingBy distance: CGFloat) {
        sheet.beginDrag()
        sheet.drag(by: distance, velocity: 0)
        sheet.endDrag(velocity: 0)
    }

    @Test("The hidden sheet rests below the screen, under every detent")
    func hiddenIsLowest() {
        let tops = metrics.tops(for: canvas)
        #expect(tops.hidden == 874)
        #expect(tops.hidden > tops.medium)
        #expect(tops.medium > tops.full)
    }

    @Test("With the sheet hidden, the pane stops one gap above the tab bar")
    func paneClearsTabBar() throws {
        #expect(try paneFrame(sheetTop: 874) == CGRect(x: 8, y: 70, width: 386, height: 700))
        #expect(try paneFrame(sheetTop: 800).maxY == 770)
    }

    @Test("The pane leaves room for its footer, and never grows into it as the sheet rises")
    func paneMakesRoomForFooter() throws {
        let tops = metrics.tops(for: canvas)
        // The footer's 30 pt and a gap above it come off the pane.
        let hidden = try paneFrame(sheetTop: tops.hidden, footerHeight: 30)
        #expect(hidden == CGRect(x: 8, y: 70, width: 386, height: 662))
        #expect(try paneFrame(sheetTop: 800, footerHeight: 30) == hidden)
        #expect(try paneFrame(sheetTop: tops.medium, footerHeight: 30) == paneFrame(sheetTop: tops.medium))
        // The footer itself stays one gap above the bottom safe area, wherever the sheet is.
        #expect(try paneLayout(sheetTop: tops.hidden, footerHeight: 30).footerBottom == 770)
        #expect(try paneLayout(sheetTop: tops.medium, footerHeight: 30).footerBottom == 770)
    }

    @Test("A footer shorter than the gap brings only as much of the gap, so its room grows from nothing")
    func footerRoomGrowsFromNothing() throws {
        let tops = metrics.tops(for: canvas)
        // 4 pt of footer brings 4 pt of the 8 pt gap; 8 pt brings all of it.
        #expect(try paneFrame(sheetTop: tops.hidden, footerHeight: 4) == CGRect(x: 8, y: 70, width: 386, height: 692))
        #expect(try paneFrame(sheetTop: tops.hidden, footerHeight: 8) == CGRect(x: 8, y: 70, width: 386, height: 684))
    }

    @Test("The footer counts as covered once the sheet's top is above its bottom edge")
    func footerCoverage() throws {
        let tops = metrics.tops(for: canvas)
        #expect(try !paneLayout(sheetTop: tops.hidden).isFooterCovered)
        #expect(try !paneLayout(sheetTop: 770).isFooterCovered)
        #expect(try paneLayout(sheetTop: 769).isFooterCovered)
        #expect(try paneLayout(sheetTop: tops.medium).isFooterCovered)
    }

    @Test("The footer's first height lands at once, and a stop settles one under way")
    func footerHeightSettles() {
        let model = TopPaneModel()
        model.setMeasuredFooter(44)
        #expect(model.footerHeight == 44)

        model.setMeasuredFooter(120)
        model.stop()
        #expect(model.footerHeight == 120)
    }

    @Test("With Reduce Motion, the footer takes every new height at once")
    func footerHeightWithReduceMotion() {
        let model = TopPaneModel()
        model.reduceMotion = true
        model.setMeasuredFooter(44)
        model.setMeasuredFooter(120)
        #expect(model.footerHeight == 120)
    }

    @Test("At medium, the pane keeps one gap above the sheet")
    func paneFollowsSheet() throws {
        let tops = metrics.tops(for: canvas)
        #expect(try paneFrame(sheetTop: tops.medium) == CGRect(x: 8, y: 70, width: 386, height: (tops.medium - 8) - 70))
    }

    @Test("Above medium, the pane holds its medium frame while the sheet covers it")
    func paneHoldsMediumFrame() throws {
        let tops = metrics.tops(for: canvas)
        let medium = try paneLayout(sheetTop: tops.medium)
        let full = try paneLayout(sheetTop: tops.full)
        #expect(medium.coverProgress == 0)
        #expect(full.paneFrame == medium.paneFrame)
        #expect(full.coverProgress == 1)
        #expect(try paneFrame(sheetTop: (tops.medium + tops.full) / 2) == medium.paneFrame)
    }

    @Test("Fixed and receding panes keep their resting frame wherever the sheet is", arguments: [ViewportMode.fixed, .receding])
    func fixedPaneKeepsFrame(mode: ViewportMode) throws {
        let tops = metrics.tops(for: canvas)
        let resting = try paneLayout(sheetTop: tops.hidden, footerHeight: 30, mode: mode)
        #expect(resting.paneFrame == CGRect(x: 8, y: 70, width: 386, height: 662))
        for top in [tops.medium, (tops.medium + tops.full) / 2, tops.full] {
            #expect(try paneLayout(sheetTop: top, footerHeight: 30, mode: mode).paneFrame == resting.paneFrame)
        }
        // Covering past medium still pauses the camera at full.
        #expect(try paneLayout(sheetTop: tops.full, mode: mode).coverProgress == 1)
    }

    @Test("A fixed pane never scales; a receding one shrinks a little by medium and more by full")
    func paneScales() throws {
        let tops = metrics.tops(for: canvas)
        for top in [tops.hidden, tops.medium, tops.full] {
            #expect(try paneLayout(sheetTop: top, mode: .fixed).scale == 1)
        }
        let scales = PaneTuning.recedingScale
        #expect(try paneLayout(sheetTop: tops.hidden, mode: .receding).scale == scales.hidden)
        #expect(try paneLayout(sheetTop: tops.medium, mode: .receding).scale == scales.medium)
        #expect(try paneLayout(sheetTop: tops.full, mode: .receding).scale == scales.full)
        #expect(scales.hidden > scales.medium && scales.medium > scales.full)
        #expect(try paneLayout(sheetTop: tops.full).scale == PaneTuning.coveredScale)
    }

    @Test("At and below medium, nothing covers the pane")
    func paneUncoveredBelowMedium() throws {
        let tops = metrics.tops(for: canvas)
        #expect(try paneLayout(sheetTop: tops.medium).coverProgress == 0)
        #expect(try paneLayout(sheetTop: tops.hidden).coverProgress == 0)
    }

    @Test("From medium, a drag past the threshold dismisses; a short one stays")
    func dragFromMedium() {
        let short = sheet(at: .medium)
        release(short, afterDraggingBy: SheetTuning.nextDetentDistance - 1)
        #expect(short.detent == .medium)

        let long = sheet(at: .medium)
        release(long, afterDraggingBy: SheetTuning.nextDetentDistance + 1)
        #expect(long.detent == .hidden)
    }

    @Test("From medium, a quick flick down dismisses")
    func flickFromMedium() {
        let sheet = sheet(at: .medium)
        sheet.beginDrag()
        sheet.drag(by: 10, velocity: SheetTuning.nextDetentVelocity + 1)
        sheet.endDrag(velocity: SheetTuning.nextDetentVelocity + 1)
        #expect(sheet.detent == .hidden)
    }

    @Test("Resting at full holds through pulls that spring back, and ends once a drag would leave full")
    func restsAtFull() {
        #expect(!sheet(at: .medium).restsAtFull)

        let sheet = sheet(at: .full)
        #expect(sheet.restsAtFull)
        // A drag the content takes leaves the sheet at full.
        sheet.beginDrag()
        sheet.drag(by: 0, velocity: 0)
        #expect(sheet.restsAtFull)
        // A pull past the top of the content, which the release snaps back.
        sheet.drag(by: SheetTuning.nextDetentDistance, velocity: 0)
        #expect(sheet.restsAtFull)
        // Past the snap distance, the release leaves full.
        sheet.drag(by: 1, velocity: 0)
        #expect(!sheet.restsAtFull)
    }

    @Test("A flick down from full ends resting there at once")
    func flickLeavesFull() {
        let sheet = sheet(at: .full)
        sheet.beginDrag()
        sheet.drag(by: 10, velocity: SheetTuning.nextDetentVelocity + 1)
        #expect(sheet.restsAtFull)
        sheet.endDrag(velocity: SheetTuning.nextDetentVelocity + 1)
        #expect(sheet.detent == .medium)
        #expect(!sheet.restsAtFull)
    }

    @Test("Settling at full rests there only once the spring arrives, not as it bounces")
    func restsAtFullOnArrival() async throws {
        let tops = metrics.tops(for: canvas)
        let sheet = sheet(at: .medium)
        sheet.settle(to: .full, velocity: 0)
        #expect(!sheet.restsAtFull)
        var restedAway = false
        let arrived = try await eventually {
            if sheet.restsAtFull, sheet.sheetTop != tops.full {
                restedAway = true
            }
            return sheet.restsAtFull
        }
        #expect(arrived)
        #expect(!restedAway)
        #expect(sheet.sheetTop == tops.full)
    }

    @Test("A settle reaches its detent once it meets or passes it, from either side")
    func settleReachesDetent() {
        // Up from hidden to medium.
        #expect(!SheetController.hasReached(497, from: 874, at: 600))
        #expect(SheetController.hasReached(497, from: 874, at: 497))
        #expect(SheetController.hasReached(497, from: 874, at: 490))
        // Down from full to medium.
        #expect(!SheetController.hasReached(497, from: 62, at: 300))
        #expect(SheetController.hasReached(497, from: 62, at: 500))
        // From the detent itself, with only a velocity to spend.
        #expect(SheetController.hasReached(497, from: 497, at: 480))
    }

    @Test("Past medium needs medium below full, as the pane's cover does")
    func pastMediumNeedsMediumBelowFull() {
        let tops = DetentValues(hidden: 874, medium: 497, full: 62)
        #expect(SheetController.isPastMedium(490, tops: tops))
        #expect(!SheetController.isPastMedium(497, tops: tops))
        // A short canvas puts medium above full.
        let short = DetentValues(hidden: 430, medium: 53, full: 62)
        #expect(!SheetController.isPastMedium(40, tops: short))
    }

    @Test("A drag counts as past medium wherever it holds the sheet above it")
    func dragPastMedium() {
        let sheet = sheet(at: .medium)
        #expect(!sheet.isPastMedium)
        sheet.beginDrag()
        sheet.drag(by: -10, velocity: 0)
        #expect(sheet.isPastMedium)
        sheet.drag(by: 20, velocity: 0)
        #expect(!sheet.isPastMedium)
    }

    @Test("A settle's bounce about medium never counts as past it", arguments: [SheetDetent.hidden, .full])
    func bounceAboutMedium(from start: SheetDetent) async throws {
        let tops = metrics.tops(for: canvas)
        let sheet = sheet(at: start)
        #expect(sheet.bounces)
        #expect(sheet.isPastMedium == (start == .full))
        let changes = ChangeCounter { sheet.isPastMedium }

        sheet.settle(to: .medium, velocity: 0)
        // The sheet itself does swing past medium, away from where it came from.
        var overshot = false
        #expect(try await eventually {
            if let top = sheet.sheetTop, start == .full ? top > tops.medium : top < tops.medium {
                overshot = true
            }
            return sheet.sheetTop == tops.medium
        })
        #expect(overshot)
        #expect(!sheet.isPastMedium)
        // From full it leaves past medium once, as it first reaches medium; from hidden it never gets there.
        #expect(changes.count == (start == .full ? 1 : 0))
    }

    @Test("A touch stopping the sheet in its bounce about medium, then letting go, is still the bounce")
    func holdInBounce() async throws {
        let tops = metrics.tops(for: canvas)
        let sheet = sheet(at: .hidden)
        let changes = ChangeCounter { sheet.isPastMedium }

        sheet.settle(to: .medium, velocity: 0)
        // Caught above medium, in its overshoot.
        #expect(try await eventually { (sheet.sheetTop ?? .infinity) < tops.medium })
        sheet.hold()
        sheet.releaseHold()
        #expect(try await eventually { sheet.sheetTop == tops.medium })
        #expect(!sheet.isPastMedium)
        #expect(changes.count == 0)
    }

    @Test("A settle from medium itself, with only a release's velocity, never counts as past it")
    func velocityFromMedium() async throws {
        let tops = metrics.tops(for: canvas)
        let sheet = sheet(at: .medium)
        let changes = ChangeCounter { sheet.isPastMedium }

        // Upward, short of the next detent's threshold.
        sheet.settle(to: .medium, velocity: -250)
        var rose = false
        #expect(try await eventually {
            if let top = sheet.sheetTop, top < tops.medium {
                rose = true
            }
            return rose && sheet.sheetTop == tops.medium
        })
        #expect(rose)
        #expect(changes.count == 0)
    }

    @Test("With the pane not following the bounce, it holds at medium from the moment the sheet first reaches it")
    func paneHoldsThroughBounce() async throws {
        let tops = metrics.tops(for: canvas)
        let sheet = sheet(at: .hidden)
        sheet.paneFollowsBounce = false

        sheet.settle(to: .medium, velocity: 0)
        var reached = false
        var leftMedium = false
        #expect(try await eventually {
            guard let top = sheet.sheetTop, let paneTop = sheet.paneSheetTop else { return false }
            if top <= tops.medium {
                reached = true
            }
            if reached, paneTop != tops.medium {
                leftMedium = true
            }
            return top == tops.medium
        })
        #expect(reached)
        #expect(!leftMedium)
    }

    @Test("From full, a drag down stops at medium")
    func dragFromFull() {
        let sheet = sheet(at: .full)
        release(sheet, afterDraggingBy: SheetTuning.nextDetentDistance + 1)
        #expect(sheet.detent == .medium)
    }

    @Test("Presenting plays no detent haptic; moving between detents does")
    func presentationHaptics() {
        let sheet = sheet(at: .hidden)
        let trigger = sheet.feedbackTrigger
        sheet.settle(to: .medium, velocity: 0)
        #expect(sheet.feedbackTrigger == trigger)
        sheet.settle(to: .full, velocity: 0)
        #expect(sheet.feedbackTrigger == trigger + 1)
    }

    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<150 {
            try await Task.sleep(for: .milliseconds(20))
            if condition() { return true }
        }
        return false
    }
}

/// Counts every change of an observed value. It observes again as each one is announced, so none slips by.
@MainActor
private final class ChangeCounter {
    private(set) var count = 0
    private let read: () -> Bool

    init(_ read: @escaping () -> Bool) {
        self.read = read
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = read()
        } onChange: { [weak self] in
            // Announced on the main actor, where the controller changes.
            MainActor.assumeIsolated {
                self?.count += 1
                self?.observe()
            }
        }
    }
}
