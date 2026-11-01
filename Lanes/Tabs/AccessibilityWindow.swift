import AppKit
import ApplicationServices

/// The Accessibility permission, which tab mode needs to move and resize
/// Claude's windows. Lanes asks for it only when tab mode is turned on.
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows macOS's own prompt, which leads to System Settings.
    static func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// One window of another app, through the Accessibility API. Lanes uses it
/// only for the frame of the active account's Claude window: never its
/// contents, titles or text.
struct AccessibilityWindow {
    let element: AXUIElement

    /// The app's focused window, else its main window, else its first
    /// standard window.
    static func main(of pid: pid_t) -> AccessibilityWindow? {
        let app = AXUIElementCreateApplication(pid)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let element = elementValue(app, attribute) {
                return AccessibilityWindow(element: element)
            }
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        let standard = windows.first { window in
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            return (subrole as? String) == kAXStandardWindowSubrole
        }
        return (standard ?? windows.first).map(AccessibilityWindow.init(element:))
    }

    /// Top-left origin, like every Accessibility frame.
    var frame: CGRect? {
        guard let position = pointValue(kAXPositionAttribute), let size = sizeValue(kAXSizeAttribute) else { return nil }
        return CGRect(origin: position, size: size)
    }

    var isFullScreen: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    var isMinimized: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    /// Size, then position, then size again: a window that can't grow past
    /// the screen edge at its old position fits once it has moved.
    @discardableResult
    func setFrame(_ frame: CGRect) -> Bool {
        var size = frame.size
        var origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return false }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        return moved == .success
    }

    private static func elementValue(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func axValue(_ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private func pointValue(_ attribute: String) -> CGPoint? {
        guard let value = axValue(attribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func sizeValue(_ attribute: String) -> CGSize? {
        guard let value = axValue(attribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
}

/// Calls back when a window moves or changes size.
final class AccessibilityWindowObserver {
    private var observer: AXObserver?
    private let element: AXUIElement
    private let onChange: () -> Void

    init?(pid: pid_t, window: AccessibilityWindow, onChange: @escaping () -> Void) {
        self.element = window.element
        self.onChange = onChange
        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let observer = Unmanaged<AccessibilityWindowObserver>.fromOpaque(refcon).takeUnretainedValue()
            observer.onChange()
        }, &created)
        guard status == .success, let created else { return nil }
        observer = created
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXMovedNotification, kAXResizedNotification] {
            AXObserverAddNotification(created, element, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
    }

    func stop() {
        guard let observer else { return }
        for notification in [kAXMovedNotification, kAXResizedNotification] {
            AXObserverRemoveNotification(observer, element, notification as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
    }

    deinit {
        stop()
    }
}
