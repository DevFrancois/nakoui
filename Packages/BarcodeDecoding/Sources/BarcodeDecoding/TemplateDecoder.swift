/// Reads the characters of a heavily blurred symbol whose quiet zones and guards were already
/// matched (`TemplateAnchor`), by comparing the grey profile with blurred character templates
/// (after Gallo-Manduchi and Iwen et al.: it keeps working when blur has merged the edges of
/// narrow elements, where edge positions no longer give the widths).
///
/// The profile is resampled at 4 samples per module between the anchor's outer edges. The blur
/// width is the one whose templates fit the known guard patterns best. Each character is then
/// fitted (gain and offset by least squares, a shift of up to half a module) against every
/// candidate digit, and the best must beat the runner-up clearly. Nothing is corrected through
/// the check digit: each digit stands on its own and the checksum only validates the result.
struct TemplateDecoder {
    private static let samplesPerModule = 4
    /// Modules resampled beyond each end of the symbol.
    private static let margin = 2
    /// Template window of a character: its 7 modules and half a module either side.
    private static let window = 8 * samplesPerModule
    /// Shift searched per window, in samples (quarter modules).
    private static let shiftRange = 2
    /// Blur widths tried (Gaussian sigma, in modules); beyond about 0.8 template matching
    /// makes confident mistakes.
    private static let blurs = (0.35, 0.5, 0.65, 0.8)
    private static let blurCount = 4
    /// The runner-up's residual must exceed the winner's by this many variances per sample, and
    /// the winner's may not exceed `maximumResidual` of them. The variance is the noise's, or for
    /// clean signals a fraction of the contrast (the template model itself is not exact).
    private static let minimumMargin: Float = 1.5
    private static let maximumResidual: Float = 6
    private static let modelError: Float = 0.05

    /// Per blur: 20 left character templates (L then G) and 10 right ones (R), `window` samples.
    private let characters: UnsafeMutablePointer<Float>
    /// Per blur: start, middle, EAN end and UPC-E end guard templates, `guardWindow` samples.
    private let guards: UnsafeMutablePointer<Float>
    private let resampled: UnsafeMutablePointer<Float>
    private static let guardWindow = 9 * samplesPerModule
    private static let maxResampled = (95 + 2 * margin) * samplesPerModule

    init() {
        characters = .allocate(capacity: Self.blurCount * 30 * Self.window)
        guards = .allocate(capacity: Self.blurCount * 4 * Self.guardWindow)
        resampled = .allocate(capacity: Self.maxResampled)
        guards.initialize(repeating: 0, count: Self.blurCount * 4 * Self.guardWindow)
        for b in 0..<Self.blurCount {
            let sigma = Self.blur(b)
            for pattern in 0..<30 {
                Self.render(bits: Self.characterBits(pattern), count: 9, sigma: sigma,
                            into: characters + (b * 30 + pattern) * Self.window, samples: Self.window)
            }
            for kind in 0..<4 {
                Self.render(bits: Self.guardBits(kind), count: Self.guardModules(kind), sigma: sigma,
                            into: guards + (b * 4 + kind) * Self.guardWindow,
                            samples: (Self.guardModules(kind) - 1) * Self.samplesPerModule)
            }
        }
    }

    func deallocate() {
        characters.deallocate()
        guards.deallocate()
        resampled.deallocate()
    }

    /// Decodes the characters of `anchor` from a line's profile, whose noise standard deviation
    /// is `noise` (profile units). Returns the digits in reading order and the parity word of the
    /// left characters (1 = odd/L), or nil when any character is not clear.
    func decode(_ anchor: TemplateAnchor, profile: UnsafePointer<Int32>, count: Int, noise: Float)
        -> (digits: DigitString, parity: Int)? {
        let layout = anchor.layout
        let module = (anchor.end - anchor.start) / Double(layout.modules)  // negative when read backwards
        guard abs(module) >= 1 else { return nil }
        let total = (layout.modules + 2 * Self.margin) * Self.samplesPerModule
        let step = module / Double(Self.samplesPerModule)
        let origin = anchor.start - Double(Self.margin) * module + step / 2
        for k in 0..<total {
            let x = origin + Double(k) * step
            let i = Int(x.rounded(.down))
            guard i >= 0 && i + 1 < count else { return nil }
            let f = Float(x - Double(i))
            resampled[k] = Float(profile[i]) * (1 - f) + Float(profile[i + 1]) * f
        }
        let variance = max(noise * noise, 1)

        // Blur: the width whose templates fit the guards best. The guards must fit as well as a
        // character has to.
        var blur = 0, bestGuardFit = Float.infinity, guardSamples = 0, guardContrast: Float = 0
        for b in 0..<Self.blurCount {
            var fit = guardFit(b, kind: 0, firstModule: -2, limit: total)
            if layout.middleGuard > 0 {
                fit = fit + guardFit(b, kind: 1, firstModule: 3 + 7 * layout.leftCharacters - 1, limit: total)
            }
            if layout.endGuardLength == 6 {
                fit = fit + guardFit(b, kind: 3, firstModule: layout.modules - 7, limit: total)
            } else if layout.endGuard > 0 {
                fit = fit + guardFit(b, kind: 2, firstModule: layout.modules - 4, limit: total)
            }
            if fit.residual < bestGuardFit {
                bestGuardFit = fit.residual
                guardSamples = fit.samples
                guardContrast = fit.contrast / Float(fit.count)
                blur = b
            }
        }
        let guardError = Self.modelError * guardContrast
        guard bestGuardFit <= Self.maximumResidual * Float(guardSamples) * max(variance, guardError * guardError) else {
            return nil
        }

        var digits = DigitString()
        var parity = 0
        for c in 0..<layout.characters {
            let right = c >= layout.leftCharacters
            let firstModule = right ? 3 + 7 * layout.leftCharacters + 5 + 7 * (c - layout.leftCharacters) : 3 + 7 * c
            let at = (Self.margin + firstModule) * Self.samplesPerModule - Self.samplesPerModule / 2
            var best = Float.infinity, second = Float.infinity, bestPattern = -1, contrast: Float = 0
            for pattern in right ? 20..<30 : 0..<20 {
                let fit = bestFit(characters + (blur * 30 + pattern) * Self.window, length: Self.window, at: at, limit: total)
                if fit.residual < best {
                    second = best
                    best = fit.residual
                    bestPattern = pattern
                    contrast = fit.contrast
                } else if fit.residual < second {
                    second = fit.residual
                }
            }
            let error = Self.modelError * contrast
            let perSample = Float(Self.window) * max(variance, error * error)
            guard bestPattern >= 0, best <= Self.maximumResidual * perSample,
                  second - best >= Self.minimumMargin * perSample else { return nil }
            digits[c] = bestPattern % 10
            if !right { parity = parity << 1 | (bestPattern < 10 ? 1 : 0) }
        }
        return (digits, parity)
    }

    /// Fit of a guard template whose first module is `firstModule` (relative to the symbol start).
    private func guardFit(_ blur: Int, kind: Int, firstModule: Int, limit: Int) -> GuardFit {
        let at = (Self.margin + firstModule) * Self.samplesPerModule + Self.samplesPerModule / 2
        let length = (Self.guardModules(kind) - 1) * Self.samplesPerModule
        let fit = bestFit(guards + (blur * 4 + kind) * Self.guardWindow, length: length, at: at, limit: limit)
        return GuardFit(residual: fit.residual, samples: length, contrast: fit.contrast, count: 1)
    }

    /// Smallest residual of `resampled ~ a + c * template` (c < 0: bars are dark) over the shifts,
    /// using the first `limit` resampled values, with the contrast |c| of that fit.
    private func bestFit(_ template: UnsafePointer<Float>, length: Int, at start: Int, limit: Int)
        -> (residual: Float, contrast: Float) {
        var sumT: Float = 0, sumTT: Float = 0
        for k in 0..<length {
            sumT += template[k]
            sumTT += template[k] * template[k]
        }
        let n = Float(length)
        let determinant = n * sumTT - sumT * sumT
        guard determinant > 1e-6 else { return (.infinity, 0) }
        var best = Float.infinity, contrast: Float = 0
        for shift in -Self.shiftRange...Self.shiftRange {
            let first = start + shift
            guard first >= 0, first + length <= limit else { continue }
            var sumP: Float = 0, sumPP: Float = 0, sumTP: Float = 0
            for k in 0..<length {
                let p = resampled[first + k]
                sumP += p
                sumPP += p * p
                sumTP += template[k] * p
            }
            let c = (n * sumTP - sumT * sumP) / determinant
            guard c < 0 else { continue }
            let a = (sumP - c * sumT) / n
            let residual = sumPP - a * sumP - c * sumTP
            if residual < best {
                best = residual
                contrast = -c
            }
        }
        return (best, contrast)
    }

    // MARK: - Templates

    private static func blur(_ index: Int) -> Double {
        switch index {
        case 0: blurs.0
        case 1: blurs.1
        case 2: blurs.2
        default: blurs.3
        }
    }

    /// Patterns 0-9: L set and 10-19: G set (left half, with the bar before and the space after);
    /// 20-29: R set (right half, with the space before and the bar after). 9 modules, 1 = bar.
    private static func characterBits(_ pattern: Int) -> [Int] {
        let odd = SymbolTables.oddCharacter(pattern % 10)
        var seven = (0..<7).map { (odd >> (6 - $0)) & 1 }
        if pattern >= 10 { seven = seven.map { 1 - $0 } }
        if pattern >= 10 && pattern < 20 { seven.reverse() }
        return pattern < 20 ? [1] + seven + [0] : [0] + seven + [1]
    }

    /// Guards with their neighbours: start (two quiet modules, 101, a space), middle (bar, 01010,
    /// bar), EAN end (space, 101, two quiet modules), UPC-E end (bar, 010101, two quiet modules).
    private static func guardBits(_ kind: Int) -> [Int] {
        switch kind {
        case 0: [0, 0, 1, 0, 1, 0]
        case 1: [1, 0, 1, 0, 1, 0, 1]
        case 2: [0, 1, 0, 1, 0, 0]
        default: [1, 0, 1, 0, 1, 0, 1, 0, 0]
        }
    }

    private static func guardModules(_ kind: Int) -> Int {
        switch kind {
        case 0, 2: 6
        case 1: 7
        default: 9
        }
    }

    /// Bar coverage (0...1) of modules `bits` blurred by a Gaussian, sampled 4 times per module
    /// from half a module into the first module to half a module into the last.
    private static func render(bits: [Int], count: Int, sigma: Double, into target: UnsafeMutablePointer<Float>,
                               samples: Int) {
        for k in 0..<samples {
            let x = 0.5 + (Double(k) + 0.5) / Double(samplesPerModule)
            var coverage = 0.0
            for (i, bit) in bits.enumerated() where bit == 1 {
                coverage += normalCDF((x - Double(i)) / sigma) - normalCDF((x - Double(i) - 1) / sigma)
            }
            target[k] = Float(coverage)
        }
    }

    /// Standard normal CDF (Abramowitz-Stegun 7.1.26, error below 1.5e-7).
    private static func normalCDF(_ z: Double) -> Double {
        let x = abs(z) / 2.0.squareRoot()
        let t = 1 / (1 + 0.3275911 * x)
        let poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
        let erf = 1 - poly * exponential(-x * x)
        return z >= 0 ? (1 + erf) / 2 : (1 - erf) / 2
    }

    /// e^x for x <= 0, for setting up the templates: halve until small, Taylor series, square back.
    private static func exponential(_ x: Double) -> Double {
        var y = x
        var squarings = 0
        while y < -0.125 {
            y /= 2
            squarings += 1
        }
        var term = 1.0, sum = 1.0
        for n in 1...12 {
            term *= y / Double(n)
            sum += term
        }
        for _ in 0..<squarings { sum *= sum }
        return sum
    }
}
