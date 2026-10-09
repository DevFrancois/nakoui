/// What one front end found on a scanline.
struct ProfileResult {
    /// Any symbol or half symbol.
    var found = false
    /// A whole symbol.
    var full = false
    /// A structure that passed the quiet-zone and guard checks.
    var promising = false

    mutating func merge(_ other: ProfileResult) {
        found = found || other.found
        full = full || other.full
        promising = promising || other.promising
    }
}
