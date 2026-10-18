import Testing
@testable import XStyle_TabBar

struct TabBarPresentationStateTests {
    @Test("Scheduling alone keeps the final revision unconfirmed and a drop retries it")
    func finalDropRetriesWithoutAContentChange() {
        var state = TabBarPresentationState()
        let first = state.submit(1, at: 1)
        #expect(state.presentedRevision == 0)
        #expect(!state.needsEncoding(1))
        let shouldRetry1 = state.resolve(first, presented: false)
        #expect(shouldRetry1)
        #expect(state.needsEncoding(1))
        let retry = state.submit(1, at: 1.02)
        state.resolve(retry, presented: true)
        #expect(state.presentedRevision == 1)
        #expect(!state.needsEncoding(1))
        #expect(state.retryUnacknowledged(at: 10) == nil)
    }

    @Test("A newer revision can submit before an older presentation is acknowledged")
    func presentationDoesNotSerializeThroughput() {
        var state = TabBarPresentationState()
        let first = state.submit(1, at: 1)
        #expect(state.needsEncoding(2))
        let second = state.submit(2, at: 1.008)
        state.resolve(first, presented: true)
        #expect(!state.needsEncoding(2))
        state.resolve(second, presented: true)
        #expect(state.presentedRevision == 2)
    }

    @Test("An old dropped warm-up frame cannot cancel a newer ticket for the same revision")
    func oldDropDoesNotClearSameRevisionRetry() {
        var state = TabBarPresentationState()
        let older = state.submit(1, at: 1)
        let newer = state.submit(1, at: 1.01)
        let shouldRetry2 = state.resolve(older, presented: false)
        #expect(!shouldRetry2)
        #expect(!state.needsEncoding(1))
        let shouldRetry3 = state.resolve(newer, presented: false)
        #expect(shouldRetry3)
        #expect(state.needsEncoding(1))
    }

    @Test("A successful older duplicate makes a later dropped duplicate harmless")
    func shownDuplicateDoesNotRetry() {
        var state = TabBarPresentationState()
        let older = state.submit(1, at: 1)
        let newer = state.submit(1, at: 1.01)
        state.resolve(older, presented: true)
        let shouldRetry4 = state.resolve(newer, presented: false)
        #expect(!shouldRetry4)
        #expect(!state.needsEncoding(1))
        let shouldRetry5 = state.resolve(older, presented: false)
        #expect(!shouldRetry5)
    }

    @Test("Out-of-order acknowledgements cannot regress the displayed revision")
    func outOfOrderAcknowledgements() {
        var state = TabBarPresentationState()
        let older = state.submit(1, at: 1)
        let newer = state.submit(2, at: 1.01)
        state.resolve(newer, presented: true)
        state.resolve(older, presented: true)
        #expect(state.presentedRevision == 2)
        #expect(!state.needsEncoding(2))
    }

    @Test("Callbacks from before invalidation cannot retire or clear new submissions")
    func invalidationRejectsOldCallbacks() {
        var state = TabBarPresentationState()
        let old = state.submit(1, at: 1)
        state.invalidate()
        let current = state.submit(2, at: 1.1)
        state.resolve(old, presented: true)
        #expect(state.presentedRevision == 0)
        let shouldRetry6 = state.resolve(old, presented: false)
        #expect(!shouldRetry6)
        #expect(!state.needsEncoding(2))
        state.resolve(current, presented: true)
        #expect(state.presentedRevision == 2)
    }

    @Test("A missing callback retries on a bounded deadline without another content change")
    func missingAcknowledgement() {
        var state = TabBarPresentationState()
        let first = state.submit(1, at: 1)
        #expect(state.retryUnacknowledged(at: 1.249) == nil)
        #expect(state.retryUnacknowledged(at: 1.25) == first)
        #expect(state.needsEncoding(1))
        let retry = state.submit(1, at: 1.25)
        state.resolve(first, presented: false)
        #expect(!state.needsEncoding(1))
        state.resolve(retry, presented: true)
        #expect(state.retryUnacknowledged(at: 100) == nil)
    }
}
