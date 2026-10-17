/// Home uses the original palette blend by default. Debug builds can
/// switch to page-attached color without changing its tuning values.
enum HomeBackgroundStyle: String {
    case pageAttached
    case originalBlended

    static let storageKey = "home.backgroundStyle"
    static let defaultStyle: Self = .originalBlended

    var usesOriginalBlended: Bool {
        get { self == .originalBlended }
        set { self = newValue ? .originalBlended : .pageAttached }
    }
}
