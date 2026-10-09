import SwiftUI

/// One letter on interactive glass. Tapping it moves it between the tray
/// and the answer slots; the board animates the trip. A wrong guess shakes
/// it, and a solve sends it hopping and wagging in a wave along the word.
struct WordWagTileView: View {
    let tile: WordWagTile
    let board: WordWagBoard
    let namespace: Namespace.ID
    let focus: AccessibilityFocusState<Int?>.Binding
    let move: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var spot: WordWagSpot {
        board.spot(of: tile.id)
    }

    private var state: WordWagTileState {
        guard board.slot(of: tile.id) != nil else { return .tray }
        return switch board.status {
        case .playing: .placed
        case .wrong: .wrong
        case .solved: .correct
        case .revealed: .revealed
        }
    }

    /// Each tile waits for the last one to land, then for its neighbors to
    /// its left, so the hop ripples along the word.
    private var hopDelay: Double {
        guard case .slot(let index) = spot else { return WordWagMetrics.landingPause }
        return WordWagMetrics.landingPause + Double(index) * WordWagMetrics.hopStagger
    }

    var body: some View {
        Button(action: move) {
            Text(tile.letter)
                .font(.title2)
                .bold()
                .fontDesign(.rounded)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Inside the label, so the glass draws it crisply on top.
                .overlay(alignment: .topTrailing) {
                    if differentiateWithoutColor, let symbol = state.symbol {
                        Image(systemName: symbol)
                            .font(.caption)
                            .bold()
                            .foregroundStyle(state.symbolTint)
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect(cornerRadius: WordWagMetrics.tileCornerRadius))
        }
        .buttonStyle(PassthroughButtonStyle())
        .disabled(board.isSettled)
        .glassEffect(state.glass, in: .rect(cornerRadius: WordWagMetrics.tileCornerRadius))
        // With Reduce Motion, a moved tile is a new view at its new spot.
        // Without a shared ID its glass fades out and back in, rather than
        // morphing across the board.
        .glassEffectID(reduceMotion ? nil : tile.id, in: namespace)
        .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
        .wordWagTileMotion(wrongGuesses: board.wrongGuesses, solves: board.solves, hopDelay: hopDelay)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(state.accessibilityValue))
        .accessibilityHint(Text(accessibilityHint))
        .accessibilitySortPriority(spot.accessibilitySortPriority)
        .accessibilityFocused(focus, equals: tile.id)
    }

    /// The letter, spelled out so "A" isn't read as a word, then where it is.
    private var accessibilityLabel: Text {
        let letter = Text(tile.letter).speechSpellsOutCharacters()
        return switch spot {
        case .slot(let index): Text("\(letter), slot \(index + 1)")
        case .tray(let position): Text("\(letter), tray tile \(position + 1)")
        case .guess: letter
        }
    }

    private var accessibilityHint: LocalizedStringResource {
        if board.isSettled {
            ""
        } else if board.slot(of: tile.id) != nil {
            "Sends this letter back to the tray."
        } else {
            "Adds this letter to the next empty slot."
        }
    }
}
