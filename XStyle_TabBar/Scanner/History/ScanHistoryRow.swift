import SwiftUI

/// One product in the history: its code first, as every product shows the
/// same illustrative report until products are looked up; then how and when
/// it was last scanned, kept current while it shows, and how many times.
struct ScanHistoryRow: View {
    let entry: ScanHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.value)
                    .font(.body.monospacedDigit().weight(.medium))
                    .speechSpellsOutCharacters()

                Text("\(Text(entry.symbology.title)) · \(Text(.currentDate, format: .reference(to: entry.lastScanned)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if entry.count > 1 {
                Text("×\(entry.count)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Scanned ^[\(entry.count) time](inflect: true)"))
            }

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }
}

#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    let history = PreviewFixtures.makeHistory(seeded: true)
    VStack {
        ForEach(history.entries) { entry in
            ScanHistoryRow(entry: entry)
        }
    }
    .padding()
}
#endif
