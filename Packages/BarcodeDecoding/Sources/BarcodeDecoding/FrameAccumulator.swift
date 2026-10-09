/// Collects one frame's line hits into codes: full decodes of the same code merge, and left and
/// right halves found on parallel scanlines are stitched when they line up and the check digit
/// holds. Each code counts its independent supporting lines.
struct FrameAccumulator {
    private(set) var hits: [LineHit] = []
    private(set) var candidates: [CodeCandidate] = []
    private(set) var candidateCount = 0
    private var averaging = 1
    private var scratch: [Int] = []
    private var conflicts: [Int] = []

    /// The largest line count of any candidate so far.
    private(set) var bestLineCount = 0

    mutating func reset(averaging: Int) {
        hits.removeAll(keepingCapacity: true)
        candidateCount = 0
        bestLineCount = 0
        self.averaging = averaging
    }

    mutating func add(_ hit: LineHit) {
        let index = hits.count
        hits.append(hit)
        switch hit.kind {
        case .full:
            let c = candidateIndex(format: hit.format, digits: hit.digits, near: hit)
            candidates[c].fullHits.append(index)
            recount(c)
        case .leftHalf, .rightHalf:
            for other in 0..<index {
                let o = hits[other]
                guard o.format == hit.format, o.kind != .full, o.kind != hit.kind else { continue }
                let (left, right) = hit.kind == .leftHalf ? (index, other) : (other, index)
                guard halvesAlign(hits[left], hits[right]) else { continue }
                let digits = hits[left].digits.merged(with: hits[right].digits)
                guard digits.hasValidCheckDigit(count: hit.format == .ean13 ? 13 : 8) else { continue }
                let c = candidateIndex(format: hit.format, digits: digits, near: hit)
                if !candidates[c].leftHalves.contains(left) { candidates[c].leftHalves.append(left) }
                if !candidates[c].rightHalves.contains(right) { candidates[c].rightHalves.append(right) }
                recount(c)
            }
        }
    }

    /// The candidate for a code near `hit`, created if needed.
    private mutating func candidateIndex(format: BarcodeFormat, digits: DigitString, near hit: LineHit) -> Int {
        for c in 0..<candidateCount where candidates[c].format == format && candidates[c].digits == digits {
            if let anchor = anyHit(of: candidates[c]), distance(hits[anchor].midpoint, hit.midpoint)
                <= max(hits[anchor].length, hit.length) * 1.2 {
                return c
            }
        }
        if candidateCount == candidates.count { candidates.append(CodeCandidate()) }
        candidates[candidateCount].reset(format: format, digits: digits)
        candidateCount += 1
        return candidateCount - 1
    }

    private func anyHit(of candidate: CodeCandidate) -> Int? {
        candidate.fullHits.first ?? candidate.leftHalves.first ?? candidate.rightHalves.first
    }

    /// Whether a left and a right half can belong to one symbol: parallel scanlines, the same
    /// reading direction, the same module where they meet, and middle-guard centres that line up
    /// along the bars.
    private func halvesAlign(_ left: LineHit, _ right: LineHit) -> Bool {
        guard left.family == right.family else { return false }
        let ratio = left.middleModuleSize / right.middleModuleSize
        guard ratio > 1 / 1.15 && ratio < 1.15 else { return false }
        let d = left.lineDirection
        let leftReading = (left.end.x - left.start.x) * d.x + (left.end.y - left.start.y) * d.y
        let rightReading = (right.start.x - right.end.x) * d.x + (right.start.y - right.end.y) * d.y
        guard (leftReading > 0) == (rightReading > 0) else { return false }
        let dx = right.end.x - left.end.x, dy = right.end.y - left.end.y
        let along = abs(dx * d.x + dy * d.y)
        let across = abs(dx * d.y - dy * d.x)
        let module = (left.moduleSize + right.moduleSize) / 2
        return across <= 40 * module && along <= across + 3 * module
    }

    /// Lines count once per independent scanline: full decodes, plus stitched pairs whose halves
    /// come from lines that did not decode the code fully. Halves carry no check digit, so on
    /// each side the agreeing lines must outnumber twice over the lines whose half, lined up
    /// with the same partners, reads differently.
    private mutating func recount(_ c: Int) {
        let full = independentCount(candidates[c].fullHits, excluding: [])
        let left = independentCount(candidates[c].leftHalves, excluding: candidates[c].fullHits)
        let right = independentCount(candidates[c].rightHalves, excluding: candidates[c].fullHits)
        var stitched = min(left, right)
        if stitched > 0 && (left < 2 * conflictingLines(candidates[c], side: .leftHalf)
                            || right < 2 * conflictingLines(candidates[c], side: .rightHalf)) {
            stitched = 0
        }
        candidates[c].lineCount = full + stitched
        bestLineCount = max(bestLineCount, candidates[c].lineCount)
    }

    /// Independent lines with a half of `side` that lines up with the candidate's halves of the
    /// other side but reads differently from the candidate.
    private mutating func conflictingLines(_ candidate: CodeCandidate, side: HitKind) -> Int {
        conflicts.removeAll(keepingCapacity: true)
        let partners = side == .leftHalf ? candidate.rightHalves : candidate.leftHalves
        for (i, h) in hits.enumerated() where h.kind == side && h.format == candidate.format
            && !candidate.digits.agrees(with: h.digits) {
            let aligned = partners.contains { p in side == .leftHalf ? halvesAlign(h, hits[p]) : halvesAlign(hits[p], h) }
            if aligned { conflicts.append(i) }
        }
        return independentCount(conflicts, excluding: [])
    }

    private mutating func independentCount(_ indices: [Int], excluding: [Int]) -> Int {
        scratch.removeAll(keepingCapacity: true)
        for i in indices {
            let hit = hits[i]
            if excluding.contains(where: { hits[$0].sharesLine(with: hit, averaging: averaging) }) { continue }
            if scratch.contains(where: { hits[$0].sharesLine(with: hit, averaging: averaging) }) { continue }
            scratch.append(i)
        }
        return scratch.count
    }

    private func distance(_ a: BarcodePoint, _ b: BarcodePoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}
