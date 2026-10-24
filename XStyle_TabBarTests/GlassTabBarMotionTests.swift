import Testing
@testable import XStyle_TabBar

@MainActor
struct GlassTabBarMotionTests {
    @Test("The calm defaults spring the highlight and return the bar without bounce")
    func calmDefaultsKeepTheHighlightSpringAndCalmReturn() throws {
        let motion = GlassTabBarMotion.calm
        let spring = try #require(motion.highlightSpring)
        #expect(spring.duration == 0.25 && spring.bounce == 0.15)
        #expect(motion.slideBounce == 0)
    }

    @Test("Enabled highlight and return effects use their configured dials")
    func enabledEffectsUseTheirDials() throws {
        let motion = GlassTabBarMotion(highlightDuration: 0.4, highlightBounce: 0.2,
                                       bounces: true, bounce: 0.4)
        let spring = try #require(motion.highlightSpring)
        #expect(spring.duration == 0.4 && spring.bounce == 0.2)
        #expect(motion.slideBounce == 0.4)
    }

    @Test("A switched-off effect ignores its dial")
    func switchedOffEffectsIgnoreTheirDials() {
        let motion = GlassTabBarMotion(highlightSlides: false, highlightDuration: 0.6,
                                       highlightBounce: 0.4, bounces: false, bounce: 0.5)
        #expect(motion.highlightSpring == nil)
        #expect(motion.slideBounce == 0)
    }
}
