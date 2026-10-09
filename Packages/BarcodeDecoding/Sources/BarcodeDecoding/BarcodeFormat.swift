public enum BarcodeFormat: Equatable, Sendable {
    /// EAN-13, including UPC-A (reported as EAN-13 with a leading 0).
    case ean13
    case ean8
    /// UPC-E, number system 0 only.
    case upcE
}
