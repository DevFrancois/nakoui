import SwiftUI

/// The clock, the matches found and the lives left, as glass pieces that
/// merge when they sit close together.
struct BubblePopHUD: View {
    let board: BubblePopBoard
    /// False for an untimed round, as under VoiceOver.
    let showsClock: Bool
    let tint: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One row with the clock leading. At accessibility text sizes the three
    /// pieces outgrow a phone's width, so they wrap into centered rows.
    private var layout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(BubblePopLayout(arrangement: .grid, spacing: 12))
        } else {
            AnyLayout(HStackLayout(spacing: 12))
        }
    }

    var body: some View {
        GlassEffectContainer {
            layout {
                if showsClock {
                    BubblePopCountdown(start: board.startDate, stoppedAt: board.stopDate, tint: tint)
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }

                BubblePopFoundCounter(found: board.foundCount, total: board.matchCount, tint: tint)

                BubblePopLives(lives: board.livesLeft, total: BubblePopMetrics.lives, tint: tint)
            }
        }
    }
}
