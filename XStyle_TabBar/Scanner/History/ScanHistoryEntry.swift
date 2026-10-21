import Foundation

/// One product in the scan history: a code, however many times it was scanned.
nonisolated struct ScanHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let value: String
    let symbology: BarcodeSymbology
    let firstScanned: Date
    var lastScanned: Date
    var count: Int

    /// The same digits in another symbology are another product.
    var id: String {
        "\(symbology.rawValue):\(value)"
    }

    init(code: ScannedCode, at date: Date) {
        value = code.value
        symbology = code.symbology
        firstScanned = date
        lastScanned = date
        count = 1
    }

    func matches(_ code: ScannedCode) -> Bool {
        code.value == value && code.symbology == symbology
    }

    /// A code to show the entry's report. Each call makes a new identity, so
    /// make it once per tap, not in a view's body.
    func makeCode() -> ScannedCode {
        ScannedCode(value: value, symbology: symbology)
    }
}
