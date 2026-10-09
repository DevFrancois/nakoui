import SwiftUI

/// Opens the quiz view for a format, pushed from the Quizz tab.
struct QuizDestination: View {
    let kind: QuizKind
    let namespace: Namespace.ID

    var body: some View {
        switch kind {
        case .classic:
            ClassicQuizView(namespace: namespace)
        case .dogOrCat:
            DogOrCatQuizView(namespace: namespace)
        case .lightning:
            LightningQuizView(namespace: namespace)
        case .estimate:
            EstimateQuizView(namespace: namespace)
        }
    }
}
