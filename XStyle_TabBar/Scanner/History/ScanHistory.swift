import SwiftUI
import Observation

/// The products the user scanned, newest first, kept across launches. It
/// also remembers the first scan, after which the aiming hint never shows
/// again, and the first dismissal, which reveals the history button.
@Observable
final class ScanHistory {
    /// Newest first: a code scanned again moves back to the top.
    private(set) var entries: [ScanHistoryEntry] {
        didSet {
            save(entries)
        }
    }
    /// Whether any code was ever scanned. Clearing the history keeps it.
    private(set) var hasScanned: Bool {
        didSet {
            defaults.set(hasScanned, forKey: Key.hasScanned)
        }
    }
    /// Whether the history button shows, from the first dismissed result on.
    /// Not saved: no result is open at launch, so a scan from an earlier run
    /// counts as dismissed.
    private(set) var isButtonRevealed: Bool
    /// Counts the scans recorded since launch, so the button can show each
    /// one being added. Not saved.
    private(set) var recordCount = 0
    /// Whether the history button's tip is to show, kept by the app from
    /// TipKit, so the button has it from its first frame. Not saved.
    var isTipEligible = false

    /// The most entries kept: the oldest go first.
    static let capacity = 100

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Key.entries).map(Self.decodeEntries) ?? []
        let hasScanned = defaults.optionalBool(forKey: Key.hasScanned) ?? false
        self.hasScanned = hasScanned
        isButtonRevealed = hasScanned
    }

    /// Adds a successful scan: a new product goes on top, a known one moves
    /// back to the top, counting the scan.
    func record(_ code: ScannedCode, at date: Date = .now) {
        var updated = entries
        if let index = updated.firstIndex(where: { $0.matches(code) }) {
            var entry = updated.remove(at: index)
            entry.lastScanned = date
            entry.count += 1
            updated.insert(entry, at: 0)
        } else {
            updated.insert(ScanHistoryEntry(code: code, at: date), at: 0)
            if updated.count > Self.capacity {
                updated.removeLast(updated.count - Self.capacity)
            }
        }
        entries = updated
        hasScanned = true
        recordCount &+= 1
    }

    /// Shows the history button, once a scanned code's result has closed.
    func revealButton() {
        guard hasScanned, !isButtonRevealed else { return }
        isButtonRevealed = true
    }

    func delete(atOffsets offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    /// Empties the history. The button stays, and the hint stays away.
    func clear() {
        entries = []
    }

    /// Forgets everything, as on a first launch: the hint comes back, and the
    /// button only once the next result closes.
    func reset() {
        entries = []
        hasScanned = false
        isButtonRevealed = false
    }

    /// One by one, so an entry this build can't read, as from a newer one,
    /// costs only itself.
    private nonisolated static func decodeEntries(from data: Data) -> [ScanHistoryEntry] {
        let decoded = try? JSONDecoder().decode([LossyEntry].self, from: data)
        return decoded?.compactMap(\.entry) ?? []
    }

    private func save(_ entries: [ScanHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Key.entries)
    }

    private enum Key {
        static let entries = "scanHistory.entries"
        static let hasScanned = "scanHistory.hasScanned"
    }
}

/// A saved entry, or nil where it can't be read.
private nonisolated struct LossyEntry: Decodable {
    let entry: ScanHistoryEntry?

    init(from decoder: any Decoder) throws {
        entry = try? ScanHistoryEntry(from: decoder)
    }
}
