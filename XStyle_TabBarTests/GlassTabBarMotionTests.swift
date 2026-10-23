import Testing
@testable import XStyle_TabBar

@MainActor
struct GlassTabBarMotionTests {
    @Test("The calm defaults settle without overshoot and slide the highlight on a snappy spring")
    func calmDefaultsNeverOvershoot() throws {
        let motion = GlassTabBarMotion.calm
        #expect(motion.pressedScale == 1.02)
        #expect(motion.releaseDamping == 1)
        let spring = try #require(motion.highlightSpring)
        #expect(spring.duration == 0.25 && spring.bounce == 0.15)
        #expect(motion.slideBounce == 0)
    }

    @Test("The original preset is how the bar itself moved before the calm defaults")
    func originalMatchesThePreviousMotion() {
        let motion = GlassTabBarMotion.original
        #expect(motion.pressedScale == 1.04)
        #expect(motion.settleDuration == 0.35)
        #expect(motion.releaseDamping == 0.45)
        #expect(motion.slideBounce == 0.3)
    }

    @Test("A switched-off effect ignores its dial")
    func switchedOffEffectsIgnoreTheirDials() {
        let motion = GlassTabBarMotion(grows: false, grow: 1.08, wobbles: false, wobbleDamping: 0.2,
                                       highlightSlides: false, highlightDuration: 0.6, bounces: false, bounce: 0.5)
        #expect(motion.pressedScale == 1)
        #expect(motion.releaseDamping == 1)
        #expect(motion.highlightSpring == nil)
        #expect(motion.slideBounce == 0)
    }
}
