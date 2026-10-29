import SwiftUI
import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct TabQuickSwitchListPresenterTests {
    @Test("A reused native surface cannot select newly installed rows before they have displayed")
    func reopeningWaitsForCurrentGenerationFrame() async throws {
        let fixture = NativeListFixture()
        defer { fixture.close() }
        let first = try fixture.open()
        try await fixture.waitUntilVisible(first)
        let point = try fixture.firstRowCenter()
        #expect(fixture.controller.destination(at: point, presentationID: first) == .scan)

        fixture.menu.collapse()
        fixture.update()
        let second = try fixture.open()
        #expect(fixture.controller.destination(at: point, presentationID: second) == nil)
        #expect(fixture.controller.destination(at: point, presentationID: first) == nil)
        try await fixture.waitUntilVisible(second)
        #expect(fixture.controller.destination(at: try fixture.firstRowCenter(), presentationID: second) == .scan)
    }

    @Test("Reopening an unchanged menu reverses its in-flight close without hiding or rebuilding its rows")
    func reopeningReversesDisplayedClose() async throws {
        let fixture = NativeListFixture()
        defer { fixture.close() }
        let first = try fixture.open()
        try await fixture.waitUntilVisible(first)
        let glass = try fixture.glass()
        let viewport = try #require(glass.contentView.subviews.first)
        let rows = try #require(viewport.subviews.first)
        let originalRow = try #require(rows.subviews.first)
        let originalFrame = glass.frame
        fixture.animations.entranceDuration = 0.3
        fixture.menu.collapse()
        fixture.update()
        let closingAnimator = try #require(fixture.controller.animator)
        closingAnimator.pauseAnimation()
        closingAnimator.fractionComplete = 0.35
        // Pause at a deterministic in-flight position; machine load cannot
        // let the short close finish before the test sends its reopen.
        try await Task.sleep(for: .milliseconds(25))
        let closingOpacity = try #require(viewport.layer.presentation()?.opacity)
        #expect(closingOpacity > 0.05)
        let reopened = try fixture.open()
        #expect(rows.subviews.first === originalRow)
        #expect(glass.frame == originalFrame)
        #expect(fixture.controller.destination(at: try fixture.firstRowCenter(), presentationID: reopened) == nil,
                "Even retained rows must cross the new generation's display fence")
        try await Task.sleep(for: .milliseconds(25))
        let resumedOpacity = viewport.layer.presentation()?.opacity ?? Float(viewport.alpha)
        #expect(resumedOpacity >= closingOpacity - 0.05, "Reopening should reverse the fade, never reset opacity to zero")
        try await fixture.waitUntilVisible(reopened)
        #expect(fixture.controller.destination(at: try fixture.firstRowCenter(), presentationID: reopened) == .scan)
    }

    @Test("Native glass stays opaque and one viewport clips rows without changing focus during scrolling")
    func opaqueGlassAndStableViewport() async throws {
        let fixture = NativeListFixture(bar: CGRect(x: 16, y: 210, width: 358, height: 64))
        defer { fixture.close() }
        let items = AppTab.allCases.map {
            TabQuickSwitchItem(tab: .home, destination: .homePage($0), title: "A longer menu item \($0)", symbol: "doc")
        }
        let id = try fixture.open(tab: .home, items: items)
        try await fixture.waitUntilVisible(id)
        let glass = try fixture.glass()
        let viewport = try #require(glass.contentView.subviews.first)
        let rows = try #require(viewport.subviews.first)
        #expect(glass.alpha == 1)
        #expect(fixture.controller.view.alpha == 1)
        #expect(glass.mask == nil)
        #expect(fixture.controller.view.mask == nil)
        #expect(viewport.clipsToBounds)
        #expect(fixture.menu.listOffsetLimit > 0)
        let originalFrame = glass.frame
        let originalFocus = fixture.menu.focusFrame
        fixture.controller.setScrollOffset(44, limit: fixture.menu.listOffsetLimit, presentationID: id)
        #expect(rows.frame.minY == -44)
        #expect(glass.frame == originalFrame)
        #expect(fixture.menu.focusFrame == originalFocus)
        #expect(fixture.controller.destination(at: CGPoint(x: glass.frame.midX, y: glass.frame.maxY + 1),
                                               presentationID: id) == nil)
    }

    @Test("Actual transformed row coordinates resolve through the same native carrier")
    func nativeTransformHitConversion() async throws {
        let fixture = NativeListFixture()
        defer { fixture.close() }
        let id = try fixture.open()
        try await fixture.waitUntilVisible(id)
        let glass = try fixture.glass()
        UIView.performWithoutAnimation {
            glass.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.96, y: 0.96)
        }
        // Allow the native presentation tree to display the transformed pose.
        try await Task.sleep(for: .milliseconds(50))
        let transformedCenter = try fixture.firstRowCenter()
        #expect(fixture.controller.destination(at: transformedCenter, presentationID: id) == .scan)
        let outside = glass.convert(CGPoint(x: -2, y: 25), to: fixture.coordinateView)
        #expect(fixture.controller.destination(at: outside, presentationID: id) == nil)
    }

    @Test("Long accessibility labels remain inward of either vertical rail", arguments: [false, true])
    func verticalCardFits(_ leading: Bool) async throws {
        let bar = CGRect(x: leading ? 8 : 318, y: 300, width: 64, height: 240)
        let fixture = NativeListFixture(bar: bar, vertical: true)
        defer { fixture.close() }
        fixture.environment.dynamicTypeSize = .accessibility3
        fixture.environment.layoutDirection = leading ? .leftToRight : .rightToLeft
        let items = [
            TabQuickSwitchItem(tab: .scanner, destination: .scan,
                               title: "A deliberately long camera menu label that must wrap inside the available space", symbol: "camera"),
            TabQuickSwitchItem(tab: .scanner, destination: .scanHistory, title: "History", symbol: "clock")
        ]
        let id = try fixture.open(items: items)
        try await fixture.waitUntilVisible(id)
        let frame = try fixture.glass().frame
        #expect(frame.minX >= fixture.area.minX - 0.5)
        #expect(frame.maxX <= fixture.area.maxX + 0.5)
        #expect(leading ? frame.minX >= bar.maxX : frame.maxX <= bar.minX)
        let viewport = try #require(try fixture.glass().contentView.subviews.first)
        let rows = try #require(viewport.subviews.first)
        #expect(rows.subviews.allSatisfy { $0.frame.height >= 44 })
    }
}

@MainActor
private final class NativeListFixture {
    let window: UIWindow
    let coordinateView = UIView()
    let controller = TabQuickSwitchListController()
    let menu = TabQuickSwitchMenu()
    let bar: CGRect
    let vertical: Bool
    let area = CGRect(x: 16, y: 16, width: 358, height: 812)
    var environment = EnvironmentValues()
    var animations = TabQuickSwitchListAnimationSettings(switchStyle: .immediate, entranceStyle: .fade,
                                                         switchDuration: 0.05, entranceDuration: 0.04)
    private let parent = UIViewController()

    init(bar: CGRect = CGRect(x: 16, y: 744, width: 358, height: 64), vertical: Bool = false) {
        self.bar = bar
        self.vertical = vertical
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        }
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = parent
        parent.view.backgroundColor = .white
        coordinateView.frame = window.bounds
        parent.view.addSubview(coordinateView)
        parent.addChild(controller)
        controller.view.frame = window.bounds
        parent.view.addSubview(controller.view)
        controller.didMove(toParent: parent)
        window.isHidden = false
        parent.view.layoutIfNeeded()
        menu.coordinateView = coordinateView
        environment.dynamicTypeSize = .large
        environment.colorScheme = .light
        environment.displayScale = 2
        environment.locale = Locale(identifier: "en_US")
    }

    func open(tab: RootTab = .scanner, items: [TabQuickSwitchItem]? = nil) throws -> UInt64 {
        let items = items ?? [
            TabQuickSwitchItem(tab: .scanner, destination: .scan, title: "Scan", symbol: "camera"),
            TabQuickSwitchItem(tab: .scanner, destination: .scanHistory, title: "History", symbol: "clock")
        ]
        let tabFrame = vertical ? CGRect(x: bar.minX, y: bar.minY + 60, width: bar.width, height: 60)
            : CGRect(x: 106, y: bar.minY, width: 88, height: bar.height)
        menu.open(tab: tab, items: items, tabFrame: tabFrame, barFrame: bar, axis: vertical ? .vertical : .horizontal)
        update()
        return try #require(menu.presentation?.id)
    }

    func update() {
        controller.update(menu: menu, presentation: menu.presentation, area: area,
                          direction: environment.layoutDirection,
                          animations: animations,
                          environment: environment)
    }

    func waitUntilVisible(_ id: UInt64) async throws {
        for _ in 0..<60 {
            if controller.canAutoscroll(presentationID: id) { return }
            try await Task.sleep(for: .milliseconds(16))
        }
        #expect(controller.canAutoscroll(presentationID: id), "Native card did not finish displaying its generation")
    }

    func glass() throws -> UIVisualEffectView {
        try #require(controller.view.subviews.compactMap { $0 as? UIVisualEffectView }.first)
    }

    func firstRowCenter() throws -> CGPoint {
        let viewport = try #require(try glass().contentView.subviews.first)
        let rows = try #require(viewport.subviews.first)
        let first = try #require(rows.subviews.first)
        return first.convert(CGPoint(x: first.bounds.midX, y: first.bounds.midY), to: coordinateView)
    }

    func close() {
        menu.cancel()
        controller.tearDown()
        window.isHidden = true
        window.rootViewController = nil
    }
}
