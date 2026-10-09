/// Reads EAN-13 (and UPC-A), EAN-8 and UPC-E codes from a luma plane along straight scanlines.
///
/// Each scanline is summed across its direction, turned into sub-pixel edges (`EdgeDetector`,
/// then on harder lines sharpened profiles and `ThresholdEdgeDetector`), stored as an element
/// run, and parsed in both directions from every start-guard candidate (`SymbolParser`); layouts
/// that fit but whose characters fail get a template-matching pass (`TemplateDecoder`). Lines
/// are visited middle-out, alternating between the enabled directions, and the neighbours of a
/// line that found something are visited next. Hits merge into codes (`FrameAccumulator`), whose
/// outlines are fitted and probed to the full bar height (`QuadEstimator`).
///
/// Not thread-safe: keep one decoder per queue (it reuses its scratch buffers between frames).
public final class BarcodeDecoder {
    /// Delay of the edge detector's smoothing, in samples.
    private static let edgeLag = 0.28
    /// Lowest edge slope, in grey levels per pixel of the averaged profile: at least
    /// `minimumSlope`, and `noiseSlopeRatio` times the noise left after averaging.
    private static let minimumSlope = 4.0
    private static let noiseSlopeRatio = 2.5
    /// Fewest edges a line needs to hold the shortest decodable structure (an EAN-8 half), and
    /// to get the threshold front end (sweep: no loss up to 28, losses from 34).
    private static let minimumEdges = 22
    private static let busyEdges = 28
    /// The sharpened profile's noise is about twice the original's.
    private static let sharpenedFloorRatio = 2
    /// Widest unsharp-mask tap distance tried on lines that came close, in samples.
    private static let widestSharpening = 3
    /// Edges weaker than this many sixteenths of their neighbours bound a sliver (a void or speck).
    private static let sliverRatio: Int32 = 11

    private var capacity = 0
    private var profile: UnsafeMutablePointer<Int32>
    private var sharpened: UnsafeMutablePointer<Int32>
    private var edges: EdgeList
    private var forward: ElementRun
    private var backward: ElementRun
    private let parser = SymbolParser()
    private let templates = TemplateDecoder()
    private var quads = QuadEstimator()
    private var runHits: [RunHit] = []
    private var anchors: [TemplateAnchor] = []
    private var accumulator = FrameAccumulator()
    private var lines: [[ScanLine]] = [[], [], [], []]
    private var visited: [[Bool]] = [[], [], [], []]
    private var pending: [(family: Int, index: Int)] = []
    /// The edge detector's slope floor for the current frame, in profile units per sample.
    private var slopeFloor = 0
    private var averaging = 1
    private var spacing = 1.0
    /// Noise standard deviation of a profile sample, in profile units.
    private var profileNoise: Float = 0
    /// Template attempts left this frame at anchors found from quiet zones alone (bar-like
    /// texture produces many of them).
    private var looseBudget = 0
    private static let looseAttempts = 16
    /// Symbols from parallel lines up to this many line spacings away lend their geometry, at
    /// most this many per line, each tried at this many start edges.
    private static let propagationReach = 3.0
    private static let propagatedSymbols = 2
    private static let propagatedStarts = 2

    public init() {
        capacity = 4096
        profile = .allocate(capacity: capacity)
        sharpened = .allocate(capacity: capacity)
        edges = EdgeList(capacity: capacity)
        forward = ElementRun(capacity: capacity + 4)
        backward = ElementRun(capacity: capacity + 4)
        runHits.reserveCapacity(16)
    }

    deinit {
        profile.deallocate()
        sharpened.deallocate()
        edges.deallocate()
        forward.deallocate()
        backward.deallocate()
        parser.deallocate()
        templates.deallocate()
        quads.deallocate()
    }

    /// Every code seen on at least one scanline in `region`, most lines first.
    public func decode(_ image: LumaImage, region: ScanRegion, options: DecoderOptions) -> [BarcodeReading] {
        let region = ScanRegion(minX: max(0, region.minX), minY: max(0, region.minY),
                                maxX: min(image.width, region.maxX), maxY: min(image.height, region.maxY))
        guard region.width > 0, region.height > 0 else { return [] }
        averaging = max(1, options.averaging)
        spacing = Double(max(1, options.lineSpacing))
        ensureCapacity(2 * max(image.width, image.height) + 8)
        accumulator.reset(averaging: averaging)
        looseBudget = Self.looseAttempts
        let sigma = NoiseEstimator.sigma(of: image, region: region)
        let noise = sigma / Double(averaging).squareRoot()
        slopeFloor = Int(max(Self.minimumSlope, Self.noiseSlopeRatio * noise) * Double(averaging << Int(ProfileSampler.scaleShift)))
        profileNoise = Float(sigma * Double(averaging).squareRoot() * Double(1 << ProfileSampler.scaleShift))

        let enabled = (options.scanColumns, options.scanRows, options.scanDiagonals)
        for f in 0..<4 {
            lines[f].removeAll(keepingCapacity: true)
            if f == 0 ? enabled.0 : f == 1 ? enabled.1 : enabled.2 {
                ScanPlanner.appendLines(ScanFamily(rawValue: f)!, image: image, region: region, spacing: Int(spacing),
                                        averaging: averaging, into: &lines[f])
            }
            visited[f].removeAll(keepingCapacity: true)
            visited[f].append(contentsOf: repeatElement(false, count: lines[f].count))
        }

        // Middle-out within each family, families in turn, neighbours of a hit first. When
        // stopping early, every other line is scanned at first (the common frame has no code at
        // all); a line that came close adds its neighbours, and a family where something decoded
        // goes back to every line until the code is confirmed.
        var cursors = (0, 0, 0, 0)
        var family = 0
        var coarse = options.stopWhenConfirmed ? (true, true, true, true) : (false, false, false, false)
        pending.removeAll(keepingCapacity: true)
        while let (f, index) = nextLine(&cursors, &family, coarse: coarse) {
            visited[f][index] = true
            let line = lines[f][index]
            ProfileSampler.sample(line, from: image, averaging: averaging, into: profile)
            let result = scanLine(line)
            guard result != .nothing else { continue }
            if index + 1 < lines[f].count && !visited[f][index + 1] { pending.append((f, index + 1)) }
            if index > 0 && !visited[f][index - 1] { pending.append((f, index - 1)) }
            if result == .found && isCoarse(coarse, f) {
                setDense(&coarse, &cursors, f)
            }
            if result == .found && options.stopWhenConfirmed && accumulator.bestLineCount >= options.minimumLines { break }
        }
        return readings(image: image, region: region)
    }

    private func isCoarse(_ coarse: (Bool, Bool, Bool, Bool), _ f: Int) -> Bool {
        switch f {
        case 0: coarse.0
        case 1: coarse.1
        case 2: coarse.2
        default: coarse.3
        }
    }

    /// Switches a family to every line, restarting its middle-out walk over the lines it skipped.
    private func setDense(_ coarse: inout (Bool, Bool, Bool, Bool), _ cursors: inout (Int, Int, Int, Int), _ f: Int) {
        switch f {
        case 0: coarse.0 = false; cursors.0 = 0
        case 1: coarse.1 = false; cursors.1 = 0
        case 2: coarse.2 = false; cursors.2 = 0
        default: coarse.3 = false; cursors.3 = 0
        }
    }

    /// The next line to scan: a pending neighbour of a hit, else middle-out within each family
    /// (skipping every other line while the family is coarse), the families taking turns.
    private func nextLine(_ cursors: inout (Int, Int, Int, Int), _ family: inout Int,
                          coarse: (Bool, Bool, Bool, Bool)) -> (Int, Int)? {
        while let candidate = pending.popLast() {
            if !visited[candidate.family][candidate.index] { return candidate }
        }
        for _ in 0..<4 {
            let f = family
            family = (family + 1) & 3
            let n = lines[f].count
            var k: Int
            switch f {
            case 0: k = cursors.0
            case 1: k = cursors.1
            case 2: k = cursors.2
            default: k = cursors.3
            }
            var found: Int?
            let mid = n / 2
            while k < n && found == nil {
                let index = k == 0 ? mid : (k & 1 == 1 ? mid - (k + 1) / 2 : mid + k / 2)
                k += 1
                if !visited[f][index] && !(isCoarse(coarse, f) && (index - mid) & 1 != 0) { found = index }
            }
            switch f {
            case 0: cursors.0 = k
            case 1: cursors.1 = k
            case 2: cursors.2 = k
            default: cursors.3 = k
            }
            if let found { return (f, found) }
        }
        return nil
    }

    /// Decodes one scanline into the accumulator with several front ends, stopping at the first
    /// whole symbol: ZBar-style edges; the same on the profile sharpened at 1, 2 and 3 samples
    /// when the line came close (blur pushes narrow elements' edges apart); zxing-style threshold
    /// crossings, which cope with blur and low contrast differently, on any line busy enough to
    /// hold a symbol; and the edges again without slivers (voids in bars, specks in spaces).
    private func scanLine(_ line: ScanLine) -> LineResult {
        anchors.removeAll(keepingCapacity: true)
        var result = scanProfile(profile, line, detector: .inflections(minSlope: slopeFloor), looseAnchors: looseBudget > 0)
        let busy = edges.count >= Self.busyEdges
        if result.promising && !result.full {
            ProfileSharpener.sharpen(profile, count: line.sampleCount, distance: 1, into: sharpened)
            result.merge(scanProfile(sharpened, line, detector: .inflections(minSlope: slopeFloor * Self.sharpenedFloorRatio)))
        }
        if busy && !result.full {
            result.merge(scanProfile(profile, line, detector: .threshold(scale: averaging << Int(ProfileSampler.scaleShift))))
        }
        for distance in 2...Self.widestSharpening where result.promising && !result.full {
            ProfileSharpener.sharpen(profile, count: line.sampleCount, distance: distance, into: sharpened)
            result.merge(scanProfile(sharpened, line, detector: .inflections(minSlope: slopeFloor * Self.sharpenedFloorRatio)))
        }
        if result.promising && !result.full {
            result.merge(scanProfile(profile, line, detector: .inflections(minSlope: slopeFloor), removeSlivers: true))
        }
        if !result.full {
            propagateAnchors(line)
        }
        if !result.full && !anchors.isEmpty {
            result.merge(scanTemplates(line))
        }
        return result.found ? .found : result.promising ? .promising : .nothing
    }

    /// Edges, runs in both directions and symbols of one profile; hits go to the accumulator.
    private func scanProfile(_ values: UnsafeMutablePointer<Int32>, _ line: ScanLine, detector: FrontEnd,
                             removeSlivers: Bool = false, looseAnchors: Bool = false) -> ProfileResult {
        switch detector {
        case .inflections(let minSlope):
            EdgeDetector.detect(values, count: line.sampleCount, minSlope: minSlope, into: &edges)
        case .threshold(let scale):
            ThresholdEdgeDetector.detect(values, count: line.sampleCount, scale: scale, into: &edges)
        }
        if removeSlivers { edges.removeSlivers(ratio: Self.sliverRatio) }
        guard edges.count >= Self.minimumEdges else { return ProfileResult() }
        forward.build(from: edges, line: line)
        runHits.removeAll(keepingCapacity: true)
        var promising = parser.parse(forward, into: &runHits, anchors: &anchors, looseAnchors: looseAnchors)
        let forwardCount = runHits.count
        backward.buildReversed(of: forward)
        promising = parser.parse(backward, into: &runHits, anchors: &anchors, looseAnchors: looseAnchors) || promising
        var full = false
        let direction = BarcodePoint(x: line.stepX / line.sampleLength, y: line.stepY / line.sampleLength)
        for (i, hit) in runHits.enumerated() {
            let run = i < forwardCount ? forward : backward
            let start = line.point(at: run.linePosition(hit.start) - Self.edgeLag)
            let end = line.point(at: run.linePosition(hit.end) - Self.edgeLag)
            accumulator.add(LineHit(kind: hit.kind, format: hit.format, digits: hit.digits, start: start, end: end,
                                    moduleSize: Double(hit.module) / Double(EdgeList.one) * line.sampleLength,
                                    middleModuleSize: Double(hit.middleModule) / Double(EdgeList.one) * line.sampleLength,
                                    family: line.family, lineOffset: line.offset, lineDirection: direction))
            full = full || hit.kind == .full
        }
        return ProfileResult(found: !runHits.isEmpty, full: full, promising: promising)
    }

    /// Adds anchors from symbols decoded on parallel lines nearby (or half decoded on this one):
    /// such a line crosses the symbol at the same angle, so the symbol's length along this line
    /// is the same. Its start is a bar edge after a quiet zone near where the other start
    /// projects. A half implies the whole symbol: its middle-guard centre is the symbol's middle.
    private func propagateAnchors(_ line: ScanLine) {
        let lengthPerSample = line.stepX * line.stepX + line.stepY * line.stepY
        func position(_ p: BarcodePoint) -> Double {
            ((p.x - line.originX) * line.stepX + (p.y - line.originY) * line.stepY) / lengthPerSample + Self.edgeLag
        }
        var known = 0
        var detected = false
        for hit in accumulator.hits where hit.family == line.family
            && abs(hit.lineOffset - line.offset) <= Self.propagationReach * spacing
            && (hit.kind != .full || hit.lineOffset != line.offset) {
            guard known < Self.propagatedSymbols else { break }
            known += 1
            // The whole symbol's outer edges along this line; `length` is negative when it reads
            // backwards along the line.
            let start: Double, end: Double
            switch hit.kind {
            case .full: (start, end) = (position(hit.start), position(hit.end))
            case .leftHalf: (start, end) = (position(hit.start), 2 * position(hit.end) - position(hit.start))
            case .rightHalf: (start, end) = (2 * position(hit.end) - position(hit.start), position(hit.start))
            }
            let length = end - start
            let layout: SymbolLayout = hit.format == .ean13 ? .ean13 : hit.format == .ean8 ? .ean8 : .upcE
            let module = abs(length) / Double(layout.modules)
            // The start can move by up to the line distance (bars tilted by 45 degrees) plus slack.
            let window = abs(hit.lineOffset - line.offset) / line.sampleLength + 2 * module
            if !detected {
                EdgeDetector.detect(profile, count: line.sampleCount, minSlope: slopeFloor, into: &edges)
                detected = true
            }
            var added = 0
            for k in 0..<edges.count where added < Self.propagatedStarts {
                let edge = Double(edges.positions[k]) / Double(EdgeList.one)
                guard abs(edge - start) <= window else { continue }
                // Reading forwards the start is a falling edge after light, backwards a rising one
                // before light; the light run must hold a quiet zone.
                let falling = (k & 1 == 0) != edges.startsDark
                guard falling == (length > 0) else { continue }
                let next = length > 0 ? k - 1 : k + 1
                let neighbour = next >= 0 && next < edges.count ? Double(edges.positions[next]) / Double(EdgeList.one)
                    : (length > 0 ? -Double.infinity : Double.infinity)
                let quiet = abs(edge - neighbour) / module
                guard quiet >= Double(SymbolParser.rightHalfQuiet) else { continue }
                anchors.append(TemplateAnchor(layout: layout, start: edge, end: edge + length, hitEnd: edge + length,
                                              module: module, middleModule: module, quiet: Float(min(quiet, 99))))
                added += 1
            }
        }
    }

    /// Template matching at the layouts whose structure fitted on this line but whose
    /// characters did not decode from edges.
    private func scanTemplates(_ line: ScanLine) -> ProfileResult {
        var result = ProfileResult()
        let direction = BarcodePoint(x: line.stepX / line.sampleLength, y: line.stepY / line.sampleLength)
        for (i, anchor) in anchors.enumerated() {
            // The same symbol found by several front ends: try it once.
            if anchors[..<i].contains(where: { $0.layout.modules == anchor.layout.modules && abs($0.start - anchor.start) < anchor.module }) {
                continue
            }
            if anchor.isLoose {
                guard looseBudget > 0 else { continue }
                looseBudget -= 1
            }
            guard let (characters, parity) = templates.decode(anchor, profile: profile, count: line.sampleCount, noise: profileNoise),
                  let (kind, digits) = SymbolAssembler.assemble(anchor.layout, characters: characters, parity: parity,
                                                                quiet: anchor.quiet) else { continue }
            accumulator.add(LineHit(kind: kind, format: anchor.layout.format, digits: digits,
                                    start: line.point(at: anchor.start - Self.edgeLag),
                                    end: line.point(at: anchor.hitEnd - Self.edgeLag),
                                    moduleSize: anchor.module * line.sampleLength,
                                    middleModuleSize: anchor.middleModule * line.sampleLength,
                                    family: line.family, lineOffset: line.offset, lineDirection: direction))
            result.found = true
            result.full = result.full || kind == .full
        }
        result.promising = true
        return result
    }

    /// Turns the frame's candidates into readings: outlines, region filter, conflicts, order.
    private func readings(image: LumaImage, region: ScanRegion) -> [BarcodeReading] {
        var results: [BarcodeReading] = []
        for c in 0..<accumulator.candidateCount {
            let candidate = accumulator.candidates[c]
            guard candidate.lineCount > 0,
                  let (corners, moduleSize) = quads.outline(of: candidate, hits: accumulator.hits, image: image)
            else { continue }
            let centreX = (corners.0.x + corners.1.x + corners.2.x + corners.3.x) / 4
            let centreY = (corners.0.y + corners.1.y + corners.2.y + corners.3.y) / 4
            guard centreX >= Double(region.minX), centreX < Double(region.maxX),
                  centreY >= Double(region.minY), centreY < Double(region.maxY) else { continue }
            results.append(BarcodeReading(format: candidate.format, text: candidate.digits.text(count: candidate.digitCount),
                                          topLeft: corners.0, topRight: corners.1, bottomRight: corners.2,
                                          bottomLeft: corners.3, lineCount: candidate.lineCount, moduleSize: moduleSize))
        }
        // Different codes on the same spot: keep the best supported one, or none on a tie.
        var keep = [Bool](repeating: true, count: results.count)
        for a in 0..<results.count {
            for b in (a + 1)..<max(a + 1, results.count) where overlaps(results[a], results[b]) {
                if results[a].lineCount >= results[b].lineCount { keep[b] = false }
                if results[b].lineCount >= results[a].lineCount { keep[a] = false }
            }
        }
        return zip(results, keep).filter(\.1).map(\.0).sorted { $0.lineCount > $1.lineCount }
    }

    private func overlaps(_ a: BarcodeReading, _ b: BarcodeReading) -> Bool {
        contains(a, centreOf: b) || contains(b, centreOf: a)
    }

    /// Whether `outer`'s outline contains the centre of `inner`'s.
    private func contains(_ outer: BarcodeReading, centreOf inner: BarcodeReading) -> Bool {
        let x = (inner.topLeft.x + inner.topRight.x + inner.bottomRight.x + inner.bottomLeft.x) / 4
        let y = (inner.topLeft.y + inner.topRight.y + inner.bottomRight.y + inner.bottomLeft.y) / 4
        // The centre is inside when it is on the same side of all four edges.
        func side(_ p: BarcodePoint, _ q: BarcodePoint) -> Double { (q.x - p.x) * (y - p.y) - (q.y - p.y) * (x - p.x) }
        let sides = (side(outer.topLeft, outer.topRight), side(outer.topRight, outer.bottomRight),
                     side(outer.bottomRight, outer.bottomLeft), side(outer.bottomLeft, outer.topLeft))
        return (sides.0 >= 0 && sides.1 >= 0 && sides.2 >= 0 && sides.3 >= 0)
            || (sides.0 <= 0 && sides.1 <= 0 && sides.2 <= 0 && sides.3 <= 0)
    }

    private func ensureCapacity(_ needed: Int) {
        guard needed > capacity else { return }
        profile.deallocate()
        sharpened.deallocate()
        edges.deallocate()
        forward.deallocate()
        backward.deallocate()
        capacity = needed
        profile = .allocate(capacity: capacity)
        sharpened = .allocate(capacity: capacity)
        edges = EdgeList(capacity: capacity)
        forward = ElementRun(capacity: capacity + 4)
        backward = ElementRun(capacity: capacity + 4)
    }
}
