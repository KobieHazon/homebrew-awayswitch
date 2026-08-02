import Testing
@testable import AwaySwitchCore

@Suite
struct PresenceStateTests {
    @Test func lockSleepWakeDoesNotBecomePresentUntilUnlock() {
        var state = PresenceState()

        #expect(state.apply(.screenLocked) == .becameAway)
        #expect(state.apply(.screensDidSleep) == .reasonChanged)
        #expect(state.apply(.screensDidWake) == .reasonChanged)
        #expect(state.isAway)
        #expect(state.reasons == [.screenLocked])
        #expect(state.apply(.screenUnlocked) == .becamePresent)
        #expect(!state.isAway)
    }

    @Test func duplicateEventsAreIdempotent() {
        var state = PresenceState()

        #expect(state.apply(.screenLocked) == .becameAway)
        #expect(state.apply(.screenLocked) == .unchanged)
        #expect(state.apply(.screenUnlocked) == .becamePresent)
        #expect(state.apply(.screenUnlocked) == .unchanged)
    }

    @Test func independentReasonsMustAllClear() {
        var state = PresenceState()

        #expect(state.apply(.sessionDidResign) == .becameAway)
        #expect(state.apply(.systemWillSleep) == .reasonChanged)
        #expect(state.apply(.sessionDidBecomeActive) == .reasonChanged)
        #expect(state.isAway)
        #expect(state.apply(.systemDidWake) == .becamePresent)
    }

    @Test func restartSnapshotPreservesCurrentAwayReasonsAndClearsStaleOnes() {
        var state = PresenceState(reasons: [.screenLocked, .systemSleeping])

        #expect(state.reconcileStartupSnapshot(
            screenLocked: true,
            screensSleeping: true,
            sessionActive: false
        ) == .reasonChanged)
        #expect(state.reasons == [.screenLocked, .screenSleeping, .sessionInactive])
        #expect(state.isAway)
    }

    @Test func restartSnapshotReturnsPresentWhenTheMacIsCurrentlyPresent() {
        var state = PresenceState(reasons: [
            .screenLocked,
            .screenSleeping,
            .sessionInactive,
            .systemSleeping,
        ])

        #expect(state.reconcileStartupSnapshot(
            screenLocked: false,
            screensSleeping: false,
            sessionActive: true
        ) == .becamePresent)
        #expect(!state.isAway)
    }

    @Test func unknownStartupValuesDoNotDiscardPersistedRecoveryState() {
        var state = PresenceState(reasons: [.screenLocked, .screenSleeping])

        #expect(state.reconcileStartupSnapshot(
            screenLocked: nil,
            screensSleeping: nil,
            sessionActive: nil
        ) == .unchanged)
        #expect(state.reasons == [.screenLocked, .screenSleeping])
    }
}
