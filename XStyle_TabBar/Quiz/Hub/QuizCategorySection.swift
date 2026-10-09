import SwiftUI

/// One group of quizzes on the hub, under its heading.
struct QuizCategorySection: View {
    let category: QuizCategory
    let namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(category.title, systemImage: category.symbol)
                .font(.title3)
                .bold()
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)

            ForEach(category.kinds) { kind in
                NavigationLink(value: kind) {
                    QuizCard(kind: kind)
                        .matchedTransitionSource(id: kind, in: namespace) { source in
                            source.clipShape(.rect(cornerRadius: QuizMetrics.cardCornerRadius))
                        }
                }
                .buttonStyle(PassthroughButtonStyle())
            }
        }
    }
}
