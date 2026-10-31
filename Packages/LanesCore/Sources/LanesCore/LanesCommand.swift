import Foundation

/// What a `lanes://` address asks for. Raycast, Alfred, Shortcuts or a plain
/// link can open accounts and scenes this way.
///
/// Only harmless commands exist: any web page can open such an address, so
/// none of them runs anything in a folder, quits an account or changes a
/// setting.
public enum LanesCommand: Equatable, Sendable {
    /// `lanes://open?account=İş` opens or brings forward an account. The
    /// account may be given by name, by ID or by its number in the list.
    case openAccount(String)
    /// `lanes://scene?name=Sabah` opens a scene by name or ID.
    case openScene(String)
    /// `lanes://show` shows the main window, `lanes://show?page=health` a page.
    case show(page: String?)
    /// `lanes://panel` opens the menu bar panel.
    case panel

    public static let scheme = "lanes"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == LanesCommand.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // lanes://open?… puts "open" in the host, lanes:open?… in the path.
        let verb = (components.host ?? components.path).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let items = components.queryItems ?? []
        func value(_ names: String...) -> String? {
            for name in names {
                if let found = items.first(where: { $0.name.lowercased() == name })?.value?.trimmingCharacters(in: .whitespaces), !found.isEmpty {
                    return found
                }
            }
            return nil
        }
        switch verb {
        case "open", "account":
            guard let account = value("account", "name", "id") else { return nil }
            self = .openAccount(account)
        case "scene":
            guard let scene = value("name", "scene", "id") else { return nil }
            self = .openScene(scene)
        case "show", "":
            self = .show(page: value("page"))
        case "panel":
            self = .panel
        default:
            return nil
        }
    }

    /// The address for a command, for the Integrations page to show.
    public var url: URL {
        var components = URLComponents()
        components.scheme = LanesCommand.scheme
        switch self {
        case let .openAccount(account):
            components.host = "open"
            components.queryItems = [URLQueryItem(name: "account", value: account)]
        case let .openScene(scene):
            components.host = "scene"
            components.queryItems = [URLQueryItem(name: "name", value: scene)]
        case let .show(page):
            components.host = "show"
            if let page { components.queryItems = [URLQueryItem(name: "page", value: page)] }
        case .panel:
            components.host = "panel"
        }
        return components.url!
    }
}

extension ProfileLibrary {
    /// Finds an account from what a person or a script typed: its ID, its
    /// name (ignoring case, with Turkish rules) or its number, 1 being the
    /// first in the list.
    public func profile(matching query: String) -> Profile? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if let byID = profile(withID: ProfileID(rawValue: trimmed)) { return byID }
        let folded = ProfileLibrary.fold(trimmed)
        if let byName = profiles.first(where: { ProfileLibrary.fold($0.name) == folded }) { return byName }
        if let number = Int(trimmed), number >= 1, number <= profiles.count { return profiles[number - 1] }
        return nil
    }

    public func scene(matching query: String) -> ProfileScene? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if let byID = scenes.first(where: { $0.id.rawValue == trimmed }) { return byID }
        let folded = ProfileLibrary.fold(trimmed)
        return scenes.first { ProfileLibrary.fold($0.name) == folded }
    }

    static func fold(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "tr_TR"))
    }
}
