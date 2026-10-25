import AVFoundation
import Testing
@testable import XStyle_TabBar

@MainActor
struct ScanSheetRequestTests {
    @Test("A request waits while the Scan tab is hidden, then is taken once it shows")
    func requestWaitsForScanTab() {
        let model = ScannerModel()
        #expect(model.takeSheetRequest(isActive: true) == nil)
        model.requestSheet(.history)
        #expect(model.takeSheetRequest(isActive: false) == nil)
        #expect(model.sheetRequest?.route == .history)
        #expect(model.takeSheetRequest(isActive: true) == .history)
        #expect(model.sheetRequest == nil)
        #expect(model.takeSheetRequest(isActive: true) == nil)
    }

    @Test("A repeated request is new, and a later one replaces one still waiting")
    func repeatsAndReplacements() throws {
        let model = ScannerModel()
        model.requestSheet(.camera)
        let first = try #require(model.sheetRequest)
        #expect(model.takeSheetRequest(isActive: true) == .camera)
        model.requestSheet(.camera)
        let repeated = try #require(model.sheetRequest)
        #expect(repeated.id != first.id)

        model.requestSheet(.history)
        #expect(model.takeSheetRequest(isActive: true) == .history)
        #expect(model.takeSheetRequest(isActive: true) == nil)

        model.requestSheet(.closeHistory)
        #expect(model.takeSheetRequest(isActive: false) == nil)
        #expect(model.takeSheetRequest(isActive: true) == .closeHistory)
    }

    @Test("Until the camera has run, the history, shown or asked for, keeps it off")
    func historyDefersFirstCameraRun() {
        func runs(hasStarted: Bool = false, pending: ScanSheetRequest.Route? = nil, route: ScanSheetRoute? = nil,
                  isSheetShown: Bool = false, isActive: Bool = true, isSceneActive: Bool = true) -> Bool {
            ScannerCameraStartup.runsCamera(isActive: isActive, isSceneActive: isSceneActive, hasStarted: hasStarted,
                                            pendingRequest: pending, route: route, isSheetShown: isSheetShown)
        }
        #expect(runs())
        #expect(!runs(isActive: false))
        #expect(!runs(isSceneActive: false))
        #expect(!runs(pending: .history))
        #expect(runs(pending: .camera))
        #expect(runs(pending: .closeHistory))
        #expect(!runs(route: .history, isSheetShown: true))
        #expect(!runs(route: .entry(.sampleEAN13), isSheetShown: true))
        #expect(runs(route: .result(.sampleEAN13), isSheetShown: true))
        // The history slid away: the camera may start.
        #expect(runs(route: .history, isSheetShown: false))
        // Once it has run, the history no longer holds it back.
        #expect(runs(hasStarted: true, pending: .history, route: .history, isSheetShown: true))
        #expect(!runs(hasStarted: true, isActive: false))
    }

    @Test("A warm-up starts the camera only with access already granted, and never over the tab's own run")
    func warmUpNeedsAccessAndNoRun() {
        #expect(ScannerCameraWarmUp.shouldStart(authorization: .authorized, isRunning: false))
        #expect(!ScannerCameraWarmUp.shouldStart(authorization: .authorized, isRunning: true))
        for status in [AVAuthorizationStatus.notDetermined, .denied, .restricted] {
            #expect(!ScannerCameraWarmUp.shouldStart(authorization: status, isRunning: false))
        }
    }
}
