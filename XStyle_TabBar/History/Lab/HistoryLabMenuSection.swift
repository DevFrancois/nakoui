import SwiftUI

/// The side menu's History entry: ten numbered chips, one per design.
/// Temporary.
struct HistoryLabMenuSection: View {
    let onSelect: (SidebarRoute) -> Void
    @ScaledMetric(relativeTo: .callout) private var minimumButtonWidth = 44.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                Text("History")
                    .font(.title3)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumButtonWidth), spacing: 6)], spacing: 6) {
                ForEach(HistoryStyle.allCases) { style in
                    Button {
                        onSelect(style.route)
                    } label: {
                        Text(style.rawValue, format: .number)
                            .font(.callout.bold().monospacedDigit())
                            .foregroundStyle(Color.primary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(.fill.tertiary, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("History, \(style.title)")
                    .accessibilityIdentifier(style.route.accessibilityID)
                }
            }
        }
    }
}
