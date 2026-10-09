import SwiftUI

/// What a scan found: the barcode type and its digits. Shared by the sheet
/// and the card.
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
                .lineLimit(1)
                .minimumScaleFactor(0.5)
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
