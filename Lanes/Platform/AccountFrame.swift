import AppKit
import CoreGraphics
import LanesCore

/// "Hesap Rengi Çerçevesi": a thin border in the account's colour around
/// the Claude window in front, so a glance tells which customer's window
/// it is. The border is a click-through window of its own; nothing is
/// drawn into Claude. The window's place comes from macOS's window list
/// (its bounds only, which need no permission); its title and contents
/// are never read.
@MainActor
final class AccountFrame {
    private var panel: NSPanel?
    private var timer: Timer?
    private var pid: pid_t?
    private var color: NSColor = .systemBlue
    private var lastFrame: CGRect?

    /// Border thickness and how far outside the window it sits.
    private static let lineWidth: CGFloat = 3
    private static let outset: CGFloat = 2
    /// macOS 26 window corners; close enough for Claude's window.
    private static let cornerRadius: CGFloat = 16

    /// Follows `pid`'s front window until `hide()`.
    func show(pid: pid_t, color: NSColor) {
        self.pid = pid
        self.color = color
        borderView?.layer?.borderColor = color.cgColor
        if timer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        update()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        pid = nil
        lastFrame = nil
        panel?.orderOut(nil)
    }

    private var borderView: NSView? { panel?.contentView }

    private func update() {
        guard let pid, let bounds = Self.frontWindowBounds(of: pid), !Self.isFullScreen(bounds) else {
            if panel?.isVisible == true { panel?.orderOut(nil) }
            lastFrame = nil
            return
        }
        let frame = Self.cocoaFrame(fromWindowListBounds: bounds)
            .insetBy(dx: -(Self.outset + Self.lineWidth), dy: -(Self.outset + Self.lineWidth))
        let panel = self.panel ?? makePanel()
        if frame != lastFrame {
            panel.setFrame(frame, display: true)
            lastFrame = frame
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        // A cue for the user only. macOS 15 and later may still capture it.
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenNone]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.borderWidth = Self.lineWidth
        view.layer?.cornerRadius = Self.cornerRadius + Self.outset + Self.lineWidth
        view.layer?.cornerCurve = .continuous
        view.layer?.borderColor = color.cgColor
        panel.contentView = view
        self.panel = panel
        return panel
    }

    /// The bounds of the app's frontmost normal window on screen, in
    /// window-list coordinates (top-left origin), or nil when it has none.
    /// Only the owner, layer and bounds keys are used.
    static func frontWindowBounds(of pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list {
            // Invisible and tiny helper windows don't count as covering Claude.
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let owner = (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init),
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  bounds.width >= 200, bounds.height >= 150 else { continue }
            // Another window (another app's, or a Lanes window) above
            // Claude's: no border drawn over it.
            guard owner == pid else { return nil }
            return bounds
        }
        return nil
    }

    /// The window list measures from the top of the main display; AppKit
    /// from its bottom.
    static func cocoaFrame(fromWindowListBounds bounds: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: bounds.minX, y: mainHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    /// A full-screen window fills its display; a border would sit off-screen.
    private static func isFullScreen(_ bounds: CGRect) -> Bool {
        let frame = cocoaFrame(fromWindowListBounds: bounds)
        return NSScreen.screens.contains { $0.frame == frame }
    }
}

/// "Pano Bekçisi": warns when something copied in one account's Claude
/// is about to be pasted into another account's. Only the pasteboard's
/// change counter is read, never what is on it.
@MainActor
final class ClipboardGuard {
    /// Called once per copy: what was copied in `from`, now `to` is in front.
    var onCrossAccount: ((_ from: ProfileID, _ to: ProfileID) -> Void)?

    private var timer: Timer?
    private var front: ProfileID?
    private var lastChangeCount = NSPasteboard.general.changeCount
    /// The account in front when the pasteboard last changed, if any.
    private var copy: (owner: ProfileID, changeCount: Int, at: Date)?
    private var warnedChangeCount: Int?
    /// The change count after Lanes itself last copied something.
    static var lanesChangeCount: Int?

    /// A copy older than this is not warned about.
    static let window: TimeInterval = 10 * 60

    func frontChanged(to id: ProfileID?) {
        // A copy made just before switching belongs to the account that
        // was in front.
        sample()
        guard id != front else { return }
        front = id
        if let id, let copy, copy.owner != id,
           copy.changeCount == NSPasteboard.general.changeCount,
           warnedChangeCount != copy.changeCount,
           Date().timeIntervalSince(copy.at) <= Self.window {
            warnedChangeCount = copy.changeCount
            onCrossAccount?(copy.owner, id)
        }
        if id == nil {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        front = nil
        copy = nil
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func sample() {
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        // Copied in another app, or by Lanes itself: not an account's copy.
        guard count != Self.lanesChangeCount else {
            copy = nil
            return
        }
        copy = front.map { (owner: $0, changeCount: count, at: Date()) }
    }
}
