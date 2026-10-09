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
        case .bubblePop:
            BubblePopQuizView(namespace: namespace)
        case .pawPairs:
            PawPairsQuizView(namespace: namespace)
        case .mysteryPet:
            MysteryPetQuizView(namespace: namespace)
        case .wordWag:
            WordWagQuizView(namespace: namespace)
        case .higherLower:
            HigherLowerQuizView(namespace: namespace)
        case .petMatch:
            PetMatchQuizView(namespace: namespace)
        case .lineUp:
            LineUpQuizView(namespace: namespace)
        case .whosHiding:
            WhosHidingQuizView(namespace: namespace)
        }
    }
}
