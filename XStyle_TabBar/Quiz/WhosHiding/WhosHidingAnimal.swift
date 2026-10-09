import SwiftUI

/// The hidden animal as a large symbol: blurred, tilted and shrunk while the
/// glass is frosted, settling as it clears. It breathes while hidden, then
/// bounces when named or wiggles when missed. With Reduce Motion on, only
/// the blur changes.
struct WhosHidingAnimal: View {
    let symbol: String
    let tint: Color
    let stage: WhosHidingStage
    let outcome: QuizOutcome?
    let size: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .foregroundStyle(tint.gradient)
            .symbolEffect(.breathe, isActive: outcome == nil)
            .symbolEffect(.bounce.up.byLayer, options: .repeat(.periodic(2)), value: outcome == .correct)
            .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(2)), value: outcome == .wrong)
            .symbolEffectsRemoved(reduceMotion)
            .scaleEffect(reduceMotion ? 1 : stage.scale)
            .rotationEffect(.degrees(reduceMotion ? 0 : stage.tilt))
            .blur(radius: stage.blurFraction * size)
            .animation(animation, value: stage)
            .accessibilityHidden(true)
    }

    private var animation: Animation {
        if reduceMotion {
            .easeInOut(duration: 0.5)
        } else if outcome != nil {
            // An answer clears the glass at once.
            .snappy
        } else {
            .spring(duration: 0.9, bounce: 0.4)
        }
    }
}

#Preview {
    HStack(spacing: 32) {
        WhosHidingAnimal(symbol: "hare.fill", tint: .pink, stage: .frosted, outcome: nil, size: 80)
        WhosHidingAnimal(symbol: "hare.fill", tint: .pink, stage: .clear, outcome: .correct, size: 80)
    }
    .padding()
}
