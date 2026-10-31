import AppKit
import LanesCore

/// Sends Apple Events to one specific process. This is how Lanes delivers a
/// link to the right Claude window when several share a bundle identifier.
///
/// The first event asks the user for Automation permission. Events are sent
/// off the main thread so that prompt never freezes the interface.
enum AppleEvents {
    enum Failure: LocalizedError {
        case notPermitted
        case notRoutable
        case other(code: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .notPermitted:
                return String(localized: "macOS, Lanes'in Claude'a komut göndermesine izin vermiyor. Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon'dan izin verebilirsin.")
            case .notRoutable:
                return String(localized: "Lanes bu bağlantıyı bir pencereye gönderemez. Giriş bağlantıları ve Lanes'in tanımadığı bağlantılar hiçbir pencereye gönderilmez.")
            case let .other(code, message):
                return "\(message) (\(code))"
            }
        }
    }

    /// `errAEEventNotPermitted`: the user denied Automation access.
    static let notPermittedCode = -1743

    static func fourCharCode(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    /// Sends a `GURL` event, the same event macOS sends when a link opens.
    /// Only routable links go out: a sign-in or OAuth link belongs to the
    /// window that started it.
    static func sendLink(_ link: ClaudeLink, to pid: pid_t) async throws {
        guard link.isRoutable else { throw Failure.notRoutable }
        try await send(eventClass: "GURL", eventID: "GURL", to: pid, directObject: link.url.absoluteString)
    }

    enum Permission: Equatable {
        case granted
        case denied
        /// macOS will ask the first time Lanes sends an event.
        case notAskedYet
        /// Only a running Claude can be checked.
        case claudeNotRunning
        case unknown(Int32)
    }

    /// Whether Lanes may send Claude its reopen event, without ever asking
    /// the user. Runs off the main thread, the check can block.
    static func reopenPermission(bundleIdentifier: String) async -> Permission {
        await Task.detached(priority: .utility) {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
            let status = AEDeterminePermissionToAutomateTarget(
                target.aeDesc,
                AppleEvents.fourCharCode("aevt"),
                AppleEvents.fourCharCode("rapp"),
                false
            )
            switch status {
            case noErr: return Permission.granted
            case OSStatus(AppleEvents.notPermittedCode): return .denied
            case -1744: return .notAskedYet // errAEEventWouldRequireUserConsent
            case OSStatus(procNotFound): return .claudeNotRunning
            default: return .unknown(status)
            }
        }.value
    }

    /// Sends a reopen event, the same event a Dock icon click sends.
    static func sendReopen(to pid: pid_t) async throws {
        try await send(eventClass: "aevt", eventID: "rapp", to: pid, directObject: nil)
    }

    private static func send(eventClass: String, eventID: String, to pid: pid_t, directObject: String?) async throws {
        try await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(processIdentifier: pid)
            let event = NSAppleEventDescriptor(
                eventClass: AppleEvents.fourCharCode(eventClass),
                eventID: AppleEvents.fourCharCode(eventID),
                targetDescriptor: target,
                returnID: -1,
                transactionID: 0
            )
            if let directObject {
                event.setParam(NSAppleEventDescriptor(string: directObject), forKeyword: AppleEvents.fourCharCode("----"))
            }
            do {
                _ = try event.sendEvent(options: [.noReply], timeout: 10)
            } catch let error as NSError {
                if error.code == AppleEvents.notPermittedCode {
                    throw Failure.notPermitted
                }
                throw Failure.other(code: error.code, message: error.localizedDescription)
            }
        }.value
    }
}
