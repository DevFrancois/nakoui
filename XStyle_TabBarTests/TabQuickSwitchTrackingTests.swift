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

    @Test("The bar never reaches an item, even one laid out under it")
    func barIsExcluded() {
        let bar = CGRect(x: 0, y: historyFrame.midY, width: 400, height: 64)
        var tracking = TabQuickSwitchTracking(excluding: bar)
        tracking.setFrame(historyFrame, for: .scanHistory)
        tracking.move(to: CGPoint(x: historyFrame.midX, y: historyFrame.maxY - 1))
        #expect(tracking.highlighted == nil)
        tracking.move(to: CGPoint(x: historyFrame.midX, y: historyFrame.minY))
        #expect(tracking.highlighted == .scanHistory)
    }

    @Test("A list's rows follow its scrolled origin, and only the visible card reaches them")
    func scrolledListRowsFollowOriginAndClip() {
        // Rows in the list's own space; the card shows the second and third.
        let rows = [TabQuickSwitchDestination.scan, .scanHistory, .homePage(.likes)].enumerated().map { index, id in
            (id, CGRect(x: 0, y: CGFloat(index) * 44, width: 200, height: 44))
        }
        let card = CGRect(x: 40, y: 500, width: 200, height: 88)
        var tracking = TabQuickSwitchTracking()
        for (id, frame) in rows { tracking.setFrame(frame, for: id) }
        tracking.setViewport(origin: CGPoint(x: card.minX, y: card.minY - 44), clip: card)

        tracking.move(to: CGPoint(x: card.midX, y: card.minY + 1))
        #expect(tracking.highlighted == .scanHistory)
        tracking.move(to: CGPoint(x: card.midX, y: card.maxY - 1))
        #expect(tracking.highlighted == .homePage(.likes))
        // The first row sits above the card, scrolled out of sight.
        tracking.move(to: CGPoint(x: card.midX, y: card.minY - 1))
        #expect(tracking.highlighted == nil)

        tracking.setViewport(origin: card.origin, clip: card)
        tracking.move(to: CGPoint(x: card.midX, y: card.minY + 1))
        #expect(tracking.highlighted == .scan)
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
        #expect(menu.items(for: .scanner, selectedTab: .scanner) == nil)
        offered.append(history)
        #expect(menu.items(for: .scanner, selectedTab: .scanner) == [item, history])
    }

    @Test("Only the tab that shows marks what it shows")
    func marksOnlyOnShownTab() {
        let current = TabQuickSwitchItem(tab: .home, destination: .homePage(.likes), title: "Likes", symbol: "heart",
                                         isCurrent: true)
        let other = TabQuickSwitchItem(tab: .home, destination: .homePage(.videos), title: "Videos",
                                       symbol: "play.square.stack")
        let menu = TabQuickSwitchMenu(items: { _ in [current, other] })
        #expect(menu.items(for: .home, selectedTab: .home)?.map(\.isCurrent) == [true, false])
        for tab in RootTab.allCases where tab != .home {
            #expect(menu.items(for: .home, selectedTab: tab)?.map(\.isCurrent) == [false, false])
        }
    }

    @Test("Focus follows what the finger rests on, and clears as the menu closes, before a release returns")
    func focusFollowsFinger() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        menu.setFrame(scanFrame, for: .scan)
        menu.setFrame(historyFrame, for: .scanHistory)
        menu.move(to: CGPoint(x: scanFrame.midX, y: scanFrame.midY))
        menu.move(to: CGPoint(x: scanFrame.midX + 1, y: scanFrame.midY))
        menu.move(to: CGPoint(x: scanFrame.maxX + 20, y: scanFrame.midY))
        menu.move(to: CGPoint(x: historyFrame.midX, y: historyFrame.midY))
        #expect(fixture.focus == [.scan, nil, .scanHistory])
        let released = menu.release(at: CGPoint(x: historyFrame.midX, y: historyFrame.midY))
        #expect(released?.destination == .scanHistory)
        #expect(fixture.focus == [.scan, nil, .scanHistory, nil])

        fixture.open()
        menu.cancel()
        #expect(fixture.focus.count == 4, "Closing with nothing under the finger reports nothing")
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

        var reached = 0
        menu.onReachItem = { reached += 1 }
        menu.move(to: CGPoint(x: scanFrame.midX, y: scanFrame.midY))
        menu.move(to: CGPoint(x: scanFrame.midX + 1, y: scanFrame.midY))
        #expect(menu.highlighted == .scan)
        #expect(reached == 1)
        // Lifting on the bar picks nothing.
        menu.move(to: CGPoint(x: fixture.tabFrame.midX, y: fixture.tabFrame.midY))
        #expect(menu.highlighted == nil)
        menu.move(to: CGPoint(x: historyFrame.midX, y: historyFrame.midY))
        #expect(reached == 2)
        let released = menu.release(at: CGPoint(x: historyFrame.midX, y: historyFrame.midY))
        #expect(released?.destination == .scanHistory)
        #expect(menu.presentation == nil)
        #expect(menu.highlighted == nil)
        #expect(fixture.applied.isEmpty)

        fixture.open()
        menu.setFrame(scanFrame, for: .scan)
        #expect(menu.release(at: fixture.tabFrame.origin) == nil)
        #expect(menu.presentation == nil)

        // A list too tall for its room: rows in its own space, shown from
        // where the card scrolls them to.
        fixture.open()
        let card = CGRect(x: 40, y: 400, width: 200, height: 44)
        menu.setFrame(CGRect(x: 0, y: 0, width: 200, height: 44), for: .scan)
        menu.setFrame(CGRect(x: 0, y: 44, width: 200, height: 44), for: .scanHistory)
        menu.setListViewport(card, contentHeight: 88)
        #expect(menu.listOffset == 0)
        #expect(menu.listOffsetLimit == 44)
        menu.move(to: CGPoint(x: card.midX, y: card.midY))
        #expect(menu.highlighted == .scan)
        // Below the card, the second row is out of sight.
        #expect(menu.release(at: CGPoint(x: card.midX, y: card.maxY + 22)) == nil)
        #expect(menu.listOffsetLimit == 0)

        fixture.open()
        menu.cancel()
        #expect(menu.presentation == nil)
        menu.setFrame(scanFrame, for: .scan)
        #expect(menu.release(at: CGPoint(x: scanFrame.midX, y: scanFrame.midY)) == nil)

        let item = try #require(fixture.items.last)
        menu.apply(item, isTabShown: false)
        #expect(fixture.applied == [.scanHistory])
    }

    @Test("Collapse, reopening and switching menus preserve one touch session and its finger")
    func continuousSessionSurvivesSubmenuChanges() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        let session = try #require(menu.session)
        let first = try #require(menu.presentation)
        #expect(menu.isActive)
        #expect(session.barFrame == fixture.barFrame)
        #expect(menu.focusFrame == fixture.barFrame)

        let scanPoint = CGPoint(x: scanFrame.midX, y: scanFrame.midY)
        menu.setFrame(scanFrame, for: .scan, presentationID: first.id)
        menu.setFocusFrame(scanFrame, presentationID: first.id)
        menu.move(to: scanPoint)
        #expect(menu.highlighted == .scan)
        #expect(menu.focusFrame == fixture.barFrame.union(scanFrame))

        menu.collapse()
        #expect(menu.session == session)
        #expect(menu.presentation == nil)
        #expect(menu.pointer == scanPoint)
        #expect(menu.highlighted == nil)
        #expect(menu.focusFrame == fixture.barFrame.union(scanFrame))
        #expect(menu.pendingFocusContraction != nil)
        #expect(fixture.focus == [.scan, nil])

        let returnPoint = CGPoint(x: fixture.tabFrame.midX, y: fixture.tabFrame.midY)
        menu.move(to: returnPoint)
        #expect(menu.pointer == returnPoint)
        fixture.open()
        let reopened = try #require(menu.presentation)
        #expect(reopened.id != first.id)
        #expect(menu.session == session)
        #expect(menu.pointer == returnPoint)

        let homeItems = [
            TabQuickSwitchItem(tab: .home, destination: .homePage(.likes), title: "Likes", symbol: "heart"),
            TabQuickSwitchItem(tab: .home, destination: .homePage(.videos), title: "Videos", symbol: "play"),
        ]
        menu.setFocusFrame(historyFrame, presentationID: reopened.id)
        let resolvedFocus = menu.focusFrame
        menu.open(tab: .home, items: homeItems, tabFrame: fixture.tabFrame,
                  barFrame: fixture.barFrame, axis: .horizontal)
        let replacement = try #require(menu.presentation)
        #expect(replacement.tab == .home)
        #expect(replacement.id != reopened.id)
        #expect(menu.session == session)
        #expect(menu.focusFrame == resolvedFocus, "Replacement keeps the resolved focus until its layout arrives")
        #expect(fixture.applied.isEmpty, "Exploring never navigates")

        menu.cancel()
        fixture.open()
        #expect(menu.session?.id != session.id)
        #expect(menu.presentation?.id != replacement.id)
        menu.cancel()
    }

    @Test("Outgoing submenu geometry cannot remove current rows, restart scrolling or move the spotlight")
    func rejectsStaleSubmenuGeometry() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        let outgoingID = try #require(menu.presentation?.id)
        menu.setFocusFrame(scanFrame, presentationID: outgoingID)
        let previousFocus = menu.focusFrame
        menu.move(to: CGPoint(x: scanFrame.midX, y: scanFrame.midY))

        fixture.open()
        let currentID = try #require(menu.presentation?.id)
        menu.setFrame(scanFrame, for: .scan, presentationID: currentID)
        #expect(menu.highlighted == .scan, "A replacement uses the current finger when its layout arrives")
        menu.setFrame(nil, for: .scan, presentationID: outgoingID)
        menu.setFrame(historyFrame, for: .scanHistory, presentationID: outgoingID)
        menu.setListViewport(scanFrame, contentHeight: 500, presentationID: outgoingID)
        menu.setFocusFrame(CGRect(x: 0, y: 0, width: 400, height: 800), presentationID: outgoingID)
        #expect(menu.highlighted == .scan)
        #expect(menu.listOffsetLimit == 0)
        #expect(menu.focusFrame == previousFocus)
        menu.move(to: CGPoint(x: historyFrame.midX, y: historyFrame.midY))
        #expect(menu.highlighted == nil)

        menu.setFrame(historyFrame, for: .scanHistory, presentationID: currentID)
        menu.setFocusFrame(historyFrame, presentationID: currentID)
        #expect(menu.highlighted == .scanHistory)
        #expect(menu.focusFrame == fixture.barFrame.union(historyFrame))
        menu.collapse()
        menu.setFrame(scanFrame, for: .scan, presentationID: currentID)
        menu.setListViewport(scanFrame, contentHeight: 500, presentationID: currentID)
        menu.setFocusFrame(historyFrame, presentationID: currentID)
        #expect(menu.highlighted == nil)
        #expect(menu.listOffsetLimit == 0)
        #expect(menu.focusFrame == fixture.barFrame.union(historyFrame))
        let contraction = try #require(menu.pendingFocusContraction)
        menu.advanceFocusContraction(generation: contraction.generation, at: contraction.deadline)
        #expect(menu.focusFrame == fixture.barFrame)
        menu.cancel()
    }

    @Test("Replacing or collapsing Scan clears camera focus and list scrolling without ending the session")
    func replacementClearsSubmenuTracking() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        let sessionID = try #require(menu.session?.id)
        let firstID = try #require(menu.presentation?.id)
        let card = CGRect(x: 40, y: 400, width: 200, height: 44)
        menu.setFrame(CGRect(x: 0, y: 0, width: 200, height: 44), for: .scan, presentationID: firstID)
        menu.setFrame(CGRect(x: 0, y: 44, width: 200, height: 44), for: .scanHistory, presentationID: firstID)
        menu.setListViewport(card, contentHeight: 88, presentationID: firstID)
        menu.setFocusFrame(card, presentationID: firstID)
        menu.move(to: CGPoint(x: card.midX, y: card.midY))
        #expect(menu.listOffsetLimit == 44)
        #expect(fixture.focus == [.scan])

        fixture.open()
        let replacementID = try #require(menu.presentation?.id)
        #expect(menu.session?.id == sessionID)
        #expect(menu.highlighted == nil)
        #expect(menu.listOffset == 0)
        #expect(menu.listOffsetLimit == 0)
        #expect(fixture.focus == [.scan, nil])
        #expect(menu.focusFrame == fixture.barFrame.union(card))
        // The replacement has no list origin left from the outgoing card.
        menu.setFrame(scanFrame, for: .scan, presentationID: replacementID)
        #expect(menu.highlighted == .scan)
        menu.collapse()
        menu.collapse()
        #expect(menu.session?.id == sessionID)
        #expect(fixture.focus == [.scan, nil, .scan, nil])
        menu.cancel()
        #expect(fixture.focus.count == 4)
        #expect(fixture.applied.isEmpty)
    }

    @Test("Release and cancellation end a collapsed session, and the next session rejects its reports",
          arguments: [false, true])
    func endsCollapsedSession(cancel: Bool) throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        let previousID = try #require(menu.presentation?.id)
        menu.setFocusFrame(scanFrame, presentationID: previousID)
        menu.collapse()
        let contraction = try #require(menu.pendingFocusContraction)
        menu.move(to: CGPoint(x: 100, y: 700))
        #expect(menu.pointer == CGPoint(x: 100, y: 700))
        if cancel {
            menu.cancel()
        } else {
            let released = menu.release(at: fixture.tabFrame.origin)
            #expect(released == nil)
        }
        #expect(!menu.isActive)
        #expect(menu.presentation == nil)
        #expect(menu.pointer == nil)
        #expect(menu.focusFrame == nil)
        #expect(menu.pendingFocusContraction == nil)
        #expect(menu.release(at: fixture.tabFrame.origin) == nil)

        fixture.open()
        let nextID = try #require(menu.presentation?.id)
        menu.setFocusFrame(historyFrame, presentationID: nextID)
        menu.advanceFocusContraction(generation: contraction.generation, at: contraction.deadline)
        #expect(menu.focusFrame == fixture.barFrame.union(historyFrame))
        menu.setFrame(scanFrame, for: .scan, presentationID: previousID)
        menu.move(to: CGPoint(x: scanFrame.midX, y: scanFrame.midY))
        #expect(menu.highlighted == nil)
        #expect(fixture.applied.isEmpty)
        menu.cancel()
    }

    @Test("Focus contracts only after its 100 ms grace, while choices and Scan focus clear immediately")
    func collapseDefersOnlyFocusContraction() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        let presentationID = try #require(menu.presentation?.id)
        let sessionID = try #require(menu.session?.id)
        menu.setFrame(scanFrame, for: .scan, presentationID: presentationID)
        menu.setFocusFrame(scanFrame, presentationID: presentationID)
        menu.move(to: CGPoint(x: scanFrame.midX, y: scanFrame.midY))
        let expandedFocus = menu.focusFrame

        menu.collapse(at: 10)
        let contraction = try #require(menu.pendingFocusContraction)
        #expect(contraction.deadline == 10 + TabQuickSwitchMenu.focusContractionDelay)
        #expect(contraction.sessionID == sessionID)
        #expect(menu.presentation == nil)
        #expect(menu.highlighted == nil)
        #expect(fixture.focus == [.scan, nil])
        #expect(menu.focusFrame == expandedFocus)
        menu.advanceFocusContraction(generation: contraction.generation &+ 1, at: contraction.deadline)
        menu.advanceFocusContraction(generation: contraction.generation, at: 10.05)
        #expect(menu.focusFrame == expandedFocus)
        menu.collapse(at: 10.07)
        #expect(menu.pendingFocusContraction == contraction, "Remaining collapsed must not extend the grace")

        menu.advanceFocusContraction(generation: contraction.generation, at: contraction.deadline)
        #expect(menu.focusFrame == fixture.barFrame)
        #expect(menu.pendingFocusContraction == nil)
        #expect(menu.session?.id == sessionID)
        #expect(fixture.applied.isEmpty)
        menu.cancel()
    }

    @Test("Quick reopening or replacement cancels contraction and preserves the previously resolved focus")
    func reopeningCancelsPendingContraction() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        let firstID = try #require(menu.presentation?.id)
        menu.setFocusFrame(scanFrame, presentationID: firstID)
        let expandedFocus = menu.focusFrame
        menu.collapse(at: 10)
        let firstContraction = try #require(menu.pendingFocusContraction)

        fixture.open()
        #expect(menu.pendingFocusContraction == nil)
        menu.advanceFocusContraction(generation: firstContraction.generation, at: firstContraction.deadline)
        #expect(menu.focusFrame == expandedFocus)
        let replacementID = try #require(menu.presentation?.id)
        menu.setFocusFrame(historyFrame, presentationID: replacementID)
        let replacementFocus = menu.focusFrame
        menu.collapse(at: 20)
        let secondContraction = try #require(menu.pendingFocusContraction)
        #expect(secondContraction.generation != firstContraction.generation)
        menu.advanceFocusContraction(generation: firstContraction.generation, at: secondContraction.deadline)
        #expect(menu.focusFrame == replacementFocus)
        #expect(menu.pendingFocusContraction == secondContraction)
        menu.cancel()
    }

    @Test("A registered native list resolves only visible transformed rows, including beneath a stationary finger")
    func nativeListUsesVisibleGeometry() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        let generation = try #require(menu.presentation?.id)
        let display = ListDisplayFixture(generation: generation)
        display.visibleFrame = historyFrame
        display.visibleDestination = .scan
        menu.setListDisplay(display, presentationID: generation)
        menu.setFrame(scanFrame, for: .scan, presentationID: generation)
        menu.setFrame(historyFrame, for: .scanHistory, presentationID: generation)
        menu.move(to: CGPoint(x: scanFrame.midX, y: scanFrame.midY))
        #expect(menu.highlighted == nil, "An invisible target row must not win through raw geometry")
        let visiblePoint = CGPoint(x: historyFrame.midX, y: historyFrame.midY)
        menu.move(to: visiblePoint)
        #expect(menu.highlighted == .scan, "The renderer's transformed row determines the destination")
        #expect(display.highlighted == .scan)
        display.visibleFrame = nil
        menu.listDisplayDidUpdate(presentationID: generation)
        #expect(menu.highlighted == nil)
        #expect(display.highlighted == nil)
        display.visibleFrame = historyFrame
        menu.listDisplayDidUpdate(presentationID: generation)
        #expect(menu.highlighted == .scan)
        #expect(fixture.applied.isEmpty)

        let released = menu.release(at: visiblePoint)
        #expect(released?.destination == .scan)
        #expect(display.highlighted == nil)
        #expect(fixture.focus == [.scan, nil, .scan, nil])
        #expect(menu.release(at: visiblePoint) == nil)
    }

    @Test("A list renderer that disappears never falls back to invisible raw rows")
    func nativeListDisappearanceCannotCommitRawRows() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        let generation = try #require(menu.presentation?.id)
        var display: ListDisplayFixture? = ListDisplayFixture(generation: generation)
        menu.setListDisplay(try #require(display), presentationID: generation)
        menu.setFrame(scanFrame, for: .scan, presentationID: generation)
        display = nil
        let point = CGPoint(x: scanFrame.midX, y: scanFrame.midY)
        menu.move(to: point)
        #expect(menu.highlighted == nil)
        #expect(menu.release(at: point) == nil)
        #expect(fixture.applied.isEmpty)
    }

    @Test("Outgoing native-list registration and readiness cannot replace the current renderer")
    func staleNativeListCannotReplaceCurrentRenderer() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        let outgoingID = try #require(menu.presentation?.id)
        let outgoing = ListDisplayFixture(generation: outgoingID)
        outgoing.visibleFrame = scanFrame
        outgoing.visibleDestination = .scan
        menu.setListDisplay(outgoing, presentationID: outgoingID)
        fixture.open()
        let currentID = try #require(menu.presentation?.id)
        let current = ListDisplayFixture(generation: currentID)
        current.visibleFrame = scanFrame
        current.visibleDestination = .scanHistory
        menu.setListDisplay(current, presentationID: currentID)
        menu.setListDisplay(outgoing, presentationID: outgoingID)
        menu.listDisplayDidUpdate(presentationID: outgoingID)
        let point = CGPoint(x: scanFrame.midX, y: scanFrame.midY)
        menu.move(to: point)
        #expect(menu.highlighted == .scanHistory)
        #expect(current.highlighted == .scanHistory)
        #expect(outgoing.highlighted == nil)
        menu.cancel()
    }

    @Test("Native list scrolling pauses during presentation motion and synchronizes each resumed offset")
    func nativeListScrollsOnlyWhenReady() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        fixture.open()
        let generation = try #require(menu.presentation?.id)
        let display = ListDisplayFixture(generation: generation)
        display.visibleFrame = scanFrame
        display.visibleDestination = .scan
        menu.setListDisplay(display, presentationID: generation)
        menu.setListViewport(scanFrame, contentHeight: 132, presentationID: generation)
        menu.setFocusFrame(scanFrame, presentationID: generation)
        let focus = menu.focusFrame
        menu.move(to: CGPoint(x: scanFrame.midX, y: scanFrame.maxY - 1))
        let paused = menu.advanceListScroll(by: 1.0 / 60)
        #expect(!paused)
        #expect(menu.listOffset == 0)
        #expect(display.offsetLimit == 88)

        display.isReadyForScrolling = true
        menu.listDisplayDidUpdate(presentationID: generation)
        let advanced = menu.advanceListScroll(by: 1.0 / 60)
        #expect(advanced)
        #expect(menu.listOffset > 0)
        #expect(display.offset == menu.listOffset)
        #expect(menu.focusFrame == focus, "Scrolling rows does not resize the visible focus card")
        display.isReadyForScrolling = false
        menu.listDisplayDidUpdate(presentationID: generation)
        let previousOffset = menu.listOffset
        let advancedWhileMoving = menu.advanceListScroll(by: 1.0 / 60)
        #expect(!advancedWhileMoving)
        #expect(menu.listOffset == previousOffset)
        menu.cancel()
    }

    @Test("An unavailable overlay cannot start a session")
    func unavailableOverlayDoesNotStartSession() {
        let menu = TabQuickSwitchMenu()
        menu.open(tab: .scanner, items: [], tabFrame: scanFrame, barFrame: historyFrame, axis: .vertical)
        #expect(!menu.canOpen)
        #expect(!menu.isActive)
        #expect(menu.presentation == nil)
    }

    @Test("Detaching or moving the overlay to another window cancels an expanded or collapsed session")
    func overlayWindowChangesCancelSession() throws {
        for collapsed in [false, true] {
            let fixture = MenuFixture()
            let menu = fixture.menu
            let coordinateView = TabQuickSwitchCoordinateView(menu: menu)
            coordinateView.frame = fixture.window.bounds
            menu.coordinateView = coordinateView
            fixture.window.addSubview(coordinateView)
            fixture.open()
            if collapsed { menu.collapse() }
            #expect(menu.isActive)
            coordinateView.removeFromSuperview()
            #expect(!menu.isActive)
            #expect(menu.pointer == nil)

            fixture.window.addSubview(coordinateView)
            fixture.open()
            if collapsed { menu.collapse() }
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let otherWindow = UIWindow(windowScene: scene)
            otherWindow.frame = fixture.window.frame
            otherWindow.addSubview(coordinateView)
            #expect(!menu.isActive)
            #expect(menu.presentation == nil)
        }
    }

    @Test("Coordinate replacement cancels the old session, while its late dismantle preserves the new one")
    func outgoingCoordinateViewCannotCancelReplacement() throws {
        let fixture = MenuFixture()
        let menu = fixture.menu
        let outgoing = TabQuickSwitchCoordinateView(menu: menu)
        outgoing.frame = fixture.window.bounds
        fixture.window.addSubview(outgoing)
        menu.coordinateView = outgoing
        fixture.open()
        let previousSession = try #require(menu.session?.id)

        let replacement = TabQuickSwitchCoordinateView(menu: menu)
        replacement.frame = fixture.window.bounds
        fixture.window.addSubview(replacement)
        menu.coordinateView = replacement
        #expect(!menu.isActive)
        fixture.open()
        let replacementSession = try #require(menu.session?.id)
        #expect(replacementSession != previousSession)
        TabQuickSwitchCoordinateSpace.dismantleUIView(outgoing, coordinator: ())
        outgoing.removeFromSuperview()
        #expect(menu.coordinateView === replacement)
        #expect(menu.session?.id == replacementSession)

        TabQuickSwitchCoordinateSpace.dismantleUIView(replacement, coordinator: ())
        #expect(!menu.isActive)
        #expect(menu.coordinateView == nil)
    }

    @MainActor
    private final class ListDisplayFixture: TabQuickSwitchListDisplaying {
        let generation: UInt64
        var visibleFrame: CGRect?
        var visibleDestination: TabQuickSwitchDestination?
        var isReadyForScrolling = false
        private(set) var highlighted: TabQuickSwitchDestination?
        private(set) var offset: CGFloat = 0
        private(set) var offsetLimit: CGFloat = 0

        init(generation: UInt64) { self.generation = generation }

        func destination(at point: CGPoint, presentationID: UInt64) -> TabQuickSwitchDestination? {
            guard presentationID == generation, visibleFrame?.contains(point) == true else { return nil }
            return visibleDestination
        }

        func setScrollOffset(_ offset: CGFloat, limit: CGFloat, presentationID: UInt64) {
            guard presentationID == generation else { return }
            self.offset = offset
            offsetLimit = limit
        }

        func setHighlighted(_ destination: TabQuickSwitchDestination?, presentationID: UInt64) {
            guard presentationID == generation else { return }
            highlighted = destination
        }

        func canAutoscroll(presentationID: UInt64) -> Bool {
            presentationID == generation && isReadyForScrolling
        }
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
        private(set) var focus: [TabQuickSwitchDestination?] = []
        private(set) lazy var menu = TabQuickSwitchMenu(items: { [items] _ in items }) { [weak self] destination, _ in
            self?.applied.append(destination)
        } focus: { [weak self] destination in
            self?.focus.append(destination)
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
