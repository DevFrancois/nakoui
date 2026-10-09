import Foundation

/// Where one round's pets are. Each starts in a shuffled pool spot that it
/// keeps, moves into the first open slot when placed, and goes back to its
/// spot when its slot is cleared. It has no UI, so it can be unit tested.
struct LineUpBoard {
    let roundID: LineUpRound.ID
    /// The pets in their pool spots, never already in the right order.
    let pool: [LineUpPet]
    /// The pet in each slot, from the top; nil while open.
    private(set) var slots: [LineUpPet.ID?]
    /// The right pet for each slot.
    private let answer: [LineUpPet.ID]

    init(round: LineUpRound) {
        roundID = round.id
        answer = round.pets.map(\.id)
        var shuffled = round.pets.shuffled()
        // Tapping the pool in reading order shouldn't win.
        while shuffled.count > 1, shuffled.map(\.id) == answer {
            shuffled.shuffle()
        }
        pool = shuffled
        slots = Array(repeating: nil, count: round.pets.count)
    }

    /// The first open slot, where the next pet goes.
    var nextSlot: Int? {
        slots.firstIndex(of: nil)
    }

    var isFull: Bool {
        nextSlot == nil
    }

    /// True while no pet has been placed, as when freshly dealt.
    var isEmpty: Bool {
        slots.allSatisfy { $0 == nil }
    }

    /// One point for each pet in its right slot.
    var points: Int {
        slots.indices.count(where: { slots[$0] == answer[$0] })
    }

    func isPlaced(_ pet: LineUpPet) -> Bool {
        slots.contains(pet.id)
    }

    func pet(inSlot slot: Int) -> LineUpPet? {
        guard slots.indices.contains(slot), let id = slots[slot] else { return nil }
        return pool.first { $0.id == id }
    }

    /// Whether the pet in a slot is in its right place, or where it belongs.
    func mark(forSlot slot: Int) -> LineUpMark? {
        guard slots.indices.contains(slot), let id = slots[slot], let rightSlot = answer.firstIndex(of: id) else {
            return nil
        }
        return rightSlot == slot ? .correct : .wrong(belongsAt: rightSlot + 1)
    }

    mutating func place(_ pet: LineUpPet) {
        guard !isPlaced(pet), let nextSlot else { return }
        slots[nextSlot] = pet.id
    }

    mutating func clear(slot: Int) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = nil
    }
}
