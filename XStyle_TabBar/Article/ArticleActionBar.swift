import SwiftUI

/// Like and bookmark controls shown under the article title, as Liquid Glass buttons.
struct ArticleActionBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var isLiked: Bool
    @Binding var isBookmarked: Bool

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading))
            : AnyLayout(HStackLayout())

        GlassEffectContainer {
            layout {
                Button("Like", systemImage: "heart", action: toggleLike)
                    .symbolVariant(isLiked ? .fill : .none)
                    .accessibilityAddTraits(isLiked ? .isSelected : [])
                    .tint(isLiked ? .pink : .primary)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isLiked)
                    .sensoryFeedback(.impact(weight: .light), trigger: isLiked)

                Button("Bookmark", systemImage: "bookmark", action: toggleBookmark)
                    .symbolVariant(isBookmarked ? .fill : .none)
                    .accessibilityAddTraits(isBookmarked ? .isSelected : [])
                    .tint(isBookmarked ? .orange : .primary)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isBookmarked)
                    .sensoryFeedback(.selection, trigger: isBookmarked)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
    }

    private func toggleLike() {
        isLiked.toggle()
    }

    private func toggleBookmark() {
        isBookmarked.toggle()
    }
}

#Preview {
    @Previewable @State var isLiked = false
    @Previewable @State var isBookmarked = true

    ArticleActionBar(isLiked: $isLiked, isBookmarked: $isBookmarked)
}
