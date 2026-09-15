import CoreGraphics
import Foundation
import Testing
@testable import AwaySwitchCore

@Suite
struct StartupPresenceSnapshotTests {
    private var unlockedSession: [String: Any] {
        [kCGSessionOnConsoleKey as String: true, kCGSessionLoginDoneKey as String: true]
    }

    @Test func batteryLossWhileLockedRecoversAfterLoginWithoutLosingQueuedApps() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AwaySwitchFileStore(directoryURL: directory)
        let app = ManagedApp.whatsapp
        // The last durable state before the battery died has no unlock event.
        let saved = RuntimeState(
            presence: PresenceState(reasons: [.screenLocked, .screenSleeping, .sessionInactive, .systemSleeping]),
            pendingTerminations: [app.id: TerminationCandidate(app: app, shouldRestore: true)],
            restorationQueue: [app.id: app]
        )
        try store.saveRuntime(saved)

        var restarted = ReconciliationState(runtime: try store.loadRuntime())
        let current = StartupPresenceSnapshot(sessionDictionary: unlockedSession, screensSleeping: false)
        #expect(restarted.reconcileStartupPresence(
            screenLocked: current.screenLocked,
            screensSleeping: current.screensSleeping,
            sessionActive: current.sessionActive
        ) == .becamePresent)
        #expect(!restarted.runtime.presence.isAway)
        #expect(restarted.runtime.pendingTerminations == saved.pendingTerminations)
        #expect(restarted.runtime.restorationQueue == saved.restorationQueue)

        try store.saveRuntime(restarted.runtime)
        #expect(try store.loadRuntime() == restarted.runtime)
        #expect(restarted.prepareForReturn(restore: true) == [app])
        #expect(restarted.prepareForReturn(restore: true).isEmpty)
    }

    @Test func unlockedSessionUsesActualCoreGraphicsConsoleKey() {
        let current = StartupPresenceSnapshot(sessionDictionary: unlockedSession, screensSleeping: false)
        #expect(current.sessionActive == true)
        #expect(current.screenLocked == false)
    }

    @Test func explicitLockWinsEvenWhenLoginHasCompleted() {
        var session = unlockedSession
        session["CGSSessionScreenIsLocked"] = true
        let current = StartupPresenceSnapshot(sessionDictionary: session, screensSleeping: false)
        #expect(current.screenLocked == true)

        var presence = PresenceState(reasons: [.screenLocked])
        #expect(presence.reconcileStartupSnapshot(
            screenLocked: current.screenLocked,
            screensSleeping: current.screensSleeping,
            sessionActive: current.sessionActive
        ) == .unchanged)
        #expect(presence.isAway)
    }

    @Test func unavailableOrIncompleteSessionDoesNotPretendToBeUnlocked() {
        let sessions: [[String: Any]?] = [
            nil,
            [:],
            [kCGSessionOnConsoleKey as String: true],
            [kCGSessionOnConsoleKey as String: true, kCGSessionLoginDoneKey as String: false],
            [kCGSessionOnConsoleKey as String: false, kCGSessionLoginDoneKey as String: true],
        ]
        for session in sessions {
            let current = StartupPresenceSnapshot(sessionDictionary: session, screensSleeping: nil)
            #expect(current.screenLocked == nil)
            var presence = PresenceState(reasons: [.screenLocked])
            presence.reconcileStartupSnapshot(
                screenLocked: current.screenLocked,
                screensSleeping: current.screensSleeping,
                sessionActive: current.sessionActive
            )
            #expect(presence.reasons.contains(.screenLocked))
        }
    }

    @Test func malformedLockFieldDoesNotCountAsAnAbsentLockField() {
        var session = unlockedSession
        session["CGSSessionScreenIsLocked"] = "unavailable"
        #expect(StartupPresenceSnapshot(sessionDictionary: session, screensSleeping: false).screenLocked == nil)
    }

    @Test func anotherUsersUnlockedConsoleDoesNotMakeThisSessionPresent() {
        var session = unlockedSession
        session[kCGSessionOnConsoleKey as String] = false
        session["CGSSessionScreenIsLocked"] = false
        let current = StartupPresenceSnapshot(sessionDictionary: session, screensSleeping: false)
        var presence = PresenceState()
        presence.reconcileStartupSnapshot(
            screenLocked: current.screenLocked,
            screensSleeping: current.screensSleeping,
            sessionActive: current.sessionActive
        )
        #expect(presence.reasons == [.sessionInactive])
    }

    @Test func sleepingDisplayStillKeepsAnUnlockedSessionAway() {
        let current = StartupPresenceSnapshot(sessionDictionary: unlockedSession, screensSleeping: true)
        var presence = PresenceState(reasons: [.screenLocked])
        presence.reconcileStartupSnapshot(
            screenLocked: current.screenLocked,
            screensSleeping: current.screensSleeping,
            sessionActive: current.sessionActive
        )
        #expect(presence.reasons == [.screenSleeping])
    }
}
