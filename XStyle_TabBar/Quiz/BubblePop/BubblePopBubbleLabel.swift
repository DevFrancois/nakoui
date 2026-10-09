import SwiftUI

/// The word inside a bubble, with the status symbol above it once there is
/// one. A wrong pop flashes red across the bubble each time it's tapped;
/// a flash, not motion, so it plays with Reduce Motion too.
struct BubblePopBubbleLabel: View {
    let word: LocalizedStringResource
    let status: BubblePopBubbleStatus
    /// Nil at accessibility text sizes, where a circle can't hold the word
    /// without breaking or cutting it, so the bubble grows to fit it instead.
    let diameter: Double?
    /// Taps on this bubble as a decoy; each one flashes it.
    let flashes: Int

    /// Keeps the words inside the circle, or gives a fitted word some room.
    private var insets: EdgeInsets {
        if let diameter {
            let inset = diameter * 0.14
            return EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
        }
        return EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    }

    private var wordCount: Int {
        max(1, String(localized: word).split(separator: " ").count)
    }

    var body: some View {
        VStack(spacing: 2) {
            if let symbol = status.symbol {
                Image(systemName: symbol)
                    .font(.callout)
                    .foregroundStyle(status.symbolTint)
                    .accessibilityHidden(true)
            }

            Text(word)
                .font(.footnote)
                .bold()
                .multilineTextAlignment(.center)
                // Shrinks a long word to fit the circle rather than breaking
                // it; a fitted word wraps between words instead. One line per
                // word stops text layout hyphenating single words ("Ha-vanese").
                .lineLimit(diameter == nil ? nil : min(3, wordCount))
                .minimumScaleFactor(diameter == nil ? 1 : 0.5)
                .allowsTightening(true)
                .foregroundStyle(status.isSubdued ? .secondary : .primary)
        }
        .padding(insets)
        .frame(width: diameter.map { CGFloat($0) }, height: diameter.map { CGFloat($0) })
        .frame(minWidth: TopMenuMetrics.minimumTapSize, minHeight: TopMenuMetrics.minimumTapSize)
        .background {
            RoundedRectangle.bubblePop(diameter: diameter)
                .fill(.red)
                .keyframeAnimator(initialValue: 0.0, trigger: flashes) { content, strength in
                    content.opacity(strength)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0.5, duration: 0.05)
                        LinearKeyframe(0, duration: 0.45)
                    }
                }
                .accessibilityHidden(true)
        }
        .contentShape(.bubblePop(diameter: diameter))
    }
}
