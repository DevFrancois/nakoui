import Foundation

/// When a hold may open its tab's menu, apart from the timer that asks: the
/// deadline is given a time, so tests needn't wait. Each hold counts as a new
/// generation, and only the latest's timer can open a menu, never a stale one
/// from a cancelled or earlier touch.
struct TabQuickSwitchHold: Equatable {
    struct Pending: Equatable {
        let deadline: TimeInterval
        let generation: UInt64
    }

    private(set) var pending: Pending?
    private var generation: UInt64 = 0

    /// Starts a hold at `time`, replacing any other; returns its generation,
    /// for its timer to hand back.
    mutating func begin(at time: TimeInterval, duration: TimeInterval) -> UInt64 {
        generation &+= 1
        pending = Pending(deadline: time + duration, generation: generation)
        return generation
    }

    /// Whether the timer for `generation` may open the menu at `time`: its
    /// hold is the latest, still waiting, and has lasted. Once only.
    mutating func fire(generation: UInt64, at time: TimeInterval) -> Bool {
        guard let pending, pending.generation == generation, time >= pending.deadline else { return false }
        self.pending = nil
        return true
    }

    mutating func cancel() {
        pending = nil
    }
}
