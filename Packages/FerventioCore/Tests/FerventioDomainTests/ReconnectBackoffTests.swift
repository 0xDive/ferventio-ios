import Testing
@testable import FerventioDomain

struct ReconnectBackoffTests {
    @Test
    func growsExponentiallyAndCapsAtMaximumDelay() {
        #expect(ReconnectBackoff.delayMilliseconds(forAttempt: 0) == 1_000)
        #expect(ReconnectBackoff.delayMilliseconds(forAttempt: 1) == 2_000)
        #expect(ReconnectBackoff.delayMilliseconds(forAttempt: 2) == 4_000)
        #expect(ReconnectBackoff.delayMilliseconds(forAttempt: 4) == 16_000)
        #expect(ReconnectBackoff.delayMilliseconds(forAttempt: 5) == 30_000)
        #expect(ReconnectBackoff.delayMilliseconds(forAttempt: 20) == 30_000)
    }

    @Test
    func negativeAttemptsUseInitialDelay() {
        #expect(ReconnectBackoff.delayMilliseconds(forAttempt: -1) == 1_000)
    }
}
