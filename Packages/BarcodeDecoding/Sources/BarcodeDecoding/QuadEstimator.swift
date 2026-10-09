/// Fits a code's outline from its line hits and probes how far its bars extend.
///
/// The reading direction comes from the gradient structure tensor along the hits (scanlines
/// cross the code at an angle, so their own direction is not the code's). The start and end
/// edges are the medians of the hits' guard edges along it. The bar extent is then found by
/// sampling profiles parallel to the reading direction beyond the decoded lines and
/// correlating them with the code's known module pattern, following any drift of the edges.
struct QuadEstimator {
    /// Template and profile samples per module.
    private static let samplesPerModule = 4
    /// Modules of quiet zone included on each side of the template.
    private static let templateMargin = 2
    /// Template shift searched on each side of the expected position, in samples.
    private static let shiftRange = 4
    private static let maxSamples = (95 + 2 * templateMargin) * samplesPerModule + 2 * shiftRange + 1
    /// How far blur moves the outline's sides outwards, in modules.
    private static let blurInset = 0.1
    /// Hits used for the orientation, and cos(2 x 10 degrees) for agreeing with the consensus.
    private static let maxTensorHits = 48
    private static let agreementCosine = 0.94

    private let modules: UnsafeMutablePointer<UInt8>
    private let template: UnsafeMutablePointer<Float>
    private let profile: UnsafeMutablePointer<Float>
    // Scratch reused from frame to frame.
    private var support: [Int] = []
    private var tensors: [Tensor] = []
    private var startEdges: [Double] = []
    private var endEdges: [Double] = []
    private var across: [Double] = []

    init() {
        modules = .allocate(capacity: 95)
        template = .allocate(capacity: Self.maxSamples)
        profile = .allocate(capacity: Self.maxSamples)
    }

    func deallocate() {
        modules.deallocate()
        template.deallocate()
        profile.deallocate()
    }

    /// The outline (TL, TR, BR, BL in reading orientation) and module size of `candidate`.
    mutating func outline(of candidate: CodeCandidate, hits: [LineHit], image: LumaImage)
        -> (corners: (BarcodePoint, BarcodePoint, BarcodePoint, BarcodePoint), moduleSize: Double)? {
        // Hits with guard edges: full decodes and both kinds of halves.
        support.removeAll(keepingCapacity: true)
        support.append(contentsOf: candidate.fullHits)
        for i in candidate.leftHalves where !support.contains(i) { support.append(i) }
        for i in candidate.rightHalves where !support.contains(i) { support.append(i) }
        guard let first = support.first else { return nil }

        // Reading direction: dominant gradient orientation along the hits. A line running along
        // the bars' ends sees their end edges, so hits that disagree with the consensus drop out.
        tensors.removeAll(keepingCapacity: true)
        for i in support.prefix(Self.maxTensorHits) {
            let t = tensor(along: hits[i], image)
            if t.isPlausible(along: hits[i]) { tensors.append(t) }
        }
        let sum = consensus()
        let halfDifference = (sum.xx - sum.yy) / 2
        let lambda = (sum.xx + sum.yy) / 2 + (halfDifference * halfDifference + sum.xy * sum.xy).squareRoot()
        var ux = sum.xy, uy = lambda - sum.xx
        if abs(ux) + abs(uy) < 1e-9 { (ux, uy) = (lambda - sum.yy, sum.xy) }
        var norm = (ux * ux + uy * uy).squareRoot()
        if norm < 1e-9 {
            // Flat gradients: fall back to the scanline direction of the first hit.
            ux = hits[first].lineDirection.x
            uy = hits[first].lineDirection.y
            norm = 1
        }
        ux /= norm
        uy /= norm
        var orientation = 0.0
        for i in support {
            let h = hits[i]
            let sign: Double = h.kind == .rightHalf ? -1 : 1
            orientation += sign * ((h.end.x - h.start.x) * ux + (h.end.y - h.start.y) * uy)
        }
        if orientation < 0 {
            ux = -ux
            uy = -uy
        }
        // "Down" (towards the human-readable digits) is to the right of the reading direction.
        let vx = -uy, vy = ux

        startEdges.removeAll(keepingCapacity: true)
        endEdges.removeAll(keepingCapacity: true)
        across.removeAll(keepingCapacity: true)
        for i in support {
            let h = hits[i]
            let startAlong = h.start.x * ux + h.start.y * uy
            switch h.kind {
            case .full:
                startEdges.append(startAlong)
                endEdges.append(h.end.x * ux + h.end.y * uy)
            case .leftHalf: startEdges.append(startAlong)
            case .rightHalf: endEdges.append(startAlong)
            }
            across.append(h.start.x * vx + h.start.y * vy)
            across.append(h.end.x * vx + h.end.y * vy)
        }
        let count = SymbolTables.modulePattern(format: candidate.format, digits: candidate.digits, into: modules)
        let codeLength = Double(count) * hits[first].moduleSize
        var start = Self.median(&startEdges) ?? .nan
        var end = Self.median(&endEdges) ?? .nan
        if start.isNaN { start = end - codeLength }
        if end.isNaN { end = start + codeLength }
        let module = (end - start) / Double(count)
        guard module > 0.3, let lowest = across.min(), let highest = across.max(),
              let middle = Self.median(&across) else { return nil }

        // Probe the bar extent on both sides of the decoded lines.
        let statistics = buildTemplate(count)
        let geometry = ProbeGeometry(ux: ux, uy: uy, vx: vx, vy: vy, start: start, module: module, moduleCount: count,
                                     templateMean: statistics.mean, templateVariance: statistics.variance)
        let reference = score(at: middle, shiftGuess: 0, geometry, image)
        let threshold = max(0.3, 0.5 * reference.value)
        let reach = Double(count) * module
        let top = probe(from: lowest, direction: -1, limit: reach, threshold: threshold, shift: reference.shift,
                        geometry, image)
        let bottom = probe(from: highest, direction: 1, limit: reach, threshold: threshold, shift: reference.shift,
                           geometry, image)

        // Blur widens the narrow guard bars and the bars' ends; pull every side in a little.
        let inset = Self.blurInset * module
        let q = module / Double(Self.samplesPerModule)
        func corner(_ along: Double, _ across: Double) -> BarcodePoint {
            BarcodePoint(x: along * ux + across * vx, y: along * uy + across * vy)
        }
        let topShift = Double(top.shift) * q, bottomShift = Double(bottom.shift) * q
        let topEdge = top.edge + inset, bottomEdge = bottom.edge - inset
        return ((corner(start + inset + topShift, topEdge), corner(end - inset + topShift, topEdge),
                 corner(end - inset + bottomShift, bottomEdge), corner(start + inset + bottomShift, bottomEdge)), module)
    }

    /// Walks away from the decoded lines until the pattern is lost twice in a row, then bisects
    /// the last step. Returns the bar end (along v) and the template shift there.
    private func probe(from origin: Double, direction: Double, limit: Double, threshold: Double, shift: Int,
                       _ g: ProbeGeometry, _ image: LumaImage) -> (edge: Double, shift: Int) {
        let step = max(2.0, 2 * g.module)
        var inside = origin, insideShift = shift
        var misses = 0
        var outside = origin + direction * step
        var distance = step
        while distance <= limit {
            let position = origin + direction * distance
            let s = score(at: position, shiftGuess: insideShift, g, image)
            if s.value >= threshold {
                inside = position
                insideShift = s.shift
                misses = 0
            } else {
                if misses == 0 { outside = position }
                misses += 1
                if misses == 2 { break }
            }
            distance += step
        }
        if misses == 0 { return (inside, insideShift) }
        var lo = inside, hi = outside
        for _ in 0..<5 {
            let mid = (lo + hi) / 2
            let s = score(at: mid, shiftGuess: insideShift, g, image)
            if s.value >= threshold {
                lo = mid
                insideShift = s.shift
            } else {
                hi = mid
            }
        }
        return ((lo + hi) / 2, insideShift)
    }

    /// Template: +1 for light modules (including the margins), -1 for bars, at 4 samples/module.
    /// Returns its mean and its summed squared deviation.
    private func buildTemplate(_ count: Int) -> (mean: Float, variance: Float) {
        let total = (count + 2 * Self.templateMargin) * Self.samplesPerModule
        var sum: Float = 0
        for k in 0..<total {
            let m = k / Self.samplesPerModule - Self.templateMargin
            template[k] = m >= 0 && m < count && modules[m] == 1 ? -1 : 1
            sum += template[k]
        }
        let mean = sum / Float(total)
        var variance: Float = 0
        for k in 0..<total { variance += (template[k] - mean) * (template[k] - mean) }
        return (mean, variance)
    }

    /// Best normalised correlation of the profile at `across` with the template, over shifts
    /// around `shiftGuess` (in samples).
    private func score(at across: Double, shiftGuess: Int, _ g: ProbeGeometry, _ image: LumaImage)
        -> (value: Double, shift: Int) {
        // Bars cut off by the image border end there (clamped samples would repeat the edge row).
        let end = g.start + Double(g.moduleCount) * g.module
        guard isInside(g.start * g.ux + across * g.vx, g.start * g.uy + across * g.vy, image),
              isInside(end * g.ux + across * g.vx, end * g.uy + across * g.vy, image) else { return (0, shiftGuess) }
        let spm = Self.samplesPerModule
        let total = (g.moduleCount + 2 * Self.templateMargin) * spm
        let q = g.module / Double(spm)
        let first = g.start + (Double(shiftGuess - Self.shiftRange - Self.templateMargin * spm) + 0.5) * q
        for i in 0..<(total + 2 * Self.shiftRange) {
            let along = first + Double(i) * q
            profile[i] = Float(bilinear(image, x: along * g.ux + across * g.vx, y: along * g.uy + across * g.vy))
        }
        var best: Float = -2
        var bestShift = 0
        for shift in 0...(2 * Self.shiftRange) {
            var mean: Float = 0
            for k in 0..<total { mean += profile[k + shift] }
            mean /= Float(total)
            var cross: Float = 0, variance: Float = 0
            for k in 0..<total {
                let x = profile[k + shift] - mean
                cross += x * (template[k] - g.templateMean)
                variance += x * x
            }
            let value = variance > 1e-3 ? cross / (variance * g.templateVariance).squareRoot() : 0
            if value > best {
                best = value
                bestShift = shift - Self.shiftRange
            }
        }
        return (Double(best), shiftGuess + bestShift)
    }

    private func isInside(_ x: Double, _ y: Double, _ image: LumaImage) -> Bool {
        x >= 0 && y >= 0 && x <= Double(image.width) && y <= Double(image.height)
    }

    private func bilinear(_ image: LumaImage, x: Double, y: Double) -> Double {
        let fx = min(max(x - 0.5, 0), Double(image.width - 1) - 1e-6)
        let fy = min(max(y - 0.5, 0), Double(image.height - 1) - 1e-6)
        let ix = Int(fx), iy = Int(fy)
        let wx = fx - Double(ix), wy = fy - Double(iy)
        let x1 = min(ix + 1, image.width - 1), y1 = min(iy + 1, image.height - 1)
        let row0 = image.pixels + iy * image.bytesPerRow, row1 = image.pixels + y1 * image.bytesPerRow
        let top = Double(row0[ix]) * (1 - wx) + Double(row0[x1]) * wx
        let bottom = Double(row1[ix]) * (1 - wx) + Double(row1[x1]) * wx
        return top * (1 - wy) + bottom * wy
    }

    /// The gradient structure tensor along a hit. The gradient is a derivative of a binomial
    /// smoothing (5 x 5 taps, weights 1 4 6 4 1 across): bar edges are often sharper than a
    /// central difference's span, which biases its orientation towards 45 degrees.
    private func tensor(along hit: LineHit, _ image: LumaImage) -> Tensor {
        var t = Tensor()
        let length = hit.length
        guard length >= 1 else { return t }
        let steps = Int(length)
        let bpr = image.bytesPerRow
        @inline(__always) func dx(_ row: UnsafePointer<UInt8>) -> Int {
            2 * (Int(row[1]) - Int(row[-1])) + Int(row[2]) - Int(row[-2])
        }
        @inline(__always) func dy(_ p: UnsafePointer<UInt8>, _ j: Int) -> Int {
            2 * (Int(p[bpr + j]) - Int(p[j - bpr])) + Int(p[2 * bpr + j]) - Int(p[j - 2 * bpr])
        }
        for k in 0...steps {
            let f = Double(k) / Double(steps)
            let x = Int(hit.start.x + (hit.end.x - hit.start.x) * f)
            let y = Int(hit.start.y + (hit.end.y - hit.start.y) * f)
            guard x >= 2, y >= 2, x < image.width - 2, y < image.height - 2 else { continue }
            let p = image.pixels + y * bpr + x
            let gx = dx(p - 2 * bpr) + 4 * dx(p - bpr) + 6 * dx(p) + 4 * dx(p + bpr) + dx(p + 2 * bpr)
            let gy = dy(p, -2) + 4 * dy(p, -1) + 6 * dy(p, 0) + 4 * dy(p, 1) + dy(p, 2)
            t.xx += Double(gx * gx)
            t.xy += Double(gx * gy)
            t.yy += Double(gy * gy)
        }
        return t
    }

    /// Sums the tensors whose orientation is within about 10 degrees of the medoid orientation,
    /// with agreement weighted by coherence (which also breaks ties between two hits).
    private func consensus() -> Tensor {
        var medoid = 0, bestAgreement = -Double.infinity
        for (a, ta) in tensors.enumerated() {
            let da = ta.direction
            var agreement = 0.0
            for tb in tensors {
                let db = tb.direction
                agreement += (da.cos * db.cos + da.sin * db.sin) * da.coherence * db.coherence
            }
            if agreement > bestAgreement {
                bestAgreement = agreement
                medoid = a
            }
        }
        var sum = Tensor()
        guard medoid < tensors.count else { return sum }
        let dm = tensors[medoid].direction
        for t in tensors {
            let d = t.direction
            if d.cos * dm.cos + d.sin * dm.sin >= Self.agreementCosine {
                sum.xx += t.xx
                sum.xy += t.xy
                sum.yy += t.yy
            }
        }
        return sum
    }

    private static func median(_ values: inout [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        values.sort()
        let n = values.count
        return n % 2 == 1 ? values[n / 2] : (values[n / 2 - 1] + values[n / 2]) / 2
    }
}
