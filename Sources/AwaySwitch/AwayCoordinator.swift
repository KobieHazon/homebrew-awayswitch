import AppKit
import AwaySwitchCore
import CoreGraphics
import Foundation

@MainActor
final class AwayCoordinator {
    private(set) var settings: AwaySwitchSettings
    private(set) var reconciliation: ReconciliationState
    private(set) var persistenceError: String?
    var onStateChange: (() -> Void)?

    private let store: AwaySwitchFileStore
    private let applicationRuntime: ApplicationRuntime
    private var verificationWorkItems: [String: DispatchWorkItem] = [:]

    init(
        store: AwaySwitchFileStore = AwaySwitchFileStore(),
        applicationRuntime: ApplicationRuntime? = nil
    ) {
        self.store = store
        self.applicationRuntime = applicationRuntime ?? SystemApplicationRuntime()

        do {
            settings = try store.loadSettings()
            reconciliation = ReconciliationState(runtime: try store.loadRuntime())
        } catch {
            settings = .default
            reconciliation = ReconciliationState()
            persistenceError = "Could not load saved state: \(error.localizedDescription)"
        }

        let wasPersistedAway = reconciliation.runtime.presence.isAway
        normalizeInitialPresence()
        persistAll()

        if reconciliation.runtime.presence.isAway, settings.protectionEnabled {
            enterAwayState(recordCurrentlyRunningForRestore: !wasPersistedAway)
        } else if !reconciliation.runtime.presence.isAway,
                  !reconciliation.runtime.restorationQueue.isEmpty {
            restoreQueuedApps()
        }
    }

    var runtimeState: RuntimeState { reconciliation.runtime }
    var isAway: Bool { runtimeState.presence.isAway }

    func handlePresenceEvent(_ event: PresenceEvent) {
        let transition = reconciliation.applyPresence(event)
        guard transition != .unchanged else { return }

        persistRuntime()
        switch transition {
        case .becameAway where settings.protectionEnabled:
            enterAwayState()
        case .becamePresent:
            returnToPresentState()
        default:
            notifyStateChange()
        }
    }

    func handleApplicationLaunched(bundleIdentifier: String) {
        guard settings.protectionEnabled,
              isAway,
              let app = managedApp(bundleIdentifier: bundleIdentifier),
              applicationRuntime.isRunning(bundleIdentifier: bundleIdentifier)
        else { return }

        let wasAlreadyQueued = runtimeState.restorationQueue[bundleIdentifier] != nil
        requestTermination(of: app, shouldRestore: wasAlreadyQueued)
    }

    func handleApplicationTerminated(bundleIdentifier: String) {
        guard runtimeState.pendingTerminations[bundleIdentifier] != nil else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self,
                  !self.applicationRuntime.isRunning(bundleIdentifier: bundleIdentifier)
            else { return }

            self.verificationWorkItems.removeValue(forKey: bundleIdentifier)?.cancel()
            let appToRestoreNow = self.reconciliation.markTerminated(bundleIdentifier: bundleIdentifier)
            self.persistRuntime()
            self.notifyStateChange()

            if let appToRestoreNow, self.settings.restoreAfterReturn {
                self.launch(appToRestoreNow)
            }
        }
    }

    func setProtectionEnabled(_ enabled: Bool) {
        guard settings.protectionEnabled != enabled else { return }
        settings.protectionEnabled = enabled
        persistSettings()

        if enabled, isAway {
            enterAwayState()
        } else if !enabled {
            cancelVerificationTimers()
            let apps = reconciliation.prepareForProtectionPause(restore: settings.restoreAfterReturn)
            persistRuntime()
            apps.forEach(launch)
            reconcilePendingTerminationsAfterReturn()
            notifyStateChange()
        } else {
            notifyStateChange()
        }
    }

    func setRestoreAfterReturn(_ enabled: Bool) {
        guard settings.restoreAfterReturn != enabled else { return }
        settings.restoreAfterReturn = enabled
        persistSettings()
        notifyStateChange()
    }

    func addManagedApp(_ app: ManagedApp) {
        if let index = settings.managedApps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            settings.managedApps[index] = app
        } else {
            settings.managedApps.append(app)
        }
        settings.managedApps.sort {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        persistSettings()

        if settings.protectionEnabled,
           isAway,
           applicationRuntime.isRunning(bundleIdentifier: app.bundleIdentifier) {
            requestTermination(of: app, shouldRestore: false)
        } else {
            notifyStateChange()
        }
    }

    func removeManagedApp(bundleIdentifier: String) {
        settings.managedApps.removeAll { $0.bundleIdentifier == bundleIdentifier }
        verificationWorkItems.removeValue(forKey: bundleIdentifier)?.cancel()
        reconciliation.removeApp(bundleIdentifier: bundleIdentifier)
        persistAll()
        notifyStateChange()
    }

    func forceQuit(bundleIdentifier: String) {
        guard let app = managedApp(bundleIdentifier: bundleIdentifier) else { return }
        if runtimeState.pendingTerminations[bundleIdentifier] == nil {
            reconciliation.requestTermination(of: app, shouldRestore: false)
        }

        guard applicationRuntime.forceTermination(bundleIdentifier: bundleIdentifier) else {
            reconciliation.markFailure(ManagedAppFailure(
                app: app,
                kind: .forceTermination,
                message: "macOS rejected the force-quit request."
            ))
            persistRuntime()
            notifyStateChange()
            return
        }

        scheduleTerminationVerification(for: app, delay: 2)
        persistRuntime()
        notifyStateChange()
    }

    func appStatus(_ app: ManagedApp) -> String {
        if runtimeState.failures.values.contains(where: { $0.app.bundleIdentifier == app.bundleIdentifier }) {
            return "needs attention"
        }
        if runtimeState.pendingTerminations[app.bundleIdentifier] != nil {
            return "disconnecting"
        }
        if runtimeState.restorationQueue[app.bundleIdentifier] != nil {
            return "disconnected"
        }
        return applicationRuntime.isRunning(bundleIdentifier: app.bundleIdentifier) ? "running" : "closed"
    }

    func isAppRunning(_ app: ManagedApp) -> Bool {
        applicationRuntime.isRunning(bundleIdentifier: app.bundleIdentifier)
    }

    func persistAll() {
        do {
            try store.saveSettings(settings)
            try store.saveRuntime(reconciliation.runtime)
            persistenceError = nil
        } catch {
            persistenceError = "Could not save AwaySwitch state: \(error.localizedDescription)"
        }
    }

    private func normalizeInitialPresence() {
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
        let isLocked = dictionary?["CGSSessionScreenIsLocked"] as? Bool
        let isOnConsole = dictionary?["kCGSessionOnConsoleKey"] as? Bool
        let screensSleeping = CGDisplayIsAsleep(CGMainDisplayID()) != 0

        reconciliation.reconcileStartupPresence(
            screenLocked: isLocked,
            screensSleeping: screensSleeping,
            sessionActive: isOnConsole
        )
    }

    private func enterAwayState(recordCurrentlyRunningForRestore: Bool = true) {
        for app in settings.managedApps where applicationRuntime.isRunning(bundleIdentifier: app.bundleIdentifier) {
            let alreadyRecorded = runtimeState.pendingTerminations[app.bundleIdentifier]?.shouldRestore == true
                || runtimeState.restorationQueue[app.bundleIdentifier] != nil
            requestTermination(
                of: app,
                shouldRestore: recordCurrentlyRunningForRestore || alreadyRecorded
            )
        }
        notifyStateChange()
    }

    private func returnToPresentState() {
        cancelVerificationTimers()
        let apps = reconciliation.prepareForReturn(restore: settings.restoreAfterReturn)
        persistRuntime()
        apps.forEach(launch)
        reconcilePendingTerminationsAfterReturn()
        notifyStateChange()
    }

    private func restoreQueuedApps() {
        let apps = reconciliation.prepareForReturn(restore: settings.restoreAfterReturn)
        persistRuntime()
        apps.forEach(launch)
        reconcilePendingTerminationsAfterReturn()
        notifyStateChange()
    }

    private func reconcilePendingTerminationsAfterReturn() {
        for candidate in reconciliation.runtime.pendingTerminations.values {
            let app = candidate.app
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.verificationWorkItems.removeValue(forKey: app.bundleIdentifier)

                if self.applicationRuntime.isRunning(bundleIdentifier: app.bundleIdentifier) {
                    self.reconciliation.abandonTermination(bundleIdentifier: app.bundleIdentifier)
                } else {
                    let appToRestore = self.reconciliation.markTerminated(bundleIdentifier: app.bundleIdentifier)
                    if let appToRestore, self.settings.restoreAfterReturn {
                        self.launch(appToRestore)
                    }
                }
                self.persistRuntime()
                self.notifyStateChange()
            }
            verificationWorkItems[app.bundleIdentifier] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
        }
    }

    private func requestTermination(of app: ManagedApp, shouldRestore: Bool) {
        reconciliation.requestTermination(of: app, shouldRestore: shouldRestore)
        persistRuntime()

        guard applicationRuntime.requestTermination(bundleIdentifier: app.bundleIdentifier) else {
            reconciliation.markFailure(ManagedAppFailure(
                app: app,
                kind: .terminationRequest,
                message: "macOS rejected the normal quit request."
            ))
            persistRuntime()
            notifyStateChange()
            return
        }

        if !applicationRuntime.isRunning(bundleIdentifier: app.bundleIdentifier) {
            if let appToRestoreNow = reconciliation.markTerminated(bundleIdentifier: app.bundleIdentifier),
               settings.restoreAfterReturn {
                launch(appToRestoreNow)
            }
            persistRuntime()
        } else {
            scheduleTerminationVerification(for: app, delay: 10)
        }
        notifyStateChange()
    }

    private func scheduleTerminationVerification(for app: ManagedApp, delay: TimeInterval) {
        verificationWorkItems.removeValue(forKey: app.bundleIdentifier)?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.verificationWorkItems.removeValue(forKey: app.bundleIdentifier)

            if self.applicationRuntime.isRunning(bundleIdentifier: app.bundleIdentifier) {
                self.reconciliation.markFailure(ManagedAppFailure(
                    app: app,
                    kind: .terminationTimeout,
                    message: "The app is still running. Use Force Quit Now if you want to disconnect it."
                ))
            } else {
                let appToRestoreNow = self.reconciliation.markTerminated(bundleIdentifier: app.bundleIdentifier)
                if let appToRestoreNow, self.settings.restoreAfterReturn {
                    self.launch(appToRestoreNow)
                }
            }
            self.persistRuntime()
            self.notifyStateChange()
        }
        verificationWorkItems[app.bundleIdentifier] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelVerificationTimers() {
        verificationWorkItems.values.forEach { $0.cancel() }
        verificationWorkItems.removeAll()
    }

    private func launch(_ app: ManagedApp) {
        applicationRuntime.launch(app) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.reconciliation.markLaunchSucceeded(bundleIdentifier: app.bundleIdentifier)
                case let .failure(error):
                    self.reconciliation.markFailure(ManagedAppFailure(
                        app: app,
                        kind: .launch,
                        message: error.localizedDescription
                    ))
                }
                self.persistRuntime()
                self.notifyStateChange()
            }
        }
    }

    private func managedApp(bundleIdentifier: String) -> ManagedApp? {
        settings.managedApps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    private func persistSettings() {
        do {
            try store.saveSettings(settings)
            persistenceError = nil
        } catch {
            persistenceError = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func persistRuntime() {
        do {
            try store.saveRuntime(reconciliation.runtime)
            persistenceError = nil
        } catch {
            persistenceError = "Could not save runtime state: \(error.localizedDescription)"
        }
    }

    private func notifyStateChange() {
        onStateChange?()
    }
}
