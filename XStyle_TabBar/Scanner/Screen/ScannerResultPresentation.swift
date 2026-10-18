import Foundation

/// Separates a pending scan result from the sheet currently on screen. Leaving
/// Scan suspends presentation; only a user's dismissal consumes the result.
struct ScannerResultPresentation {
    private var pendingCode: ScannedCode?
    private var presentedCode: ScannedCode?
    private var visibleID: ScannedCode.ID?
    private var isActive = false
    private var dismissal: Dismissal?

    private enum Dismissal {
        case user(ScannedCode.ID)
        case suspended
    }

    var sheetItem: ScannedCode? {
        get { presentedCode }
        set {
            // SwiftUI writes nil for both a user dismissal and a presentation
            // withdrawn by its owner. A suspension has already recorded why.
            guard newValue == nil, dismissal == nil, let presentedCode else { return }
            dismissal = .user(presentedCode.id)
            self.presentedCode = nil
        }
    }

    mutating func update(isActive: Bool, pendingCode: ScannedCode?) {
        self.isActive = isActive
        self.pendingCode = pendingCode

        if !isActive {
            if presentedCode != nil || dismissal != nil {
                // A request withdrawn before the sheet appears has no later
                // onDismiss callback to wait for.
                dismissal = visibleID != nil || dismissal != nil ? .suspended : nil
                presentedCode = nil
            }
        } else if dismissal == nil {
            // Wait for an old sheet to finish dismissing before presenting a
            // different item, including after a rapid leave and re-entry.
            if let presentedCode, presentedCode.id != pendingCode?.id {
                dismissal = visibleID != nil ? .suspended : nil
                self.presentedCode = visibleID != nil ? nil : pendingCode
            } else {
                presentedCode = pendingCode
            }
        }
    }

    mutating func didPresent(_ id: ScannedCode.ID) {
        visibleID = id
        if !isActive || pendingCode?.id != id {
            dismissal = .suspended
            presentedCode = nil
        }
    }

    /// Returns the consumed result's identity, so a delayed dismissal cannot
    /// clear a newer result that arrived while the old sheet was closing.
    mutating func didDismiss() -> ScannedCode.ID? {
        let reason = dismissal
        dismissal = nil
        visibleID = nil
        var consumedID: ScannedCode.ID?
        if case .user(let id) = reason, pendingCode?.id == id {
            consumedID = id
            pendingCode = nil
        }
        presentedCode = isActive ? pendingCode : nil
        return consumedID
    }
}
