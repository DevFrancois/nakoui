/// The template fit of one or more guards: summed residual, samples and contrast.
struct GuardFit {
    var residual: Float
    var samples: Int
    var contrast: Float
    var count: Int

    static func + (a: GuardFit, b: GuardFit) -> GuardFit {
        GuardFit(residual: a.residual + b.residual, samples: a.samples + b.samples,
                 contrast: a.contrast + b.contrast, count: a.count + b.count)
    }
}
