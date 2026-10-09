import SwiftUI

/// How far the logo row has slid away. It follows the selected page's scroll
/// point for point, as X's header does: content moving up pushes the row out,
/// content moving down brings it back, and when scrolling stops it settles
/// fully in or out.
///
/// Only user scrolling moves it, as in Apple's `onScrollPhaseChange` example:
/// geometry changes while idle, or during programmatic scrolls, leave it be,
/// except that a scroll back to the top always brings it back.
/// The collapse is drawn with transforms and never changes the menu's size,
/// so it can't move the pages it follows. It lives in its own observable
/// object so per-frame changes redraw the menu alone.
@Observable
final class LogoCollapse {
    /// 0 when the row is shown, up to `TopMenuMetrics.logoRowHeight` when hidden.
    private(set) var distance: CGFloat
    /// Whether the user is scrolling the selected page. No view reads it.
    @ObservationIgnored private var isFollowing = false
    /// Each page's last offset, to settle sensibly when the selection moves.
    @ObservationIgnored private var pageOffsets: [AnyHashable: CGFloat] = [:]

    init(distance: CGFloat = 0) {
        self.distance = distance
    }

    /// 0 when shown, 1 when hidden.
    var progress: CGFloat {
        distance / TopMenuMetrics.logoRowHeight
    }

    var isShown: Bool {
        progress < 0.5
    }

    /// Remembers where a page is, selected or not.
    func record(_ position: PageScrollPosition, for page: AnyHashable) {
        pageOffsets[page] = position.offset
    }

    /// Settles for the newly selected page: never left half-way, and fully
    /// back if that page is near its top, where a hidden row would leave a gap.
    func selectedPageDidChange(to page: AnyHashable) {
        isFollowing = false
        let offset = pageOffsets[page] ?? 0
        animate(to: isShown || offset < TopMenuMetrics.logoRowHeight ? 0 : TopMenuMetrics.logoRowHeight)
    }

    /// Follows the selected page from `old` to `new` while the user scrolls it.
    func follow(from old: PageScrollPosition, to new: PageScrollPosition) {
        guard isFollowing else {
            // Other scrolls, such as a tap on the status bar, leave the row
            // alone until they near the top, where it comes back with them.
            if distance > new.offset {
                distance = new.offset
            }
            return
        }
        let moved = distance + new.offset - old.offset
        // Near the top, the row can't be more hidden than the content has
        // scrolled, so it's always fully back at the top.
        distance = min(max(moved, 0), TopMenuMetrics.logoRowHeight, new.offset)
    }

    /// Tracks the selected page's scroll phase, and finishes a half-way
    /// collapse, whichever way is nearer, once the page comes to rest.
    func scrollPhaseDidChange(to phase: ScrollPhase) {
        isFollowing = phase == .interacting || phase == .decelerating
        if phase == .idle {
            animate(to: isShown ? 0 : TopMenuMetrics.logoRowHeight)
        }
    }

    func hide() {
        animate(to: TopMenuMetrics.logoRowHeight)
    }

    func reveal() {
        animate(to: 0)
    }

    private func animate(to target: CGFloat) {
        guard distance != target else { return }
        withAnimation(TopMenuMetrics.logoSettleAnimation) {
            distance = target
        }
    }
}
