import Foundation
import Observation

/// One Paw Pairs board in play: the shuffled cards, which are turned up or
/// matched, and the moves so far. A move is two cards turned up. It has no
/// UI and no timing of its own, so it can be unit tested.
@Observable
final class PawPairsGame {
    /// In the order they were dealt, shuffled once per deal.
    private(set) var cards: [PawPairsCard] = []
    /// The cards turned up in the current move, at most two.
    private(set) var turnedUp: [PawPairsCard.ID] = []
    private(set) var matchedPairs: Set<Int> = []
    private(set) var moves = 0
    /// True while a mismatched pair stays up; flips wait until it turns back.
    private(set) var isShowingMiss = false
    /// What the latest flip did, with a count that changes on every flip so
    /// the same result twice in a row still triggers feedback.
    private(set) var lastFlip: PawPairsFlip?
    private(set) var flipCount = 0
    /// Changes with every deal, so views can restart per-board work.
    private(set) var dealCount = 0
    /// How often each card has been part of a miss; each one shakes it.
    private var missCounts: [PawPairsCard.ID: Int] = [:]

    init(board: PawPairsBoard) {
        deal(board)
    }

    var pairCount: Int {
        cards.count / 2
    }

    var isCleared: Bool {
        pairCount > 0 && matchedPairs.count == pairCount
    }

    /// The cards in the board's own order, each animal just before its match.
    var cardsInPairs: [PawPairsCard] {
        cards.sorted { $0.boardIndex < $1.boardIndex }
    }

    /// Lays out a fresh board, shuffled once, all cards face down.
    func deal(_ board: PawPairsBoard) {
        let faces = board.pairs.flatMap { [$0.first, $0.second] }
        cards = faces.indices.shuffled().enumerated().map { position, boardIndex in
            PawPairsCard(
                pairID: boardIndex / 2,
                face: faces[boardIndex],
                number: position + 1,
                boardIndex: boardIndex
            )
        }
        turnedUp = []
        matchedPairs = []
        moves = 0
        isShowingMiss = false
        lastFlip = nil
        missCounts = [:]
        dealCount += 1
    }

    func state(of card: PawPairsCard) -> PawPairsCardState {
        if matchedPairs.contains(card.pairID) {
            .matched
        } else if turnedUp.contains(card.id) {
            isShowingMiss ? .missed : .faceUp
        } else {
            .faceDown
        }
    }

    func missCount(of card: PawPairsCard) -> Int {
        missCounts[card.id, default: 0]
    }

    /// The other card of the same pair.
    func partner(of card: PawPairsCard) -> PawPairsCard? {
        cards.first { $0.pairID == card.pairID && $0.id != card.id }
    }

    /// Turns a face-down card up, and settles the move once two are up.
    /// Returns nil when the flip isn't allowed: the card is already up, a
    /// miss is still showing, or the card isn't on this table, such as one
    /// from the last board tapped as it fades out. Letting that one in would
    /// leave a move that can never settle.
    @discardableResult
    func flip(_ card: PawPairsCard) -> PawPairsFlip? {
        guard !isShowingMiss,
              cards.contains(where: { $0.id == card.id }),
              state(of: card) == .faceDown
        else { return nil }
        turnedUp.append(card.id)

        let result: PawPairsFlip
        if let firstID = turnedUp.first, turnedUp.count == 2,
           let first = cards.first(where: { $0.id == firstID }) {
            moves += 1
            if first.pairID == card.pairID {
                matchedPairs.insert(card.pairID)
                turnedUp = []
                result = .matched
            } else {
                missCounts[first.id, default: 0] += 1
                missCounts[card.id, default: 0] += 1
                isShowingMiss = true
                result = .missed
            }
        } else {
            result = .turned
        }

        lastFlip = result
        flipCount += 1
        return result
    }

    /// Turns a mismatched pair face down again.
    func turnBack() {
        guard isShowingMiss else { return }
        turnedUp = []
        isShowingMiss = false
    }
}
