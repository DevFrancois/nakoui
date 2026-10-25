import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
struct TabQuickSwitchTrackingTests {
    private let scanFrame = CGRect(x: 40, y: 400, width: 200, height: 44)
    private let historyFrame = CGRect(x: 40, y: 444, width: 200, height: 44)

    @Test("The finger highlights the item it's over, including one laid out after the finger arrived")
    func highlightsItemUnderFinger() {
        var tracking = TabQuickSwitchTracking()
        let onHistory = CGPoint(x: historyFrame.midX, y: historyFrame.midY)
        tracking.move(to: onHistory)
        #expect(tracking.highlighted == nil)

        tracking.setFrame(scanFrame, for: .scan)
        tracking.setFrame(historyFrame, for: .scanHistory)
        #expect(tracking.highlighted == .scanHistory)
        tracking.move(to: CGPoint(x: scanFrame.midX, y: scanFrame.midY))
        #expect(tracking.highlighted == .scan)
        tracking.move(to: CGPoint(x: scanFrame.maxX + 1, y: scanFrame.midY))
        #expect(tracking.highlighted == nil)

        tracking.move(to: onHistory)
        tracking.setFrame(nil, for: .scanHistory)
        #expect(tracking.highlighted == nil)
    }

    @Test("Release returns the item under the finger once, and nothing off every item")
    func releasesItemOnce() {
        var tracking = TabQuickSwitchTracking()
        tracking.setFrame(scanFrame, for: .scan)
        tracking.setFrame(historyFrame, for: .scanHistory)
        #expect(tracking.release(at: CGPoint(x: historyFrame.midX, y: historyFrame.midY)) == .scanHistory)
        #expect(tracking == TabQuickSwitchTracking())
        #expect(tracking.release(at: CGPoint(x: historyFrame.midX, y: historyFrame.midY)) == nil)

        tracking.setFrame(scanFrame, for: .scan)
        tracking.move(to: CGPoint(x: scanFrame.midX, y: scanFrame.midY))
        #expect(tracking.release(at: CGPoint(x: scanFrame.midX, y: scanFrame.maxY + 200)) == nil)
    }

    @Test("A tab needs two items for a menu")
    func singleItemShowsNoMenu() {
        let item = TabQuickSwitchItem(tab: .scanner, destination: .scan, title: "Scan", symbol: "barcode.viewfinder")
        let history = TabQuickSwitchItem(tab: .scanner, destination: .scanHistory, title: "History",
                                         symbol: "clock.arrow.circlepath")
        var offered = [item]
        let menu = TabQuickSwitchMenu(items: { _ in offered })
        #expect(menu.items(for: .scanner) == nil)
        offered.append(history)
        #expect(menu.items(for: .scanner) == [item, history])
    }

    @Test("The menu follows the finger in window points and closes on release or cancel, applying nothing itself")
    func menuOpensFollowsAndCloses() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        #expect(menu.canOpen)

        fixture.open()
        let presentation = try #require(menu.presentation)
        // The overlay sits at the window's origin, so its space is the window's.
        #expect(presentation.tabFrame == fixture.tabFrame)
        #expect(presentation.barFrame == fixture.barFrame)
        #expect(presentation.axis == .horizontal)
        menu.setFrame(scanFrame, for: .scan)
        menu.setFrame(historyFrame, for: .scanHistory)

        #expect(menu.move(to: CGPoint(x: scanFrame.midX, y: scanFrame.midY)))
        #expect(!menu.move(to: CGPoint(x: scanFrame.midX + 1, y: scanFrame.midY)))
        #expect(menu.highlighted == .scan)
        #expect(menu.move(to: CGPoint(x: historyFrame.midX, y: historyFrame.midY)))
        let released = menu.release(at: CGPoint(x: historyFrame.midX, y: historyFrame.midY))
        #expect(released?.destination == .scanHistory)
        #expect(menu.presentation == nil)
        #expect(menu.highlighted == nil)
        #expect(fixture.applied.isEmpty)

        fixture.open()
        menu.setFrame(scanFrame, for: .scan)
        #expect(menu.release(at: fixture.tabFrame.origin) == nil)
        #expect(menu.presentation == nil)

        fixture.open()
        menu.cancel()
        #expect(menu.presentation == nil)
        menu.setFrame(scanFrame, for: .scan)
        #expect(menu.release(at: CGPoint(x: scanFrame.midX, y: scanFrame.midY)) == nil)

        let item = try #require(fixture.items.last)
        menu.apply(item, isTabShown: false)
        #expect(fixture.applied == [.scanHistory])
    }

    @MainActor
    private final class MenuFixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let overlay = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let tabFrame = CGRect(x: 120.5, y: 782, width: 78.5, height: 52)
        let barFrame = CGRect(x: 38, y: 776, width: 326, height: 64)
        let items = [
            TabQuickSwitchItem(tab: .scanner, destination: .scan, title: "Scan", symbol: "barcode.viewfinder"),
            TabQuickSwitchItem(tab: .scanner, destination: .scanHistory, title: "History", symbol: "clock.arrow.circlepath"),
        ]
        private(set) var applied: [TabQuickSwitchDestination] = []
        private(set) lazy var menu = TabQuickSwitchMenu(items: { [items] _ in items }) { [weak self] destination, _ in
            self?.applied.append(destination)
        }

        init() {
            window.addSubview(overlay)
            menu.coordinateView = overlay
        }

        func open() {
            menu.open(tab: .scanner, items: items, tabFrame: tabFrame, barFrame: barFrame, axis: .horizontal)
        }
    }
}
