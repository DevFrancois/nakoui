import SwiftUI
import Testing
import UIKit
@testable import XStyle_TabBar

/// Opt-in, identical before/after script. Set TAB_COMPARISON_LABEL and
/// TAB_COMPARISON_AXIS in the test runner; recordings use the active Duo display.
@MainActor
@Suite(.serialized)
struct RootTabMotionComparisonTests {
    @Test("Record presentation-layer motion through the real tab delegate",
          .enabled(if: ProcessInfo.processInfo.environment["TAB_COMPARISON_LABEL"] != nil))
    func captureComparison() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let label = environment["TAB_COMPARISON_LABEL"] else { return }
        let expectedAxis = environment["TAB_COMPARISON_AXIS"] ?? "horizontal"
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let state = MotionComparisonState()
        let host = UIHostingController(rootView: MotionComparisonFixture(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        try #require(await eventually { self.findTabs(in: host) != nil && self.findBar(in: host.view) != nil })
        let tabs = try #require(findTabs(in: host))
        let bar = try #require(findBar(in: host.view))
        try #require(await eventually {
            bar.bounds.width > 0 && bar.bounds.height > 0
                && (bar.bounds.width > bar.bounds.height ? "horizontal" : "vertical") == expectedAxis
        }, "The system must actually place the toolbar on the requested axis")
        let axis: NSLayoutConstraint.Axis = bar.bounds.width > bar.bounds.height ? .horizontal : .vertical
        #expect((axis == .horizontal ? "horizontal" : "vertical") == expectedAxis)
        let originalHosts = tabs.viewControllers?.map(ObjectIdentifier.init)

        let badge = UILabel()
        badge.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        badge.textColor = .white
        badge.backgroundColor = .black.withAlphaComponent(0.8)
        badge.numberOfLines = 2
        badge.frame = CGRect(x: 12, y: 55, width: 330, height: 32)
        badge.isUserInteractionEnabled = false
        window.addSubview(badge)
        let recorder = MotionComparisonRecorder(label: label, axis: expectedAxis, tabs: tabs, bar: bar, badge: badge)
        recorder.start()
        defer { recorder.stop() }

        func select(_ tab: RootTab, phase: String, wait: Int) async throws {
            recorder.mark(phase, target: tab)
            state.selection = tab
            try await Task.sleep(for: .milliseconds(wait))
        }
        func update(_ tab: RootTab, axis updatedAxis: NSLayoutConstraint.Axis? = nil, reduceMotion: Bool = false) {
            tabs.update(selection: tab, layoutAxis: updatedAxis ?? axis, isRightToLeft: false,
                        reduceMotion: reduceMotion, isEnabled: true, isVisible: true, animated: true)
        }
        recorder.mark("ready", target: .home)
        try await Task.sleep(for: .milliseconds(500))
        for repetition in 1...3 {
            for tab: RootTab in [.profile, .search, .scanner, .home] {
                try await select(tab, phase: "r\(repetition).normal.\(tab)", wait: 450)
                #expect(tabs.activeAnimator == nil)
                #expect(tabs.committedSelection == tab)
            }
            try await select(.profile, phase: "r\(repetition).rapid.profile", wait: 60)
            try await select(.search, phase: "r\(repetition).rapid.search", wait: 40)
            try await select(.home, phase: "r\(repetition).rapid.home", wait: 450)

            // Direct updates deliberately share a run loop. SwiftUI would
            // coalesce three binding writes before reaching the controller.
            recorder.mark("r\(repetition).burst", target: .profile)
            for tab: RootTab in [.scanner, .search, .profile] { update(tab) }
            state.selection = .profile
            try await Task.sleep(for: .milliseconds(450))
            #expect(tabs.committedSelection == .profile && tabs.activeAnimator == nil)

            try await select(.search, phase: "r\(repetition).axis.start", wait: 60)
            recorder.mark("r\(repetition).axis.settle", target: .search)
            update(.search, axis: axis == .horizontal ? .vertical : .horizontal)
            try await Task.sleep(for: .milliseconds(200))
            #expect(tabs.activeAnimator == nil)
            update(.search)

            try await select(.home, phase: "r\(repetition).reduce.start", wait: 60)
            recorder.mark("r\(repetition).reduce.settle", target: .home)
            update(.home, reduceMotion: true)
            try await Task.sleep(for: .milliseconds(200))
            #expect(tabs.activeAnimator == nil)
            update(.home)
            try await Task.sleep(for: .milliseconds(100))
            #expect(tabs.viewControllers?.map(ObjectIdentifier.init) == originalHosts)
        }
        recorder.mark("finished", target: .home)
        try await Task.sleep(for: .milliseconds(500))
        recorder.stop()
        let directory = URL.documentsDirectory.appending(path: "TransitionComparison", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appending(path: "\(label).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(recorder.result).write(to: output)
        print("COMPARISON_OUTPUT=\(output.path)")
    }

    private func findTabs(in controller: UIViewController) -> RootTabController? {
        if let tabs = controller as? RootTabController { return tabs }
        return controller.children.lazy.compactMap { findTabs(in: $0) }.first
    }
    private func findBar(in view: UIView) -> GlassTabBarView? {
        if let bar = view as? GlassTabBarView { return bar }
        return view.subviews.lazy.compactMap { findBar(in: $0) }.first
    }
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<150 {
            try await Task.sleep(for: .milliseconds(20))
            if condition() { return true }
        }
        return false
    }
}

@MainActor @Observable
private final class MotionComparisonState {
    var selection: RootTab = .home
    let navigation = RootNavigation()
    let pager = PagerState()
    let scanner = ScannerModel()
    let logo = LogoCollapse()
    let tasks = ForYouTaskList()
}

private struct MotionComparisonFixture: View {
    @Bindable var state: MotionComparisonState
    @Namespace private var zoom
    var body: some View {
        @Bindable var navigation = state.navigation
        NavigationStack(path: $navigation.path) {
            RootTabContent(selection: $state.selection, scanner: state.scanner) {
                HomeRootView(title: "Nako", pager: state.pager, logoCollapse: state.logo,
                             taskList: state.tasks, zoomNamespace: zoom,
                             onSelect: state.pager.select, onUpdate: {}) { EmptyView() }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .environment(\.rootNavigation, state.navigation)
    }
}

private struct MotionComparisonResult: Codable {
    struct Event: Codable { let time: Double; let phase: String; let target: String }
    struct Page: Codable {
        let tab: String; let attached: Bool; let opacity: Float
        let x: CGFloat; let y: CGFloat; let scaleX: CGFloat; let scaleY: CGFloat
    }
    struct Sample: Codable {
        let time: Double; let phase: String; let selection: String
        let activeMotion: [CGFloat]?; let usesSnapshot: Bool
        let pages: [Page]; let toolbar: [CGFloat]
    }
    let label: String
    let axis: String
    let startedAt: Date
    var events: [Event] = []
    var samples: [Sample] = []
}

@MainActor
private final class MotionComparisonRecorder: NSObject {
    private let tabs: RootTabController
    private let bar: GlassTabBarView
    private let badge: UILabel
    private var displayLink: CADisplayLink?
    private let startTime = CACurrentMediaTime()
    private var phase = "initial"
    private(set) var result: MotionComparisonResult

    init(label: String, axis: String, tabs: RootTabController, bar: GlassTabBarView, badge: UILabel) {
        self.tabs = tabs; self.bar = bar; self.badge = badge
        result = .init(label: label, axis: axis, startedAt: Date())
    }
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(sample))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    func stop() { displayLink?.invalidate(); displayLink = nil }
    func mark(_ phase: String, target: RootTab) {
        self.phase = phase
        badge.text = " \(result.label)\n \(phase)"
        result.events.append(.init(time: CACurrentMediaTime() - startTime, phase: phase, target: "\(target)"))
    }
    @objc private func sample() {
        let pages = zip(RootTab.allCases, tabs.viewControllers ?? []).map { tab, host in
            let layer = host.view.layer.presentation() ?? host.view.layer
            return MotionComparisonResult.Page(tab: "\(tab)", attached: host.view.window != nil,
                opacity: layer.opacity, x: layer.transform.m41, y: layer.transform.m42,
                scaleX: layer.transform.m11, scaleY: layer.transform.m22)
        }
        let rect = bar.convert(bar.bounds, to: bar.window)
        let animator = tabs.activeAnimator
        result.samples.append(.init(time: CACurrentMediaTime() - startTime, phase: phase,
            selection: "\(tabs.committedSelection)", activeMotion: animator.map { [$0.motion.x, $0.motion.y] },
            usesSnapshot: animator?.usesPresentationSnapshot ?? false, pages: pages,
            toolbar: [rect.minX, rect.minY, rect.width, rect.height]))
    }
}
