#if DEBUG
import SwiftUI

/// The tab bar's motion, effect by effect. It sits on the Profile page, right
/// above the bar, so a change can be felt at once. Compiled into debug builds
/// only, so it never ships.
struct GlassTabBarDebugControls: View {
    @StoredGlassTabBarMotion private var motion: GlassTabBarMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DebugPanelHeader(title: "Tab bar motion", systemImage: "dock.rectangle", isDefault: motion == .calm) {
                motion = .calm
            }

            Button("Use the original motion", systemImage: "clock.arrow.circlepath") {
                motion = .original
            }
            .font(.caption.bold())
            .disabled(motion == .original)

            EffectDials(title: "Grow while held", isOn: $motion.grows) {
                DebugSliderRow(title: "Grow", value: $motion.grow, range: GlassTabBarMotion.growRange)
                DebugSliderRow(title: "Settle time", value: $motion.settleDuration,
                               range: GlassTabBarMotion.settleDurationRange)
            }

            EffectDials(title: "Wobble after a tap", isOn: $motion.wobbles) {
                DebugSliderRow(title: "Damping", value: $motion.wobbleDamping,
                               range: GlassTabBarMotion.wobbleDampingRange)
            }
            // Without the grow there is nothing to settle, so nothing wobbles.
            .disabled(!motion.grows)

            EffectDials(title: "Highlight slides between tabs", isOn: $motion.highlightSlides) {
                DebugSliderRow(title: "Duration", value: $motion.highlightDuration,
                               range: GlassTabBarMotion.highlightDurationRange)
                DebugSliderRow(title: "Bounce", value: $motion.highlightBounce,
                               range: GlassTabBarMotion.highlightBounceRange)
            }

            EffectDials(title: "Bounce coming back", isOn: $motion.bounces) {
                DebugSliderRow(title: "Bounce", value: $motion.bounce, range: GlassTabBarMotion.bounceRange)
            }
        }
    }
}

/// One effect's switch, with its dials greyed out while it's off.
private struct EffectDials<Dials: View>: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    @ViewBuilder let dials: Dials

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            Toggle(title, isOn: $isOn)
                .font(.subheadline.bold())

            dials
                .disabled(!isOn)
        }
    }
}

#Preview {
    ScrollView {
        GlassTabBarDebugControls()
            .padding()
    }
}
#endif
