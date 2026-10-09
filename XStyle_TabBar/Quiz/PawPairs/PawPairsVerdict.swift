import SwiftUI

/// How a cleared board went against its par, in words, a symbol and a tint.
struct PawPairsVerdict {
    let moves: Int
    let par: Int
    let pairCount: Int

    /// Within par earns the board's point.
    var isWithinPar: Bool {
        moves <= par
    }

    /// Every move found a pair, without a single miss.
    var isFlawless: Bool {
        moves == pairCount
    }

    var title: LocalizedStringResource {
        if isFlawless {
            "Flawless!"
        } else if isWithinPar {
            "Within par!"
        } else {
            "Board cleared"
        }
    }

    var symbol: String {
        if isFlawless {
            "crown.fill"
        } else if isWithinPar {
            "star.fill"
        } else {
            "flag.checkered"
        }
    }

    var tint: Color {
        isWithinPar ? .green : .orange
    }

    var detail: LocalizedStringResource {
        if isFlawless {
            "Not a single miss in \(moves) moves. Paw-sitively perfect, and a point!"
        } else if moves < par {
            "\(moves) moves, \(par - moves) under par. You earn a point."
        } else if moves == par {
            "\(moves) moves, right on par. You earn a point."
        } else {
            "\(moves) moves, \(moves - par) over par. No point this time, but every pair is yours."
        }
    }
}
