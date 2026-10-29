import SwiftUI
import UIKit

/// A retained list surface resolves against its currently visible geometry.
/// The model keeps interaction ownership and supplies scrolling and hover.
@MainActor
protocol TabQuickSwitchListDisplaying: AnyObject {
    func destination(at point: CGPoint, presentationID: UInt64) -> TabQuickSwitchDestination?
    func setScrollOffset(_ offset: CGFloat, limit: CGFloat, presentationID: UInt64)
    func setHighlighted(_ destination: TabQuickSwitchDestination?, presentationID: UInt64)
    func canAutoscroll(presentationID: UInt64) -> Bool
}

/// One held touch can browse the bar and several menus without ending its
/// spotlight session. The bar owns the finger; the overlay reports where
/// the current menu's items are. All stored geometry is in overlay space.
@MainActor
@Observable
final class TabQuickSwitchMenu {
    struct Session: Equatable {
        let id: UInt64
        let barFrame: CGRect
        let axis: Axis
    }

    struct Presentation: Equatable {
        /// A submenu's generation, independent of the uninterrupted touch.
        let id: UInt64
        let tab: RootTab
        let items: [TabQuickSwitchItem]
        /// Where the held tab and the whole bar rest, without the press zoom.
        let tabFrame: CGRect
        let barFrame: CGRect
        let axis: Axis
    }

    struct FocusContraction: Equatable {
        let deadline: TimeInterval
        let generation: UInt64
        let sessionID: UInt64
    }

    static let focusContractionDelay: TimeInterval = 0.1

    /// Remains alive while the finger browses the bar with no submenu open.
    private(set) var session: Session?
    var isActive: Bool { session != nil }
    /// The most recent finger location, including while choices collapse.
    private(set) var pointer: CGPoint?
    /// Last resolved active area, retained while a replacement menu lays out.
    private(set) var focusFrame: CGRect?
    /// The currently expanded submenu, if any.
    private(set) var presentation: Presentation?
    /// The item under the finger.
    private(set) var highlighted: TabQuickSwitchDestination?
    /// How far a list too tall for its room has scrolled, and can.
    private(set) var listOffset: CGFloat = 0
    private(set) var listOffsetLimit: CGFloat = 0

    @ObservationIgnored weak var coordinateView: UIView? {
        willSet {
            if coordinateView !== newValue { cancel() }
        }
    }
    /// Called as the finger reaches an item it wasn't on, for a haptic.
    @ObservationIgnored var onReachItem: (() -> Void)?
    @ObservationIgnored private var tracking = TabQuickSwitchTracking()
    @ObservationIgnored private var listScroll: TabQuickSwitchListScroll?
    @ObservationIgnored private var scrollLink: CADisplayLink?
    @ObservationIgnored private var lastScrollTime: CFTimeInterval?
    @ObservationIgnored private var sessionGeneration: UInt64 = 0
    @ObservationIgnored private var presentationGeneration: UInt64 = 0
    @ObservationIgnored private var focusContractionGeneration: UInt64 = 0
    @ObservationIgnored private var focusContractionTask: Task<Void, Never>?
    @ObservationIgnored private(set) var pendingFocusContraction: FocusContraction?
    @ObservationIgnored private weak var listDisplay: (any TabQuickSwitchListDisplaying)?
    /// Kept even if the renderer disappears, so list hits never fall back to
    /// invisible rows in the raw layout snapshot.
    @ObservationIgnored private var listDisplayGeneration: UInt64?
    @ObservationIgnored private let catalog: (RootTab) -> [TabQuickSwitchItem]
    @ObservationIgnored private let destinationHandler: (TabQuickSwitchDestination, Bool) -> Void
    @ObservationIgnored private let focusHandler: (TabQuickSwitchDestination?) -> Void

    /// - Parameters:
    ///   - items: What holding a tab offers, read as each hold opens.
    ///   - apply: Takes a tab to a destination; see `apply(_:isTabShown:)`.
    ///   - focus: What the finger rests on, as it changes; nil once it rests
    ///     on nothing, and as the menu closes, before a release applies its
    ///     item.
    init(
        items: @escaping (RootTab) -> [TabQuickSwitchItem] = { _ in [] },
        apply: @escaping (_ destination: TabQuickSwitchDestination, _ isTabShown: Bool) -> Void = { _, _ in },
        focus: @escaping (TabQuickSwitchDestination?) -> Void = { _ in }
    ) {
        catalog = items
        destinationHandler = apply
        focusHandler = focus
    }

    /// What holding `tab` would offer, while `selectedTab` shows: nil for
    /// fewer than two items, which leaves the hold to preview tabs as usual.
    /// Only the tab that shows marks what it shows.
    func items(for tab: RootTab, selectedTab: RootTab) -> [TabQuickSwitchItem]? {
        var items = catalog(tab)
        guard items.count > 1 else { return nil }
        if tab != selectedTab {
            for index in items.indices { items[index].isCurrent = false }
        }
        return items
    }

    /// Takes the item's tab to it. The bar calls this before changing tabs,
    /// so a page comes in already showing the item; `isTabShown` tells
    /// whether the tab shows already, and the change can animate.
    func apply(_ item: TabQuickSwitchItem, isTabShown: Bool) {
        destinationHandler(item.destination, isTabShown)
    }

    /// Whether the overlay is on screen to show a menu.
    var canOpen: Bool { coordinateView?.window != nil }

    /// Opens or replaces `tab`'s submenu without ending the active touch.
    /// The frames are in window space.
    func open(tab: RootTab, items: [TabQuickSwitchItem], tabFrame: CGRect, barFrame: CGRect,
              axis: NSLayoutConstraint.Axis) {
        guard let coordinateView, coordinateView.window != nil else { return }
        cancelFocusContraction()
        resetSubmenuTracking()
        presentationGeneration &+= 1
        let presentation = Presentation(
            id: presentationGeneration, tab: tab, items: items,
            tabFrame: coordinateView.convert(tabFrame, from: nil),
            barFrame: coordinateView.convert(barFrame, from: nil),
            axis: axis == .vertical ? .vertical : .horizontal
        )
        if session == nil {
            sessionGeneration &+= 1
            session = Session(id: sessionGeneration, barFrame: presentation.barFrame, axis: presentation.axis)
            pointer = CGPoint(x: presentation.tabFrame.midX, y: presentation.tabFrame.midY)
            focusFrame = presentation.barFrame
        }
        // The interaction pipeline handles bar releases separately.
        tracking = TabQuickSwitchTracking(excluding: presentation.barFrame)
        if let pointer { tracking.move(to: pointer) }
        self.presentation = presentation
    }

    /// From the overlay as it lays an item out: a bubble in the overlay's
    /// space, a list row in its list's; see `setListViewport`.
    func setFrame(_ frame: CGRect?, for destination: TabQuickSwitchDestination, presentationID: UInt64? = nil) {
        guard let presentation,
              presentationID == nil || presentationID == presentation.id,
              presentation.items.contains(where: { $0.destination == destination }) else { return }
        tracking.setFrame(frame, for: destination)
        updateHighlight()
    }

    /// From a list as it lays out: its visible card, in the overlay's space,
    /// and its rows' whole height. Rows outside the card can't be picked.
    func setListViewport(_ viewport: CGRect, contentHeight: CGFloat, presentationID: UInt64? = nil) {
        guard let presentation, presentationID == nil || presentationID == presentation.id else { return }
        var scroll = listScroll ?? TabQuickSwitchListScroll(viewport: viewport, contentHeight: contentHeight)
        scroll.update(viewport: viewport, contentHeight: contentHeight)
        listScroll = scroll
        applyListScroll()
        updateScrolling()
    }

    /// Registers before the list publishes layout. A registered list uses
    /// only the renderer's visible geometry for hover and release.
    func setListDisplay(_ display: any TabQuickSwitchListDisplaying, presentationID: UInt64) {
        guard presentation?.id == presentationID else { return }
        listDisplay = display
        listDisplayGeneration = presentationID
        display.setScrollOffset(listOffset, limit: listOffsetLimit, presentationID: presentationID)
        updateHighlight()
        display.setHighlighted(highlighted, presentationID: presentationID)
        updateScrolling()
    }

    /// Entrance/exit changes can reveal a row beneath a stationary finger.
    func listDisplayDidUpdate(presentationID: UInt64) {
        guard presentation?.id == presentationID, listDisplayGeneration == presentationID else { return }
        updateHighlight()
        updateScrolling()
    }

    /// Reports a complete submenu's visible area. Outgoing panels cannot
    /// change the spotlight while the next generation lays itself out.
    func setFocusFrame(_ frame: CGRect, presentationID: UInt64) {
        guard let session, presentation?.id == presentationID,
              !frame.isEmpty, !frame.isNull,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.maxX.isFinite, frame.maxY.isFinite else { return }
        focusFrame = session.barFrame.union(frame)
    }

    /// Hides choices immediately, allowing a brief crossing to another tab
    /// before the spotlight contracts to the bar.
    func collapse(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let session else { return }
        resetSubmenuTracking()
        presentation = nil
        guard focusFrame != session.barFrame, pendingFocusContraction == nil else { return }
        focusContractionGeneration &+= 1
        let contraction = FocusContraction(deadline: time + Self.focusContractionDelay,
                                           generation: focusContractionGeneration, sessionID: session.id)
        pendingFocusContraction = contraction
        startFocusContractionTimer(contraction, after: Self.focusContractionDelay)
    }

    /// Takes time explicitly so grace-period transitions need no real waits
    /// in tests. Both generation and session reject an outgoing timer.
    func advanceFocusContraction(generation: UInt64, at time: TimeInterval) {
        guard let pending = pendingFocusContraction, pending.generation == generation,
              let session, session.id == pending.sessionID, presentation == nil else { return }
        guard time >= pending.deadline else {
            startFocusContractionTimer(pending, after: pending.deadline - time)
            return
        }
        cancelFocusContraction()
        focusFrame = session.barFrame
    }

    /// Follows the finger, in window space.
    func move(to windowPoint: CGPoint) {
        guard isActive, let point = convert(windowPoint) else { return }
        pointer = point
        guard presentation != nil else { return }
        tracking.move(to: point)
        updateHighlight()
        updateScrolling()
    }

    /// Ends the touch, returning the item the finger lifted on, if any.
    func release(at windowPoint: CGPoint) -> TabQuickSwitchItem? {
        guard isActive else { return nil }
        let items = presentation?.items ?? []
        let destination: TabQuickSwitchDestination?
        if let point = convert(windowPoint) {
            tracking.move(to: point)
            destination = resolvedDestination
        } else {
            destination = nil
        }
        close()
        return items.first { $0.destination == destination }
    }

    func cancel() {
        guard isActive else { return }
        close()
    }

    private func close() {
        cancelFocusContraction()
        resetSubmenuTracking()
        presentation = nil
        session = nil
        pointer = nil
        focusFrame = nil
    }

    private func resetSubmenuTracking() {
        stopScrolling()
        if let listDisplayGeneration {
            listDisplay?.setHighlighted(nil, presentationID: listDisplayGeneration)
        }
        listDisplay = nil
        listDisplayGeneration = nil
        tracking = TabQuickSwitchTracking()
        listScroll = nil
        listOffset = 0
        listOffsetLimit = 0
        if highlighted != nil {
            highlighted = nil
            focusHandler(nil)
        }
    }

    private func updateHighlight() {
        let previous = highlighted
        highlighted = resolvedDestination
        guard highlighted != previous else { return }
        if let listDisplayGeneration {
            listDisplay?.setHighlighted(highlighted, presentationID: listDisplayGeneration)
        }
        if highlighted != nil { onReachItem?() }
        focusHandler(highlighted)
    }

    private var resolvedDestination: TabQuickSwitchDestination? {
        guard let presentation, let point = tracking.point else { return nil }
        guard let listDisplayGeneration else { return tracking.highlighted }
        guard listDisplayGeneration == presentation.id,
              !presentation.barFrame.contains(point),
              let destination = listDisplay?.destination(at: point, presentationID: presentation.id),
              presentation.items.contains(where: { $0.destination == destination }) else { return nil }
        return destination
    }

    private func startFocusContractionTimer(_ contraction: FocusContraction, after delay: TimeInterval) {
        focusContractionTask?.cancel()
        focusContractionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.advanceFocusContraction(generation: contraction.generation, at: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func cancelFocusContraction() {
        focusContractionTask?.cancel()
        focusContractionTask = nil
        pendingFocusContraction = nil
    }

    /// Moves the list's rows, and what the finger can reach, to its offset.
    private func applyListScroll() {
        guard let listScroll else { return }
        listOffset = listScroll.offset
        listOffsetLimit = listScroll.maximumOffset
        let viewport = listScroll.viewport
        tracking.setViewport(origin: CGPoint(x: viewport.minX, y: viewport.minY - listScroll.offset), clip: viewport)
        if let listDisplayGeneration {
            listDisplay?.setScrollOffset(listOffset, limit: listOffsetLimit, presentationID: listDisplayGeneration)
        }
        updateHighlight()
    }

    private var scrollVelocity: CGFloat {
        guard presentation != nil, let listScroll, let point = tracking.point else { return 0 }
        if let listDisplayGeneration {
            guard presentation?.id == listDisplayGeneration,
                  listDisplay?.canAutoscroll(presentationID: listDisplayGeneration) == true else { return 0 }
        }
        return listScroll.velocity(at: point)
    }

    /// Scrolls each frame while the finger rests near the list's edge.
    private func updateScrolling() {
        guard scrollVelocity != 0 else {
            stopScrolling()
            return
        }
        guard scrollLink == nil else { return }
        let target = TabQuickSwitchScrollTarget { [weak self] link in self?.scrollStep(link) }
        let link = CADisplayLink(target: target, selector: #selector(TabQuickSwitchScrollTarget.step(_:)))
        link.add(to: .main, forMode: .common)
        scrollLink = link
    }

    private func scrollStep(_ link: CADisplayLink) {
        guard scrollLink === link else { return }
        guard scrollVelocity != 0 else {
            stopScrolling()
            return
        }
        // The first frame only starts the clock. A late frame moves no
        // further than a slow one would.
        let previousTime = lastScrollTime
        lastScrollTime = link.timestamp
        guard let previousTime else { return }
        if !advanceListScroll(by: link.timestamp - previousTime) { stopScrolling() }
    }

    /// The same bounded step used by the display link, with an explicit
    /// elapsed time for deterministic transition and scrolling tests.
    @discardableResult
    func advanceListScroll(by elapsed: TimeInterval) -> Bool {
        let velocity = scrollVelocity
        guard velocity != 0, var scroll = listScroll, elapsed.isFinite, elapsed > 0 else { return false }
        let elapsed = min(elapsed, 1.0 / 15)
        guard scroll.scroll(by: velocity * elapsed) else {
            return false
        }
        listScroll = scroll
        applyListScroll()
        return true
    }

    private func stopScrolling() {
        scrollLink?.invalidate()
        scrollLink = nil
        lastScrollTime = nil
    }

    private func convert(_ windowPoint: CGPoint) -> CGPoint? {
        guard let coordinateView, coordinateView.window != nil else { return nil }
        return coordinateView.convert(windowPoint, from: nil)
    }
}

/// The display link's target, which it keeps: the menu itself stays free.
private final class TabQuickSwitchScrollTarget: NSObject {
    private let onStep: (CADisplayLink) -> Void

    init(onStep: @escaping (CADisplayLink) -> Void) {
        self.onStep = onStep
    }

    @objc func step(_ link: CADisplayLink) {
        onStep(link)
    }
}

/// Spans the overlay, so window points reach its space.
struct TabQuickSwitchCoordinateSpace: UIViewRepresentable {
    let menu: TabQuickSwitchMenu

    func makeUIView(context: Context) -> TabQuickSwitchCoordinateView {
        let view = TabQuickSwitchCoordinateView(menu: menu)
        menu.coordinateView = view
        return view
    }

    func updateUIView(_ view: TabQuickSwitchCoordinateView, context: Context) {
        if view.menu !== menu {
            if let previous = view.menu, previous.coordinateView === view {
                previous.coordinateView = nil
            }
            view.menu = menu
        }
        if menu.coordinateView !== view { menu.coordinateView = view }
    }

    static func dismantleUIView(_ view: TabQuickSwitchCoordinateView, coordinator: ()) {
        // A late dismantle from an outgoing overlay must leave its successor.
        if let menu = view.menu, menu.coordinateView === view {
            menu.coordinateView = nil
        }
        view.menu = nil
    }
}

/// Cancels a touch if its overlay leaves or changes windows while the bar
/// itself remains mounted. Geometry from that window cannot be reused.
final class TabQuickSwitchCoordinateView: UIView {
    weak var menu: TabQuickSwitchMenu?
    private var windowIdentity: ObjectIdentifier?

    init(menu: TabQuickSwitchMenu) {
        self.menu = menu
        super.init(frame: .zero)
        isOpaque = false
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let nextWindow = window.map { ObjectIdentifier($0) }
        defer { windowIdentity = nextWindow }
        guard nextWindow != windowIdentity, let menu, menu.coordinateView === self else { return }
        menu.cancel()
    }
}
