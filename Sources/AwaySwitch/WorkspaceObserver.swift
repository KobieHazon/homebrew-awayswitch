import AppKit
import AwaySwitchCore
import Foundation

@MainActor
final class WorkspaceObserver {
    private weak var coordinator: AwayCoordinator?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []

    init(coordinator: AwayCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(workspaceCenter, NSWorkspace.screensDidSleepNotification) { $0.handlePresenceEvent(.screensDidSleep) }
        observe(workspaceCenter, NSWorkspace.screensDidWakeNotification) { $0.handlePresenceEvent(.screensDidWake) }
        observe(workspaceCenter, NSWorkspace.sessionDidResignActiveNotification) { $0.handlePresenceEvent(.sessionDidResign) }
        observe(workspaceCenter, NSWorkspace.sessionDidBecomeActiveNotification) { $0.handlePresenceEvent(.sessionDidBecomeActive) }
        observe(workspaceCenter, NSWorkspace.willSleepNotification) { $0.handlePresenceEvent(.systemWillSleep) }
        observe(workspaceCenter, NSWorkspace.didWakeNotification) { $0.handlePresenceEvent(.systemDidWake) }

        workspaceTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleIdentifier = application.bundleIdentifier
            else { return }
            MainActor.assumeIsolated {
                self?.coordinator?.handleApplicationLaunched(bundleIdentifier: bundleIdentifier)
            }
        })

        workspaceTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleIdentifier = application.bundleIdentifier
            else { return }
            MainActor.assumeIsolated {
                self?.coordinator?.handleApplicationTerminated(bundleIdentifier: bundleIdentifier)
            }
        })

        let distributedCenter = DistributedNotificationCenter.default()
        distributedTokens.append(distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.coordinator?.handlePresenceEvent(.screenLocked)
            }
        })
        distributedTokens.append(distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.coordinator?.handlePresenceEvent(.screenUnlocked)
            }
        })
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(workspaceCenter.removeObserver)
        workspaceTokens.removeAll()

        let distributedCenter = DistributedNotificationCenter.default()
        distributedTokens.forEach(distributedCenter.removeObserver)
        distributedTokens.removeAll()
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        handler: @escaping @MainActor (AwayCoordinator) -> Void
    ) {
        workspaceTokens.append(center.addObserver(
            forName: name,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let coordinator = self?.coordinator else { return }
                handler(coordinator)
            }
        })
    }
}
