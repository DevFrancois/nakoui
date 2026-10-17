#if DEBUG
import SwiftUI

/// A labeled debug slider showing its value to two decimals.
struct DebugSliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.bold())

                Spacer(minLength: 8)

                Text(value, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Slider(value: $value, in: range) {
                Text(title)
            }
            .accessibilityValue(Text(value, format: .number.precision(.fractionLength(2))))
        }
    }
}
#endif
