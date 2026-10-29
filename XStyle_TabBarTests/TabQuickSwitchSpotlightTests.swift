import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
struct TabQuickSwitchSpotlightTests {
    @Test("Active-area focus encloses horizontal bars, vertical rails, and their menus",
          arguments: [
            CGRect(x: 12, y: 390, width: 370, height: 430),
            CGRect(x: 12, y: 180, width: 380, height: 500),
            CGRect(x: 620, y: 180, width: 380, height: 500)
          ])
    func activeAreaEnclosesVisibleBounds(_ focus: CGRect) {
        let geometry = TabQuickSwitchSpotlightGeometry.resolve(focus: focus)
        #expect(geometry.center == CGPoint(x: focus.midX, y: focus.midY))
        expectEnclosure(geometry, of: focus)
    }

    @Test("Returning to the bar reduces active-area focus")
    func collapsedFocusUsesBar() {
        let bar = CGRect(x: 16, y: 740, width: 360, height: 64)
        let expanded = bar.union(CGRect(x: 48, y: 430, width: 280, height: 296))
        let open = TabQuickSwitchSpotlightGeometry.resolve(focus: expanded)
        let closed = TabQuickSwitchSpotlightGeometry.resolve(focus: bar)
        #expect(closed.radius < open.radius)
        expectEnclosure(closed, of: bar)
    }

    @Test("List autoscrolling does not change the spotlight's visible focus")
    func scrollingKeepsVisibleCardFocus() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let coordinateView = UIView(frame: window.bounds)
        window.addSubview(coordinateView)
        let bar = CGRect(x: 16, y: 744, width: 358, height: 64)
        let card = CGRect(x: 44, y: 440, width: 260, height: 280)
        let menu = TabQuickSwitchMenu()
        menu.coordinateView = coordinateView
        let items = [
            TabQuickSwitchItem(tab: .scanner, destination: .scan, title: "Scan", symbol: "camera"),
            TabQuickSwitchItem(tab: .scanner, destination: .scanHistory, title: "History", symbol: "clock")
        ]
        menu.open(tab: .scanner, items: items, tabFrame: CGRect(x: 106, y: 744, width: 88, height: 64),
                  barFrame: bar, axis: .horizontal)
        let presentationID = try #require(menu.presentation?.id)
        menu.setFocusFrame(card, presentationID: presentationID)
        let focus = try #require(menu.focusFrame)
        menu.setListViewport(card, contentHeight: 900, presentationID: presentationID)
        var scroll = TabQuickSwitchListScroll(viewport: card, contentHeight: 900)
        let pointer = CGPoint(x: card.midX, y: card.maxY - 1)
        scroll.scroll(by: scroll.velocity(at: pointer) * 0.25)
        #expect(scroll.offset > 0)
        menu.setListViewport(scroll.viewport, contentHeight: scroll.contentHeight, presentationID: presentationID)
        #expect(menu.focusFrame == focus)
        #expect(focus == bar.union(card), "Only the visible card is illuminated, not the full 900-point content")
        let before = TabQuickSwitchSpotlightGeometry.resolve(focus: focus)
        let after = TabQuickSwitchSpotlightGeometry.resolve(focus: bar.union(scroll.viewport))
        #expect(before == after)
        menu.cancel()
    }

    @Test("Spotlight duration uses a slower default and safely clamps debug values")
    func durationBounds() {
        #expect(TabQuickSwitchSettings.defaultSpotlightDuration == 0.45)
        #expect(TabQuickSwitchSettings.clampedSpotlightDuration(-1) == 0.1)
        #expect(TabQuickSwitchSettings.clampedSpotlightDuration(10) == 1.5)
        #expect(TabQuickSwitchSettings.clampedSpotlightDuration(0.85) == 0.85)
        #expect(TabQuickSwitchSettings.clampedSpotlightDuration(.nan) == 0.45)
        #expect(TabQuickSwitchSettings.clampedSpotlightDuration(.infinity) == 0.45)
        #expect(TabQuickSwitchSettings.clampedSpotlightDuration(-.infinity) == 0.45)
    }

    @Test("Debug duration persists independently of obsolete spotlight and halo preferences")
    func durationPersistsIndependently() throws {
        let name = "TabQuickSwitchSpotlightTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(TabQuickSwitchSettings.spotlightDuration(in: defaults) == 0.45)
        defaults.set("fingertip", forKey: "tabBar.quickSwitch.spotlightBehavior")
        defaults.set("glowRing", forKey: "tabBar.quickSwitch.halo")
        #expect(TabQuickSwitchSettings.spotlightDuration(in: defaults) == 0.45)

        defaults.set(0.85, forKey: TabQuickSwitchSettings.spotlightAnimationDurationKey)
        let reopened = try #require(UserDefaults(suiteName: name))
        #expect(TabQuickSwitchSettings.spotlightDuration(in: reopened) == 0.85)
        defaults.set(-4, forKey: TabQuickSwitchSettings.spotlightAnimationDurationKey)
        #expect(TabQuickSwitchSettings.spotlightDuration(in: defaults) == 0.1)
        defaults.set(8, forKey: TabQuickSwitchSettings.spotlightAnimationDurationKey)
        #expect(TabQuickSwitchSettings.spotlightDuration(in: defaults) == 1.5)
        defaults.set(TabQuickSwitchSettings.defaultSpotlightDuration,
                     forKey: TabQuickSwitchSettings.spotlightAnimationDurationKey)
        #expect(TabQuickSwitchSettings.spotlightDuration(in: defaults) == 0.45)
    }

    private func expectEnclosure(_ geometry: TabQuickSwitchSpotlightGeometry, of frame: CGRect) {
        for corner in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)] {
            #expect(hypot(corner.x - geometry.center.x, corner.y - geometry.center.y) <= geometry.radius + 0.001)
        }
    }
}
