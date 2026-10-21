import CoreGraphics
import Testing
@testable import XStyle_TabBar

@MainActor
struct ScannerSheetTests {
    /// A 402 × 874 pt iPhone whose bottom safe area holds the tab bar's toolbar.
    private let canvas = PaneCanvas(size: CGSize(width: 402, height: 874), safeAreaTop: 62, safeAreaBottom: 96)
    private let metrics = SheetMetrics.floating

    private func paneLayout(sheetTop: CGFloat, footerHeight: CGFloat = 0) throws -> PaneLayout {
        try #require(PaneLayout(
            sheetTop: sheetTop, canvas: canvas, sideInset: metrics.paneSideInset,
            tops: metrics.tops(for: canvas), footerHeight: footerHeight
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
}
