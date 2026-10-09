import SwiftUI

/// Stand-in for the article's hero image. Drawn identically in the feed and at
/// the top of the article so the zoom transition reads as the image growing into place.
struct ArticleHeroPlaceholder: View {
    let tint: Color

    var body: some View {
        Rectangle()
            .fill(tint.gradient)
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.white.secondary)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    ArticleHeroPlaceholder(tint: .green)
        .frame(height: 240)
}
