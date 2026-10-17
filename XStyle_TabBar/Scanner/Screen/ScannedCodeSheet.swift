import SwiftUI

/// A scrollable system sheet that can expand when the window or text size
/// needs more space. At a medium detent it floats over the found code.
struct ScannedCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let code: ScannedCode

    var body: some View {
        NavigationStack {
            ScrollView {
                ScannedCodeDetails(code: code)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .scrollBounceBehavior(.basedOnSize)
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
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
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
