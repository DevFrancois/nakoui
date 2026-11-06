import SwiftUI
import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct GlassTabBarToolbarTests {
    @Test("The real navigation toolbar gives the horizontal bar its preferred width", arguments: [false, true])
    func navigationToolbarUsesPreferredWidth(rightToLeft: Bool) async throws {
        let fixture = try ToolbarWindowFixture(
            root: NavigationToolbarFixture(rightToLeft: rightToLeft), width: 440
        )
        defer { fixture.close() }

        let bar = try await waitForBar(in: fixture.host.view, width: 326)
        #expect(abs(bar.bounds.height - 64) < 0.5)
        let controls = try #require(bar.accessibilityElements as? [GlassTabBarButton])
        #expect(controls.count == 4)
        for control in controls {
            #expect(abs(control.bounds.width - 78.5) < 0.5)
            #expect(abs(control.bounds.height - 52) < 0.5)
        }
        try expectContainedControls(in: bar, rightToLeft: rightToLeft)
        try expectMatchingTouchAnchor(in: bar)
    }

    @Test("The compatibility bar ignores a toolbar-sized minimum probe but still respects its real container",
          arguments: [CGFloat(320), 220])
    func boundedIdealRespectsNarrowContainer(containerWidth: CGFloat) async throws {
        let fixture = try ToolbarWindowFixture(
            root: BoundedToolbarItemFixture(containerWidth: containerWidth, accessible: false), width: 440
        )
        defer { fixture.close() }

        // The fixture proposes only 176 points to the item, as the older
        // toolbar does, while its real container has more room available.
        let bar = try await waitForBar(in: fixture.host.view, width: containerWidth - 32)
        #expect(abs(bar.bounds.height - bar.fittingHeight(for: bar.bounds.width)) < 0.5)
        try expectContainedControls(in: bar, rightToLeft: false)
        try expectMatchingTouchAnchor(in: bar)
    }

    @Test("Accessibility text keeps its content-driven ideal within the compatibility bar's available width",
          arguments: [CGFloat(440), 320])
    func accessibleIdealIsBounded(containerWidth: CGFloat) async throws {
        let fixture = try ToolbarWindowFixture(
            root: BoundedToolbarItemFixture(containerWidth: containerWidth, accessible: true), width: 440
        )
        defer { fixture.close() }

        let ready = try await eventually {
            fixture.host.view.layoutIfNeeded()
            guard let bar = self.findBar(in: fixture.host.view),
                  bar.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge else { return false }
            let expected = bar.fittingSize(proposedWidth: containerWidth - 32)
            return abs(bar.bounds.width - expected.width) < 0.5 && abs(bar.bounds.height - expected.height) < 0.5
        }
        try #require(ready)
        let bar = try #require(findBar(in: fixture.host.view))
        #expect(bar.fittingSize(proposedWidth: nil).width > GlassTabBarMetrics.preferredHorizontalWidth)
        #expect(bar.bounds.width <= containerWidth - 32 + 0.5)
        try expectContainedControls(in: bar, rightToLeft: false)
        for control in try #require(bar.accessibilityElements as? [GlassTabBarButton]) {
            let required = control.sizeThatFits(CGSize(width: control.bounds.width, height: .greatestFiniteMagnitude))
            #expect(control.bounds.height >= required.height - 0.5,
                    "The available width must wrap large labels without clipping their required height")
        }
        try expectMatchingTouchAnchor(in: bar)
    }

    private func waitForBar(in host: UIView, width: CGFloat) async throws -> GlassTabBarView {
        let ready = try await eventually {
            host.layoutIfNeeded()
            guard let bar = self.findBar(in: host) else { return false }
            return abs(bar.bounds.width - width) < 0.5 && bar.bounds.height > 0
        }
        try #require(ready, "The hosted toolbar must finish laying out at its resolved width")
        return try #require(findBar(in: host))
    }

    private func expectContainedControls(in bar: GlassTabBarView, rightToLeft: Bool) throws {
        let controls = try #require(bar.accessibilityElements as? [GlassTabBarButton])
        for control in controls {
            #expect(control.bounds.width >= 44 && control.bounds.height >= 44)
            #expect(bar.bounds.insetBy(dx: -0.5, dy: -0.5).contains(control.frame))
            #expect(!(control.accessibilityLabel ?? "").isEmpty)
        }
        for (first, second) in zip(controls, controls.dropFirst()) {
            #expect(first.frame.intersection(second.frame).isEmpty)
            #expect(rightToLeft ? second.frame.maxX <= first.frame.minX : first.frame.maxX <= second.frame.minX)
        }
    }

    private func expectMatchingTouchAnchor(in bar: GlassTabBarView) throws {
        let recognizer = try #require(bar.gestureRecognizers?.compactMap { $0 as? GlassTabBarTouchRecognizer }.first)
        let controls = try #require(bar.accessibilityElements as? [GlassTabBarButton])
        let search = try #require(controls.first { $0.tab == .search })
        let highlight = try #require(search.superview?.subviews.first { $0 is GlassTabBarHighlight })
        // Beginning a touch is rejected unless the actual SwiftUI coordinate
        // anchor is in the same window and has exactly the native bar's size.
        recognizer.onBegin?(search.center)
        #expect(highlight.frame == search.frame,
                "The displayed bar and its unscaled touch anchor must share the same measured bounds")
        #expect(controls.filter(\.isSelected).map(\.tab) == [.home])
        bar.trackTouch(state: .cancelled, at: search.center)
    }

    private func findBar(in view: UIView) -> GlassTabBarView? {
        if let bar = view as? GlassTabBarView { return bar }
        return view.subviews.lazy.compactMap { findBar(in: $0) }.first
    }

    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

private struct NavigationToolbarFixture: View {
    let rightToLeft: Bool
    @State private var selection: RootTab = .home
    @State private var axis: NSLayoutConstraint.Axis = .horizontal
    @State private var top: CGFloat?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Color.clear
                    .toolbar {
                        GlassTabBarToolbar(selection: $selection, layoutAxis: $axis, top: $top,
                                           availableHorizontalWidth: geometry.size.width - 32)
                    }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .dynamicTypeSize(.large)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
        .transaction { $0.disablesAnimations = true }
    }
}

private struct BoundedToolbarItemFixture: View {
    let containerWidth: CGFloat
    let accessible: Bool

    var body: some View {
        GeometryReader { geometry in
            GlassTabBar(selection: .constant(.home), availableHorizontalWidth: geometry.size.width - 32)
                .frame(width: 176)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: containerWidth, height: 600)
        .dynamicTypeSize(accessible ? .accessibility5 : .large)
        .environment(\.locale, Locale(identifier: "en"))
        .transaction { $0.disablesAnimations = true }
    }
}

@MainActor
private final class ToolbarWindowFixture<Content: View> {
    let window: UIWindow
    let host: UIHostingController<Content>

    init(root: Content, width: CGFloat) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 956)
        host = UIHostingController(rootView: root)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
}
