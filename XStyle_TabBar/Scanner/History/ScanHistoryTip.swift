import SwiftUI
import TipKit

/// Introduces the history button the first time it appears, inline beside
/// it, which shows it only with the button. Shown once: tapping the button,
/// or the tip's own close, retires it.
struct ScanHistoryTip: Tip {
    var title: Text {
        Text("Scan History")
    }

    var message: Text? {
        Text("Every product you scan is kept here.")
    }

    var image: Image? {
        Image(systemName: "clock.arrow.circlepath")
    }
}
