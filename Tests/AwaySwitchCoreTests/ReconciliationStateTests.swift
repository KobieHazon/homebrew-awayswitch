import Foundation
import Testing
@testable import AwaySwitchCore

@Suite
struct ReconciliationStateTests {
    private let whatsapp = ManagedApp.whatsapp

    @Test func appRunningAtAwayEntryIsQueuedAfterSuccessfulTermination() {
        var state = ReconciliationState()
        #expect(state.applyPresence(.screenLocked) == .becameAway)

        state.requestTermination(of: whatsapp, shouldRestore: true)
        #expect(state.markTerminated(bundleIdentifier: whatsapp.bundleIdentifier) == nil)
        #expect(state.runtime.restorationQueue[whatsapp.bundleIdentifier] == whatsapp)

        #expect(state.applyPresence(.screenUnlocked) == .becamePresent)
        #expect(state.prepareForReturn(restore: true) == [whatsapp])
        #expect(state.runtime.restorationQueue.isEmpty)
    }

    @Test func appStartedWhileAwayIsNotRestored() {
        var state = ReconciliationState()
        _ = state.applyPresence(.screenLocked)

        state.requestTermination(of: whatsapp, shouldRestore: false)
        #expect(state.markTerminated(bundleIdentifier: whatsapp.bundleIdentifier) == nil)
        _ = state.applyPresence(.screenUnlocked)
        #expect(state.prepareForReturn(restore: true).isEmpty)
    }

    @Test func duplicateTerminationRequestPreservesRestoreIntent() {
        var state = ReconciliationState()
        _ = state.applyPresence(.screenLocked)

        state.requestTermination(of: whatsapp, shouldRestore: true)
        state.requestTermination(of: whatsapp, shouldRestore: false)

        #expect(state.runtime.pendingTerminations[whatsapp.bundleIdentifier]?.shouldRestore == true)
    }

    @Test func terminationCompletingAfterReturnRequestsImmediateRestore() {
        var state = ReconciliationState()
        _ = state.applyPresence(.screenLocked)
        state.requestTermination(of: whatsapp, shouldRestore: true)
        _ = state.applyPresence(.screenUnlocked)
        #expect(state.prepareForReturn(restore: true).isEmpty)

        #expect(state.markTerminated(bundleIdentifier: whatsapp.bundleIdentifier) == whatsapp)
        #expect(state.runtime.restorationQueue.isEmpty)
    }

    @Test func abandonedTerminationDoesNotRestoreAfterReturn() {
        var state = ReconciliationState()
        _ = state.applyPresence(.screenLocked)
        state.requestTermination(of: whatsapp, shouldRestore: true)
        _ = state.applyPresence(.screenUnlocked)
        _ = state.prepareForReturn(restore: true)

        state.abandonTermination(bundleIdentifier: whatsapp.bundleIdentifier)

        #expect(state.markTerminated(bundleIdentifier: whatsapp.bundleIdentifier) == nil)
    }

    @Test func removalClearsPendingRestoreAndFailures() {
        var state = ReconciliationState()
        _ = state.applyPresence(.screenLocked)
        state.requestTermination(of: whatsapp, shouldRestore: true)
        state.markFailure(ManagedAppFailure(
            app: whatsapp,
            kind: .terminationTimeout,
            message: "still running"
        ))
        _ = state.markTerminated(bundleIdentifier: whatsapp.bundleIdentifier)

        state.removeApp(bundleIdentifier: whatsapp.bundleIdentifier)

        #expect(state.runtime.pendingTerminations.isEmpty)
        #expect(state.runtime.restorationQueue.isEmpty)
        #expect(state.runtime.failures.isEmpty)
    }

    @Test func restoreDisabledClearsQueueWithoutLaunching() {
        var state = ReconciliationState()
        _ = state.applyPresence(.screenLocked)
        state.requestTermination(of: whatsapp, shouldRestore: true)
        _ = state.markTerminated(bundleIdentifier: whatsapp.bundleIdentifier)

        #expect(state.prepareForReturn(restore: false).isEmpty)
        #expect(state.runtime.restorationQueue.isEmpty)
    }

    @Test func retryClearsOnlyTerminationFailuresForTheApp() {
        let signal = ManagedApp(
            bundleIdentifier: "org.whispersystems.signal-desktop",
            displayName: "Signal",
            bundleURL: URL(fileURLWithPath: "/Applications/Signal.app")
        )
        var state = ReconciliationState()
        state.markFailure(ManagedAppFailure(
            app: whatsapp,
            kind: .terminationTimeout,
            message: "still running"
        ))
        state.markFailure(ManagedAppFailure(
            app: whatsapp,
            kind: .launch,
            message: "not found"
        ))
        state.markFailure(ManagedAppFailure(
            app: signal,
            kind: .terminationTimeout,
            message: "still running"
        ))

        state.requestTermination(of: whatsapp, shouldRestore: true)

        #expect(state.runtime.failures.values.contains {
            $0.app.bundleIdentifier == whatsapp.bundleIdentifier && $0.kind == .launch
        })
        #expect(!state.runtime.failures.values.contains {
            $0.app.bundleIdentifier == whatsapp.bundleIdentifier && $0.kind == .terminationTimeout
        })
        #expect(state.runtime.failures.values.contains {
            $0.app.bundleIdentifier == signal.bundleIdentifier && $0.kind == .terminationTimeout
        })
    }
}
