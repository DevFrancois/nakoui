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
    private(set) var isButtonRevealed: Bool {
        didSet {
            defaults.set(isButtonRevealed, forKey: Key.isButtonRevealed)
        }
    }
    /// Counts the scans recorded since launch, so the button can show each
    /// one being added. Not saved.
    private(set) var recordCount = 0

    /// The most entries kept: the oldest go first.
    static let capacity = 100

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Key.entries)
            .flatMap { try? JSONDecoder().decode([ScanHistoryEntry].self, from: $0) } ?? []
        let hasScanned = Self.bool(Key.hasScanned, in: defaults) ?? false
        self.hasScanned = hasScanned
        isButtonRevealed = Self.bool(Key.isButtonRevealed, in: defaults) ?? false
        // No result is open at launch, so a scan from an earlier run counts
        // as dismissed.
        if hasScanned {
            revealButton()
        }
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

    private func save(_ entries: [ScanHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Key.entries)
    }

    /// `bool(forKey:)` also reads `-key YES` launch arguments, which arrive as strings.
    private static func bool(_ key: String, in defaults: UserDefaults) -> Bool? {
        defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
    }

    private enum Key {
        static let entries = "scanHistory.entries"
        static let hasScanned = "scanHistory.hasScanned"
        static let isButtonRevealed = "scanHistory.isButtonRevealed"
    }
}
