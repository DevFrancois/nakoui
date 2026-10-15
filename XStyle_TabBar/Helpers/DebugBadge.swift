#if DEBUG
import SwiftUI

/// The orange tag marking a side menu control as debug-only.
struct DebugBadge: View {
    var body: some View {
        Text("Debug")
            .font(.caption.bold())
            .textCase(.uppercase)
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.quaternary, in: .capsule)
    }
}
#endif
