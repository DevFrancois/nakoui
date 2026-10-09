import SwiftUI

/// One word on a glass bubble. A match pops: its glass bursts into sparkles
/// and is gone. A decoy shakes, flashes and stays, tinted red. Held still, a
/// popped bubble keeps its place with a checkmark, so VoiceOver doesn't lose
/// it, and a decoy flashes without shaking.
struct BubblePopBubble: View {
    let item: BubblePopItem
    let status: BubblePopBubbleStatus
    /// Nil at accessibility text sizes, where the bubble grows to fit its
    /// word rather than squeezing it into a circle.
    let diameter: Double?
    /// Whether bubbles hold still, for Reduce Motion, VoiceOver or large text.
    let isStatic: Bool
    /// Whether the round is in play, so the bubble takes taps.
    let isLive: Bool
    /// Taps on this bubble as a decoy; each one shakes it.
    let shakes: Int
    let namespace: Namespace.ID
    let action: () -> Void

    private var showsBubble: Bool {
        switch status {
        case .waiting: false
        case .popped: isStatic
        default: true
        }
    }

    /// Blows in small and pops out big, or just fades when held still.
    private var transition: AnyTransition {
        if isStatic {
            .opacity
        } else {
            .asymmetric(
                insertion: .scale(scale: 0.3).combined(with: .opacity),
                removal: .scale(scale: 1.6).combined(with: .opacity)
            )
        }
    }

    var body: some View {
        ZStack {
            if diameter == nil {
                // A bubble that fits its word has no fixed size, so this
                // keeps its room in the grid while it waits to blow in.
                BubblePopBubbleLabel(word: item.word.text, status: .floating, diameter: nil, flashes: 0)
                    .hidden()
                    .accessibilityHidden(true)
            }

            if showsBubble {
                Button(action: action) {
                    BubblePopBubbleLabel(word: item.word.text, status: status, diameter: diameter, flashes: shakes)
                }
                .buttonStyle(PassthroughButtonStyle())
                .glassEffect(
                    status.glass(tint: item.tint, isInteractive: isLive && status.isTappable),
                    in: .bubblePop(diameter: diameter)
                )
                .glassEffectID(item.id, in: namespace)
                .glassEffectTransition(.materialize)
                .keyframeAnimator(initialValue: 0.0, trigger: isStatic ? 0 : shakes) { content, wobble in
                    content
                        .rotationEffect(.degrees(wobble))
                        .offset(x: wobble * 0.8)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-10, duration: 0.06)
                        LinearKeyframe(10, duration: 0.08)
                        LinearKeyframe(-7, duration: 0.08)
                        LinearKeyframe(5, duration: 0.08)
                        SpringKeyframe(0, duration: 0.2)
                    }
                }
                .disabled(!isLive || !status.isTappable)
                .accessibilityValue(Text(status.accessibilityValue))
                .transition(transition)
            }

            if status == .popped && !isStatic, let diameter {
                BubblePopSparkles(tint: item.tint, radius: diameter * 0.75)
            }
        }
        .frame(width: diameter.map { CGFloat($0) }, height: diameter.map { CGFloat($0) })
        // Staggers the bubbles as they blow in after "Pop!".
        .animation(isStatic ? .smooth : .bouncy.delay(item.entranceDelay), value: status == .waiting)
    }
}
