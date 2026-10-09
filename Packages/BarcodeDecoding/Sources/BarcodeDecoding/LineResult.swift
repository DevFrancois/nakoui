/// What one scanline yielded.
enum LineResult {
    case nothing
    /// A start guard, quiet zone, character widths and guards all fitted, but no digits decoded.
    case promising
    case found
}
