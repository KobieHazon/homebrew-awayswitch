import Foundation

public struct ReconciliationState: Equatable, Sendable {
    public private(set) var runtime: RuntimeState

    public init(runtime: RuntimeState = .empty) {
        self.runtime = runtime
    }

    public mutating func replaceRuntime(_ runtime: RuntimeState) {
        self.runtime = runtime
    }

    @discardableResult
    public mutating func applyPresence(_ event: PresenceEvent) -> PresenceTransition {
        runtime.presence.apply(event)
    }

    public mutating func setPresenceReasons(_ reasons: Set<AwayReason>) {
        runtime.presence.replaceReasons(with: reasons)
    }

    @discardableResult
    public mutating func reconcileStartupPresence(
        screenLocked: Bool?,
        screensSleeping: Bool?,
        sessionActive: Bool?
    ) -> PresenceTransition {
        runtime.presence.reconcileStartupSnapshot(
            screenLocked: screenLocked,
            screensSleeping: screensSleeping,
            sessionActive: sessionActive
        )
    }

    public mutating func requestTermination(of app: ManagedApp, shouldRestore: Bool) {
        let existing = runtime.pendingTerminations[app.bundleIdentifier]
        runtime.pendingTerminations[app.bundleIdentifier] = TerminationCandidate(
            app: app,
            shouldRestore: existing?.shouldRestore == true || shouldRestore
        )
        clearFailures(for: app.bundleIdentifier, kinds: [.terminationRequest, .terminationTimeout, .forceTermination])
    }

    @discardableResult
    public mutating func markTerminated(bundleIdentifier: String) -> ManagedApp? {
        guard let candidate = runtime.pendingTerminations.removeValue(forKey: bundleIdentifier) else {
            return nil
        }

        clearFailures(for: bundleIdentifier, kinds: [.terminationRequest, .terminationTimeout, .forceTermination])
        guard candidate.shouldRestore else { return nil }

        if runtime.presence.isAway {
            runtime.restorationQueue[bundleIdentifier] = candidate.app
            return nil
        }
        return candidate.app
    }

    public mutating func markFailure(_ failure: ManagedAppFailure) {
        runtime.failures[failure.id] = failure
    }

    public mutating func removeApp(bundleIdentifier: String) {
        runtime.pendingTerminations.removeValue(forKey: bundleIdentifier)
        runtime.restorationQueue.removeValue(forKey: bundleIdentifier)
        clearFailures(for: bundleIdentifier)
    }

    public mutating func abandonTermination(bundleIdentifier: String) {
        runtime.pendingTerminations.removeValue(forKey: bundleIdentifier)
        clearFailures(
            for: bundleIdentifier,
            kinds: [.terminationRequest, .terminationTimeout, .forceTermination]
        )
    }

    public mutating func prepareForReturn(restore: Bool) -> [ManagedApp] {
        let apps = restore
            ? runtime.restorationQueue.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            : []
        runtime.restorationQueue.removeAll()
        clearFailures(kinds: [.terminationRequest, .terminationTimeout, .forceTermination])
        return apps
    }

    public mutating func prepareForProtectionPause(restore: Bool) -> [ManagedApp] {
        prepareForReturn(restore: restore)
    }

    public mutating func markLaunchSucceeded(bundleIdentifier: String) {
        clearFailures(for: bundleIdentifier, kinds: [.launch])
    }

    public mutating func clearFailures(
        for bundleIdentifier: String? = nil,
        kinds: Set<AppFailureKind>? = nil
    ) {
        runtime.failures = runtime.failures.filter { _, failure in
            if let bundleIdentifier, failure.app.bundleIdentifier != bundleIdentifier {
                return true
            }
            if let kinds, !kinds.contains(failure.kind) {
                return true
            }
            return false
        }
    }
}
