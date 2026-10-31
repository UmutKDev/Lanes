import AppKit
import Carbon.HIToolbox
import LanesCore
import Observation

/// Marks Lanes's own hot keys, "LANE".
private let hotKeySignature: OSType = 0x4C41_4E45

/// Global keyboard shortcuts through Carbon's hot keys. They work in every
/// app without Accessibility or Input Monitoring permission, because macOS
/// tells Lanes only about the exact keys it registered.
@MainActor
@Observable
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    @ObservationIgnored private var registered: [UInt32: (ref: EventHotKeyRef, action: @MainActor () -> Void)] = [:]
    @ObservationIgnored private var nextID: UInt32 = 1
    @ObservationIgnored private var handlerInstalled = false
    /// While a shortcut is being recorded the keys must reach the recorder.
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var pending: [(KeyShortcut, @MainActor () -> Void)] = []

    /// Shortcuts macOS refused, usually because another app holds the keys.
    private(set) var unavailable: [KeyShortcut] = []

    /// Replaces every registered shortcut.
    func register(_ items: [(KeyShortcut, @MainActor () -> Void)]) {
        pending = items
        guard !isSuspended else { return }
        apply()
    }

    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        isSuspended = false
        apply()
    }

    private func apply() {
        installHandlerIfNeeded()
        unregisterAll()
        var refused: [KeyShortcut] = []
        for (shortcut, action) in pending {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: hotKeySignature, id: nextID)
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                HotKeyCenter.carbonModifiers(shortcut.modifiers),
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registered[nextID] = (ref, action)
                nextID &+= 1
            } else {
                refused.append(shortcut)
            }
        }
        if !refused.isEmpty {
            Log.app.error("\(refused.count) shortcuts could not be registered")
        }
        if unavailable != refused {
            unavailable = refused
        }
    }

    private func unregisterAll() {
        for entry in registered.values {
            UnregisterEventHotKey(entry.ref)
        }
        registered.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        registered[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == hotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    HotKeyCenter.shared.fire(id)
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    static func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> ShortcutModifiers {
        var modifiers: ShortcutModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }

    /// A key's label for a recorded shortcut. Named keys get their symbol,
    /// letters are upper-cased.
    static func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return String(localized: "Boşluk")
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_ForwardDelete: return "⌦"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default:
            let characters = event.charactersIgnoringModifiers ?? ""
            return characters.uppercased(with: Locale(identifier: "tr_TR"))
        }
    }
}
