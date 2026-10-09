import CoreGraphics

/// Where everything sits on a board of a given width: the answer slots in
/// rows on top, the tray in matching rows below. Tiles are square, as large
/// as preferred but no wider than fits, and wrap onto more rows only when a
/// single row would shrink them below the smallest allowed size.
struct WordWagBoardGrid {
    let width: Double
    let letterCount: Int
    let tileSize: Double
    let columns: Int
    let rows: Int
    let tileSpacing: Double
    let traySpacing: Double
    /// False once the word is settled and the empty tray folds away.
    let showsTray: Bool

    init(
        width: Double,
        letterCount: Int,
        preferredTileSize: Double,
        minimumTileSize: Double,
        tileSpacing: Double,
        traySpacing: Double,
        showsTray: Bool
    ) {
        let count = max(letterCount, 1)
        let width = max(width, 0)

        func fittingSize(columns: Int) -> Double {
            (width - Double(columns - 1) * tileSpacing) / Double(columns)
        }

        var rows = 1
        var columns = count
        while columns > 1, fittingSize(columns: columns) < minimumTileSize {
            rows += 1
            columns = (count + rows - 1) / rows
        }

        self.width = width
        self.letterCount = count
        self.columns = columns
        self.rows = (count + columns - 1) / columns
        self.tileSize = max(min(preferredTileSize, fittingSize(columns: columns)), 0)
        self.tileSpacing = tileSpacing
        self.traySpacing = traySpacing
        self.showsTray = showsTray
    }

    /// The height of the slots, or of the tray.
    var sectionHeight: Double {
        Double(rows) * tileSize + Double(rows - 1) * tileSpacing
    }

    var size: CGSize {
        let height = showsTray ? sectionHeight * 2 + traySpacing : sectionHeight
        return CGSize(width: width, height: height)
    }

    func frame(for spot: WordWagSpot) -> CGRect {
        switch spot {
        case .guess:
            CGRect(x: rowOrigin(row: 0), y: 0, width: rowWidth(row: 0), height: sectionHeight)
        case .slot(let index):
            tileFrame(at: index, top: 0)
        case .tray(let position):
            tileFrame(at: position, top: sectionHeight + traySpacing)
        }
    }

    private func tileFrame(at index: Int, top: Double) -> CGRect {
        let row = index / columns
        let column = index % columns
        return CGRect(
            x: rowOrigin(row: row) + Double(column) * (tileSize + tileSpacing),
            y: top + Double(row) * (tileSize + tileSpacing),
            width: tileSize,
            height: tileSize
        )
    }

    /// A short last row is centered under the full ones.
    private func rowOrigin(row: Int) -> Double {
        (width - rowWidth(row: row)) / 2
    }

    private func rowWidth(row: Int) -> Double {
        let count = max(min(columns, letterCount - row * columns), 0)
        return Double(count) * tileSize + Double(max(count - 1, 0)) * tileSpacing
    }
}
