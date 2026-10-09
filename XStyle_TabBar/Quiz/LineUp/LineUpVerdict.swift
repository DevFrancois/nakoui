import SwiftUI

/// How a checked line-up went overall, from the pets in their right place.
/// Three of four can't be right without the fourth, so it's all, half, one
/// or none.
enum LineUpVerdict {
    case perfect
    case close
    case warm
    case missed

    init(points: Int, total: Int) {
        self = if points >= total {
            .perfect
        } else if points * 2 >= total {
            .close
        } else if points > 0 {
            .warm
        } else {
            .missed
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .perfect: "Perfect line-up!"
        case .close: "Halfway there"
        case .warm: "Getting warmer"
        case .missed: "All mixed up"
        }
    }

    var symbol: String {
        switch self {
        case .perfect: "checkmark.seal.fill"
        case .close: "circle.lefthalf.filled"
        case .warm: "thermometer.medium"
        case .missed: "shuffle"
        }
    }

    var tint: Color {
        switch self {
        case .perfect: .green
        case .close, .warm: .orange
        case .missed: .red
        }
    }
}
