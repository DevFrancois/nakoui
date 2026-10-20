import CoreGraphics
import Testing
@testable import XStyle_TabBar

struct SplitPaneDragTests {
    private let breakpoints: [SplitPaneBreakpoint] = [.large, .peek, .half]
    /// Peek, half and large rest at 200, 400 and 600 points.
    private let totalHeight: CGFloat = 800

    private func target(from current: SplitPaneBreakpoint, start: CGFloat, end: CGFloat, velocity: CGFloat) -> SplitPaneBreakpoint {
        SplitPaneDrag.target(
            from: current, in: breakpoints, startHeight: start, endHeight: end,
            velocity: velocity, totalHeight: totalHeight
        )
    }

    @Test("Dragging past the snap points resists, and within them doesn't")
    func rubberBands() {
        let range: ClosedRange<CGFloat> = 200...600
        let resistance = 1 - SplitPaneDrag.rubberBandingStrength
        #expect(SplitPaneDrag.rubberBanded(700, within: range) == 600 + 100 * resistance)
        #expect(SplitPaneDrag.rubberBanded(150, within: range) == 200 - 50 * resistance)
        #expect(SplitPaneDrag.rubberBanded(350, within: range) == 350)
    }

    @Test("A short, slow drag goes back to where it started")
    func shortSlowDragReturns() {
        #expect(target(from: .peek, start: 200, end: 240, velocity: -100) == .peek)
        #expect(target(from: .half, start: 400, end: 360, velocity: 100) == .half)
    }

    @Test("A long or fast drag moves exactly one snap point")
    func longOrFastDragMovesOne() {
        // Long, slow, up.
        #expect(target(from: .peek, start: 200, end: 300, velocity: -50) == .half)
        // Short, fast, up.
        #expect(target(from: .peek, start: 200, end: 220, velocity: -400) == .half)
        // Long, slow, down.
        #expect(target(from: .half, start: 400, end: 300, velocity: 50) == .peek)
    }

    @Test("Drags past the ends stay at the ends")
    func endsHold() {
        #expect(target(from: .large, start: 600, end: 680, velocity: -500) == .large)
        #expect(target(from: .peek, start: 200, end: 140, velocity: 500) == .peek)
    }

    @Test("A release without velocity goes the way the drag went")
    func zeroVelocityUsesDistance() {
        #expect(target(from: .half, start: 400, end: 320, velocity: 0) == .peek)
        #expect(target(from: .half, start: 400, end: 480, velocity: 0) == .large)
    }

    @Test("Like a sheet, the pane moves until it's fully open, then its content scrolls")
    func movesPaneOrScrolls() {
        // The top edge always moves the pane.
        #expect(SplitPaneDrag.movesPane(startsInStrip: true, isAtTallest: true, isContentAtTop: false, isDownward: false))
        // Below its tallest point, any drag grows or shrinks it.
        #expect(SplitPaneDrag.movesPane(startsInStrip: false, isAtTallest: false, isContentAtTop: false, isDownward: false))
        #expect(SplitPaneDrag.movesPane(startsInStrip: false, isAtTallest: false, isContentAtTop: true, isDownward: true))
        // Fully open: down from the content's top shrinks it...
        #expect(SplitPaneDrag.movesPane(startsInStrip: false, isAtTallest: true, isContentAtTop: true, isDownward: true))
        // ...and everything else scrolls.
        #expect(!SplitPaneDrag.movesPane(startsInStrip: false, isAtTallest: true, isContentAtTop: true, isDownward: false))
        #expect(!SplitPaneDrag.movesPane(startsInStrip: false, isAtTallest: true, isContentAtTop: false, isDownward: true))
        #expect(!SplitPaneDrag.movesPane(startsInStrip: false, isAtTallest: true, isContentAtTop: false, isDownward: false))
    }

    @Test("Wide windows put the scanner's panes side by side", arguments: [
        (CGSize(width: 393, height: 852), false),
        (CGSize(width: 466, height: 678), false),
        (CGSize(width: 500, height: 300), false),
        (CGSize(width: 736, height: 678), true),
        (CGSize(width: 852, height: 393), true),
    ])
    func sideBySide(size: CGSize, expected: Bool) {
        #expect(ScannerMetrics.usesSideBySide(in: size) == expected)
    }
}
