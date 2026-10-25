import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct GlassTabBarQuickSwitchTests {
    @Test("A held tab's menu opens at its deadline, follows the finger, and commits its tab and item once")
    func holdOpensPreviewsAndCommits() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        fixture.press(.profile)
        let pending = try #require(fixture.view.quickSwitchHold.pending)
        fixture.view.openQuickSwitch(generation: pending.generation, at: pending.deadline.nextDown)
        #expect(fixture.menu.presentation == nil, "Woken early, the hold waits out the rest")
        fixture.view.openQuickSwitch(generation: pending.generation &+ 1, at: pending.deadline)
        #expect(fixture.menu.presentation == nil, "Another hold's timer opens nothing")

        fixture.view.openQuickSwitch(generation: pending.generation, at: pending.deadline)
        let presentation = try #require(fixture.menu.presentation)
        #expect(presentation.tab == .profile)
        #expect(presentation.items.map(\.destination) == PetProfile.samples.map { .pet($0.id) })
        #expect(presentation.tabFrame == fixture.window.convert(fixture.button(.profile).frame, from: fixture.view))

        let row = fixture.row(for: .pet("miso"))
        fixture.move(to: CGPoint(x: row.midX, y: row.midY))
        #expect(fixture.menu.highlighted == .pet("miso"))
        #expect(fixture.commits.isEmpty)
        fixture.release(at: CGPoint(x: row.midX, y: row.midY))
        #expect(fixture.commits == [.profile])
        #expect(fixture.applied.destinations == [.pet("miso")])
        #expect(fixture.applied.wereTabsShown == [false])
        #expect(fixture.menu.presentation == nil)
    }

    @Test("Lifting off the items, or back on the bar, changes nothing; the next touch navigates as before")
    func liftingOffItemsChangesNothing() async throws {
        for lift in [CGPoint(x: 20, y: 20), nil] {
            let fixture = try QuickSwitchFixture()
            await drainMainQueue()
            fixture.press(.profile)
            try fixture.openMenu()
            let row = fixture.row(for: .pet("miso"))
            fixture.move(to: CGPoint(x: row.midX, y: row.midY))
            let onBar = fixture.window.convert(fixture.button(.search).center, from: fixture.view)
            fixture.release(at: lift ?? onBar)
            #expect(fixture.commits.isEmpty)
            #expect(fixture.applied.destinations.isEmpty)
            #expect(fixture.menu.presentation == nil)

            fixture.press(.search)
            fixture.release(at: onBar)
            #expect(fixture.commits == [.search])
        }
    }

    @Test("Drifting before the deadline leaves the hold to preview tabs, committing on release as before")
    func driftRulesOutMenu() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        fixture.press(.profile)
        let center = fixture.window.convert(fixture.button(.profile).center, from: fixture.view)
        let drift = GlassTabBarMotion.calm.quickSwitchAllowableMovement + 1
        fixture.move(to: CGPoint(x: center.x, y: center.y - drift))
        let pending = try #require(fixture.view.quickSwitchHold.pending)
        fixture.view.openQuickSwitch(generation: pending.generation, at: pending.deadline)
        #expect(fixture.menu.presentation == nil)
        fixture.release(at: center)
        #expect(fixture.commits == [.profile])
        #expect(fixture.applied.destinations.isEmpty)
    }

    @Test("Hiding the bar, a changed window or new text settings close an open menu and take its touch along")
    func interruptionsCloseMenu() async throws {
        let interruptions: [(QuickSwitchFixture) -> Void] = [
            { $0.view.updateQuickSwitchAvailability(false) },
            { $0.window.frame = $0.window.frame.insetBy(dx: 0, dy: 20) },
            { $0.configure(contentSizeCategory: .extraExtraLarge) },
        ]
        for interrupt in interruptions {
            let fixture = try QuickSwitchFixture()
            await drainMainQueue()
            fixture.press(.profile)
            try fixture.openMenu()
            let row = fixture.row(for: .pet("miso"))
            interrupt(fixture)
            fixture.move(to: CGPoint(x: row.midX, y: row.midY))
            #expect(fixture.menu.presentation == nil)
            fixture.release(at: CGPoint(x: row.midX, y: row.midY))
            #expect(fixture.commits.isEmpty)
            #expect(fixture.applied.destinations.isEmpty)
        }
    }

    @Test("A menu held on another tab marks nothing; on its own tab, what it shows")
    func marksOnlyOnShownTab() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        fixture.press(.home)
        try fixture.openMenu()
        #expect(fixture.menu.presentation?.items.filter(\.isCurrent).map(\.destination) == [.homePage(.bookmarks)])
        fixture.release(at: CGPoint(x: 20, y: 20))

        fixture.press(.profile)
        try fixture.openMenu()
        #expect(fixture.menu.presentation?.items.contains(where: \.isCurrent) == false)
    }

    @Test("A hold lasts as long as the bar's motion says")
    func holdTimeFollowsMotion() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        fixture.presentation.motion.quickSwitchHoldDuration = 0.2
        let before = ProcessInfo.processInfo.systemUptime
        fixture.press(.profile)
        let after = ProcessInfo.processInfo.systemUptime
        let pending = try #require(fixture.view.quickSwitchHold.pending)
        #expect(pending.deadline >= before + 0.2 && pending.deadline <= after + 0.2)
    }

    @Test("A release or tap on the tab that shows reselects it; a real change never does")
    func reselectsShownTab() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        var reselected: [RootTab] = []
        fixture.view.onReselect = { reselected.append($0) }
        let home = fixture.window.convert(fixture.button(.home).center, from: fixture.view)
        fixture.press(.home)
        fixture.release(at: home)
        #expect(reselected == [.home])
        #expect(fixture.commits.isEmpty)

        let search = fixture.window.convert(fixture.button(.search).center, from: fixture.view)
        fixture.press(.home)
        fixture.release(at: search)
        #expect(fixture.commits == [.search])
        #expect(reselected == [.home])

        #expect(fixture.button(.search).accessibilityActivate())
        #expect(reselected == [.home, .search])
        #expect(fixture.commits == [.search])
    }

    @Test("Unavailable, a hold opens no menu and VoiceOver offers no items")
    func unavailableOpensNothing() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        let profile = fixture.button(.profile)
        let actions = try #require(profile.accessibilityCustomActions)
        #expect(actions.map(\.name) == PetProfile.samples.map(\.name))
        #expect(actions[1].actionHandler?(actions[1]) == true)
        #expect(fixture.commits == [.profile])
        #expect(fixture.applied.destinations == [.pet("miso")])

        fixture.view.updateQuickSwitchAvailability(false)
        #expect(profile.accessibilityCustomActions?.isEmpty == true)
        fixture.press(.search)
        #expect(fixture.view.quickSwitchHold.pending == nil)
        fixture.view.updateQuickSwitchAvailability(true)
        fixture.press(.search)
        let pending = try #require(fixture.view.quickSwitchHold.pending)
        fixture.view.updateQuickSwitchAvailability(false)
        fixture.view.openQuickSwitch(generation: pending.generation, at: pending.deadline)
        #expect(fixture.menu.presentation == nil)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

/// A bar resting near the window's bottom, its menu's overlay spanning the
/// window, so overlay and window points match.
@MainActor
private final class QuickSwitchFixture {
    final class Applied {
        var destinations: [TabQuickSwitchDestination] = []
        var wereTabsShown: [Bool] = []
    }

    let window: UIWindow
    let toolbar: UIView
    let anchor = UIView()
    let placement = UIView()
    let overlay: UIView
    let presentation = GlassTabBarPresentation()
    let view: GlassTabBarView
    let menu: TabQuickSwitchMenu
    let applied = Applied()
    private(set) var commits: [RootTab] = []

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        overlay = UIView(frame: window.bounds)
        let size = CGSize(width: 360, height: 64)
        toolbar = UIView(frame: CGRect(x: (window.bounds.width - size.width) / 2, y: window.bounds.height - 120,
                                      width: size.width, height: size.height))
        view = GlassTabBarView(selection: .home, presentation: presentation)
        window.addSubview(overlay)
        window.addSubview(toolbar)
        anchor.frame = toolbar.bounds
        placement.frame = toolbar.bounds
        view.frame = toolbar.bounds
        toolbar.addSubview(placement)
        toolbar.addSubview(anchor)
        toolbar.addSubview(view)
        presentation.coordinateView = anchor
        presentation.placementView = placement

        let context = TabQuickSwitchCatalog.Context(homePage: .bookmarks, isHistoryAvailable: true,
                                                    petID: PetProfile.defaultID, searchScope: .breeds)
        menu = TabQuickSwitchMenu(items: { TabQuickSwitchCatalog.items(for: $0, in: context) }) { [applied] destination, isTabShown in
            applied.destinations.append(destination)
            applied.wereTabsShown.append(isTabShown)
        }
        menu.coordinateView = overlay
        view.quickSwitch = menu
        view.onSelect = { [weak self] in self?.commits.append($0) }
        configure()
        window.layoutIfNeeded()
        view.layoutIfNeeded()
    }

    func configure(contentSizeCategory: UIContentSizeCategory = .large) {
        view.updateEnvironment(locale: Locale(identifier: "en"), contentSizeCategory: contentSizeCategory,
                               layoutDirection: .leftToRight, layoutAxis: .horizontal, reduceMotion: false,
                               isEnabled: true)
    }

    func button(_ tab: RootTab) -> GlassTabBarButton {
        (view.accessibilityElements as? [GlassTabBarButton])!.first { $0.tab == tab }!
    }

    func press(_ tab: RootTab) {
        let recognizer = view.gestureRecognizers!.compactMap { $0 as? GlassTabBarTouchRecognizer }.first!
        recognizer.onBegin?(button(tab).center)
    }

    func openMenu() throws {
        let pending = try #require(view.quickSwitchHold.pending)
        view.openQuickSwitch(generation: pending.generation, at: pending.deadline)
        _ = try #require(menu.presentation)
    }

    /// Lays an item out above the bar, as the overlay would.
    func row(for destination: TabQuickSwitchDestination) -> CGRect {
        let frame = CGRect(x: toolbar.frame.minX, y: toolbar.frame.minY - 100, width: 200, height: 44)
        menu.setFrame(frame, for: destination)
        return frame
    }

    /// Finger positions in window points.
    func move(to point: CGPoint) {
        view.trackTouch(state: .changed, at: view.convert(point, from: nil))
    }

    func release(at point: CGPoint) {
        view.trackTouch(state: .ended, at: view.convert(point, from: nil))
    }
}
