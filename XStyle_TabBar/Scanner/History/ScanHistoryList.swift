import SwiftUI

/// The sheet's history content: the scanned products, newest first, each
/// opening its report. Swipe a row to delete it. A `List`, for its swipe
/// actions, styled like the report's cards.
struct ScanHistoryList: View {
    let history: ScanHistory
    var horizontalPadding: CGFloat
    var bottomPadding: CGFloat
    var onSelect: (ScanHistoryEntry) -> Void

    var body: some View {
        if history.entries.isEmpty {
            ContentUnavailableView(
                "No Scans Yet", systemImage: "clock.arrow.circlepath",
                description: Text("The products you scan show up here.")
            )
            // Its own height, at the top: the content is as tall as the sheet
            // at full, so centered it would sit below the screen at medium.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            List {
                ForEach(history.entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        ScanHistoryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(SheetCardFill.color)
                }
                .onDelete(perform: history.delete)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, horizontalPadding, for: .scrollContent)
            .contentMargins(.top, 4, for: .scrollContent)
            .contentMargins(.bottom, bottomPadding + 24, for: .scrollContent)
            /// As for the report: the sheet never rests under the tab bar.
            .scrollEdgeEffectHidden(true, for: .bottom)
        }
    }
}

/// The history header's Clear button, which asks first: it can't be undone.
struct ScanHistoryClearButton: View {
    let history: ScanHistory
    @State private var isConfirming = false

    var body: some View {
        Button("Clear") {
            isConfirming = true
        }
        .buttonStyle(.glass)
        .disabled(history.entries.isEmpty)
        .confirmationDialog("Clear the scan history?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Clear History", role: .destructive, action: history.clear)
        } message: {
            Text("The products you scanned will no longer be listed.")
        }
    }
}

#if DEBUG
#Preview("History", traits: .fixedLayout(width: 393, height: 650)) {
    ScanHistoryList(
        history: PreviewFixtures.makeHistory(seeded: true),
        horizontalPadding: SheetMetrics.current.scrollContentPadding,
        bottomPadding: PreviewFixtures.canvas.safeAreaBottom,
        onSelect: { _ in }
    )
    .background(Color(.systemGroupedBackground))
}

#Preview("Empty · Dark", traits: .fixedLayout(width: 393, height: 650)) {
    ScanHistoryList(
        history: PreviewFixtures.makeHistory(),
        horizontalPadding: SheetMetrics.current.scrollContentPadding,
        bottomPadding: PreviewFixtures.canvas.safeAreaBottom,
        onSelect: { _ in }
    )
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
#endif
