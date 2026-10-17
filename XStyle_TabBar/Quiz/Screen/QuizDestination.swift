import SwiftUI

/// Opens the quiz view for a format, pushed from the Quizz tab.
struct QuizDestination: View {
    let kind: QuizKind

    var body: some View {
        // The stack's native push keeps navigation space and quiz content
        // moving together; zoom applied the navigation inset after arrival.
        Group {
            switch kind {
            case .classic:
                ClassicQuizView()
            case .dogOrCat:
                DogOrCatQuizView()
            case .lightning:
                LightningQuizView()
            case .estimate:
                EstimateQuizView()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
    }
}

#Preview("Wide quiz", traits: .fixedLayout(width: 960, height: 700)) {
    NavigationStack {
        QuizDestination(kind: .classic)
    }
}

#Preview("Large text", traits: .fixedLayout(width: 393, height: 852)) {
    NavigationStack {
        QuizDestination(kind: .estimate)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
