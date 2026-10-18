import Foundation

/// Main-thread bookkeeping only: submission is not proof of presentation.
/// Tickets prevent a late failure from clearing a newer in-flight submission.
nonisolated struct TabBarPresentationState {
    struct Ticket: Equatable, Sendable {
        let generation: UInt64
        let id: UInt64
        let revision: UInt64
        let submittedAt: TimeInterval
    }

    private var generation: UInt64 = 0
    private var nextID: UInt64 = 0
    private var latest: Ticket?
    private(set) var presentedRevision: UInt64 = 0
    static let acknowledgementTimeout: TimeInterval = 0.25

    func needsEncoding(_ revision: UInt64) -> Bool {
        revision > presentedRevision && latest?.revision != revision
    }

    mutating func submit(_ revision: UInt64, at time: TimeInterval) -> Ticket {
        nextID &+= 1
        let ticket = Ticket(generation: generation, id: nextID,
                            revision: revision, submittedAt: time)
        latest = ticket
        return ticket
    }

    /// Returns true only when the latest unshown revision becomes retryable.
    @discardableResult
    mutating func resolve(_ ticket: Ticket, presented: Bool) -> Bool {
        guard ticket.generation == generation else { return false }
        if presented { presentedRevision = max(presentedRevision, ticket.revision) }
        guard latest?.id == ticket.id else { return false }
        latest = nil
        return !presented && ticket.revision > presentedRevision
    }

    /// A discarded drawable need not produce an acknowledgement. Retry without
    /// retaining its drawable or creating one timer/allocation per frame.
    mutating func retryUnacknowledged(at time: TimeInterval) -> Ticket? {
        guard let ticket = latest, ticket.revision > presentedRevision,
              time - ticket.submittedAt >= Self.acknowledgementTimeout else { return nil }
        latest = nil
        return ticket
    }

    mutating func invalidate() {
        generation &+= 1
        latest = nil
        presentedRevision = 0
    }
}
