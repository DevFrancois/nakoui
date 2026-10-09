import SwiftUI

/// Result style A: a system sheet. At a medium detent iOS floats it on Liquid
/// Glass over the live camera, and it can be swiped away as well as closed.
struct ScannedCodeSheet: View {
    let code: ScannedCode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScannedCodeDetails(code: code)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Code Found")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close, action: close)
                    }
                }
        }
        // No presentation background, which would replace the glass, and no
        // dimming, so the found code stays bright above the sheet.
        .presentationDetents([.medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func close() {
        dismiss()
    }
}

#Preview {
    ScannerBackdropPlaceholder()
        .ignoresSafeArea()
        .sheet(item: .constant(ScannedCode.sampleEAN13), content: ScannedCodeSheet.init)
}
