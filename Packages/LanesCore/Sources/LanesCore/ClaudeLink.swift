import Foundation

/// What a `claude://` link (or a claude.ai link) asks for, and whether Lanes may
/// route it to a profile.
///
/// The rule that matters most: sign-in links are never forwarded. A magic link,
/// an SSO callback or an OAuth return from Google belongs to the window that
/// started the sign-in. Lanes steps aside during sign-in so Claude receives
/// those links itself.
public struct ClaudeLink: Equatable, Sendable {
    public let url: URL
    public let kind: Kind

    public enum Kind: Equatable, Sendable {
        /// Part of signing in. Never forwarded.
        case signIn
        /// An MCP or connector OAuth return. Goes back to the instance that
        /// started the flow, never to a profile the user picks.
        case oauthCallback
        /// A link Lanes may send to the profile the user chooses.
        case routable(Route)
        /// Not a Claude link Lanes understands. Held back like a sign-in link,
        /// because it may be one in a form Lanes does not know yet.
        case unknown
    }

    public enum Route: Equatable, Sendable {
        case newChat(prompt: String?)
        case newCodeSession
        case continueCodeSession(sessionID: String?)
        case codeNeedsInput
        case resume(sessionID: String?)
        case cowork(path: String)
        case settings(path: String)
    }

    public init?(url: URL) {
        guard let kind = ClaudeLink.classify(url) else { return nil }
        self.url = url
        self.kind = kind
    }

    /// True only for links Lanes may deliver to a profile of the user's choice.
    public var isRoutable: Bool {
        if case .routable = kind { return true }
        return false
    }

    /// True for links Lanes must never hand to another window.
    public var mustNotForward: Bool {
        switch kind {
        case .signIn, .oauthCallback: return true
        case .routable, .unknown: return false
        }
    }

    static let claudeHosts: Set<String> = ["claude.ai", "www.claude.ai"]

    /// Returns `nil` for links that are neither `claude://` nor claude.ai.
    static func classify(_ url: URL) -> Kind? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        let host = components.host?.lowercased() ?? ""

        var segments: [String]
        switch scheme {
        case "claude":
            // `claude://claude.ai/new` and `claude://login/google-auth` both occur.
            let pathSegments = components.path.split(separator: "/").map(String.init)
            segments = claudeHosts.contains(host) ? pathSegments : [host] + pathSegments
        case "https", "http":
            guard claudeHosts.contains(host) else { return nil }
            segments = components.path.split(separator: "/").map(String.init)
        default:
            return nil
        }
        segments = segments.filter { !$0.isEmpty }.map { $0.lowercased() }

        let query = components.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first(where: { $0.name == name })?.value
        }

        guard let first = segments.first else { return .unknown }
        switch first {
        // Anything that looks like sign-in is treated as sign-in: wrongly
        // holding back a link is harmless, forwarding a sign-in link is not.
        case "login", "magic-link", "sso-callback", "sso", "oauth", "auth":
            return .signIn
        case "mcp-auth-callback":
            return .oauthCallback
        case "new":
            return .routable(.newChat(prompt: value("q")))
        case "resume":
            return .routable(.resume(sessionID: value("session")))
        case "code":
            switch segments.dropFirst().first {
            case "new": return .routable(.newCodeSession)
            case "continue": return .routable(.continueCodeSession(sessionID: value("session")))
            case "needs-input": return .routable(.codeNeedsInput)
            default: return .unknown
            }
        case "cowork":
            return .routable(.cowork(path: segments.dropFirst().joined(separator: "/")))
        case "settings":
            return .routable(.settings(path: segments.dropFirst().joined(separator: "/")))
        default:
            return .unknown
        }
    }
}

/// What Lanes does with a link that reaches it while it holds the `claude://`
/// default.
public enum LinkHandling: Equatable, Sendable {
    /// Opened with Claude.app, as macOS would without Lanes.
    case openWithClaude
    /// Kept back. Lanes gives the default to Claude, so the next try reaches
    /// Claude directly.
    case holdBack
}

extension ClaudeLink {
    /// Only links Lanes recognises as routable go anywhere. Sign-in and OAuth
    /// links belong to the window that started them. Links Lanes does not
    /// recognise are held too, because a sign-in link in a form missing from
    /// `classify` must not reach another window.
    public static func handling(for url: URL) -> LinkHandling {
        guard let link = ClaudeLink(url: url), link.isRoutable else { return .holdBack }
        return .openWithClaude
    }
}
