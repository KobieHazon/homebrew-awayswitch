import AppKit
import AwaySwitchCore
import Foundation

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let coordinator: AwayCoordinator
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private lazy var settingsWindow = SettingsWindowController(coordinator: coordinator)

    init(coordinator: AwayCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.autosaveName = "AwaySwitch"
        statusItem.isVisible = true
        menu.delegate = self
        statusItem.menu = menu
        update()
    }

    func update() {
        let description: String
        if !coordinator.settings.protectionEnabled {
            description = "AwaySwitch paused"
        } else if coordinator.isAway {
            description = "AwaySwitch protecting phone notifications"
        } else {
            description = "AwaySwitch ready"
        }

        if let button = statusItem.button {
            button.image = nil
            button.title = "AS"
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.toolTip = description
            button.setAccessibilityLabel(description)
            button.setAccessibilityHelp("Open the AwaySwitch menu")
        }
        settingsWindow.refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    func showSettings() {
        settingsWindow.showWindow(nil)
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let protectionItem = NSMenuItem(
            title: "Protection Enabled",
            action: #selector(toggleProtection(_:)),
            keyEquivalent: ""
        )
        protectionItem.target = self
        protectionItem.state = coordinator.settings.protectionEnabled ? .on : .off
        menu.addItem(protectionItem)

        let stateTitle: String
        if coordinator.isAway {
            let reasons = coordinator.runtimeState.presence.reasons
                .map(\.displayName)
                .sorted()
                .joined(separator: ", ")
            stateTitle = "Mac: Away — \(reasons)"
        } else {
            stateTitle = "Mac: Present"
        }
        let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        if let error = coordinator.persistenceError {
            let errorItem = NSMenuItem(title: "Storage error: \(error)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())
        for app in coordinator.settings.managedApps {
            let item = NSMenuItem(
                title: "\(app.displayName): \(coordinator.appStatus(app))",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)

            let failures = coordinator.runtimeState.failures.values
                .filter { $0.app.bundleIdentifier == app.bundleIdentifier }
                .sorted { $0.kind.rawValue < $1.kind.rawValue }
            for failure in failures {
                let failureItem = NSMenuItem(
                    title: "  \(failure.message)",
                    action: nil,
                    keyEquivalent: ""
                )
                failureItem.isEnabled = false
                menu.addItem(failureItem)
            }

            if failures.contains(where: {
                $0.app.bundleIdentifier == app.bundleIdentifier
                    && [.terminationRequest, .terminationTimeout, .forceTermination].contains($0.kind)
            }) {
                let forceItem = NSMenuItem(
                    title: "Force Quit \(app.displayName) Now",
                    action: #selector(forceQuit(_:)),
                    keyEquivalent: ""
                )
                forceItem.target = self
                forceItem.representedObject = app.bundleIdentifier
                menu.addItem(forceItem)
            }
        }

        menu.addItem(.separator())
        let restoreItem = NSMenuItem(
            title: "Restore Apps After Unlock",
            action: #selector(toggleRestore(_:)),
            keyEquivalent: ""
        )
        restoreItem.target = self
        restoreItem.state = coordinator.settings.restoreAfterReturn ? .on : .off
        menu.addItem(restoreItem)

        let settingsItem = NSMenuItem(
            title: "Manage Apps…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About AwaySwitch", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit AwaySwitch", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleProtection(_ sender: NSMenuItem) {
        coordinator.setProtectionEnabled(!coordinator.settings.protectionEnabled)
    }

    @objc private func toggleRestore(_ sender: NSMenuItem) {
        coordinator.setRestoreAfterReturn(!coordinator.settings.restoreAfterReturn)
    }

    @objc private func forceQuit(_ sender: NSMenuItem) {
        guard let bundleIdentifier = sender.representedObject as? String else { return }
        coordinator.forceQuit(bundleIdentifier: bundleIdentifier)
    }

    @objc private func showSettings(_ sender: Any?) {
        settingsWindow.showWindow(sender)
    }

    @objc private func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "AwaySwitch 0.1.0"
        alert.informativeText = "Keeps selected desktop apps disconnected while your Mac is away, so notifications can return to your phone.\n\nAwaySwitch changes no sleep or power settings and sends no telemetry."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }
}
