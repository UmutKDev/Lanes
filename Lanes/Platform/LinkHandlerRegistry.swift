import AppKit

/// Reads and changes which app opens `claude://` links.
enum LinkHandlerRegistry {
    static let scheme = "claude"
    private static let probe = URL(string: "claude://claude.ai/new")!

    static func currentHandler() -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    static func candidates() -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: probe)
    }

    static func setHandler(_ application: URL) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: application, toOpenURLsWithScheme: scheme)
    }

    static var lanesIsHandler: Bool {
        guard let handler = currentHandler() else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }
}
