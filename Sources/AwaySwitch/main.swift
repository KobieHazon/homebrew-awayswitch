import AppKit
import AwaySwitchCore
import Darwin
import Foundation

private let awaySwitchVersion = "0.1.0"
private let showSettingsNotification = Notification.Name("com.kobiehazon.AwaySwitch.showSettings")
private let awaySwitchBundleIdentifier = "com.kobiehazon.AwaySwitch"

private var userApplicationURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true)
        .appendingPathComponent("AwaySwitch.app", isDirectory: true)
}

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

    if arguments == ["--remove-app"] {
        do {
            try removeUserApplicationCopy()
            print("AwaySwitch was removed from the user Applications folder")
            exit(EXIT_SUCCESS)
        } catch {
            fputs("AwaySwitch: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
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

    fputs("Usage: awayswitch [--version | --status | --check-config | --show-settings | --remove-app]\n", stderr)
    exit(EXIT_FAILURE)
}

private func installUserApplicationCopyIfNeeded() {
    guard Bundle.main.bundleIdentifier == awaySwitchBundleIdentifier else { return }

    let fileManager = FileManager.default
    let sourceURL = Bundle.main.bundleURL.standardizedFileURL
    let destinationURL = userApplicationURL.standardizedFileURL

    // A copy launched directly from ~/Applications is already in place.
    guard sourceURL.resolvingSymlinksInPath() != destinationURL.resolvingSymlinksInPath() else {
        return
    }

    let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
        || (try? fileManager.destinationOfSymbolicLink(atPath: destinationURL.path)) != nil
    if destinationExists,
       Bundle(url: destinationURL)?.bundleIdentifier != awaySwitchBundleIdentifier {
        return
    }

    let applicationsURL = destinationURL.deletingLastPathComponent()
    let temporaryURL = applicationsURL.appendingPathComponent(
        ".AwaySwitch-installing-\(ProcessInfo.processInfo.processIdentifier).app",
        isDirectory: true
    )
    defer { try? fileManager.removeItem(at: temporaryURL) }

    do {
        try fileManager.createDirectory(at: applicationsURL, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: temporaryURL)
        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        if destinationExists {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        registerUserApplication(at: destinationURL)
    } catch {
        fputs("AwaySwitch: could not install the user Applications copy: \(error.localizedDescription)\n", stderr)
    }
}

private func registerUserApplication(at url: URL) {
    let commands = [
        (
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            ["-f", url.path]
        ),
        ("/usr/bin/mdimport", ["-i", url.path]),
    ]

    for command in commands {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.0)
        process.arguments = command.1
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fputs("AwaySwitch: could not register the app with macOS: \(error.localizedDescription)\n", stderr)
        }
    }
    NSWorkspace.shared.noteFileSystemChanged(url.path)
}

private func removeUserApplicationCopy() throws {
    let fileManager = FileManager.default
    let url = userApplicationURL
    let exists = fileManager.fileExists(atPath: url.path)
        || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    guard exists else { return }
    guard Bundle(url: url)?.bundleIdentifier == awaySwitchBundleIdentifier else {
        throw AwaySwitchAppInstallError.unexpectedApplication(url.path)
    }
    try fileManager.removeItem(at: url)
    NSWorkspace.shared.noteFileSystemChanged(url.path)
}

private enum AwaySwitchAppInstallError: LocalizedError {
    case unexpectedApplication(String)

    var errorDescription: String? {
        switch self {
        case let .unexpectedApplication(path):
            "Refusing to remove an application not owned by AwaySwitch at \(path)."
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AwayCoordinator?
    private var observer: WorkspaceObserver?
    private var statusMenuController: StatusMenuController?
    private var showSettingsToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isBackgroundService = ProcessInfo.processInfo.environment["AWAYSWITCH_SERVICE"] == "1"
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let hasExistingInstance = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == awaySwitchBundleIdentifier
                && $0.processIdentifier != currentPID
                && !$0.isTerminated
        }

        if !isBackgroundService, hasExistingInstance {
            DistributedNotificationCenter.default().postNotificationName(
                showSettingsNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NSApp.terminate(nil)
            return
        }

        installUserApplicationCopyIfNeeded()

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

}

runCommandLineModeIfNeeded()

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    application.run()
}
