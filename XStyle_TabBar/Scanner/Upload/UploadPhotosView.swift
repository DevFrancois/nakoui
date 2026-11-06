import SwiftUI

/// A local sample gallery for trying the upload flow before photo picking is wired up.
/// Its owner keeps selections when returning to the camera and clears them on tab exit.
struct UploadPhotosView: View {
    @Binding var selectedPhotos: Set<Int>
    let onBack: () -> Void
    @State private var isShowingConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Back to scanner", systemImage: "chevron.down", action: onBack)
                .buttonStyle(.glass)
                .controlSize(.regular)
                .accessibilityIdentifier("uploadPhotos.back")
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    UploadPhotosHeading()
                    UploadPhotosGrid(selectedPhotos: $selectedPhotos)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("uploadPhotos.grid")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                UploadPhotosFooter(selectedCount: selectedPhotos.count) {
                    isShowingConfirmation = true
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .alert("Demo upload complete", isPresented: $isShowingConfirmation) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("^[\(selectedPhotos.count) sample photo](inflect: true) selected. No files were uploaded.")
        }
    }
}

private struct UploadPhotosHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upload photos")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            Text("Select a few sample photos to try it out.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UploadPhotosGrid: View {
    @Binding var selectedPhotos: Set<Int>
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            // These integers identify the bundled samples, independently of selection and order.
            ForEach(1...7, id: \.self) { id in
                UploadPhotoTile(id: id, isSelected: selectedPhotos.contains(id)) {
                    if selectedPhotos.contains(id) {
                        selectedPhotos.remove(id)
                    } else {
                        selectedPhotos.insert(id)
                    }
                }
            }
        }
    }
}

private struct UploadPhotoTile: View {
    let id: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Rectangle()
                .fill(Color(.secondarySystemGroupedBackground))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image("Pic \(id)")
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : .black.opacity(0.35))
                        .background(.black.opacity(0.25), in: .circle)
                        .padding(9)
                }
                .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sample photo \(id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? Text("Deselect photo") : Text("Select photo"))
        .accessibilityIdentifier("uploadPhotos.sample.\(id)")
    }
}

private struct UploadPhotosFooter: View {
    let selectedCount: Int
    let onUpload: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("^[\(selectedCount) photo](inflect: true) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("uploadPhotos.selectedCount")

            Button(action: onUpload) {
                Label("Upload photos", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(selectedCount == 0)
            .accessibilityIdentifier("uploadPhotos.submit")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color(.systemGroupedBackground))
    }
}

#if DEBUG
#Preview("Upload photos") {
    @Previewable @State var selectedPhotos: Set<Int> = [2, 6]
    UploadPhotosView(selectedPhotos: $selectedPhotos, onBack: {})
}

#Preview("Upload photos · Large text") {
    @Previewable @State var selectedPhotos: Set<Int> = []
    UploadPhotosView(selectedPhotos: $selectedPhotos, onBack: {})
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}
#endif
