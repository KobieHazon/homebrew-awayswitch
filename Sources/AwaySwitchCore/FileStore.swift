import Foundation

public struct AwaySwitchFileStore: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.directoryURL = applicationSupport.appendingPathComponent("AwaySwitch", isDirectory: true)
        }
    }

    public var settingsURL: URL { directoryURL.appendingPathComponent("config.json") }
    public var runtimeURL: URL { directoryURL.appendingPathComponent("state.json") }

    public func loadSettings() throws -> AwaySwitchSettings {
        try load(AwaySwitchSettings.self, from: settingsURL) ?? .default
    }

    public func loadRuntime() throws -> RuntimeState {
        try load(RuntimeState.self, from: runtimeURL) ?? .empty
    }

    public func saveSettings(_ settings: AwaySwitchSettings) throws {
        try save(settings, to: settingsURL)
    }

    public func saveRuntime(_ runtime: RuntimeState) throws {
        try save(runtime, to: runtimeURL)
    }

    private func load<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try Self.encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder { JSONDecoder() }
}
