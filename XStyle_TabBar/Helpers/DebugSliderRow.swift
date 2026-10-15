#if DEBUG
import SwiftUI

/// A labeled debug slider showing its value to two decimals.
struct DebugSliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.bold())
                .frame(width: 62, alignment: .leading)

            Slider(value: $value, in: range)

            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
