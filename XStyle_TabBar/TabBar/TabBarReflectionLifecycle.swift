import Foundation
import CoreGraphics

/// Native root appearance and path updates arrive independently. Neither alone
/// is enough to admit a window capture during an interactive navigation return.
nonisolated struct TabBarRootReflectionLifecycle {
    enum Phase: Equatable { case covered, returning, appeared }
    private(set) var phase: Phase = .covered
    private(set) var generation: UInt64 = 0
    private(set) var pathIsEmpty = true

    var canRestore: Bool { phase != .covered }
    var canCapture: Bool { phase == .appeared && pathIsEmpty }

    mutating func setPathIsEmpty(_ value: Bool) { pathIsEmpty = value }

    @discardableResult
    mutating func willAppear() -> UInt64 {
        generation &+= 1
        phase = .returning
        return generation
    }

    mutating func didAppear(generation token: UInt64) {
        guard token == generation, phase == .returning else { return }
        phase = .appeared
    }

    @discardableResult
    mutating func suspend() -> UInt64 {
        generation &+= 1
        phase = .covered
        return generation
    }

    mutating func cancelReturn(generation token: UInt64) {
        guard token == generation else { return }
        suspend()
    }
}

/// Compare stable root-local layout, never the animated window-space origin.
/// A hard invalidation while detached overrides an otherwise matching window.
nonisolated struct TabBarReflectionCompatibility: Equatable {
    var context: UInt64
    var capsule: CGRect
    var viewport: CGRect
    var windowBounds: CGRect
    var scale: CGFloat
    var appearance: Int
    var reduceTransparency: Bool

    func permitsResume(_ current: Self, sameWindow: Bool, invalidated: Bool) -> Bool {
        sameWindow && !invalidated && self == current
    }
}

/// Each source keeps its original sampling origin through cancelled returns.
/// Re-suspending must not re-anchor an old texture to an intermediate position.
nonisolated struct TabBarReflectionAnchors {
    private(set) var ui: CGPoint?
    private(set) var scene: CGPoint?

    mutating func suspend(at origin: CGPoint, hasUI: Bool, hasScene: Bool) {
        if hasUI, ui == nil { ui = origin }
        if hasScene, scene == nil { scene = origin }
    }

    mutating func replaceUI() { ui = nil }
    mutating func replaceScene() { scene = nil }

    func uiOffset(at origin: CGPoint) -> CGPoint { offset(origin, from: ui) }
    func sceneOffset(at origin: CGPoint) -> CGPoint { offset(origin, from: scene) }

    private func offset(_ origin: CGPoint, from anchor: CGPoint?) -> CGPoint {
        guard let anchor else { return .zero }
        return CGPoint(x: origin.x - anchor.x, y: origin.y - anchor.y)
    }
}
