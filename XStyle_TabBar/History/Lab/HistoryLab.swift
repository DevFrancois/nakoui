import SwiftUI

/// The History screen in the given design.
struct HistoryLab: View {
    let style: HistoryStyle

    var body: some View {
        switch style {
        case .list: HistoryListVariant()
        case .timeline: HistoryTimelineVariant()
        case .cards: HistoryCardsVariant()
        case .grid: HistoryGridVariant()
        case .log: HistoryLogVariant()
        case .dayStrip: HistoryDayStripVariant()
        case .filters: HistoryFiltersVariant()
        case .resume: HistoryResumeVariant()
        case .glass: HistoryGlassVariant()
        case .stats: HistoryStatsVariant()
        }
    }
}
