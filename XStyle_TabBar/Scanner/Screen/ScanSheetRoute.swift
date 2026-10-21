/// What the Scan tab's sheet shows.
nonisolated enum ScanSheetRoute: Equatable, Sendable {
    /// A code just found, the live result.
    case result(ScannedCode)
    /// The scan history list.
    case history
    /// A product from the history, with a way back to the list.
    case entry(ScannedCode)
}

/// What the view does for a route change.
nonisolated enum ScanSheetEffect: Equatable, Sendable {
    /// Bring the sheet up, if it's hidden.
    case present
    /// Send the sheet below the screen.
    case hide
    /// Close the live result, which scans again.
    case closeResult
}

/// The sheet's route and how it changes. The route stays while the sheet
/// slides away, so its content doesn't vanish mid-slide.
nonisolated struct ScanSheetState: Equatable, Sendable {
    private(set) var route: ScanSheetRoute?

    /// A code was found: its result replaces whatever shows.
    mutating func found(_ code: ScannedCode) -> [ScanSheetEffect] {
        route = .result(code)
        return [.present]
    }

    /// The live result closed. The sheet goes away only if it was showing it:
    /// opening the history closes the result too.
    mutating func resultClosed() -> [ScanSheetEffect] {
        guard case .result = route else { return [] }
        return [.hide]
    }

    /// The history button: the list replaces a live result, which closes, as
    /// it's now at the top of the history.
    mutating func showHistory() -> [ScanSheetEffect] {
        let wasResult = if case .result = route { true } else { false }
        route = .history
        return wasResult ? [.closeResult, .present] : [.present]
    }

    /// A product picked from the history.
    mutating func show(_ code: ScannedCode) -> [ScanSheetEffect] {
        route = .entry(code)
        return []
    }

    /// From a product back to the history list.
    mutating func back() -> [ScanSheetEffect] {
        if case .entry = route {
            route = .history
        }
        return []
    }

    /// The close button: a live result closes, scanning again; the history
    /// and its products just go away.
    func close() -> [ScanSheetEffect] {
        if case .result = route {
            return [.closeResult]
        }
        return [.hide]
    }
}
