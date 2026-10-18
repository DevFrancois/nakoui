import Testing
@testable import XStyle_TabBar

@MainActor
struct ScannerResultPresentationTests {
    @Test("An asynchronous result stays pending until Scan becomes active")
    func defersInactiveResult() {
        let code = ScannedCode.sampleEAN13
        var presentation = ScannerResultPresentation()
        presentation.update(isActive: false, pendingCode: code)
        #expect(presentation.sheetItem == nil)
        presentation.sheetItem = nil
        #expect(presentation.didDismiss() == nil)
        presentation.update(isActive: true, pendingCode: code)
        #expect(presentation.sheetItem == code)
    }

    @Test("Leaving Scan withdraws the sheet without consuming its pending result")
    func suspendsWithoutConsuming() {
        let code = ScannedCode.sampleEAN13
        var presentation = ScannerResultPresentation()
        presentation.update(isActive: true, pendingCode: code)
        presentation.didPresent(code.id)
        presentation.update(isActive: false, pendingCode: code)
        #expect(presentation.sheetItem == nil)
        presentation.sheetItem = nil
        #expect(presentation.didDismiss() == nil)
        presentation.update(isActive: true, pendingCode: code)
        #expect(presentation.sheetItem == code)
    }

    @Test("Rapid re-entry waits for the suspended sheet to finish dismissing")
    func resumesAfterDismissal() {
        let code = ScannedCode.sampleEAN13
        var presentation = ScannerResultPresentation()
        presentation.update(isActive: true, pendingCode: code)
        presentation.didPresent(code.id)
        presentation.update(isActive: false, pendingCode: code)
        presentation.update(isActive: true, pendingCode: code)
        #expect(presentation.sheetItem == nil)
        presentation.sheetItem = nil
        #expect(presentation.didDismiss() == nil)
        #expect(presentation.sheetItem == code)
    }

    @Test("A user dismissal consumes the matching scan once")
    func consumesUserDismissalOnce() {
        let code = ScannedCode.sampleEAN13
        var presentation = ScannerResultPresentation()
        presentation.update(isActive: true, pendingCode: code)
        presentation.sheetItem = nil
        #expect(presentation.didDismiss() == code.id)
        #expect(presentation.sheetItem == nil)
        #expect(presentation.didDismiss() == nil)
    }

    @Test("A delayed dismissal cannot consume a newer result")
    func preservesNewerResult() {
        let first = ScannedCode.sampleEAN13
        let second = ScannedCode(value: "96385074", symbology: .ean8)
        var presentation = ScannerResultPresentation()
        presentation.update(isActive: true, pendingCode: first)
        presentation.sheetItem = nil
        presentation.update(isActive: true, pendingCode: second)
        #expect(presentation.didDismiss() == nil)
        #expect(presentation.sheetItem == second)
    }

    @Test("Deactivation also preserves a result when a nil write arrives first")
    func deactivationDuringDismissalPreservesResult() {
        let code = ScannedCode.sampleEAN13
        var presentation = ScannerResultPresentation()
        presentation.update(isActive: true, pendingCode: code)
        presentation.sheetItem = nil
        presentation.update(isActive: false, pendingCode: code)
        #expect(presentation.didDismiss() == nil)
        presentation.update(isActive: true, pendingCode: code)
        #expect(presentation.sheetItem == code)
    }

    @Test("Repeated active updates keep the same presentation")
    func identicalUpdatesKeepPresentation() {
        let code = ScannedCode.sampleEAN13
        var presentation = ScannerResultPresentation()
        presentation.update(isActive: true, pendingCode: code)
        presentation.update(isActive: true, pendingCode: code)
        #expect(presentation.sheetItem == code)
        presentation.sheetItem = nil
        presentation.update(isActive: true, pendingCode: code)
        #expect(presentation.sheetItem == nil)
        #expect(presentation.didDismiss() == code.id)
    }

    @Test("Withdrawing a request before appearance does not wait for a nonexistent dismissal")
    func immediatelyWithdrawnRequestCanResume() {
        let code = ScannedCode.sampleEAN13
        var presentation = ScannerResultPresentation()
        presentation.update(isActive: true, pendingCode: code)
        presentation.update(isActive: false, pendingCode: code)
        presentation.update(isActive: true, pendingCode: code)
        #expect(presentation.sheetItem == code)
    }
}
