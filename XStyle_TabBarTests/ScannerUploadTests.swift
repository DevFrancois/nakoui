import CoreGraphics
import Testing
@testable import XStyle_TabBar

@MainActor
struct ScannerUploadTests {
    @Test("Upload entry waits for the sheet and scan reveal to finish")
    func entryEligibility() {
        #expect(ScannerUploadController.canOpen(
            sheetIsHidden: true, sheetHasSettled: true, hasResult: false, isRevealing: false
        ))
        #expect(!ScannerUploadController.canOpen(
            sheetIsHidden: false, sheetHasSettled: true, hasResult: false, isRevealing: false
        ))
        #expect(!ScannerUploadController.canOpen(
            sheetIsHidden: true, sheetHasSettled: false, hasResult: false, isRevealing: false
        ))
        #expect(!ScannerUploadController.canOpen(
            sheetIsHidden: true, sheetHasSettled: true, hasResult: true, isRevealing: false
        ))
        #expect(!ScannerUploadController.canOpen(
            sheetIsHidden: true, sheetHasSettled: true, hasResult: false, isRevealing: true
        ))
    }

    @Test("Short drags and threshold-edge releases keep their starting page",
          arguments: [ScannerUploadPage.camera, .upload])
    func smallDragsStayOnPage(page: ScannerUploadPage) {
        for distance in [CGFloat(-70), 0, 70] {
            for velocity in [CGFloat(-300), 0, 300] {
                #expect(ScannerUploadController.destination(from: page, distance: distance, velocity: velocity) == page)
            }
        }
    }

    @Test("Distance commits a page change while a short fast fling can open or close")
    func distanceAndFlingThresholds() {
        #expect(ScannerUploadController.destination(from: .camera, distance: -71, velocity: 0) == .upload)
        #expect(ScannerUploadController.destination(from: .upload, distance: 71, velocity: 0) == .camera)
        #expect(ScannerUploadController.destination(from: .camera, distance: -8, velocity: -301) == .upload)
        #expect(ScannerUploadController.destination(from: .upload, distance: 8, velocity: 301) == .camera)
    }

    @Test("A fast reversal wins over distance; slow release drift does not")
    func reversalUsesDeliberateVelocity() {
        #expect(ScannerUploadController.destination(from: .camera, distance: -180, velocity: 500) == .camera)
        #expect(ScannerUploadController.destination(from: .upload, distance: 180, velocity: -500) == .upload)
        #expect(ScannerUploadController.destination(from: .camera, distance: -180, velocity: 20) == .upload)
        #expect(ScannerUploadController.destination(from: .upload, distance: 180, velocity: -20) == .camera)
    }

    @Test("Button and completed upward drag reach the same upload presentation")
    func buttonAndDragAgree() {
        let (button, _) = makeController()
        let (drag, _) = makeController()
        button.showUpload()
        button.finish()

        drag.beginDrag()
        drag.drag(by: -800)
        drag.endDrag(velocity: 0, cancelled: false)
        drag.finish()

        #expect(button.page == .upload && drag.page == .upload)
        #expect(button.progress == 1 && drag.progress == 1)
        #expect(button.isUploadSettled && drag.isUploadSettled)
        #expect(button.activity == drag.activity)
        #expect(drag.activity.blocksRecognition && drag.activity.suspendsCapture)
    }

    @Test("Cancelled and short drags resume recognition only after the camera settles")
    func cancelledOrShortDragRestoresCamera() {
        for cancel in [true, false] {
            let (controller, _) = makeController()
            controller.beginDrag()
            controller.drag(by: cancel ? -300 : -40)
            #expect(controller.progress > 0)
            #expect(controller.activity.blocksRecognition)
            #expect(!controller.activity.suspendsCapture)

            controller.endDrag(velocity: cancel ? -900 : 0, cancelled: cancel)
            #expect(controller.page == .camera)
            #expect(controller.isAnimating)
            #expect(controller.activity.blocksRecognition)

            controller.finish()
            #expect(controller.isCameraSettled)
            #expect(controller.progress == 0)
            #expect(controller.activity == .camera)
        }
    }

    @Test("Cancelling a return gesture restores Upload and suspends capture again")
    func cancellingReturnRestoresUpload() {
        let (controller, _) = makeController()
        controller.showUpload()
        controller.finish()
        controller.beginDrag()
        controller.drag(by: 300)
        #expect(!controller.activity.suspendsCapture)

        controller.cancelDrag()
        #expect(controller.page == .upload)
        #expect(controller.activity.blocksRecognition)
        controller.finish()
        #expect(controller.isUploadSettled)
        #expect(controller.activity.suspendsCapture)
    }

    @Test("Camera recognition is blocked synchronously before button animation starts")
    func buttonPublishesActivityBeforeAnimation() {
        let (controller, animator) = makeController()
        let model = ScannerModel(state: .scanning)
        var callbackSawRunningAnimator: Bool?
        controller.onActivityChange = { activity in
            if callbackSawRunningAnimator == nil {
                callbackSawRunningAnimator = animator.state == .running
            }
            model.setUploadActivity(activity)
        }
        #expect(model.canRecognizeCodes)

        controller.showUpload()
        defer { controller.finish() }
        #expect(callbackSawRunningAnimator == .some(false))
        #expect(!model.canRecognizeCodes)
        #expect(!model.shouldSuspendCamera)
        #expect(controller.progress == 0)
        #expect(animator.state == .running)
    }

    @Test("Animator completion suspends the hidden camera and restores recognition after returning")
    func animationCompletionUpdatesCameraActivity() {
        let (controller, animator) = makeController()
        let model = ScannerModel(state: .scanning)
        var activities: [ScannerUploadCameraActivity] = []
        controller.onActivityChange = { activity in
            activities.append(activity)
            model.setUploadActivity(activity)
        }
        defer { controller.finish() }

        controller.showUpload()
        #expect(!model.canRecognizeCodes && !model.shouldSuspendCamera)
        // Complete via the animator's real callback without advancing a wall clock.
        animator.spring = WaveSpring(dampingRatio: 1, response: 0)
        animator.updateAnimation(dt: 0.01)
        #expect(controller.isUploadSettled)
        #expect(controller.progress == 1)
        #expect(animator.state == .ended)
        #expect(!model.canRecognizeCodes && model.shouldSuspendCamera)

        controller.showCamera()
        #expect(!model.canRecognizeCodes && !model.shouldSuspendCamera)
        animator.spring = WaveSpring(dampingRatio: 1, response: 0)
        animator.updateAnimation(dt: 0.01)
        #expect(controller.isCameraSettled)
        #expect(controller.progress == 0)
        #expect(animator.state == .ended)
        #expect(model.canRecognizeCodes && !model.shouldSuspendCamera)
        #expect(activities == [
            ScannerUploadCameraActivity(blocksRecognition: true, suspendsCapture: false),
            ScannerUploadCameraActivity(blocksRecognition: true, suspendsCapture: true),
            ScannerUploadCameraActivity(blocksRecognition: true, suspendsCapture: false),
            .camera
        ])
    }

    @Test("Recognition blocks at touch recognition, before any drag distance")
    func dragBlocksRecognitionImmediately() {
        let (controller, _) = makeController()
        let model = ScannerModel(state: .scanning)
        controller.onActivityChange = model.setUploadActivity
        controller.beginDrag()

        #expect(controller.progress == 0)
        #expect(!model.canRecognizeCodes)
        #expect(!model.shouldSuspendCamera)
        controller.cancelDrag()
        #expect(model.canRecognizeCodes)
    }

    @Test("Reduce Motion keeps the drag still while its distance still chooses the page")
    func reducedMotionTracksIntentWithoutTranslation() {
        let (controller, animator) = makeController()
        controller.reduceMotion = true
        controller.beginDrag()
        controller.drag(by: -160)

        #expect(controller.progress == 0)
        #expect(controller.dragProgress > 0)
        #expect(controller.activity.blocksRecognition)
        controller.endDrag(velocity: 0, cancelled: false)
        #expect(controller.page == .upload)
        #expect(controller.isAnimating)
        #expect(animator.spring.response == 0.15)
        controller.finish()
        #expect(controller.progress == 1)
    }

    @Test("Leaving Scan resets the presentation, animation and temporary sample selection")
    func tabExitClearsSelection() {
        let (controller, animator) = makeController()
        controller.selectedPhotos = [2, 6]
        controller.showUpload()
        animator.updateAnimation(dt: 0.05)
        #expect(controller.progress > 0 && controller.progress < 1)

        controller.reset()
        #expect(controller.isCameraSettled)
        #expect(controller.progress == 0)
        #expect(controller.selectedPhotos.isEmpty)
        #expect(controller.activity == .camera)
        #expect(animator.state == .ended)
    }

    @Test("Quick-switch requests restore the scanner without clearing sample selections",
          arguments: [ScanSheetRequest.Route.camera, .history, .closeHistory])
    func quickSwitchPreservesSelection(request: ScanSheetRequest.Route) {
        let (controller, _) = makeController()
        controller.selectedPhotos = [1, 7]
        controller.showUpload()
        controller.finish()

        controller.takeRequest(request)
        #expect(controller.isCameraSettled)
        #expect(controller.activity == .camera)
        #expect(controller.selectedPhotos == [1, 7])
    }

    @Test("Resizing during a drag restores its starting page with the new travel distance",
          arguments: [ScannerUploadPage.camera, .upload])
    func resizeCancelsOldGestureCoordinates(page: ScannerUploadPage) {
        let (controller, _) = makeController()
        if page == .upload {
            controller.showUpload()
            controller.finish()
        }
        controller.beginDrag()
        controller.drag(by: page == .camera ? -200 : 200)
        controller.updateTravelDistance(400)

        #expect(controller.page == page)
        #expect(controller.progress == page.progress)
        #expect(!controller.isDragging && !controller.isAnimating)
        #expect(controller.travelDistance == 400)
        // A stale pan callback after the resize cannot move the restored page.
        controller.drag(by: -150)
        controller.endDrag(velocity: -600, cancelled: false)
        #expect(controller.page == page)
        #expect(controller.progress == page.progress)
    }

    @Test("Sheet and Upload are independent capture suspension reasons")
    func suspensionReasonsDoNotClearEachOther() {
        let model = ScannerModel(state: .scanning)
        let upload = ScannerUploadCameraActivity(blocksRecognition: true, suspendsCapture: true)
        #expect(!model.shouldSuspendCamera)
        model.setCameraSuspended(true)
        model.setUploadActivity(upload)
        model.setCameraSuspended(false)
        #expect(model.shouldSuspendCamera)

        model.setCameraSuspended(true)
        model.setUploadActivity(.camera)
        #expect(model.shouldSuspendCamera)
        model.setCameraSuspended(false)
        #expect(!model.shouldSuspendCamera)
    }

    @Test("An upload transition blocks queued detections independently of sheet visibility")
    func recognitionReasonsDoNotClearEachOther() {
        let model = ScannerModel(state: .scanning)
        let transitioning = ScannerUploadCameraActivity(blocksRecognition: true, suspendsCapture: false)
        model.setUploadActivity(transitioning)
        model.setCameraHidden(true)
        model.setCameraHidden(false)
        #expect(!model.canRecognizeCodes)
        #expect(!model.shouldSuspendCamera)

        model.setCameraHidden(true)
        model.setUploadActivity(.camera)
        #expect(!model.canRecognizeCodes)
        model.setCameraHidden(false)
        #expect(model.canRecognizeCodes)
    }

    private func makeController() -> (ScannerUploadController, SpringAnimator<CGFloat>) {
        let animator = SpringAnimator<CGFloat>(
            spring: WaveSpring(dampingRatio: 1, response: 0.38), value: 0, target: 0
        )
        let controller = ScannerUploadController(animator: animator)
        controller.updateTravelDistance(800)
        return (controller, animator)
    }
}
