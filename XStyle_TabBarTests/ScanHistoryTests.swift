import Foundation
import Testing
@testable import XStyle_TabBar

/// A class, so each test's preferences go away with it.
@MainActor
final class ScanHistoryTests {
    private let suiteName = "ScanHistoryTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let ean13 = ScannedCode(value: "4006381333931", symbology: .ean13)
    private let upcA = ScannedCode(value: "036000291452", symbology: .upcA)
    private let ean8 = ScannedCode(value: "96385074", symbology: .ean8)

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func id(of code: ScannedCode) -> String {
        "\(code.symbology.rawValue):\(code.value)"
    }

    @Test("A new code goes on top and marks the first scan, without revealing the button")
    func recordsNewCode() throws {
        let history = ScanHistory(defaults: defaults)
        #expect(!history.hasScanned)

        history.record(ean13, at: start)

        let entry = try #require(history.entries.first)
        #expect(history.entries.count == 1)
        #expect(entry.value == ean13.value)
        #expect(entry.symbology == .ean13)
        #expect(entry.firstScanned == start)
        #expect(entry.lastScanned == start)
        #expect(entry.count == 1)
        #expect(entry.matches(ean13))
        #expect(entry.makeCode().value == ean13.value && entry.makeCode().symbology == .ean13)
        #expect(history.hasScanned)
        #expect(history.recordCount == 1)
        #expect(!history.isButtonRevealed)
    }

    @Test("Scanning a known code again moves it back to the top and counts it")
    func rescanMovesToTop() throws {
        let history = ScanHistory(defaults: defaults)
        history.record(ean13, at: start)
        history.record(upcA, at: start + 60)
        // Another sighting of the same product: a new identity, the same code.
        history.record(ScannedCode(value: ean13.value, symbology: .ean13), at: start + 120)

        #expect(history.entries.map(\.id) == [id(of: ean13), id(of: upcA)])
        let entry = try #require(history.entries.first)
        #expect(entry.count == 2)
        #expect(entry.firstScanned == start)
        #expect(entry.lastScanned == start + 120)
        #expect(history.recordCount == 3)
    }

    @Test("The same digits in another symbology are another product")
    func symbologySplitsEntries() {
        let history = ScanHistory(defaults: defaults)
        history.record(ScannedCode(value: "01234565", symbology: .ean8), at: start)
        history.record(ScannedCode(value: "01234565", symbology: .upcE), at: start + 60)

        #expect(history.entries.count == 2)
        #expect(history.entries.allSatisfy { $0.count == 1 })
    }

    @Test("Past its capacity, the history drops the oldest products; a known one drops none")
    func capacityDropsOldest() {
        let history = ScanHistory(defaults: defaults)
        let codes = (0...ScanHistory.capacity).map { ScannedCode(value: String(format: "%08d", $0), symbology: .ean8) }
        for (index, code) in codes.enumerated() {
            history.record(code, at: start + Double(index))
        }

        #expect(history.entries.count == ScanHistory.capacity)
        #expect(history.entries.first?.id == id(of: codes[ScanHistory.capacity]))
        #expect(!history.entries.contains { $0.matches(codes[0]) })

        history.record(codes[1], at: start + 1_000)
        #expect(history.entries.count == ScanHistory.capacity)
        #expect(history.entries.first?.id == id(of: codes[1]))
    }

    @Test("The history and its flags survive a relaunch")
    func persistsAcrossLaunches() {
        let history = ScanHistory(defaults: defaults)
        history.record(ean13, at: start)
        history.record(ean8, at: start + 60)
        history.record(ean13, at: start + 120)
        history.revealButton()

        let relaunched = ScanHistory(defaults: defaults)
        #expect(relaunched.entries == history.entries)
        #expect(relaunched.hasScanned)
        #expect(relaunched.isButtonRevealed)
        #expect(relaunched.recordCount == 0)
    }

    @Test("The button shows only once a code was scanned")
    func revealNeedsScan() {
        let history = ScanHistory(defaults: defaults)
        history.revealButton()
        #expect(!history.isButtonRevealed)

        history.record(ean13, at: start)
        history.revealButton()
        #expect(history.isButtonRevealed)
    }

    @Test("A scan from an earlier run reveals the button at launch, as no result is open then")
    func launchRevealsButton() {
        let history = ScanHistory(defaults: defaults)
        history.record(ean13, at: start)
        #expect(!history.isButtonRevealed)

        #expect(ScanHistory(defaults: defaults).isButtonRevealed)
    }

    @Test("Deleting and clearing keep the button shown and the hint away")
    func deleteAndClearKeepFlags() {
        let history = ScanHistory(defaults: defaults)
        history.record(ean13, at: start)
        history.record(upcA, at: start + 60)
        history.record(ean8, at: start + 120)
        history.revealButton()

        history.delete(atOffsets: [1])
        #expect(history.entries.map(\.id) == [id(of: ean8), id(of: ean13)])

        history.clear()
        #expect(history.entries.isEmpty)
        #expect(history.hasScanned)
        #expect(history.isButtonRevealed)

        let relaunched = ScanHistory(defaults: defaults)
        #expect(relaunched.entries.isEmpty)
        #expect(relaunched.hasScanned)
        #expect(relaunched.isButtonRevealed)
    }

    @Test("Resetting forgets the scans and both flags, as on a first launch")
    func resetStartsOver() {
        let history = ScanHistory(defaults: defaults)
        history.record(ean13, at: start)
        history.revealButton()

        history.reset()
        #expect(history.entries.isEmpty)
        #expect(!history.hasScanned)
        #expect(!history.isButtonRevealed)

        let relaunched = ScanHistory(defaults: defaults)
        #expect(relaunched.entries.isEmpty)
        #expect(!relaunched.hasScanned)
        #expect(!relaunched.isButtonRevealed)
    }

    @Test("An entry this build can't read costs only itself")
    func unreadableEntrySkipped() throws {
        let history = ScanHistory(defaults: defaults)
        history.record(ean13, at: start)
        history.record(upcA, at: start + 60)
        // As if a newer build had saved a symbology this one doesn't know.
        let data = try #require(defaults.data(forKey: "scanHistory.entries"))
        var saved = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        saved[0]["symbology"] = "qrCode"
        defaults.set(try JSONSerialization.data(withJSONObject: saved), forKey: "scanHistory.entries")

        #expect(ScanHistory(defaults: defaults).entries.map(\.id) == [id(of: ean13)])
    }

    @Test("Closing a result reveals the history button")
    func closingResultReveals() {
        let history = ScanHistory(defaults: defaults)
        history.record(ean13, at: start)
        let scanner = ScannerModel(state: .scanning, scannedCode: ean13, history: history)

        scanner.scanAgain()
        #expect(history.isButtonRevealed)
    }

    #if targetEnvironment(simulator)
    @Test("The scanner records each code it finds")
    func scannerRecordsFoundCode() async throws {
        let history = ScanHistory(defaults: defaults)
        let scanner = ScannerModel(history: history)
        scanner.updateScreen(size: CGSize(width: 386, height: 662), displayScale: 3)
        let run = Task { await scanner.run() }
        defer { run.cancel() }
        try #require(await eventually(within: 3) { scanner.isAiming })

        scanner.simulateScan()
        try #require(await eventually(within: 3) { scanner.scannedCode != nil })
        let code = try #require(scanner.scannedCode)
        #expect(history.entries.map(\.id) == [id(of: code)])
        #expect(history.recordCount == 1)
        // Revealed only once the result closes.
        #expect(!history.isButtonRevealed)
    }
    #endif

    private func eventually(within seconds: Double, _ condition: () -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test("Unreadable saved entries start an empty history")
    func corruptEntriesDecodeEmpty() {
        defaults.set(Data("not json".utf8), forKey: "scanHistory.entries")

        #expect(ScanHistory(defaults: defaults).entries.isEmpty)
    }
}
