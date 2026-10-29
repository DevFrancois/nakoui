import CoreGraphics
import Foundation

/// A single visible card advances through explicit stages. A generation
/// identifies each request, so interrupted animation completions do nothing.
struct TabQuickSwitchListTransition: Equatable {
    enum Stage: Equatable {
        case hidden, entrance, visible, moveFadeOut, moving, moveFadeIn, sequentialFadeOut, sequentialFadeIn, closing
    }

    private(set) var generation: UInt64 = 0
    private(set) var requestedID: UInt64?
    private(set) var displayedID: UInt64?
    private(set) var stage: Stage = .hidden

    var permitsVisibleRows: Bool {
        requestedID != nil && requestedID == displayedID
            && [.entrance, .visible, .moveFadeIn, .sequentialFadeIn].contains(stage)
    }

    func acceptsRows(presentationID: UInt64, contentOpacity: Float, hasPresentationLayer: Bool) -> Bool {
        permitsVisibleRows && requestedID == presentationID && contentOpacity > 0.01
            && (stage == .visible || hasPresentationLayer)
    }

    /// Returns false for duplicate updates of a running request.
    @discardableResult
    mutating func request(_ id: UInt64?, style: TabQuickSwitchListSwitchStyle) -> Bool {
        guard id != requestedID else { return false }
        let reopening = requestedID == nil
        generation &+= 1
        requestedID = id
        guard let id else {
            stage = displayedID == nil ? .hidden : .closing
            return true
        }
        guard displayedID != nil, stage != .hidden, !reopening else {
            displayedID = id
            stage = .entrance
            return true
        }
        switch style {
        case .immediate:
            displayedID = id
            stage = .visible
        case .movingCard:
            if stage == .moving {
                // Content is already hidden. Retarget from the displayed pose.
                displayedID = id
            } else {
                stage = .moveFadeOut
            }
        case .sequentialFade:
            stage = .sequentialFadeOut
        }
        return true
    }

    @discardableResult
    mutating func complete(generation completedGeneration: UInt64) -> Bool {
        guard generation == completedGeneration else { return false }
        switch stage {
        case .entrance, .moveFadeIn, .sequentialFadeIn:
            stage = .visible
        case .moveFadeOut:
            displayedID = requestedID
            stage = .moving
        case .moving:
            stage = .moveFadeIn
        case .sequentialFadeOut:
            displayedID = requestedID
            stage = .sequentialFadeIn
        case .closing:
            displayedID = nil
            stage = .hidden
        case .hidden, .visible:
            return false
        }
        return true
    }
}

/// Final, untransformed geometry shared by rendering, focus and row hits.
struct TabQuickSwitchListSnapshot: Equatable {
    struct Row: Equatable {
        let destination: TabQuickSwitchDestination
        let frame: CGRect
    }

    let presentationID: UInt64
    let cardFrame: CGRect
    let rows: [Row]
    let contentHeight: CGFloat

    static func maximumCardWidth(area: CGRect, bar: CGRect, vertical: Bool) -> CGFloat {
        guard vertical else { return area.width }
        let inward = bar.midX < area.midX
            ? area.maxX - bar.maxX - TabQuickSwitchMetrics.spacing
            : bar.minX - TabQuickSwitchMetrics.spacing - area.minX
        return max(1, min(area.width, inward))
    }

    static func entranceAnchor(tab: CGRect, card: CGRect, bar: CGRect, vertical: Bool) -> CGPoint {
        if vertical {
            return CGPoint(x: card.midX > bar.midX ? 0 : 1,
                           y: min(max((tab.midY - card.minY) / max(1, card.height), 0), 1))
        }
        return CGPoint(x: min(max((tab.midX - card.minX) / max(1, card.width), 0), 1), y: 1)
    }

    func destination(at localPoint: CGPoint, scrollOffset: CGFloat) -> TabQuickSwitchDestination? {
        let viewport = CGRect(origin: .zero, size: cardFrame.size)
        guard Self.contains(localPoint, in: viewport, radius: TabQuickSwitchMetrics.listCornerRadius) else { return nil }
        let contentPoint = CGPoint(x: localPoint.x, y: localPoint.y + scrollOffset)
        return rows.first { $0.frame.contains(contentPoint) }?.destination
    }

    /// Rounded-card clipping matters at the top and bottom corner pixels.
    static func contains(_ point: CGPoint, in rect: CGRect, radius: CGFloat) -> Bool {
        guard rect.contains(point) else { return false }
        let radius = min(radius, rect.width / 2, rect.height / 2)
        let nearest = CGPoint(x: min(max(point.x, rect.minX + radius), rect.maxX - radius),
                              y: min(max(point.y, rect.minY + radius), rect.maxY - radius))
        return hypot(point.x - nearest.x, point.y - nearest.y) <= radius
    }
}

/// Reused native layers can still describe an outgoing menu until the next
/// rendered frame. Two distinct display ticks fence each installed generation.
struct TabQuickSwitchListDisplayFence {
    private(set) var presentationID: UInt64?
    private var firstTick: TimeInterval?
    private(set) var hasDisplayedFrame = false

    mutating func install(_ id: UInt64) {
        presentationID = id
        firstTick = nil
        hasDisplayedFrame = false
    }

    mutating func tick(at timestamp: TimeInterval, presentationID id: UInt64) {
        guard id == presentationID else { return }
        if let firstTick {
            hasDisplayedFrame = timestamp > firstTick
        } else {
            firstTick = timestamp
        }
    }

    func permits(_ id: UInt64) -> Bool { presentationID == id && hasDisplayedFrame }
}
