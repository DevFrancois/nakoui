import BarcodeDecoding
import Foundation

/// A barcode the camera read: its digits and how they're encoded.
nonisolated struct ScannedCode: Identifiable, Hashable, Sendable {
    let id = UUID()
    let value: String
    let symbology: BarcodeSymbology

    init(value: String, symbology: BarcodeSymbology) {
        self.value = value
        self.symbology = symbology
    }

    /// The value as the decoder reports it: UPC-A with its leading zero.
    var decoderText: String {
        symbology == .upcA ? "0" + value : value
    }

    /// A decoder reading as shown to the user. A UPC-A arrives as an EAN-13
    /// with a leading zero, which is dropped.
    init(_ reading: BarcodeReading) {
        switch reading.format {
        case .ean13 where reading.text.count == 13 && reading.text.hasPrefix("0"):
            self.init(value: String(reading.text.dropFirst()), symbology: .upcA)
        case .ean13:
            self.init(value: reading.text, symbology: .ean13)
        case .ean8:
            self.init(value: reading.text, symbology: .ean8)
        case .upcE:
            self.init(value: reading.text, symbology: .upcE)
        }
    }
}

/// A real-world code for previews and the Simulator's backdrop.
extension ScannedCode {
    static let sampleEAN13 = ScannedCode(value: "4006381333931", symbology: .ean13)
}
