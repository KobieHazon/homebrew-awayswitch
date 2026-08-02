import AppKit
import AwaySwitchCore
import Darwin
import Foundation

private let awaySwitchVersion = "0.1.0"
private let showSettingsNotification = Notification.Name("com.kobiehazon.AwaySwitch.showSettings")

private func runCommandLineModeIfNeeded() {
    let arguments = Set(CommandLine.arguments.dropFirst())
    guard !arguments.isEmpty else { return }

    if arguments == ["--show-settings"] {
        DistributedNotificationCenter.default().postNotificationName(
            showSettingsNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        exit(EXIT_SUCCESS)
    }

    if arguments.contains("--version") {
        print("AwaySwitch \(awaySwitchVersion)")
        exit(EXIT_SUCCESS)
    }

    if arguments.contains("--check-config") || arguments.contains("--status") {
        do {
            let store = AwaySwitchFileStore()
            let settings = try store.loadSettings()
            let runtime = try store.loadRuntime()

            if arguments.contains("--check-config") {
                print("AwaySwitch configuration is valid")
            } else {
                let presence = runtime.presence.isAway
                    ? "away (\(runtime.presence.reasons.map(\.displayName).sorted().joined(separator: ", ")))"
                    : "present"
                print("AwaySwitch \(awaySwitchVersion)")
                print("Protection: \(settings.protectionEnabled ? "enabled" : "paused")")
                print("Presence: \(presence)")
                print("Restore after return: \(settings.restoreAfterReturn ? "yes" : "no")")
                print("Managed apps: \(settings.managedApps.map(\.displayName).joined(separator: ", "))")
            }
            exit(EXIT_SUCCESS)
        } catch {
            fputs("AwaySwitch: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    fputs("Usage: awayswitch [--version | --status | --check-config | --show-settings]\n", stderr)
    exit(EXIT_FAILURE)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AwayCoordinator?
    private var observer: WorkspaceObserver?
    private var statusMenuController: StatusMenuController?
    private var showSettingsToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installUserApplicationsShortcutIfNeeded()

        let store = AwaySwitchFileStore()
        let isFirstLaunch = !FileManager.default.fileExists(atPath: store.settingsURL.path)
        let coordinator = AwayCoordinator(store: store)
        let observer = WorkspaceObserver(coordinator: coordinator)
        let statusMenuController = StatusMenuController(coordinator: coordinator)

        coordinator.onStateChange = { [weak statusMenuController] in
            statusMenuController?.update()
        }

        self.coordinator = coordinator
        self.observer = observer
        self.statusMenuController = statusMenuController
        observer.start()

        showSettingsToken = DistributedNotificationCenter.default().addObserver(
            forName: showSettingsNotification,
            object: nil,
            queue: .main
        ) { [weak statusMenuController] _ in
            MainActor.assumeIsolated {
                statusMenuController?.showSettings()
            }
        }

        let isBackgroundService = ProcessInfo.processInfo.environment["AWAYSWITCH_SERVICE"] == "1"
        if isFirstLaunch || CommandLine.arguments.contains("--show-settings") || !isBackgroundService {
            statusMenuController.showSettings()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        statusMenuController?.showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let showSettingsToken {
            DistributedNotificationCenter.default().removeObserver(showSettingsToken)
        }
        observer?.stop()
        coordinator?.persistAll()
    }

    private func installUserApplicationsShortcutIfNeeded() {
        guard Bundle.main.bundleIdentifier == "com.kobiehazon.AwaySwitch" else { return }

        let fileManager = FileManager.default
        let applicationsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let shortcutURL = applicationsURL.appendingPathComponent("AwaySwitch.app")

        // Preserve any existing app or link. The Homebrew opt path is stable
        // across upgrades, so an AwaySwitch-created link never needs rewriting.
        if fileManager.fileExists(atPath: shortcutURL.path)
            || (try? fileManager.destinationOfSymbolicLink(atPath: shortcutURL.path)) != nil {
            return
        }

        do {
            try fileManager.createDirectory(
                at: applicationsURL,
                withIntermediateDirectories: true
            )
            try fileManager.createSymbolicLink(
                at: shortcutURL,
                withDestinationURL: Bundle.main.bundleURL
            )
            NSWorkspace.shared.noteFileSystemChanged(shortcutURL.path)
        } catch {
            fputs("AwaySwitch: could not create the Applications shortcut: \(error.localizedDescription)\n", stderr)
        }
    }
}

runCommandLineModeIfNeeded()

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    application.run()
}
