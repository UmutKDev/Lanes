import AppKit
import LanesCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// One account's claude.ai window. Windows of all accounts share a
/// tabbing identifier, so macOS shows them as tabs of one window.
@MainActor
final class WebAccountWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let profileID: ProfileID
    let webView: WKWebView
    var onClose: ((ProfileID) -> Void)?
    var onBecomeKey: ((ProfileID) -> Void)?
    /// The user closed the tab, as opposed to Lanes quitting.
    var onUserClose: ((ProfileID) -> Void)?

    /// Hosts that stay inside the tab: claude.ai itself and the pages its
    /// sign-in passes through. Anything else opens in the default browser.
    static let inTabHosts = ["claude.ai", "anthropic.com", "claudeusercontent.com", "accounts.google.com", "appleid.apple.com", "stripe.com", "hcaptcha.com", "cloudflare.com"]

    init(profile: Profile, store: WKWebsiteDataStore, start: URL) {
        profileID = profile.id
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        // Look like Safari, so claude.ai and sign-in pages treat the tab as
        // a browser.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // No white flash behind the page while it loads, in dark mode too.
        webView.underPageBackgroundColor = .windowBackgroundColor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred
        window.tabbingIdentifier = WebAccounts.tabbingIdentifier
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 420)
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("LanesAccountWindow")
        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        apply(profile)
        webView.load(URLRequest(url: start))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    /// The window title and the tab's badge follow the profile.
    func apply(_ profile: Profile) {
        guard let window else { return }
        window.title = profile.name
        window.tab.title = profile.name
        let badge = NSHostingView(rootView: MonogramView(profile: profile, size: DS.Monogram.tiny))
        // The tab bar lays accessories out with Auto Layout.
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: DS.Monogram.tiny),
            badge.heightAnchor.constraint(equalToConstant: DS.Monogram.tiny),
        ])
        window.tab.accessoryView = badge
    }

    // MARK: Window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onUserClose?(profileID)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        onClose?(profileID)
        DockPresence.windowDidClose(window)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey?(profileID)
    }

    // MARK: Navigation

    static func staysInTab(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" { return true }
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return inTabHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if navigationAction.shouldPerformDownload {
            return (.download, preferences)
        }
        let url = navigationAction.request.url
        // A link to another site opens in the browser; claude.ai and the
        // sign-in pages stay here.
        if navigationAction.targetFrame?.isMainFrame != false, navigationAction.navigationType == .linkActivated, !Self.staysInTab(url) {
            if let url { NSWorkspace.shared.open(url) }
            return (.cancel, preferences)
        }
        // claude:// links from the page would reach Claude.app, the main
        // account. They stay unhandled here.
        if let scheme = url?.scheme, !["https", "http", "about", "blob", "data"].contains(scheme) {
            return (.cancel, preferences)
        }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: Pages that open windows

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        if Self.staysInTab(url), let url {
            webView.load(URLRequest(url: url))
        } else if let url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        guard let window else {
            return panel.runModal() == .OK ? panel.urls : nil
        }
        // A sheet on this account's window, so other tabs stay usable.
        let response = await withCheckedContinuation { (continuation: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            panel.beginSheetModal(for: window) { result in
                continuation.resume(returning: result)
            }
        }
        return response == .OK ? panel.urls : nil
    }

    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        // Voice mode. WebKit asks the user; macOS asks once for the microphone.
        origin.host.hasSuffix("claude.ai") ? .prompt : .deny
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = frame.securityOrigin.host
        _ = await presentSheet(alert)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: String(localized: "Tamam"))
        alert.addButton(withTitle: String(localized: "Vazgeç"))
        alert.informativeText = frame.securityOrigin.host
        return await presentSheet(alert) == .alertFirstButtonReturn
    }

    /// Shows a page's alert as a sheet on this account's window, so it
    /// blocks only this tab. Falls back to a modal alert without a window.
    private func presentSheet(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let window else { return alert.runModal() }
        return await withCheckedContinuation { (continuation: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }

    // MARK: Downloads

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let name = (suggestedFilename as NSString).lastPathComponent
        var destination = folder.appendingPathComponent(name.isEmpty ? "indirilen" : name)
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            destination = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        Log.app.info("A download from an account tab finished")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        Log.app.error("A download failed: \(error.localizedDescription, privacy: .public)")
    }
}
