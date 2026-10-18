import Foundation

/// A single cold-start ramp for both sources. Capturing content only arms it;
/// acquiring a drawable or waiting for the GPU never consumes the ramp.
nonisolated struct TabBarReflectionPresence {
    enum State: Equatable {
        case waitingForContent
        case readyToStart
        case fading(start: TimeInterval)
        case complete
    }

    static let duration: TimeInterval = 0.2
    private(set) var state: State = .waitingForContent

    mutating func reset() { state = .waitingForContent }

    mutating func noteContent() {
        if state == .waitingForContent { state = .readyToStart }
    }

    func value(at time: TimeInterval, reduceMotion: Bool = false) -> Double {
        switch state {
        case .waitingForContent: return 0
        case .readyToStart: return reduceMotion ? 1 : 0
        case .complete: return 1
        case .fading(let start):
            guard !reduceMotion else { return 1 }
            guard time.isFinite else { return 0 }
            let progress = min(1, max(0, (time - start) / Self.duration))
            return progress * progress * (3 - 2 * progress)
        }
    }

    /// Includes the exact final 1.0 frame until it is successfully submitted.
    /// Presentation failure of that submission is retried by the ticket state.
    var needsSubmission: Bool {
        switch state {
        case .readyToStart, .fading: true
        case .waitingForContent, .complete: false
        }
    }

    mutating func didSubmit(at time: TimeInterval, reduceMotion: Bool = false) {
        guard time.isFinite else { return }
        switch state {
        case .readyToStart:
            state = reduceMotion ? .complete : .fading(start: time)
        case .fading:
            if value(at: time, reduceMotion: reduceMotion) == 1 { state = .complete }
        case .waitingForContent, .complete:
            break
        }
    }
}
