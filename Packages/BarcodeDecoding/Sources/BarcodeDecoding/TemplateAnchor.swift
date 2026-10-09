/// A layout whose quiet zones, character widths and guards fitted on a scanline but whose
/// characters did not decode from edges: where `TemplateDecoder` should look. Positions are in
/// samples along the line; `end < start` when the symbol reads backwards along it.
struct TemplateAnchor {
    var layout: SymbolLayout
    /// The start guard's leading edge and the far end of the layout.
    var start: Double
    var end: Double
    /// Where the hit's end would be (the middle guard's centre for halves, else `end`).
    var hitEnd: Double
    /// Module width in samples, on average and next to the middle guard.
    var module: Double
    var middleModule: Double
    /// Quiet zone before the start guard, in modules.
    var quiet: Float
    /// Whether only the quiet zones were found (the element layout did not fit).
    var isLoose = false
}
