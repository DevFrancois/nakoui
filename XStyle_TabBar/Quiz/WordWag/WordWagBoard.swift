import Observation

/// One word's tiles as the player moves them: where each sits in the tray,
/// which slots hold which tiles, and whether the word is settled. Each word
/// gets a fresh board, so a word sliding out keeps its own letters. It
/// knows nothing of scores or UI, so it can be unit tested.
@Observable
final class WordWagBoard {
    let puzzle: WordWagPuzzle
    let tiles: [WordWagTile]
    /// The tile ID at each tray position. A tile out in a slot leaves its
    /// position empty, and goes back there when it returns.
    private(set) var trayOrder: [Int] = []
    /// The tile ID in each answer slot, or nil while it's empty.
    private(set) var slots: [Int?] = []
    private(set) var status = WordWagStatus.playing
    private(set) var usedHint = false

    // Counters that only go up, as triggers for haptics and animations.
    private(set) var moves = 0
    private(set) var shuffles = 0
    private(set) var wrongGuesses = 0
    private(set) var solves = 0

    /// Deals the word, scrambled.
    init(puzzle: WordWagPuzzle) {
        self.puzzle = puzzle
        tiles = puzzle.tiles
        slots = Array(repeating: nil, count: tiles.count)
        trayOrder = scrambledOrder()
    }

    var isSettled: Bool {
        status == .solved || status == .revealed
    }

    /// What solving the word is worth now, or what it earned once settled.
    var points: Int {
        if status == .revealed {
            0
        } else if usedHint {
            WordWagRounds.pointsPerWord - WordWagRounds.hintCost
        } else {
            WordWagRounds.pointsPerWord
        }
    }

    /// The slot the next tray tile goes to.
    var nextSlot: Int? {
        slots.firstIndex(of: nil)
    }

    /// True once every slot is filled, which leaves the tray empty.
    var isTrayEmpty: Bool {
        nextSlot == nil
    }

    /// The first tile still resting in the tray, in tray order.
    var firstTrayTile: Int? {
        trayOrder.first { slot(of: $0) == nil }
    }

    func slot(of tileID: Int) -> Int? {
        slots.firstIndex(of: tileID)
    }

    /// The tile resting at a tray position, if it isn't out in a slot.
    func tile(atTray position: Int) -> Int? {
        let tileID = trayOrder[position]
        return slot(of: tileID) == nil ? tileID : nil
    }

    func spot(of tileID: Int) -> WordWagSpot {
        if let index = slot(of: tileID) {
            .slot(index)
        } else {
            .tray(trayOrder.firstIndex(of: tileID) ?? 0)
        }
    }

    /// Sends a tray tile to the next empty slot, or a placed tile back to
    /// the tray. Filling the last slot checks the guess.
    func move(_ tileID: Int) {
        guard !isSettled, tiles.indices.contains(tileID) else { return }
        if let index = slot(of: tileID) {
            slots[index] = nil
            status = .playing
        } else if let index = nextSlot {
            slots[index] = tileID
            checkGuess()
        } else {
            return
        }
        moves += 1
    }

    /// Mixes up the tiles left in the tray, retrying a few times so the tap
    /// always visibly changes something.
    func shuffle() {
        guard !isSettled, !isTrayEmpty else { return }
        let before = trayLetters(in: trayOrder)
        var order = trayOrder
        for _ in 0..<8 {
            order.shuffle()
            if trayLetters(in: order) != before {
                break
            }
        }
        trayOrder = order
        shuffles += 1
    }

    /// Sends every placed tile back to the tray.
    func clear() {
        guard !isSettled, slots.contains(where: { $0 != nil }) else { return }
        slots = Array(repeating: nil, count: tiles.count)
        status = .playing
        moves += 1
    }

    func useHint() {
        guard !isSettled, !usedHint else { return }
        usedHint = true
    }

    /// Gives up: spells the breed out, leaving any letter already in its
    /// right slot where it is, so only the others move.
    func reveal() {
        guard !isSettled else { return }
        let letters = puzzle.word.map(String.init)
        var answer: [Int?] = slots.indices.map { index in
            slots[index].flatMap { tiles[$0].letter == letters[index] ? $0 : nil }
        }
        var spare = tiles.map(\.id).filter { !answer.contains($0) }
        for index in answer.indices where answer[index] == nil {
            if let pick = spare.firstIndex(where: { tiles[$0].letter == letters[index] }) {
                answer[index] = spare.remove(at: pick)
            }
        }
        slots = answer
        status = .revealed
    }

    private func checkGuess() {
        guard isTrayEmpty else { return }
        let guess = slots.compactMap { $0 }.map { tiles[$0].letter }.joined()
        if guess == puzzle.word {
            status = .solved
            solves += 1
        } else {
            status = .wrong
            wrongGuesses += 1
        }
    }

    /// A tray order that never deals the letters already spelling the word.
    /// Compares letters rather than tiles, since swapping two identical
    /// letters would still spell it.
    private func scrambledOrder() -> [Int] {
        var order = tiles.map(\.id)
        // A word of one repeated letter can't be scrambled.
        guard Set(puzzle.word).count > 1 else { return order }
        repeat {
            order.shuffle()
        } while order.map({ tiles[$0].letter }).joined() == puzzle.word
        return order
    }

    /// What the tray shows for an order: each resting tile's letter, or nil
    /// for an empty position.
    private func trayLetters(in order: [Int]) -> [String?] {
        order.map { slot(of: $0) == nil ? tiles[$0].letter : nil }
    }
}
