import SwiftUI

/// Paging state is read only by the Home surfaces that draw it, keeping
/// per-frame geometry changes out of the root navigation stack.
@Observable
final class PagerState {
    private(set) var progress: CGFloat = 0
    /// Last settled page, also used for vertical scroll and accessibility.
    private(set) var selectedTab: AppTab = .bookmarks
    /// Remains fixed during a drag and changes when native paging commits.
    private(set) var highlightedTab: AppTab = .bookmarks
    private(set) var tapTransition: TabTransition?
    /// The full scroll viewport, including the area under a lateral tab rail.
    private(set) var viewportWidth: CGFloat = 0
    /// Captured by the target observer; interruption invalidates older reports.
    private(set) var gestureID: UInt64 = 0
    private(set) var hapticTick = 0
    var scrollPosition = ScrollPosition(idType: AppTab.self)

    @ObservationIgnored private(set) var geometry = PagerGeometry()
    @ObservationIgnored private(set) var phase: ScrollPhase = .idle
    @ObservationIgnored private(set) var pendingTab: AppTab?
    @ObservationIgnored private var pendingTarget: PagerTarget?
    @ObservationIgnored private var resizeDestination: AppTab?
    @ObservationIgnored private var hapticPage = 0
    @ObservationIgnored private var reduceMotion = false

    var isAtFirstPage: Bool {
        geometry.width > 0 && geometry.offset <= 0.5
    }

    var isAtRest: Bool {
        phase == .idle && tapTransition == nil && pendingTab == nil && resizeDestination == nil
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
    }

    /// Later chip taps replace a choice waiting for an active scroll to finish.
    func select(_ tab: AppTab) {
        pendingTab = tab
        startPendingTransition()
    }

    func receive(_ target: PagerTarget) {
        guard target.gestureID == gestureID, tapTransition == nil,
              resizeDestination == nil, target.width.isFinite,
              abs(target.width - viewportWidth) < 0.5,
              AppTab.allCases.indices.contains(target.index),
              phase == .tracking || phase == .interacting || phase == .decelerating else { return }
        pendingTarget = target
        if phase == .decelerating {
            highlight(AppTab.allCases[target.index])
        }
    }

    func scrollPhaseDidChange(from oldPhase: ScrollPhase, to newPhase: ScrollPhase, geometry: PagerGeometry) {
        if (newPhase == .tracking && oldPhase != .interacting)
            || (newPhase == .interacting && oldPhase != .tracking) {
            invalidateTarget()
        }
        phase = newPhase
        if newPhase == .decelerating, let target = pendingTarget {
            highlight(AppTab.allCases[target.index])
        }
        if newPhase == .idle {
            invalidateTarget()
        }
        update(geometry, didFinishScrolling: oldPhase != .idle && newPhase == .idle)
    }

    func update(_ newGeometry: PagerGeometry, didFinishScrolling: Bool = false) {
        guard newGeometry.width.isFinite, newGeometry.width > 0,
              newGeometry.offset.isFinite else { return }
        let widthChanged = viewportWidth != newGeometry.width
        let wasLaidOut = viewportWidth > 0
        geometry = newGeometry
        if widthChanged {
            viewportWidth = newGeometry.width
            invalidateTarget()
            if wasLaidOut {
                let destination = tapTransition?.destination
                    ?? (phase == .decelerating ? highlightedTab : selectedTab)
                resizeDestination = destination
                snap(to: destination)
            }
        }
        progress = newGeometry.progress

        if let destination = resizeDestination {
            guard isAligned(with: destination) else {
                if didFinishScrolling { snap(to: destination) }
                return
            }
            resizeDestination = nil
        }
        updateHapticPage()

        if let transition = tapTransition {
            if isAligned(with: transition.destination) && phase == .idle {
                withoutAnimation {
                    selectedTab = transition.destination
                    highlightedTab = transition.destination
                    tapTransition = nil
                }
                startPendingTransition()
            } else if didFinishScrolling {
                snap(to: transition.destination)
            }
        } else if phase == .idle {
            let tab = AppTab.allCases[newGeometry.nearestPageIndex(pageCount: AppTab.allCases.count)]
            selectedTab = tab
            highlight(tab)
            startPendingTransition()
        }
    }

    private func invalidateTarget() {
        gestureID &+= 1
        pendingTarget = nil
    }

    private func isAligned(with tab: AppTab) -> Bool {
        abs(geometry.offset - CGFloat(tab.index) * geometry.width) < 0.5
    }

    private func snap(to tab: AppTab) {
        withoutAnimation {
            scrollPosition.scrollTo(id: tab, anchor: .leading)
        }
    }

    private func highlight(_ tab: AppTab) {
        guard highlightedTab != tab else { return }
        if reduceMotion {
            withoutAnimation { highlightedTab = tab }
        } else {
            withAnimation(TopMenuMetrics.selectionAnimation) { highlightedTab = tab }
        }
    }

    private func startPendingTransition() {
        guard phase == .idle, tapTransition == nil, resizeDestination == nil,
              viewportWidth > 0, let destination = pendingTab else { return }
        pendingTab = nil
        guard destination != selectedTab else { return }
        invalidateTarget()
        withoutAnimation {
            tapTransition = TabTransition(source: selectedTab, destination: destination)
        }
        highlight(destination)
        if reduceMotion {
            snap(to: destination)
        } else {
            withAnimation(.smooth(duration: 0.45, extraBounce: 0)) {
                scrollPosition.scrollTo(id: destination, anchor: .leading)
            }
        }
    }

    /// Preserve the existing single midpoint tick for a compressed distant jump.
    private func updateHapticPage() {
        let page: Int
        if let transition = tapTransition {
            let source = transition.source.index
            let destination = transition.destination.index
            page = abs(progress - CGFloat(source)) <= abs(progress - CGFloat(destination)) ? source : destination
        } else {
            page = geometry.nearestPageIndex(pageCount: AppTab.allCases.count)
        }
        guard page != hapticPage else { return }
        if tapTransition != nil || phase == .interacting || phase == .decelerating {
            hapticTick += 1
        }
        hapticPage = page
    }
}
