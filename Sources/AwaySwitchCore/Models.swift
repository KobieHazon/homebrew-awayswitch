import Foundation

public struct ManagedApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let bundleIdentifier: String
    public var displayName: String
    public var bundleURL: URL

    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, displayName: String, bundleURL: URL) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.bundleURL = bundleURL
    }

    public static let whatsapp = ManagedApp(
        bundleIdentifier: "net.whatsapp.WhatsApp",
        displayName: "WhatsApp",
        bundleURL: URL(fileURLWithPath: "/Applications/WhatsApp.app")
    )
}

public struct AwaySwitchSettings: Codable, Equatable, Sendable {
    public var protectionEnabled: Bool
    public var restoreAfterReturn: Bool
    public var managedApps: [ManagedApp]

    public init(
        protectionEnabled: Bool = true,
        restoreAfterReturn: Bool = true,
        managedApps: [ManagedApp] = [.whatsapp]
    ) {
        self.protectionEnabled = protectionEnabled
        self.restoreAfterReturn = restoreAfterReturn
        self.managedApps = managedApps
    }

    public static let `default` = AwaySwitchSettings()
}

public enum AwayReason: String, Codable, CaseIterable, Hashable, Sendable {
    case screenLocked
    case screenSleeping
    case sessionInactive
    case systemSleeping

    public var displayName: String {
        switch self {
        case .screenLocked: "screen locked"
        case .screenSleeping: "screen asleep"
        case .sessionInactive: "session inactive"
        case .systemSleeping: "system sleeping"
        }
    }
}

public enum PresenceEvent: Equatable, Sendable {
    case screenLocked
    case screenUnlocked
    case screensDidSleep
    case screensDidWake
    case sessionDidResign
    case sessionDidBecomeActive
    case systemWillSleep
    case systemDidWake
}

public enum PresenceTransition: Equatable, Sendable {
    case unchanged
    case reasonChanged
    case becameAway
    case becamePresent
}

public struct PresenceState: Codable, Equatable, Sendable {
    public private(set) var reasons: Set<AwayReason>

    public var isAway: Bool { !reasons.isEmpty }

    public init(reasons: Set<AwayReason> = []) {
        self.reasons = reasons
    }

    @discardableResult
    public mutating func apply(_ event: PresenceEvent) -> PresenceTransition {
        let wasAway = isAway
        let previousReasons = reasons

        switch event {
        case .screenLocked:
            reasons.insert(.screenLocked)
        case .screenUnlocked:
            reasons.remove(.screenLocked)
        case .screensDidSleep:
            reasons.insert(.screenSleeping)
        case .screensDidWake:
            reasons.remove(.screenSleeping)
        case .sessionDidResign:
            reasons.insert(.sessionInactive)
        case .sessionDidBecomeActive:
            reasons.remove(.sessionInactive)
        case .systemWillSleep:
            reasons.insert(.systemSleeping)
        case .systemDidWake:
            reasons.remove(.systemSleeping)
        }

        return transition(wasAway: wasAway, previousReasons: previousReasons)
    }

    @discardableResult
    public mutating func reconcileStartupSnapshot(
        screenLocked: Bool?,
        screensSleeping: Bool?,
        sessionActive: Bool?
    ) -> PresenceTransition {
        let wasAway = isAway
        let previousReasons = reasons

        update(.screenLocked, isActive: screenLocked)
        update(.screenSleeping, isActive: screensSleeping)
        if let sessionActive {
            update(.sessionInactive, isActive: !sessionActive)
        }

        // A process executing at startup is necessarily past system sleep, even
        // if it missed the corresponding wake notification while not running.
        reasons.remove(.systemSleeping)

        return transition(wasAway: wasAway, previousReasons: previousReasons)
    }

    public mutating func replaceReasons(with reasons: Set<AwayReason>) {
        self.reasons = reasons
    }

    private mutating func update(_ reason: AwayReason, isActive: Bool?) {
        guard let isActive else { return }
        if isActive {
            reasons.insert(reason)
        } else {
            reasons.remove(reason)
        }
    }

    private func transition(
        wasAway: Bool,
        previousReasons: Set<AwayReason>
    ) -> PresenceTransition {
        guard reasons != previousReasons else { return .unchanged }
        if !wasAway && isAway { return .becameAway }
        if wasAway && !isAway { return .becamePresent }
        return .reasonChanged
    }
}

public enum AppFailureKind: String, Codable, Equatable, Sendable {
    case terminationRequest
    case terminationTimeout
    case forceTermination
    case launch
    case persistence
}

public struct ManagedAppFailure: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(app.bundleIdentifier):\(kind.rawValue)" }
    public let app: ManagedApp
    public let kind: AppFailureKind
    public let message: String

    public init(app: ManagedApp, kind: AppFailureKind, message: String) {
        self.app = app
        self.kind = kind
        self.message = message
    }
}

public struct TerminationCandidate: Codable, Equatable, Sendable {
    public let app: ManagedApp
    public let shouldRestore: Bool

    public init(app: ManagedApp, shouldRestore: Bool) {
        self.app = app
        self.shouldRestore = shouldRestore
    }
}

public struct RuntimeState: Codable, Equatable, Sendable {
    public var presence: PresenceState
    public var pendingTerminations: [String: TerminationCandidate]
    public var restorationQueue: [String: ManagedApp]
    public var failures: [String: ManagedAppFailure]

    public init(
        presence: PresenceState = PresenceState(),
        pendingTerminations: [String: TerminationCandidate] = [:],
        restorationQueue: [String: ManagedApp] = [:],
        failures: [String: ManagedAppFailure] = [:]
    ) {
        self.presence = presence
        self.pendingTerminations = pendingTerminations
        self.restorationQueue = restorationQueue
        self.failures = failures
    }

    public static let empty = RuntimeState()
}
