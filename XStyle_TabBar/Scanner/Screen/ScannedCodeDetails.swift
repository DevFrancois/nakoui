import SwiftUI

/// What a scan found: the barcode type and its digits, in the result pane.
struct ScannedCodeDetails: View {
    let code: ScannedCode

    var body: some View {
        VStack(spacing: 8) {
            Label {
                Text(code.symbology.title)
            } icon: {
                Image(systemName: "barcode")
            }
            .font(.headline)
            .foregroundStyle(.secondary)

            Text(code.value)
                .font(.largeTitle.monospaced())
                .bold()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // Digit by digit, not as one huge number.
                .speechSpellsOutCharacters()
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScannedCodeDetails(code: .sampleEAN13)
}
