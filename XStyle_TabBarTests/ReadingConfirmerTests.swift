import BarcodeDecoding
import Testing
@testable import XStyle_TabBar

struct ReadingConfirmerTests {
    /// Read on two scanlines, so one frame confirms it.
    private func reading(_ text: String) -> BarcodeReading {
        let corner = BarcodePoint(x: 0, y: 0)
        return BarcodeReading(
            format: .ean13, text: text, topLeft: corner, topRight: corner,
            bottomRight: corner, bottomLeft: corner, lineCount: 2, moduleSize: 1
        )
    }

    @Test("A result's code stays held back, even after leaving the frame, while others scan")
    func holdsResultCode() {
        var confirmer = ReadingConfirmer()
        confirmer.reset(suppressing: "4006381333931", hold: .indefinitely)
        #expect(confirmer.confirm([reading("4006381333931")], at: 0) == nil)
        #expect(confirmer.confirm([], at: 2) == nil)
        #expect(confirmer.confirm([reading("4006381333931")], at: 5) == nil)
        #expect(confirmer.confirm([reading("5000112637922")], at: 5.1)?.text == "5000112637922")
    }

    @Test("A dismissed code still in view scans again after the hold limit")
    func releasesClosedCodeAfterLimit() {
        var confirmer = ReadingConfirmer()
        confirmer.reset(suppressing: "4006381333931", hold: .untilGone(limit: 1))
        #expect(confirmer.confirm([reading("4006381333931")], at: 0) == nil)
        #expect(confirmer.confirm([reading("4006381333931")], at: 0.5) == nil)
        #expect(confirmer.confirm([reading("4006381333931")], at: 1)?.text == "4006381333931")
    }

    @Test("A dismissed code that leaves the frame scans again once it has been gone a moment")
    func releasesClosedCodeOnceGone() {
        var confirmer = ReadingConfirmer()
        confirmer.reset(suppressing: "4006381333931", hold: .untilGone(limit: .infinity))
        #expect(confirmer.confirm([reading("4006381333931")], at: 0) == nil)
        #expect(confirmer.confirm([], at: 0.3) == nil)
        #expect(confirmer.confirm([], at: 0.7) == nil)
        #expect(confirmer.confirm([reading("4006381333931")], at: 0.8)?.text == "4006381333931")
    }
}
