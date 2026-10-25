import SwiftUI
import UIKit

/// A held tab's menu of pages, pets or views to switch to. The tab bar owns
/// the finger and drives the menu; `TabQuickSwitchOverlay` draws the halo and
/// the items, and reports where the items are. Frames and points here are in
/// the overlay's space: `coordinateView` takes window points into it.
@Observable
final class TabQuickSwitchMenu {
    struct Presentation: Equatable {
        let tab: RootTab
        let items: [TabQuickSwitchItem]
        /// Where the held tab and the whole bar rest, without the press zoom.
        let tabFrame: CGRect
        let barFrame: CGRect
        let axis: Axis
    }

    /// The open menu; nil while none is.
    private(set) var presentation: Presentation?
    /// The item under the finger.
    private(set) var highlighted: TabQuickSwitchDestination?
    /// How far a list too tall for its room has scrolled, and can.
    private(set) var listOffset: CGFloat = 0
    private(set) var listOffsetLimit: CGFloat = 0

    @ObservationIgnored weak var coordinateView: UIView?
    /// Called as the finger reaches an item it wasn't on, for a haptic.
    @ObservationIgnored var onReachItem: (() -> Void)?
    @ObservationIgnored private var tracking = TabQuickSwitchTracking()
    @ObservationIgnored private var listScroll: TabQuickSwitchListScroll?
    @ObservationIgnored private var scrollLink: CADisplayLink?
    @ObservationIgnored private var lastScrollTime: CFTimeInterval?
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

    /// Opens `tab`'s menu. The frames are in window space.
    func open(tab: RootTab, items: [TabQuickSwitchItem], tabFrame: CGRect, barFrame: CGRect,
              axis: NSLayoutConstraint.Axis) {
        guard let coordinateView, coordinateView.window != nil else { return }
        close()
        let presentation = Presentation(
            tab: tab, items: items,
            tabFrame: coordinateView.convert(tabFrame, from: nil),
            barFrame: coordinateView.convert(barFrame, from: nil),
            axis: axis == .vertical ? .vertical : .horizontal
        )
        // Lifting on the bar, the held tab included, picks nothing.
        tracking = TabQuickSwitchTracking(excluding: presentation.barFrame)
        self.presentation = presentation
    }

    /// From the overlay as it lays an item out: a bubble in the overlay's
    /// space, a list row in its list's; see `setListViewport`.
    func setFrame(_ frame: CGRect?, for destination: TabQuickSwitchDestination) {
        guard presentation != nil else { return }
        tracking.setFrame(frame, for: destination)
        updateHighlight()
    }

    /// From a list as it lays out: its visible card, in the overlay's space,
    /// and its rows' whole height. Rows outside the card can't be picked.
    func setListViewport(_ viewport: CGRect, contentHeight: CGFloat) {
        guard presentation != nil else { return }
        var scroll = listScroll ?? TabQuickSwitchListScroll(viewport: viewport, contentHeight: contentHeight)
        scroll.update(viewport: viewport, contentHeight: contentHeight)
        listScroll = scroll
        applyListScroll()
        updateScrolling()
    }

    /// Follows the finger, in window space.
    func move(to windowPoint: CGPoint) {
        guard presentation != nil, let point = convert(windowPoint) else { return }
        tracking.move(to: point)
        updateHighlight()
        updateScrolling()
    }

    /// Closes the menu, returning the item the finger lifted on, if any.
    func release(at windowPoint: CGPoint) -> TabQuickSwitchItem? {
        guard let presentation else { return nil }
        let destination = convert(windowPoint).flatMap { tracking.release(at: $0) }
        close()
        return presentation.items.first { $0.destination == destination }
    }

    func cancel() {
        guard presentation != nil else { return }
        close()
    }

    private func close() {
        stopScrolling()
        tracking = TabQuickSwitchTracking()
        listScroll = nil
        listOffset = 0
        listOffsetLimit = 0
        if highlighted != nil {
            highlighted = nil
            focusHandler(nil)
        }
        presentation = nil
    }

    private func updateHighlight() {
        let previous = highlighted
        highlighted = tracking.highlighted
        guard highlighted != previous else { return }
        if highlighted != nil { onReachItem?() }
        focusHandler(highlighted)
    }

    /// Moves the list's rows, and what the finger can reach, to its offset.
    private func applyListScroll() {
        guard let listScroll else { return }
        listOffset = listScroll.offset
        listOffsetLimit = listScroll.maximumOffset
        let viewport = listScroll.viewport
        tracking.setViewport(origin: CGPoint(x: viewport.minX, y: viewport.minY - listScroll.offset), clip: viewport)
        updateHighlight()
    }

    private var scrollVelocity: CGFloat {
        guard presentation != nil, let listScroll, let point = tracking.point else { return 0 }
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
        let velocity = scrollVelocity
        guard velocity != 0, var scroll = listScroll else {
            stopScrolling()
            return
        }
        // The first frame only starts the clock. A late frame moves no
        // further than a slow one would.
        defer { lastScrollTime = link.timestamp }
        guard let lastScrollTime else { return }
        let elapsed = min(link.timestamp - lastScrollTime, 1.0 / 15)
        guard scroll.scroll(by: velocity * elapsed) else {
            stopScrolling()
            return
        }
        listScroll = scroll
        applyListScroll()
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

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        menu.coordinateView = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        if menu.coordinateView !== view { menu.coordinateView = view }
    }
}
