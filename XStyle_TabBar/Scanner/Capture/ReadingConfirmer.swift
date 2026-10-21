import BarcodeDecoding

/// Decides when a reading is trustworthy enough to show. A checksum alone
/// lets one random error in ten through, so a code must be read on several
/// independent scanlines in one frame, or in two frames in a row. EAN-8 and
/// UPC-E are short and easier to fake, so they need more. A code can be held
/// back: the one a result shows, for as long as it shows, and one just closed
/// until it has left the frame for a moment or a short while has passed, so
/// one left in front of the camera doesn't reopen at once.
nonisolated struct ReadingConfirmer {
    /// How long a held-back code stays held.
    nonisolated enum Hold: Equatable, Sendable {
        /// For as long as the confirmer isn't reset: the code a result shows.
        case indefinitely
        /// Until it has been out of view for `rearmDelay`, or `limit` seconds
        /// after the first frame since the reset.
        case untilGone(limit: Double)
    }

    /// Lines from the previous frame, by text.
    private var previousLines: [String: Int] = [:]
    private var previousTime = -Double.infinity
    private var suppressed: String?
    private var hold = Hold.indefinitely
    /// When the held-back code was last seen; nil until the first frame
    /// after the reset, so the wait never starts from a stale time.
    private var suppressedLastSeen: Double?
    /// The first frame's time since the reset, which `Hold.untilGone`'s limit
    /// counts from.
    private var suppressedSince: Double?

    /// The longest gap that still counts as consecutive frames.
    static let frameGap = 0.25
    /// How long a just-closed code must be out of view before it can return.
    static let rearmDelay = 0.6
    /// How long a just-closed code is held at most, even if it never leaves.
    static let closedCodeHoldLimit = 1.0

    /// - Parameter time: The frame's presentation time, in seconds.
    /// - Returns: The first reading in `readings` that's now confirmed.
    mutating func confirm(_ readings: [BarcodeReading], at time: Double) -> BarcodeReading? {
        defer {
            previousLines = Dictionary(readings.map { ($0.text, $0.lineCount) }, uniquingKeysWith: max)
            previousTime = time
        }
        if let suppressed, case .untilGone(let limit) = hold {
            let since = suppressedSince ?? time
            suppressedSince = since
            if readings.contains(where: { $0.text == suppressed }) || suppressedLastSeen == nil {
                suppressedLastSeen = time
            }
            if let lastSeen = suppressedLastSeen, time - lastSeen >= Self.rearmDelay || time - since >= limit {
                self.suppressed = nil
            }
        }
        let isConsecutive = time - previousTime <= Self.frameGap
        return readings.first { reading in
            guard reading.text != suppressed else { return false }
            let isShort = reading.format != .ean13
            if reading.lineCount >= (isShort ? 3 : 2) { return true }
            guard isConsecutive, let previous = previousLines[reading.text] else { return false }
            return min(previous, reading.lineCount) >= (isShort ? 2 : 1)
        }
    }

    /// Starts afresh, holding `text` (the decoder's form) back as `hold` says.
    mutating func reset(suppressing text: String?, hold: Hold = .untilGone(limit: .infinity)) {
        previousLines = [:]
        previousTime = -.infinity
        suppressed = text
        self.hold = hold
        suppressedLastSeen = nil
        suppressedSince = nil
    }
}
