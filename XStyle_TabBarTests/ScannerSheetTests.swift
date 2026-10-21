import CoreGraphics
import Testing
@testable import XStyle_TabBar

@MainActor
struct ScannerSheetTests {
    /// A 402 × 874 pt iPhone whose bottom safe area holds the tab bar's toolbar.
    private let canvas = PaneCanvas(size: CGSize(width: 402, height: 874), safeAreaTop: 62, safeAreaBottom: 96)
    private let metrics = SheetMetrics.floating

    private func paneFrame(sheetTop: CGFloat) throws -> CGRect {
        let layout = try #require(PaneLayout(
            sheetTop: sheetTop, canvas: canvas, sideInset: metrics.paneSideInset,
            collapseEnd: metrics.tops(for: canvas).full, reduceMotion: false
        ))
        return layout.paneFrame
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
        #expect(tops.hidden > tops.collapsed)
        #expect(tops.collapsed > tops.medium)
        #expect(tops.medium > tops.full)
    }

    @Test("With the sheet hidden, the pane stops one gap above the tab bar")
    func paneClearsTabBar() throws {
        #expect(try paneFrame(sheetTop: 874) == CGRect(x: 8, y: 70, width: 386, height: 700))
        #expect(try paneFrame(sheetTop: 800).maxY == 770)
    }

    @Test("At collapsed and medium, the pane keeps one gap above the sheet")
    func paneFollowsSheet() throws {
        let tops = metrics.tops(for: canvas)
        #expect(try paneFrame(sheetTop: tops.collapsed) == CGRect(x: 8, y: 70, width: 386, height: (tops.collapsed - 8) - 70))
        #expect(try paneFrame(sheetTop: tops.medium) == CGRect(x: 8, y: 70, width: 386, height: (tops.medium - 8) - 70))
    }

    @Test("Released past collapsed, the sheet is dismissed")
    func dragDismissesFromCollapsed() {
        let sheet = sheet(at: .collapsed)
        release(sheet, afterDraggingBy: 80)
        #expect(sheet.detent == .hidden)
    }

    @Test("From medium, a short drag stops at collapsed and a long one dismisses")
    func dragFromMedium() {
        let short = sheet(at: .medium)
        release(short, afterDraggingBy: 100)
        #expect(short.detent == .collapsed)

        let long = sheet(at: .medium)
        release(long, afterDraggingBy: 300)
        #expect(long.detent == .hidden)
    }

    @Test("Released just above collapsed, the result stays open")
    func dragStopsAtCollapsed() {
        let tops = metrics.tops(for: canvas)
        let sheet = sheet(at: .medium)
        release(sheet, afterDraggingBy: tops.collapsed - tops.medium - 3)
        #expect(sheet.detent == .collapsed)
    }

    @Test("Presenting plays no detent haptic; moving between detents does")
    func presentationHaptics() {
        let sheet = sheet(at: .hidden)
        let trigger = sheet.feedbackTrigger
        sheet.settle(to: .medium, velocity: 0)
        #expect(sheet.feedbackTrigger == trigger)
        sheet.settle(to: .collapsed, velocity: 0)
        #expect(sheet.feedbackTrigger == trigger + 1)
    }

    @Test("Tapping the pane never brings a hidden sheet up")
    func collapseKeepsHidden() {
        let sheet = sheet(at: .hidden)
        sheet.collapse()
        #expect(sheet.detent == .hidden)
    }
}
