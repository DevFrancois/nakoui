import SwiftUI
import TipKit

/// Introduces the history button the first time it appears. Shown once:
/// tapping the button, or the tip's own close, retires it.
struct ScanHistoryTip: Tip {
    /// Whether the history button shows, set by the scanner on every launch.
    @Parameter(.transient)
    static var isButtonShown: Bool = false

    /// Waits for the button. TipKit presents a tip as it turns eligible, so
    /// one reset while the button was away shows once the button is back.
    var rules: [Rule] {
        #Rule(Self.$isButtonShown) { $0 == true }
    }

    var title: Text {
        Text("Scan History")
    }

    var message: Text? {
        Text("Every product you scan is kept here, to look at again.")
    }

    var image: Image? {
        Image(systemName: "clock.arrow.circlepath")
    }
}
