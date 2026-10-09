import SwiftUI

/// "3, 2, 1, Pop!" on a tinted glass bubble that bumps with each beat, over
/// the play area before a round. VoiceOver plays without a count-in, so it's
/// hidden there.
struct BubblePopCountIn: View {
    let value: Int
    let tint: Color

    @ScaledMetric(relativeTo: .largeTitle) private var size = 110.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: LocalizedStringResource {
        value > 0 ? "\(value)" : "Pop!"
    }

    var body: some View {
        Text(label)
            .font(.largeTitle)
            .fontDesign(.rounded)
            .bold()
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(tint.opacity(0.3)), in: .circle)
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : value) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.15, duration: 0.1)
                    SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                }
            }
            .transition(reduceMotion ? .opacity : .scale(scale: 1.4).combined(with: .opacity))
            .accessibilityHidden(true)
    }
}

#Preview {
    BubblePopCountIn(value: 3, tint: .cyan)
        .padding()
        .background(.cyan.gradient)
}
