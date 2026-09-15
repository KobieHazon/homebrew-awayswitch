import CoreGraphics
import Foundation

/// A current session snapshot, separate from the state saved before shutdown.
public struct StartupPresenceSnapshot: Equatable, Sendable {
    public let screenLocked: Bool?
    public let screensSleeping: Bool?
    public let sessionActive: Bool?

    public init(sessionDictionary: [String: Any]?, screensSleeping: Bool?) {
        sessionActive = sessionDictionary?[kCGSessionOnConsoleKey as String] as? Bool
        self.screensSleeping = screensSleeping

        if let lockValue = sessionDictionary?["CGSSessionScreenIsLocked"] {
            screenLocked = lockValue as? Bool
        } else if sessionActive == true,
                  sessionDictionary?[kCGSessionLoginDoneKey as String] as? Bool == true {
            // macOS omits this optional field for an unlocked console session.
            // Treating its absence as unknown would retain a lock saved before
            // battery loss forever, even after the user has logged in again.
            screenLocked = false
        } else {
            // No usable console session: preserve the saved lock until macOS
            // provides evidence. A sleeping display alone cannot prove unlock.
            screenLocked = nil
        }
    }

    public static func current() -> Self {
        let display = CGMainDisplayID()
        return Self(
            sessionDictionary: CGSessionCopyCurrentDictionary() as? [String: Any],
            screensSleeping: display == kCGNullDirectDisplay ? nil : CGDisplayIsAsleep(display) != 0
        )
    }
}
