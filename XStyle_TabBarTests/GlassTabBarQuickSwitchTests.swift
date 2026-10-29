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

    @Test("An active release outside cancels, while a release on the bar selects its actual tab")
    func releasesResolveFinalPhysicalTarget() async throws {
        for releasesOnBar in [false, true] {
            let fixture = try QuickSwitchFixture()
            await drainMainQueue()
            fixture.press(.profile)
            try fixture.openMenu()
            let row = fixture.row(for: .pet("miso"))
            fixture.move(to: CGPoint(x: row.midX, y: row.midY))
            let onBar = fixture.center(.search)
            fixture.release(at: releasesOnBar ? onBar : CGPoint(x: 20, y: 20))
            #expect(fixture.commits == (releasesOnBar ? [.search] : []))
            #expect(fixture.applied.destinations.isEmpty)
            #expect(fixture.menu.presentation == nil)
            #expect(!fixture.menu.isActive)

            // Duplicate end events cannot navigate or reselect again.
            fixture.release(at: onBar)
            #expect(fixture.commits == (releasesOnBar ? [.search] : []))
            #expect(fixture.reselections.isEmpty)
            fixture.press(.search)
            fixture.release(at: onBar)
            #expect(fixture.commits == [.search])
            #expect(fixture.reselections == (releasesOnBar ? [.search] : []))
        }
    }

    @Test("Motion beyond the dwell tolerance rearms the hold and rejects the old deadline")
    func driftRearmsMenu() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        fixture.press(.profile)
        let old = try #require(fixture.view.quickSwitchHold.pending)
        let center = fixture.center(.profile)
        let drift = GlassTabBarMotion.calm.quickSwitchAllowableMovement + 1
        fixture.move(to: CGPoint(x: center.x, y: center.y - drift))
        let replacement = try #require(fixture.view.quickSwitchHold.pending)
        #expect(replacement.generation != old.generation)
        fixture.view.openQuickSwitch(generation: old.generation, at: replacement.deadline)
        #expect(fixture.menu.presentation == nil)
        fixture.view.openQuickSwitch(generation: replacement.generation, at: replacement.deadline)
        #expect(fixture.menu.presentation?.tab == .profile)
        #expect(fixture.commits.isEmpty)
        fixture.release(at: center)
        #expect(fixture.commits == [.profile])
        #expect(fixture.applied.destinations.isEmpty)
    }

    @Test("Sliding onto another tab before the first hold rearms there, and leaving the bar cancels its dwell")
    func initialSlideThenHold() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        fixture.press(.home)
        let first = try #require(fixture.view.quickSwitchHold.pending)
        fixture.move(to: fixture.center(.profile))
        let second = try #require(fixture.view.quickSwitchHold.pending)
        #expect(second.generation != first.generation)
        fixture.view.openQuickSwitch(generation: first.generation, at: second.deadline)
        #expect(!fixture.menu.isActive)

        fixture.move(to: fixture.outwardPoint(over: .profile, distance: 20))
        #expect(fixture.view.quickSwitchHold.pending == nil)
        fixture.view.openQuickSwitch(generation: second.generation, at: second.deadline)
        #expect(!fixture.menu.isActive)
        fixture.move(to: fixture.center(.profile))
        let returned = try #require(fixture.view.quickSwitchHold.pending)
        #expect(returned.generation != second.generation)
        try fixture.openMenu()
        #expect(fixture.menu.presentation?.tab == .profile)
        #expect(fixture.commits.isEmpty)
        fixture.release(at: CGPoint(x: 20, y: 20))
    }

    @Test("One touch repeatedly browses menus and the bar, with one session and only one final destination")
    func continuouslyBrowsesMenus() async throws {
        for (axis, direction): (NSLayoutConstraint.Axis, UIUserInterfaceLayoutDirection) in [
            (.horizontal, .leftToRight), (.horizontal, .rightToLeft), (.vertical, .leftToRight),
        ] {
            let fixture = try QuickSwitchFixture(axis: axis, direction: direction)
            await drainMainQueue()
            fixture.press(.profile)
            try fixture.openMenu()
            let sessionID = try #require(fixture.menu.session?.id)
            let firstMenuID = try #require(fixture.menu.presentation?.id)
            let firstRow = fixture.row(for: .pet("miso"))
            fixture.move(to: CGPoint(x: firstRow.midX, y: firstRow.midY))
            #expect(fixture.menu.highlighted == .pet("miso"))

            fixture.move(to: fixture.center(.profile))
            #expect(fixture.menu.presentation == nil)
            #expect(fixture.menu.session?.id == sessionID)
            #expect(fixture.menu.highlighted == nil)
            fixture.move(to: fixture.center(.profile))
            #expect(fixture.menu.presentation == nil, "Remaining on the same tab stays collapsed")

            fixture.move(to: fixture.outwardPoint(over: .profile))
            #expect(fixture.menu.presentation?.tab == .profile)
            #expect(fixture.menu.presentation?.id != firstMenuID)
            #expect(fixture.view.quickSwitchHold.pending == nil, "A later opening needs no new hold")
            let reopened = fixture.row(for: .pet("miso"))
            fixture.move(to: CGPoint(x: reopened.midX, y: reopened.midY))
            fixture.move(to: fixture.center(.search))
            #expect(fixture.menu.presentation?.tab == .search, "A direct return to another tab opens it immediately")
            fixture.move(to: fixture.center(.home))
            #expect(fixture.menu.presentation?.tab == .home)
            fixture.move(to: fixture.center(.profile))
            #expect(fixture.menu.presentation?.tab == .profile)
            #expect(fixture.menu.session?.id == sessionID)
            #expect(fixture.commits.isEmpty)
            #expect(fixture.reselections.isEmpty)
            #expect(fixture.applied.destinations.isEmpty)

            let finalRow = fixture.row(for: .pet("miso"))
            let finalPoint = CGPoint(x: finalRow.midX, y: finalRow.midY)
            fixture.move(to: finalPoint)
            #expect(fixture.commits.isEmpty)
            fixture.release(at: finalPoint)
            fixture.release(at: finalPoint)
            #expect(fixture.commits == [.profile])
            #expect(fixture.applied.destinations == [.pet("miso")])
            #expect(fixture.applied.wereTabsShown == [false])
            #expect(!fixture.menu.isActive)
        }
    }

    @Test("Opening while on the bar does not collapse, and a short boundary excursion does not flicker")
    func barBoundaryHysteresis() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        fixture.press(.profile)
        try fixture.openMenu()
        let menuID = try #require(fixture.menu.presentation?.id)
        let sessionID = try #require(fixture.menu.session?.id)
        fixture.move(to: fixture.center(.profile))
        fixture.move(to: fixture.outwardPoint(over: .profile, distance: 4))
        fixture.move(to: fixture.center(.profile))
        #expect(fixture.menu.presentation?.id == menuID)

        fixture.move(to: fixture.outwardPoint(over: .profile, distance: 9))
        fixture.move(to: fixture.center(.profile))
        #expect(fixture.menu.presentation == nil)
        fixture.move(to: fixture.outwardPoint(over: .profile, distance: 7))
        #expect(fixture.menu.presentation == nil)
        fixture.move(to: fixture.outwardPoint(over: .profile, distance: 9))
        #expect(fixture.menu.presentation?.tab == .profile)
        #expect(fixture.menu.session?.id == sessionID)
        #expect(fixture.commits.isEmpty)
        fixture.release(at: CGPoint(x: 20, y: 20))
    }

    @Test("A tab without a submenu keeps browsing active and remains selectable")
    func singleItemTabRemainsSelectable() async throws {
        let fixture = try QuickSwitchFixture(isHistoryAvailable: false)
        await drainMainQueue()
        fixture.press(.profile)
        try fixture.openMenu()
        let sessionID = try #require(fixture.menu.session?.id)
        fixture.move(to: fixture.center(.scanner))
        #expect(fixture.menu.presentation == nil)
        #expect(fixture.menu.session?.id == sessionID)
        fixture.move(to: fixture.outwardPoint(over: .scanner))
        #expect(fixture.menu.presentation == nil)
        #expect(fixture.menu.session?.id == sessionID)
        fixture.move(to: fixture.center(.home))
        #expect(fixture.menu.presentation?.tab == .home)
        fixture.move(to: fixture.center(.scanner))
        fixture.release(at: fixture.center(.scanner))
        #expect(fixture.commits == [.scanner])
        #expect(fixture.applied.destinations.isEmpty)
        #expect(!fixture.menu.isActive)
    }

    @Test("An active release in bar padding cancels instead of selecting the nearest tab")
    func barPaddingReleaseCancels() async throws {
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            for collapsed in [false, true] {
                let fixture = try QuickSwitchFixture(axis: axis)
                await drainMainQueue()
                fixture.press(.profile)
                try fixture.openMenu()
                let row = fixture.row(for: .pet("miso"))
                fixture.move(to: CGPoint(x: row.midX, y: row.midY))
                if collapsed { fixture.move(to: fixture.center(.profile)) }

                let padding = CGPoint(x: fixture.view.bounds.midX, y: fixture.view.bounds.minY + 1)
                #expect(fixture.view.bounds.contains(padding))
                #expect(RootTab.allCases.allSatisfy { !fixture.button($0).frame.contains(padding) })
                let releasePoint = fixture.window.convert(padding, from: fixture.view)
                fixture.release(at: releasePoint)
                fixture.release(at: releasePoint)
                #expect(!fixture.menu.isActive)
                #expect(fixture.commits.isEmpty)
                #expect(fixture.reselections.isEmpty)
                #expect(fixture.applied.destinations.isEmpty)
            }
        }
    }

    @Test("Outward movement on a tab without choices does not repeatedly request a replacement")
    func menuLessTabDoesNotRepeatedlyOpen() async throws {
        let fixture = try QuickSwitchFixture(isHistoryAvailable: false)
        await drainMainQueue()
        fixture.press(.profile)
        try fixture.openMenu()
        let sessionID = try #require(fixture.menu.session?.id)
        fixture.move(to: fixture.center(.scanner))
        let initialReads = fixture.applied.catalogReads.filter { $0 == .scanner }.count
        #expect(initialReads == 1)

        for distance: CGFloat in [9, 20, 35] {
            fixture.move(to: fixture.outwardPoint(over: .scanner, distance: distance))
        }
        fixture.move(to: fixture.center(.scanner))
        fixture.move(to: fixture.outwardPoint(over: .scanner))
        #expect(fixture.applied.catalogReads.filter { $0 == .scanner }.count == initialReads)
        #expect(fixture.menu.presentation == nil)
        #expect(fixture.menu.session?.id == sessionID)
        #expect(fixture.applied.focus.isEmpty)

        fixture.move(to: fixture.center(.home))
        fixture.move(to: fixture.center(.scanner))
        #expect(fixture.applied.catalogReads.filter { $0 == .scanner }.count == initialReads + 1)
        fixture.release(at: fixture.center(.scanner))
        #expect(fixture.commits == [.scanner])
        #expect(fixture.applied.destinations.isEmpty)
    }

    @Test("Returning from Scan clears camera focus without closing the session")
    func cameraFocusClearsDuringTraversal() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        fixture.press(.scanner)
        try fixture.openMenu()
        let sessionID = try #require(fixture.menu.session?.id)
        let scan = fixture.row(for: .scan)
        fixture.move(to: CGPoint(x: scan.midX, y: scan.midY))
        #expect(fixture.applied.focus == [.scan])
        fixture.move(to: fixture.center(.scanner))
        #expect(fixture.applied.focus == [.scan, nil])
        #expect(fixture.menu.session?.id == sessionID)
        #expect(fixture.menu.presentation == nil)
        fixture.move(to: fixture.outwardPoint(over: .scanner))
        let reopenedScan = fixture.row(for: .scan)
        fixture.move(to: CGPoint(x: reopenedScan.midX, y: reopenedScan.midY))
        fixture.move(to: fixture.center(.profile))
        #expect(fixture.applied.focus == [.scan, nil, .scan, nil])
        #expect(fixture.menu.session?.id == sessionID)
        #expect(fixture.applied.destinations.isEmpty)
        fixture.release(at: fixture.center(.profile))
        #expect(fixture.commits == [.profile])
    }

    @Test("A stale submenu frame cannot highlight or commit an item after moving to another tab")
    func ignoresOutgoingMenuGeometry() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        fixture.press(.profile)
        try fixture.openMenu()
        let oldID = try #require(fixture.menu.presentation?.id)
        let oldRow = fixture.row(for: .pet("miso"))
        fixture.move(to: fixture.center(.search))
        #expect(fixture.menu.presentation?.tab == .search)
        fixture.menu.setFrame(oldRow, for: .pet("miso"), presentationID: oldID)
        fixture.move(to: CGPoint(x: oldRow.midX, y: oldRow.midY))
        #expect(fixture.menu.highlighted == nil)
        fixture.release(at: CGPoint(x: oldRow.midX, y: oldRow.midY))
        #expect(fixture.applied.destinations.isEmpty)
        #expect(fixture.commits.isEmpty)
    }

    @Test("Availability and geometry interruptions also cancel a collapsed browsing session")
    func interruptionsCloseCollapsedSession() async throws {
        let interruptions: [(QuickSwitchFixture) -> Void] = [
            { $0.view.updateQuickSwitchAvailability(false) },
            { $0.window.frame = $0.window.frame.insetBy(dx: 0, dy: 20) },
            { $0.configure(contentSizeCategory: .extraExtraLarge) },
            { $0.view.select(.scanner, animated: false) },
        ]
        for interrupt in interruptions {
            let fixture = try QuickSwitchFixture()
            await drainMainQueue()
            fixture.press(.profile)
            try fixture.openMenu()
            fixture.move(to: fixture.outwardPoint(over: .profile))
            fixture.move(to: fixture.center(.profile))
            #expect(fixture.menu.presentation == nil)
            #expect(fixture.menu.isActive)
            interrupt(fixture)
            fixture.move(to: fixture.center(.search))
            fixture.release(at: fixture.center(.search))
            #expect(!fixture.menu.isActive)
            #expect(fixture.commits.isEmpty)
            #expect(fixture.applied.destinations.isEmpty)
        }
    }

    @Test("External menu cancellation ends the whole expanded or collapsed touch")
    func externalMenuCancellationCannotReopenOrCommit() async throws {
        for collapsed in [false, true] {
            let fixture = try QuickSwitchFixture()
            await drainMainQueue()
            fixture.press(.profile)
            try fixture.openMenu()
            if collapsed {
                fixture.move(to: fixture.outwardPoint(over: .profile))
                fixture.move(to: fixture.center(.profile))
                #expect(fixture.menu.presentation == nil)
            }
            fixture.menu.cancel()
            fixture.move(to: fixture.center(.search))
            fixture.release(at: fixture.center(.search))
            #expect(!fixture.menu.isActive)
            #expect(fixture.view.quickSwitchHold.pending == nil)
            #expect(fixture.commits.isEmpty)
            #expect(fixture.reselections.isEmpty)
            #expect(fixture.applied.destinations.isEmpty)

            fixture.press(.search)
            try fixture.openMenu()
            fixture.release(at: fixture.center(.search))
            #expect(fixture.commits == [.search], "A fresh touch still works after cancellation")
        }
    }

    @Test("Layout and timing changes cancel expanded or collapsed sessions, while identical values preserve them")
    func preferenceChangesCancelActiveSession() async throws {
        let replacements: [(TabQuickSwitchLayout, TimeInterval, TimeInterval)] = [
            (.bubbles, 0.45, 0.18), (.list, 0.6, 0.18), (.list, 0.45, 0.3),
        ]
        for (layout, holdDuration, spotlightDuration) in replacements {
            for collapsed in [false, true] {
                let fixture = try QuickSwitchFixture()
                await drainMainQueue()
                fixture.view.updateQuickSwitchPreferences(layout: .list, holdDuration: 0.45, spotlightDuration: 0.18)
                fixture.press(.profile)
                let oldHold = try #require(fixture.view.quickSwitchHold.pending)
                try fixture.openMenu()
                if collapsed {
                    fixture.move(to: fixture.outwardPoint(over: .profile))
                    fixture.move(to: fixture.center(.profile))
                }
                let session = fixture.menu.session
                let presentation = fixture.menu.presentation
                fixture.view.updateQuickSwitchPreferences(layout: .list, holdDuration: 0.45, spotlightDuration: 0.18)
                #expect(fixture.menu.session == session)
                #expect(fixture.menu.presentation == presentation)

                fixture.view.updateQuickSwitchPreferences(layout: layout, holdDuration: holdDuration,
                                                         spotlightDuration: spotlightDuration)
                #expect(!fixture.menu.isActive)
                fixture.view.openQuickSwitch(generation: oldHold.generation, at: oldHold.deadline)
                fixture.move(to: fixture.center(.search))
                fixture.release(at: fixture.center(.search))
                #expect(!fixture.menu.isActive)
                #expect(fixture.view.quickSwitchHold.pending == nil)
                #expect(fixture.commits.isEmpty)
                #expect(fixture.reselections.isEmpty)
                #expect(fixture.applied.destinations.isEmpty)
            }
        }
    }

    @Test("Layout and timing changes invalidate a pending hold's timer")
    func preferenceChangesInvalidatePendingHold() async throws {
        let replacements: [(TabQuickSwitchLayout, TimeInterval, TimeInterval)] = [
            (.bubbles, 0.45, 0.18), (.list, 0.6, 0.18), (.list, 0.45, 0.3),
        ]
        for (layout, holdDuration, spotlightDuration) in replacements {
            let fixture = try QuickSwitchFixture()
            await drainMainQueue()
            fixture.view.updateQuickSwitchPreferences(layout: .list, holdDuration: 0.45, spotlightDuration: 0.18)
            fixture.press(.profile)
            let pending = try #require(fixture.view.quickSwitchHold.pending)
            fixture.view.updateQuickSwitchPreferences(layout: .list, holdDuration: 0.45, spotlightDuration: 0.18)
            #expect(fixture.view.quickSwitchHold.pending == pending)
            fixture.view.updateQuickSwitchPreferences(layout: layout, holdDuration: holdDuration,
                                                     spotlightDuration: spotlightDuration)
            #expect(fixture.view.quickSwitchHold.pending == nil)
            fixture.view.openQuickSwitch(generation: pending.generation, at: pending.deadline)
            #expect(!fixture.menu.isActive)
            #expect(fixture.commits.isEmpty)
            #expect(fixture.applied.destinations.isEmpty)
            fixture.view.trackTouch(state: .cancelled, at: .zero)
        }
    }

    @Test("List animation experiments cancel active touches and invalidate pending holds")
    func listAnimationPreferencesCancelTracking() async throws {
        var alternatives = Array(repeating: TabQuickSwitchListAnimationSettings.defaults, count: 4)
        alternatives[0].switchStyle = .sequentialFade
        alternatives[1].entranceStyle = .slide
        alternatives[2].switchDuration = 0.6
        alternatives[3].entranceDuration = 0.6
        for animations in alternatives {
            for activated in [false, true] {
                let fixture = try QuickSwitchFixture()
                await drainMainQueue()
                fixture.view.updateQuickSwitchPreferences(layout: .list, holdDuration: 0.45, spotlightDuration: 0.45)
                fixture.press(.profile)
                let hold = try #require(fixture.view.quickSwitchHold.pending)
                if activated { try fixture.openMenu() }
                fixture.view.updateQuickSwitchPreferences(layout: .list, holdDuration: 0.45,
                                                         spotlightDuration: 0.45, listAnimations: animations)
                #expect(fixture.view.quickSwitchHold.pending == nil)
                #expect(!fixture.menu.isActive)
                fixture.view.openQuickSwitch(generation: hold.generation, at: hold.deadline)
                #expect(!fixture.menu.isActive)
                if activated {
                    fixture.release(at: fixture.center(.search))
                    #expect(fixture.commits.isEmpty)
                }
                fixture.view.trackTouch(state: .cancelled, at: .zero)
            }
        }
    }

    @Test("Returning to the selected tab and releasing reselects it only once")
    func activeSessionReselectsShownTab() async throws {
        let fixture = try QuickSwitchFixture()
        await drainMainQueue()
        fixture.press(.home)
        try fixture.openMenu()
        fixture.move(to: fixture.outwardPoint(over: .home))
        fixture.move(to: fixture.center(.home))
        #expect(fixture.menu.presentation == nil)
        fixture.release(at: fixture.center(.home))
        fixture.release(at: fixture.center(.home))
        #expect(fixture.reselections == [.home])
        #expect(fixture.commits.isEmpty)
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
        var focus: [TabQuickSwitchDestination?] = []
        var catalogReads: [RootTab] = []
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
    private(set) var reselections: [RootTab] = []
    let axis: NSLayoutConstraint.Axis
    let direction: UIUserInterfaceLayoutDirection

    init(axis: NSLayoutConstraint.Axis = .horizontal,
         direction: UIUserInterfaceLayoutDirection = .leftToRight,
         isHistoryAvailable: Bool = true) throws {
        self.axis = axis
        self.direction = direction
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        overlay = UIView(frame: window.bounds)
        let size = axis == .vertical ? CGSize(width: 60, height: 244) : CGSize(width: 360, height: 64)
        toolbar = UIView(frame: CGRect(x: axis == .vertical ? window.bounds.width - 80 : (window.bounds.width - size.width) / 2,
                                      y: axis == .vertical ? (window.bounds.height - size.height) / 2 : window.bounds.height - 120,
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

        let context = TabQuickSwitchCatalog.Context(homePage: .bookmarks, isHistoryAvailable: isHistoryAvailable,
                                                    petID: PetProfile.defaultID, searchScope: .breeds)
        menu = TabQuickSwitchMenu(items: { [applied] tab in
            applied.catalogReads.append(tab)
            return TabQuickSwitchCatalog.items(for: tab, in: context)
        }, apply: { [applied] destination, isTabShown in
            applied.destinations.append(destination)
            applied.wereTabsShown.append(isTabShown)
        }, focus: { [applied] destination in
            applied.focus.append(destination)
        })
        menu.coordinateView = overlay
        view.quickSwitch = menu
        view.onSelect = { [weak self] in self?.commits.append($0) }
        view.onReselect = { [weak self] in self?.reselections.append($0) }
        configure()
        window.layoutIfNeeded()
        view.layoutIfNeeded()
    }

    func configure(contentSizeCategory: UIContentSizeCategory = .large) {
        view.updateEnvironment(locale: Locale(identifier: "en"), contentSizeCategory: contentSizeCategory,
                               layoutDirection: direction, layoutAxis: axis, reduceMotion: false,
                               isEnabled: true)
    }

    func button(_ tab: RootTab) -> GlassTabBarButton {
        (view.accessibilityElements as? [GlassTabBarButton])!.first { $0.tab == tab }!
    }

    func center(_ tab: RootTab) -> CGPoint {
        window.convert(button(tab).center, from: view)
    }

    func outwardPoint(over tab: RootTab, distance: CGFloat = 9) -> CGPoint {
        let center = center(tab)
        return axis == .vertical
            ? CGPoint(x: toolbar.frame.minX - distance, y: center.y)
            : CGPoint(x: center.x, y: toolbar.frame.minY - distance)
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
        let frame = axis == .vertical
            ? CGRect(x: toolbar.frame.minX - 210, y: menu.presentation?.tabFrame.minY ?? toolbar.frame.minY,
                     width: 200, height: 44)
            : CGRect(x: toolbar.frame.minX, y: toolbar.frame.minY - 100, width: 200, height: 44)
        menu.setFrame(frame, for: destination, presentationID: menu.presentation?.id)
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
