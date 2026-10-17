/// Home's page-attached wash is the shipping default. Debug builds can
/// restore the original palette blend without changing its tuning values.
enum HomeBackgroundStyle: String {
    case pageAttached
    case originalBlended

    static let storageKey = "home.backgroundStyle"

    var usesOriginalBlended: Bool {
        get { self == .originalBlended }
        set { self = newValue ? .originalBlended : .pageAttached }
    }
}
