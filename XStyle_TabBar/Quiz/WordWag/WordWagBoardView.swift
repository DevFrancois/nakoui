import SwiftUI

/// The answer slots above a tray of scrambled glass tiles. Every tile is
/// one view with one glass effect ID, placed by the board layout, so a tap
/// sends it gliding to its new spot, melting into other glass it passes.
/// A solved word fuses into one piece of glass; with Reduce Motion, tiles
/// fade between spots instead.
struct WordWagBoardView: View {
    let board: WordWagBoard

    @ScaledMetric(relativeTo: .title2) private var tileSize = WordWagMetrics.tileSize
    @Namespace private var glassNamespace
    @AccessibilityFocusState private var focusedTile: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        GlassEffectContainer(spacing: board.status == .solved ? WordWagMetrics.fusedBlend : WordWagMetrics.looseBlend) {
            WordWagBoardLayout(
                letterCount: board.tiles.count,
                preferredTileSize: tileSize,
                minimumTileSize: max(TopMenuMetrics.minimumTapSize, tileSize * WordWagMetrics.smallestTileScale),
                tileSpacing: WordWagMetrics.tileSpacing,
                traySpacing: WordWagMetrics.traySpacing,
                showsTray: !board.isSettled
            ) {
                WordWagGuessSummary(board: board)
                    .layoutValue(key: WordWagSpotKey.self, value: .guess)

                ForEach(board.slots.indices, id: \.self) { index in
                    WordWagSocket(style: slotStyle(at: index))
                        .layoutValue(key: WordWagSpotKey.self, value: .slot(index))
                }

                ForEach(board.trayOrder.indices, id: \.self) { position in
                    WordWagSocket(style: trayStyle(at: position))
                        .layoutValue(key: WordWagSpotKey.self, value: .tray(position))
                }

                ForEach(board.tiles) { tile in
                    let spot = board.spot(of: tile.id)

                    WordWagTileView(tile: tile, board: board, namespace: glassNamespace, focus: $focusedTile) {
                        move(tile.id)
                    }
                    // A new identity per spot under Reduce Motion, so a
                    // move is a fade out and in rather than a glide.
                    .id(reduceMotion ? spot : nil)
                    .transition(.opacity)
                    .layoutValue(key: WordWagSpotKey.self, value: spot)
                }
            }
        }
        .animation(reduceMotion ? .smooth : .bouncy(duration: 0.45, extraBounce: 0.1), value: board.slots)
        .animation(reduceMotion ? .smooth : .bouncy(duration: 0.5), value: board.trayOrder)
        .animation(.smooth, value: board.status)
        .accessibilityElement(children: .contain)
    }

    private func slotStyle(at index: Int) -> WordWagSocketStyle {
        if board.slots[index] != nil {
            .hidden
        } else if index == board.nextSlot {
            .nextSlot
        } else {
            .slot
        }
    }

    private func trayStyle(at position: Int) -> WordWagSocketStyle {
        board.isSettled || board.tile(atTray: position) != nil ? .hidden : .hole
    }

    /// Moves a tile. With VoiceOver, placing a letter moves focus on to the
    /// first letter left in the tray, ready to pick the next one; otherwise
    /// focus stays with the tile it just moved, even when Reduce Motion
    /// rebuilds that tile at its new spot.
    private func move(_ tileID: Int) {
        let isLeavingTray = board.slot(of: tileID) == nil
        board.move(tileID)
        guard voiceOverEnabled else { return }
        focusedTile = isLeavingTray ? board.firstTrayTile ?? tileID : tileID
    }
}
