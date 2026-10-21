import Foundation

/// The product barcodes the scanner reads, as shown to the user. The raw
/// values are saved with the scan history: never rename them.
nonisolated enum BarcodeSymbology: String, Codable, Hashable, Sendable {
    case ean13
    case upcA
    case ean8
    case upcE

    var title: LocalizedStringResource {
        switch self {
        case .ean13: "EAN-13"
        case .upcA: "UPC-A"
        case .ean8: "EAN-8"
        case .upcE: "UPC-E"
        }
    }

    /// Modules from the start guard's first bar to the end guard's last.
    var moduleCount: Int {
        switch self {
        case .ean13, .upcA: 95
        case .ean8: 67
        case .upcE: 51
        }
    }
}
