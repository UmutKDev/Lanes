import AppKit

/// Sends Apple Events to one specific process. This is how Lanes delivers a
/// link to the right Claude window when several share a bundle identifier.
///
/// The first event asks the user for Automation permission. Events are sent
/// off the main thread so that prompt never freezes the interface.
enum AppleEvents {
    enum Failure: LocalizedError {
        case notPermitted
        case other(code: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .notPermitted:
                return String(localized: "macOS, Lanes'in Claude'a komut göndermesine izin vermiyor. Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon'dan izin verebilirsin.")
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
    static func sendURL(_ url: URL, to pid: pid_t) async throws {
        try await send(eventClass: "GURL", eventID: "GURL", to: pid, directObject: url.absoluteString)
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
