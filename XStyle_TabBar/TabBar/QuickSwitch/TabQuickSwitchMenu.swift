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

    @ObservationIgnored weak var coordinateView: UIView?
    @ObservationIgnored private var tracking = TabQuickSwitchTracking()
    @ObservationIgnored private let catalog: (RootTab) -> [TabQuickSwitchItem]
    @ObservationIgnored private let destinationHandler: (TabQuickSwitchDestination, Bool) -> Void

    /// - Parameters:
    ///   - items: What holding a tab offers, read as each hold opens.
    ///   - apply: Takes a tab to a destination; see `apply(_:isTabShown:)`.
    init(
        items: @escaping (RootTab) -> [TabQuickSwitchItem] = { _ in [] },
        apply: @escaping (_ destination: TabQuickSwitchDestination, _ isTabShown: Bool) -> Void = { _, _ in }
    ) {
        catalog = items
        destinationHandler = apply
    }

    /// What holding `tab` would offer: nil for fewer than two items, which
    /// leaves the hold to preview tabs as usual.
    func items(for tab: RootTab) -> [TabQuickSwitchItem]? {
        let items = catalog(tab)
        return items.count > 1 ? items : nil
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
        tracking = TabQuickSwitchTracking()
        highlighted = nil
        presentation = Presentation(
            tab: tab, items: items,
            tabFrame: coordinateView.convert(tabFrame, from: nil),
            barFrame: coordinateView.convert(barFrame, from: nil),
            axis: axis == .vertical ? .vertical : .horizontal
        )
    }

    /// From the overlay as it lays an item out, in its own space.
    func setFrame(_ frame: CGRect?, for destination: TabQuickSwitchDestination) {
        guard presentation != nil else { return }
        tracking.setFrame(frame, for: destination)
        highlighted = tracking.highlighted
    }

    /// Follows the finger, in window space. Returns whether it reached an
    /// item it wasn't on.
    @discardableResult
    func move(to windowPoint: CGPoint) -> Bool {
        guard presentation != nil, let point = convert(windowPoint) else { return false }
        let previous = highlighted
        tracking.move(to: point)
        highlighted = tracking.highlighted
        return highlighted != nil && highlighted != previous
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
        tracking = TabQuickSwitchTracking()
        highlighted = nil
        presentation = nil
    }

    private func convert(_ windowPoint: CGPoint) -> CGPoint? {
        guard let coordinateView, coordinateView.window != nil else { return nil }
        return coordinateView.convert(windowPoint, from: nil)
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
