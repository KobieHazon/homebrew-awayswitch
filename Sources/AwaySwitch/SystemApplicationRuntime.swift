import AppKit
import AwaySwitchCore
import Foundation

@MainActor
protocol ApplicationRuntime: AnyObject {
    func isRunning(bundleIdentifier: String) -> Bool
    func requestTermination(bundleIdentifier: String) -> Bool
    func forceTermination(bundleIdentifier: String) -> Bool
    func launch(_ app: ManagedApp, completion: @escaping (Result<Void, Error>) -> Void)
}

@MainActor
final class SystemApplicationRuntime: ApplicationRuntime {
    func isRunning(bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { !$0.isTerminated }
    }

    func requestTermination(bundleIdentifier: String) -> Bool {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
        guard !applications.isEmpty else { return true }
        return applications.map { $0.terminate() }.allSatisfy { $0 }
    }

    func forceTermination(bundleIdentifier: String) -> Bool {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
        guard !applications.isEmpty else { return true }
        return applications.map { $0.forceTerminate() }.allSatisfy { $0 }
    }

    func launch(_ app: ManagedApp, completion: @escaping (Result<Void, Error>) -> Void) {
        let workspace = NSWorkspace.shared
        let configuredURL = app.bundleURL
        let applicationURL: URL?

        if FileManager.default.fileExists(atPath: configuredURL.path) {
            applicationURL = configuredURL
        } else {
            applicationURL = workspace.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
        }

        guard let applicationURL else {
            completion(.failure(AwaySwitchRuntimeError.applicationNotFound(app.displayName)))
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        workspace.openApplication(at: applicationURL, configuration: configuration) { _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}

enum AwaySwitchRuntimeError: LocalizedError {
    case applicationNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .applicationNotFound(name):
            "Could not find \(name) on this Mac."
        }
    }
}
