import Foundation
import Testing
import UIKit
@testable import XStyle_TabBar

struct TabBarReflectionLifecycleTests {
    @Test func repeatedSuspensionKeepsOriginalAnchorsUntilEachSourceChanges() {
        var anchors = TabBarReflectionAnchors()
        anchors.suspend(at: CGPoint(x: 100, y: 600), hasUI: true, hasScene: true)
        anchors.suspend(at: CGPoint(x: 200, y: 610), hasUI: true, hasScene: true)
        #expect(anchors.uiOffset(at: CGPoint(x: 110, y: 605)) == CGPoint(x: 10, y: 5))
        #expect(anchors.sceneOffset(at: CGPoint(x: 110, y: 605)) == CGPoint(x: 10, y: 5))
        anchors.replaceUI()
        anchors.suspend(at: CGPoint(x: 110, y: 605), hasUI: true, hasScene: true)
        #expect(anchors.uiOffset(at: CGPoint(x: 110, y: 605)) == .zero)
        #expect(anchors.sceneOffset(at: CGPoint(x: 110, y: 605)) == CGPoint(x: 10, y: 5))
        anchors.replaceScene()
        #expect(anchors.sceneOffset(at: CGPoint(x: 110, y: 605)) == .zero)
    }

    @Test @MainActor func navigationTransformsDoNotChangeStableLayout() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 900))
        let root = UIView(frame: window.bounds)
        let observer = UIView(frame: root.bounds)
        let menu = UIView(frame: CGRect(x: 396, y: 448, width: 44, height: 206))
        window.addSubview(root)
        root.addSubview(observer)
        root.addSubview(menu)
        let stable = TabBarStableLayout.rect(of: menu, in: observer)
        menu.transform = CGAffineTransform(scaleX: 1.2, y: 1.08)
        #expect(menu.convert(menu.bounds, to: observer) != stable)
        #expect(TabBarStableLayout.rect(of: menu, in: observer) == stable)
        menu.center.x -= 10
        #expect(TabBarStableLayout.rect(of: menu, in: observer) == stable?.offsetBy(dx: -10, dy: 0))
    }

    @Test @MainActor func navigationWrapperExpansionKeepsTheCapsuleCenter() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        let root = UIView(frame: window.bounds)
        let wrapper = UIView(frame: CGRect(x: 396, y: 448, width: 44, height: 206))
        let menu = UIView(frame: wrapper.bounds)
        window.addSubview(root)
        root.addSubview(wrapper)
        wrapper.addSubview(menu)
        let stable = TabBarStableLayout.rect(of: menu, in: root)
        // UIKit also changes the wrapper's origin during the expansion. Merely
        // ignoring transforms would incorrectly treat this as a layout change.
        wrapper.frame = CGRect(x: 391.6, y: 440, width: 52.8, height: 222)
        menu.layer.anchorPoint = .zero
        menu.layer.position = .zero
        menu.transform = CGAffineTransform(scaleX: 1.2, y: 222.0 / 206.0)
        let expanded = TabBarStableLayout.rect(of: menu, in: root)
        #expect(abs(expanded!.minX - stable!.minX) < 0.001)
        #expect(abs(expanded!.minY - stable!.minY) < 0.001)
        #expect(expanded!.size == stable!.size)
        wrapper.center.y += 20
        #expect(abs(TabBarStableLayout.rect(of: menu, in: root)!.minY - stable!.minY - 20) < 0.001)
    }

    @Test func contentArmsButDelayedDrawableDoesNotConsumeRamp() {
        var presence = TabBarReflectionPresence()
        #expect(presence.value(at: 1) == 0)
        #expect(!presence.needsSubmission)
        presence.noteContent()
        #expect(presence.value(at: 100) == 0)
        #expect(presence.needsSubmission)
        presence.didSubmit(at: 100)
        #expect(presence.value(at: 100) == 0)
        #expect(abs(presence.value(at: 100.1) - 0.5) < 0.0001)
        #expect(presence.value(at: 100.201) == 1)
    }

    @Test func finalFrameRemainsRequiredAfterClockExpiresUntilSubmission() {
        var presence = TabBarReflectionPresence()
        presence.noteContent()
        presence.didSubmit(at: 1)
        #expect(presence.needsSubmission)
        #expect(presence.value(at: 2) == 1)
        // No didSubmit call models an unavailable drawable/failed encoding.
        #expect(presence.needsSubmission)
        presence.didSubmit(at: 2)
        #expect(!presence.needsSubmission)
        #expect(presence.state == .complete)
    }

    @Test func laterSourcesAndCompatibleReturnsDoNotRestartFade() {
        var presence = TabBarReflectionPresence()
        presence.noteContent()
        presence.didSubmit(at: 1)
        presence.noteContent()
        #expect(abs(presence.value(at: 1.1) - 0.5) < 0.0001)
        presence.didSubmit(at: 1.21)
        presence.noteContent()
        #expect(presence.value(at: 5) == 1)
        presence.reset()
        #expect(presence.state == .waitingForContent)
        #expect(presence.value(at: 5) == 0)
    }

    @Test func reduceMotionSkipsRampButStillRequiresContentAndSubmission() {
        var presence = TabBarReflectionPresence()
        #expect(presence.value(at: 1, reduceMotion: true) == 0)
        presence.noteContent()
        #expect(presence.value(at: 1, reduceMotion: true) == 1)
        presence.didSubmit(at: 1, reduceMotion: true)
        #expect(presence.state == .complete)
        presence.reset()
        presence.noteContent()
        presence.didSubmit(at: 2)
        presence.didSubmit(at: 2.05, reduceMotion: true)
        #expect(presence.state == .complete)
    }

    @Test func captureNeedsBothRootAppearanceAndEmptyPath() {
        var lifecycle = TabBarRootReflectionLifecycle()
        lifecycle.setPathIsEmpty(false)
        let token = lifecycle.willAppear()
        #expect(lifecycle.canRestore)
        #expect(!lifecycle.canCapture)
        lifecycle.didAppear(generation: token)
        #expect(!lifecycle.canCapture)
        lifecycle.setPathIsEmpty(true)
        #expect(lifecycle.canCapture)
    }

    @Test func cancelledReturnRejectsObsoleteAppearanceCompletion() {
        var lifecycle = TabBarRootReflectionLifecycle()
        let token = lifecycle.willAppear()
        lifecycle.cancelReturn(generation: token)
        lifecycle.didAppear(generation: token)
        #expect(!lifecycle.canRestore)
        #expect(!lifecycle.canCapture)
        let next = lifecycle.willAppear()
        lifecycle.didAppear(generation: token)
        #expect(!lifecycle.canCapture)
        lifecycle.didAppear(generation: next)
        #expect(lifecycle.canCapture)
    }

    @Test func cancelledPushCanResumeAndOldCancelCannotSuspendIt() {
        var lifecycle = TabBarRootReflectionLifecycle()
        let initial = lifecycle.willAppear()
        lifecycle.didAppear(generation: initial)
        let departure = lifecycle.suspend()
        let returning = lifecycle.willAppear()
        lifecycle.didAppear(generation: returning)
        lifecycle.cancelReturn(generation: departure)
        #expect(lifecycle.canCapture)
    }

    @Test func compatibilityRejectsDetachedInvalidationsAndChangedContext() {
        let old = TabBarReflectionCompatibility(context: 1,
            capsule: CGRect(x: 20, y: 800, width: 300, height: 60),
            viewport: CGRect(x: 0, y: 0, width: 390, height: 844),
            windowBounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            scale: 3, appearance: 1, reduceTransparency: false)
        #expect(old.permitsResume(old, sameWindow: true, invalidated: false))
        #expect(!old.permitsResume(old, sameWindow: false, invalidated: false))
        #expect(!old.permitsResume(old, sameWindow: true, invalidated: true))
        var changed = old
        changed.context = 2
        #expect(!old.permitsResume(changed, sameWindow: true, invalidated: false))
        changed = old; changed.scale = 2
        #expect(!old.permitsResume(changed, sameWindow: true, invalidated: false))
        changed = old; changed.appearance = 2
        #expect(!old.permitsResume(changed, sameWindow: true, invalidated: false))
        changed = old; changed.reduceTransparency = true
        #expect(!old.permitsResume(changed, sameWindow: true, invalidated: false))
        changed = old; changed.viewport.size.width += 1
        #expect(!old.permitsResume(changed, sameWindow: true, invalidated: false))
        changed = old; changed.capsule.origin.x += 1
        #expect(!old.permitsResume(changed, sameWindow: true, invalidated: false))
    }
}
