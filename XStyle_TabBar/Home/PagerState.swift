import SwiftUI

/// The Home pager: which page is shown, chip taps jumping to another page,
/// and the scroll in between. It changes on every frame of a swipe, so it
/// lives outside `ContentView`: only the views drawing the pager read it,
/// and the root view holding the navigation stack is never redrawn by it.
@Observable
final class PagerState {
    /// Fractional index of the page in view, including skipped pages during
    /// a tap transition.
    private(set) var progress: CGFloat = 0
    /// The page the pager last came to rest on.
    private(set) var selectedTab: AppTab = .bookmarks
    /// The chip tap being carried out, if any.
    private(set) var tapTransition: TabTransition?
    /// The tapped tab being reached. The chips show it at once and ignore the
    /// pager, so the skipped tabs never light up.
    private(set) var lockedTab: AppTab?
    /// Bumps each time the pager passes a page's midpoint.
    private(set) var hapticTick = 0
    var scrollPosition = ScrollPosition(idType: AppTab.self)

    // The rest drives the logic below and no view reads it.
    @ObservationIgnored private(set) var geometry = PagerGeometry()
    @ObservationIgnored private(set) var phase: ScrollPhase = .idle
    /// A tapped tab waiting for the pager to come to rest.
    @ObservationIgnored private(set) var pendingTab: AppTab?
    @ObservationIgnored private var hapticPage = 0

    /// Whether the first page sits fully in view.
    var isAtFirstPage: Bool {
        geometry.width > 0 && geometry.offset <= 0.5
    }

    /// Whether the pager is still, with no tap being carried out or waiting.
    var isAtRest: Bool {
        phase == .idle && tapTransition == nil && pendingTab == nil
    }

    /// Moves to `tab`, once the pager comes to rest if it's moving. A later
    /// tap replaces one still waiting.
    func select(_ tab: AppTab) {
        pendingTab = tab
        startPendingTransition()
    }

    func scrollPhaseDidChange(from oldPhase: ScrollPhase, to newPhase: ScrollPhase, geometry: PagerGeometry) {
        phase = newPhase
        update(geometry, didFinishScrolling: oldPhase != .idle && newPhase == .idle)
    }

    func update(_ newGeometry: PagerGeometry, didFinishScrolling: Bool = false) {
        let widthChanged = geometry.width != newGeometry.width
        geometry = newGeometry
        guard newGeometry.width > 0 else { return }

        if progress != newGeometry.progress {
            progress = newGeometry.progress
        }
        updateHapticPage()

        if let transition = tapTransition {
            let destinationIndex = transition.destination.index
            let reachedDestination = abs(newGeometry.offset - CGFloat(destinationIndex) * newGeometry.width) < 0.5

            if reachedDestination && phase == .idle {
                withoutAnimation {
                    selectedTab = transition.destination
                    tapTransition = nil
                    lockedTab = nil
                }
                startPendingTransition()
            } else if !reachedDestination && (widthChanged || didFinishScrolling) {
                // Keep other pages hidden until an interrupted/resized scroll reaches its target.
                withoutAnimation {
                    scrollPosition.scrollTo(id: transition.destination, anchor: .leading)
                }
            }
        } else if phase == .idle {
            let index = min(max(Int(newGeometry.progress.rounded()), 0), AppTab.allCases.count - 1)
            let tab = AppTab.allCases[index]
            if selectedTab != tab {
                selectedTab = tab
            }
            startPendingTransition()
        }
    }

    private func startPendingTransition() {
        // A tap during a swipe or another tap animation replaces the queued choice.
        guard phase == .idle, tapTransition == nil,
              geometry.width > 0, let destination = pendingTab else { return }

        pendingTab = nil
        guard destination != selectedTab else { return }

        withoutAnimation {
            tapTransition = TabTransition(source: selectedTab, destination: destination)
        }
        // A transaction of its own: the chip highlight fades straight to the
        // destination, which withoutAnimation would turn into a jump.
        withAnimation(TopMenuMetrics.selectionAnimation) {
            lockedTab = destination
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            scrollPosition.scrollTo(id: destination, anchor: .leading)
        }
    }

    /// One tick each time the pager passes a page's midpoint. A tap transition
    /// ticks once, at its compressed midpoint, not once per skipped page.
    private func updateHapticPage() {
        let page: Int
        if let transition = tapTransition {
            let source = transition.source.index
            let destination = transition.destination.index
            page = abs(progress - CGFloat(source)) <= abs(progress - CGFloat(destination)) ? source : destination
        } else {
            page = min(max(Int(progress.rounded()), 0), AppTab.allCases.count - 1)
        }
        guard page != hapticPage else { return }

        // Programmatic scrolls, such as the side menu's snap, move silently.
        if tapTransition != nil || phase == .interacting || phase == .decelerating {
            hapticTick += 1
        }
        hapticPage = page
    }
}
