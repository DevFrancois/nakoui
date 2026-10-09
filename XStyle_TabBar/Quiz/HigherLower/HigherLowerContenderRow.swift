import SwiftUI

/// A pet's symbol, name and value side by side, stacking at accessibility
/// text sizes. A nil value waits behind a gently breathing question mark.
struct HigherLowerContenderRow: View {
    let contender: HigherLowerContender
    let stat: HigherLowerStat
    let value: Double?

    @ScaledMetric(relativeTo: .title) private var symbolSize = QuizMetrics.iconSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: QuizMetrics.sectionSpacing))

        layout {
            Image(systemName: contender.symbol)
                .font(.title)
                .foregroundStyle(contender.tint)
                .frame(width: symbolSize, height: symbolSize)
                .background(contender.tint.quaternary, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(contender.name)
                    .font(.headline)

                Group {
                    if let value {
                        HigherLowerStatValue(stat: stat, value: value)
                            .contentTransition(.numericText(value: value))
                    } else {
                        // An invisible digit holds a full line of the value's
                        // text, so the card keeps its height at the reveal.
                        Text(verbatim: "0")
                            .hidden()
                            .overlay(alignment: .leading) {
                                Image(systemName: "questionmark")
                                    .symbolEffect(.breathe)
                                    .accessibilityLabel(Text("Unknown"))
                            }
                    }
                }
                .font(.largeTitle)
                .bold()
                .fontDesign(.rounded)
                .monospacedDigit()
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(spacing: 24) {
        HigherLowerContenderRow(contender: .dog("Beagle", 10), stat: .weight, value: 10)
        HigherLowerContenderRow(contender: .dog("Labrador Retriever", 30), stat: .weight, value: nil)
    }
    .padding()
}
