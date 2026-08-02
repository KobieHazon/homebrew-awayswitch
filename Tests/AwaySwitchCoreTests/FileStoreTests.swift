import Foundation
import Testing
@testable import AwaySwitchCore

@Suite
struct FileStoreTests {
    @Test func defaultsAndAtomicRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AwaySwitchFileStore(directoryURL: directory)

        #expect(try store.loadSettings() == .default)
        #expect(try store.loadRuntime() == .empty)

        var settings = AwaySwitchSettings.default
        settings.protectionEnabled = false
        let runtime = RuntimeState(presence: PresenceState(reasons: [.screenLocked]))
        try store.saveSettings(settings)
        try store.saveRuntime(runtime)

        #expect(try store.loadSettings() == settings)
        #expect(try store.loadRuntime() == runtime)
        #expect(FileManager.default.fileExists(atPath: store.settingsURL.path))
        #expect(FileManager.default.fileExists(atPath: store.runtimeURL.path))
    }

    @Test func invalidJSONIsReported() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AwaySwitchFileStore(directoryURL: directory)
        try Data("not-json".utf8).write(to: store.settingsURL)

        #expect(throws: (any Error).self) {
            try store.loadSettings()
        }
    }
}
