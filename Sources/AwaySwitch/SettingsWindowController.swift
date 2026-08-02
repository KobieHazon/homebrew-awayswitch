import AppKit
import AwaySwitchCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let coordinator: AwayCoordinator
    private let tableView = NSTableView()
    private let protectionCheckbox = NSButton()
    private let restoreCheckbox = NSButton()
    private let removeButton = NSButton()
    private let stateLabel = NSTextField(labelWithString: "")

    init(coordinator: AwayCoordinator) {
        self.coordinator = coordinator
        super.init(window: nil)
        window = makeWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refresh()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        protectionCheckbox.state = coordinator.settings.protectionEnabled ? .on : .off
        restoreCheckbox.state = coordinator.settings.restoreAfterReturn ? .on : .off
        let reasons = coordinator.runtimeState.presence.reasons
            .map(\.displayName)
            .sorted()
            .joined(separator: ", ")
        stateLabel.stringValue = coordinator.isAway
            ? "Mac state: Away (\(reasons))"
            : "Mac state: Present"
        tableView.reloadData()
        removeButton.isEnabled = tableView.selectedRow >= 0
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        coordinator.settings.managedApps.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard coordinator.settings.managedApps.indices.contains(row) else { return nil }
        let app = coordinator.settings.managedApps[row]
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "\(app.displayName) — \(coordinator.appStatus(app))")
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = "\(app.bundleIdentifier)\n\(app.bundleURL.path)"
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = tableView.selectedRow >= 0
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 390),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AwaySwitch Settings"
        window.isReleasedWhenClosed = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        let title = NSTextField(labelWithString: "Disconnect selected apps while your Mac is away")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let explanation = NSTextField(wrappingLabelWithString:
            "AwaySwitch normally quits these apps when the screen locks or sleeps, then restores only the apps it closed after you return."
        )
        explanation.textColor = .secondaryLabelColor

        protectionCheckbox.setButtonType(.switch)
        protectionCheckbox.title = "Protection enabled"
        protectionCheckbox.target = self
        protectionCheckbox.action = #selector(toggleProtection(_:))

        restoreCheckbox.setButtonType(.switch)
        restoreCheckbox.title = "Restore apps after unlock"
        restoreCheckbox.target = self
        restoreCheckbox.action = #selector(toggleRestore(_:))

        stateLabel.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ManagedApp"))
        column.title = "Managed Apps"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let addButton = NSButton(title: "Add App…", target: self, action: #selector(addApp(_:)))
        removeButton.title = "Remove"
        removeButton.target = self
        removeButton.action = #selector(removeSelectedApp(_:))
        removeButton.isEnabled = false

        let buttonRow = NSStackView(views: [addButton, removeButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let stack = NSStackView(views: [
            title,
            explanation,
            protectionCheckbox,
            restoreCheckbox,
            stateLabel,
            scrollView,
            buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])

        return window
    }

    @objc private func toggleProtection(_ sender: NSButton) {
        coordinator.setProtectionEnabled(sender.state == .on)
        refresh()
    }

    @objc private func toggleRestore(_ sender: NSButton) {
        coordinator.setRestoreAfterReturn(sender.state == .on)
        refresh()
    }

    @objc private func addApp(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose apps to disconnect while away"
        panel.prompt = "Add"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                guard let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier
                else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                self.coordinator.addManagedApp(ManagedApp(
                    bundleIdentifier: bundleIdentifier,
                    displayName: name,
                    bundleURL: url
                ))
            }
            self.refresh()
        }
    }

    @objc private func removeSelectedApp(_ sender: Any?) {
        let row = tableView.selectedRow
        guard coordinator.settings.managedApps.indices.contains(row) else { return }
        let app = coordinator.settings.managedApps[row]
        coordinator.removeManagedApp(bundleIdentifier: app.bundleIdentifier)
        refresh()
    }
}
