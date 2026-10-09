/// Finds EAN-13, EAN-8 and UPC-E symbols, and EAN-13/EAN-8 half symbols, in an element run.
///
/// Every bar is tried as a start guard. Following zxing-cpp (Apache-2.0), the quiet zone is
/// checked first and the fixed element layout (middle guard at +27 and end guard at +56 for
/// EAN-13, +19/+40 for EAN-8, a 6-element end guard at +27 for UPC-E) is validated with the
/// character widths before any digit is decoded. Characters are classified from like-edge
/// distances (see `CharacterCandidates`); the 1/7 and 2/8 ties use bar widths corrected for the
/// ink spread measured on the guards and the unambiguous characters.
///
/// A half symbol runs from an outer guard (with its quiet zone) to the middle guard, so reading
/// both directions of a line finds left halves and (reversed) right halves for stitching.
struct SymbolParser {
    /// Quiet zone before a full symbol or a left half, in modules.
    static let leftQuiet: Float = 5
    /// Quiet zone after an EAN-13/EAN-8 end guard.
    static let rightQuiet: Float = 3
    /// Quiet zone after the UPC-E end guard, which is otherwise easy to find inside other codes.
    static let upcEQuiet: Float = 5
    /// Quiet zone before a right half read backwards from its end guard.
    static let rightHalfQuiet: Float = 4
    /// Edges weaker than 1/`weakEdgeRatio` of the guard's edge count as noise in a quiet zone.
    static let weakEdgeRatio: Int32 = 2
    /// Allowed deviation of a character's width from its neighbour's, and the widest allowed
    /// ratio between any two characters (perspective and curved packs shrink one end).
    static let neighbourTolerance: Float = 0.125
    static let widthSpread: Float = 2
    /// Minimum distance, in modules, of a corrected bar width from the 1/7 or 2/8 decision point.
    static let tieMargin: Float = 0.25
    /// Maximum deviation, in modules, of an unambiguous character's corrected bar width.
    static let barTolerance: Float = 1
    /// Largest mean distance, in modules, of the like-edge distances from whole modules.
    static let maximumMeanDeviation: Float = 0.3
    /// Template-matching anchors kept per line: from fitted layouts, and from quiet zones alone.
    static let maxAnchors = 4
    static let maxLooseAnchors = 2

    private let readings: UnsafeMutablePointer<CharacterReading>

    init() {
        readings = .allocate(capacity: 12)
    }

    func deallocate() {
        readings.deallocate()
    }

    /// Appends every symbol and half symbol in `run` to `hits`, and to `anchors` the layouts
    /// whose structure fitted but whose characters did not decode (and, with `looseAnchors`,
    /// symbols bounded only by quiet zones). Returns whether some candidate passed the
    /// quiet-zone and guard checks, which makes the line worth another front end.
    func parse(_ run: ElementRun, into hits: inout [RunHit], anchors: inout [TemplateAnchor], looseAnchors: Bool) -> Bool {
        var promising = false
        var g = 1
        while g + SymbolLayout.ean8Half.elements < run.count {
            if startGuardPlausible(at: g, in: run) {
                let anchorCount = anchors.count
                if let (hit, elements) = decodeAny(at: g, in: run, promising: &promising, anchors: &anchors) {
                    hits.append(hit)
                    // Bars sit at odd indices: whole symbols end on a space,
                    // halves just before a bar.
                    g += elements + (elements.isMultiple(of: 2) ? 0 : 1)
                    continue
                }
                if looseAnchors && anchors.count == anchorCount { looseAnchor(at: g, in: run, anchors: &anchors) }
            }
            g += 2
        }
        return promising
    }

    private func decodeAny(at g: Int, in run: ElementRun, promising: inout Bool,
                           anchors: inout [TemplateAnchor]) -> (RunHit, Int)? {
        for layout in Self.layouts {
            if let hit = decode(layout, at: g, in: run, promising: &promising, anchors: &anchors) {
                return (hit, layout.elements)
            }
        }
        return nil
    }

    /// Layouts in the order tried: a symbol inside a longer one must not win over it.
    private static let layouts: [SymbolLayout] = [.ean13, .ean8, .upcE, .ean13Half, .ean8Half]
    private static let wholeLayouts: [SymbolLayout] = [.ean13, .ean8, .upcE]

    /// Cheap screen: three guard-like elements after a space at least 2.5 guard modules wide.
    @inline(__always)
    private func startGuardPlausible(at g: Int, in run: ElementRun) -> Bool {
        let w = run.widths
        let a = w[g], b = w[g + 1], c = w[g + 2]
        let sum = a &+ b &+ c
        guard 12 &* a >= sum, 12 &* b >= sum, 12 &* c >= sum,
              3 &* a <= 2 &* sum, 3 &* b <= 2 &* sum, 3 &* c <= 2 &* sum else { return false }
        if g == 1 && run.leadingUnbounded { return true }
        if 6 &* w[g &- 1] >= 5 &* sum { return true }
        return quietBefore(g, in: run, needed: Float(sum) * 2.5 / 3) >= Float(sum) * 2.5 / 3
    }

    private func decode(_ layout: SymbolLayout, at g: Int, in run: ElementRun, promising: inout Bool,
                        anchors: inout [TemplateAnchor]) -> RunHit? {
        let count = layout.elements
        guard g + count < run.count else { return nil }
        let starts = run.starts
        let module = Float(starts[g + count] &- starts[g]) / Float(layout.modules)
        guard module > 0 else { return nil }

        // Quiet zones.
        let quietNeeded = layout.isHalf ? min(Self.leftQuiet, Self.rightHalfQuiet) : Self.leftQuiet
        let quiet = quietBefore(g, in: run, needed: Self.leftQuiet * module) / module
        guard quiet >= quietNeeded else { return nil }
        if !layout.isHalf {
            // As in zxing-cpp, one pixel of slack: it matters at two or three pixels per module.
            let needed = (layout.format == .upcE ? Self.upcEQuiet : Self.rightQuiet) * module - Float(run.onePixel)
            guard quietAfter(g + count, in: run, needed: needed) >= needed else { return nil }
        }

        // Character widths: each close to its neighbour's, all within a factor of two.
        var previous: Float = 0, narrowest = Float.infinity, widest: Float = 0
        for c in 0..<layout.characters {
            let s = g + layout.characterStart(c)
            let width = Float(starts[s + 4] &- starts[s])
            if c > 0 && abs(width / previous - 1) > Self.neighbourTolerance { return nil }
            previous = width
            narrowest = min(narrowest, width)
            widest = max(widest, width)
        }
        guard widest <= Self.widthSpread * narrowest else { return nil }

        // Guards, each measured against its neighbouring characters.
        let first = characterWidth(g + 3, starts)
        guard let startInk = guardInk(at: g, count: 3, characterWidth: first, run) else { return nil }
        var inkSum = startInk.sum
        var inkCount = startInk.count
        if layout.middleGuard > 0 {
            let before = characterWidth(g + layout.middleGuard - 4, starts)
            let reference = layout.rightCharacters > 0
                ? (before + characterWidth(g + layout.middleGuard + 5, starts)) / 2 : before
            guard let ink = guardInk(at: g + layout.middleGuard, count: 5, characterWidth: reference, run) else { return nil }
            inkSum += ink.sum
            inkCount += ink.count
        }
        if layout.endGuard > 0 {
            let last = characterWidth(g + layout.endGuard - 4, starts)
            guard let ink = guardInk(at: g + layout.endGuard, count: layout.endGuardLength,
                                     characterWidth: last, run) else { return nil }
            inkSum += ink.sum
            inkCount += ink.count
        }
        promising = true

        let end = layout.isHalf
            ? (starts[g + layout.middleGuard] &+ starts[g + layout.middleGuard + 5]) / 2
            : starts[g + count]
        let middleModule = layout.middleGuard > 0 ? characterWidth(g + layout.middleGuard - 4, starts) / 7 : module
        if let (characters, parity) = classify(layout, at: g, in: run, guardExcess: inkSum / inkCount),
           let (kind, digits) = SymbolAssembler.assemble(layout, characters: characters, parity: parity, quiet: quiet) {
            return RunHit(kind: kind, format: layout.format, digits: digits, start: starts[g], end: end, module: module,
                          middleModule: middleModule)
        }
        if anchors.count(where: { !$0.isLoose }) < Self.maxAnchors {
            let unit = Double(EdgeList.one)
            anchors.append(TemplateAnchor(layout: layout, start: run.linePosition(starts[g]),
                                          end: run.linePosition(starts[g + count]), hitEnd: run.linePosition(end),
                                          module: Double(module) / unit, middleModule: Double(middleModule) / unit,
                                          quiet: quiet))
        }
        return nil
    }

    /// Blur can merge narrow elements, so the element count no longer fits any layout. From a
    /// start guard with its quiet zone, look for a right quiet zone by distance instead: within
    /// -20%...+25% of the symbol length the guard's module implies, at least 3 modules wide.
    private func looseAnchor(at g: Int, in run: ElementRun, anchors: inout [TemplateAnchor]) {
        guard anchors.count(where: \.isLoose) < Self.maxLooseAnchors else { return }
        let starts = run.starts, w = run.widths
        let guardModule = Float(starts[g + 3] &- starts[g]) / 3
        let quiet = quietBefore(g, in: run, needed: Self.leftQuiet * guardModule) / guardModule
        guard quiet >= Self.leftQuiet else { return }
        for layout in Self.wholeLayouts {
            let expected = guardModule * Float(layout.modules)
            // First space at or beyond 80% of the expected length (starts are increasing).
            let earliest = starts[g] &+ Int32(0.8 * expected)
            var low = g + 21, high = run.count
            while low < high {
                let mid = (low + high) / 2
                if starts[mid] < earliest { low = mid + 1 } else { high = mid }
            }
            var j = (low & 1) == 1 ? low + 1 : low  // spaces have even indices
            while j < run.count {
                let length = Float(starts[j] &- starts[g])
                if length > 1.25 * expected { break }
                let module = length / Float(layout.modules)
                if Float(w[j]) >= Self.rightQuiet * module - Float(run.onePixel) {
                    let unit = Double(EdgeList.one)
                    anchors.append(TemplateAnchor(layout: layout, start: run.linePosition(starts[g]),
                                                  end: run.linePosition(starts[j]), hitEnd: run.linePosition(starts[j]),
                                                  module: Double(module) / unit, middleModule: Double(module) / unit,
                                                  quiet: quiet / guardModule * module, isLoose: true))
                    return
                }
                j += 2
            }
        }
    }

    /// Classifies the characters of a layout whose structure fitted: like-edge cells first, then
    /// the ties with the measured ink spread. Bars that grow by d modules (spaces shrinking by d)
    /// make a guard's mean bar minus mean space, and a character's two bars minus their nominal
    /// width, both 2d: `excess` averages it over the guards and the unambiguous characters.
    private func classify(_ layout: SymbolLayout, at g: Int, in run: ElementRun, guardExcess: Float)
        -> (characters: DigitString, parity: Int)? {
        let w = run.widths
        var deviation: Float = 0
        var excessSum = 2 * guardExcess
        var excessCount: Float = 2
        for c in 0..<layout.characters {
            let s = g + layout.characterStart(c)
            let barFirst = c >= layout.leftCharacters
            let e0 = Float(w[s]), e1 = Float(w[s + 1]), e2 = Float(w[s + 2]), e3 = Float(w[s + 3])
            let scale = 7 / (e0 + e1 + e2 + e3)
            let distance1 = (e0 + e1) * scale, distance2 = (e1 + e2) * scale
            let t1 = Int(distance1 + 0.5), t2 = Int(distance2 + 0.5)
            deviation += abs(distance1 - Float(t1)) + abs(distance2 - Float(t2))
            // A half has no check digit of its own, so the variance matcher's guesses are not
            // good enough for it.
            var candidates = (2...5).contains(t1) && (2...5).contains(t2)
                ? CharacterCandidates.lookup(t1: t1, t2: t2, barFirst: barFirst) : .invalid
            var bars = (barFirst ? e0 + e2 : e1 + e3) * scale
            if candidates.digit < 0 {
                guard !layout.isHalf, let match = VarianceMatcher.match(e0, e1, e2, e3, barFirst: barFirst) else { return nil }
                candidates = .fixed(match.digit, even: match.isEven)
                bars = .nan
            }
            readings[c] = CharacterReading(candidates: candidates, bars: bars, digit: candidates.digit,
                                           isEven: candidates.isEven)
            if candidates.tieDigit < 0 && !bars.isNaN {
                excessSum += bars - Float(candidates.bars)
                excessCount += 1
            }
        }
        // Each distance may round either way, but a real symbol's distances sit near whole
        // modules on average; a misaligned layout that only just rounds into valid cells does not.
        guard deviation / Float(2 * layout.characters) <= Self.maximumMeanDeviation else { return nil }
        let excess = excessSum / excessCount
        var characters = DigitString()
        var parity = 0
        for c in 0..<layout.characters {
            let candidates = readings[c].candidates
            let corrected = readings[c].bars - excess
            if candidates.tieDigit >= 0 {
                let decision = Float(candidates.bars + candidates.tieBars) / 2
                if abs(corrected - decision) >= Self.tieMargin {
                    let pickFirst = (corrected > decision) == (candidates.bars > candidates.tieBars)
                    readings[c].digit = pickFirst ? candidates.digit : candidates.tieDigit
                } else {
                    // Too close to call from the bar widths: let the variance matcher pick one of the two.
                    let s = g + layout.characterStart(c)
                    guard !layout.isHalf,
                          let match = VarianceMatcher.match(Float(w[s]), Float(w[s + 1]), Float(w[s + 2]), Float(w[s + 3]),
                                                            barFirst: c >= layout.leftCharacters),
                          match.digit == candidates.digit || match.digit == candidates.tieDigit,
                          match.isEven == candidates.isEven else { return nil }
                    readings[c].digit = match.digit
                }
            } else if !readings[c].bars.isNaN {
                guard abs(corrected - Float(candidates.bars)) <= Self.barTolerance else { return nil }
            }
            characters[c] = readings[c].digit
            if c < layout.leftCharacters { parity = parity << 1 | (readings[c].isEven ? 0 : 1) }
        }
        return (characters, parity)
    }

    @inline(__always)
    private func characterWidth(_ s: Int, _ starts: UnsafeMutablePointer<Int32>) -> Float {
        Float(starts[s + 4] &- starts[s])
    }

    /// Checks a guard of single-module elements against the module implied by a neighbouring
    /// character (like-edge pairs must round to 2 modules, as in ZBar) and returns its mean bar
    /// minus mean space width in modules, with weight 1, for the ink-spread estimate.
    private func guardInk(at i: Int, count: Int, characterWidth: Float, _ run: ElementRun) -> (sum: Float, count: Float)? {
        let module = characterWidth / 7
        let w = run.widths
        var bars: Float = 0, spaces: Float = 0, barCount: Float = 0, spaceCount: Float = 0
        for k in 0..<count {
            let width = Float(w[i + k]) / module
            guard width >= 0.35 && width <= 1.9 else { return nil }
            if k + 1 < count {
                let pair = width + Float(w[i + k + 1]) / module
                guard pair >= 1.5 && pair < 2.5 else { return nil }
            }
            if (i + k) & 1 == 1 {
                bars += width
                barCount += 1
            } else {
                spaces += width
                spaceCount += 1
            }
        }
        return (bars / barCount - spaces / spaceCount, 1)
    }

    /// Width of the light run before bar `g`, absorbing noise blips whose edges are weak next to
    /// the guard's first edge, up to `needed`. Infinite when it reaches an unbounded line start.
    private func quietBefore(_ g: Int, in run: ElementRun, needed: Float) -> Float {
        var i = g - 1
        var width = Float(run.widths[i])
        let reference = run.strengths[g]
        while width < needed && i >= 2 {
            let blip = max(run.strengths[i], run.strengths[i - 1])
            guard blip &* Self.weakEdgeRatio < reference else { break }
            width += Float(run.widths[i - 1] &+ run.widths[i - 2])
            i -= 2
        }
        return i == 0 && run.leadingUnbounded ? .infinity : width
    }

    /// Width of the light run starting at space `j` after a symbol, absorbing weak blips.
    private func quietAfter(_ j: Int, in run: ElementRun, needed: Float) -> Float {
        var i = j
        var width = Float(run.widths[i])
        let reference = run.strengths[j]
        while width < needed && i + 2 < run.count {
            let blip = max(run.strengths[i + 1], run.strengths[i + 2])
            guard blip &* Self.weakEdgeRatio < reference else { break }
            width += Float(run.widths[i + 1] &+ run.widths[i + 2])
            i += 2
        }
        return i == run.count - 1 && run.trailingUnbounded ? .infinity : width
    }
}
