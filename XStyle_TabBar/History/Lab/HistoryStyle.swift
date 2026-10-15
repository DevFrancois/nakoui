import SwiftUI

/// The History designs to compare, each opened from the side menu.
/// Temporary: remove once a design is chosen.
enum HistoryStyle: Int, CaseIterable, Identifiable {
    case list = 1
    case timeline
    case cards
    case grid
    case log
    case dayStrip
    case filters
    case resume
    case glass
    case stats

    var id: Self { self }

    var title: String {
        switch self {
        case .list: "List"
        case .timeline: "Timeline"
        case .cards: "Cards"
        case .grid: "Grid"
        case .log: "Log"
        case .dayStrip: "Day strip"
        case .filters: "Filters"
        case .resume: "Resume"
        case .glass: "Glass"
        case .stats: "Stats"
        }
    }

    /// The side menu route that opens this design.
    var route: SidebarRoute {
        SidebarRoute(rawValue: "history\(rawValue)") ?? .settings
    }
}

extension SidebarRoute {
    /// The History design this route opens, if it's one of them.
    var historyStyle: HistoryStyle? {
        guard rawValue.hasPrefix("history"), let number = Int(rawValue.dropFirst("history".count)) else { return nil }
        return HistoryStyle(rawValue: number)
    }

    /// The routes listed in the side menu; the History ones get their own section.
    static let menuRoutes = allCases.filter { $0.historyStyle == nil }
}
