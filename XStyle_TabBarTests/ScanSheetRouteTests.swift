import Testing
@testable import XStyle_TabBar

struct ScanSheetRouteTests {
    private let found = ScannedCode(value: "4006381333931", symbology: .ean13)
    private let picked = ScannedCode(value: "96385074", symbology: .ean8)

    @Test("A found code shows its result and brings the sheet up")
    func foundShowsResult() {
        var state = ScanSheetState()
        #expect(state.found(found) == [.present])
        #expect(state.route == .result(found))
    }

    @Test("A closed result hides the sheet, which keeps showing it as it slides away")
    func resultClosedHides() {
        var state = ScanSheetState()
        #expect(state.resultClosed() == [])

        _ = state.found(found)
        #expect(state.resultClosed() == [.hide])
        #expect(state.route == .result(found))
    }

    @Test("The history replaces a live result, closing it, and leaves the sheet up as the result closes")
    func historyReplacesResult() {
        var state = ScanSheetState()
        _ = state.found(found)

        #expect(state.showHistory() == [.closeResult, .present])
        #expect(state.route == .history)
        #expect(state.resultClosed() == [])
    }

    @Test("The history opens the sheet when nothing shows", arguments: [false, true])
    func historyPresents(afterPicking: Bool) {
        var state = ScanSheetState()
        if afterPicking {
            _ = state.showHistory()
            _ = state.show(picked)
        }
        #expect(state.showHistory() == [.present])
        #expect(state.route == .history)
    }

    @Test("A product picked from the history opens, and back returns to the list")
    func entryAndBack() {
        var state = ScanSheetState()
        _ = state.showHistory()

        #expect(state.show(picked) == [])
        #expect(state.route == .entry(picked))
        #expect(state.back() == [])
        #expect(state.route == .history)
    }

    @Test("Back does nothing away from a picked product")
    func backOnlyFromEntry() {
        var state = ScanSheetState()
        _ = state.found(found)
        _ = state.back()
        #expect(state.route == .result(found))

        _ = state.showHistory()
        _ = state.back()
        #expect(state.route == .history)
    }

    @Test("Close scans again from a result, and hides the history and its products")
    func closeByRoute() {
        var state = ScanSheetState()
        _ = state.found(found)
        #expect(state.close() == [.closeResult])

        _ = state.showHistory()
        #expect(state.close() == [.hide])

        _ = state.show(picked)
        #expect(state.close() == [.hide])
        #expect(state.route == .entry(picked))
    }

    @Test("A scan while the history shows switches to its result")
    func scanOverHistory() {
        var state = ScanSheetState()
        _ = state.showHistory()
        _ = state.show(picked)

        #expect(state.found(found) == [.present])
        #expect(state.route == .result(found))
    }
}
