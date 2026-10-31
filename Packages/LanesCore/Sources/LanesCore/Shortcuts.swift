import Foundation

/// Modifier keys of a keyboard shortcut. Stored on their own, not as AppKit
/// or Carbon flags, so LanesCore stays free of both.
public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let control = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let shift = ShortcutModifiers(rawValue: 1 << 2)
    public static let command = ShortcutModifiers(rawValue: 1 << 3)

    /// In the order macOS menus print them.
    public var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }
}

/// A global keyboard shortcut: a key on the keyboard plus modifiers.
public struct KeyShortcut: Codable, Hashable, Sendable, CustomStringConvertible {
    /// The hardware key code, the same on every keyboard layout.
    public var keyCode: UInt32
    public var modifiers: ShortcutModifiers
    /// What the key showed when it was recorded, such as "L" or "F5".
    public var key: String

    public init(keyCode: UInt32, modifiers: ShortcutModifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// The function keys F1 to F20 work on their own. Every other key needs
    /// ⌘, ⌥ or ⌃, or the shortcut would swallow ordinary typing in every
    /// app. Shift alone is not enough, it only types capitals.
    public var isAllowed: Bool {
        if KeyShortcut.functionKeyCodes.contains(keyCode) { return true }
        return !modifiers.intersection([.command, .option, .control]).isEmpty
    }

    public var description: String {
        modifiers.symbols + key
    }

    /// Two shortcuts clash when the same keys are pressed, whatever the key
    /// showed when each was recorded.
    public func sameKeys(as other: KeyShortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    /// kVK_F1 … kVK_F20 from Carbon's Events.h.
    static let functionKeyCodes: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80, 90,
    ]
}

/// What a shortcut does.
public enum ShortcutTarget: Hashable, Sendable, CustomStringConvertible {
    /// Opens or closes the menu bar panel.
    case panel
    /// Opens the account, or brings its window forward.
    case profile(ProfileID)
    /// Opens every account in a scene.
    case scene(SceneID)

    /// The key it is saved under.
    public var description: String {
        switch self {
        case .panel: return "panel"
        case let .profile(id): return "profile:\(id.rawValue)"
        case let .scene(id): return "scene:\(id.rawValue)"
        }
    }

    public init?(key: String) {
        if key == "panel" {
            self = .panel
        } else if key.hasPrefix("profile:") {
            self = .profile(ProfileID(rawValue: String(key.dropFirst("profile:".count))))
        } else if key.hasPrefix("scene:") {
            self = .scene(SceneID(rawValue: String(key.dropFirst("scene:".count))))
        } else {
            return nil
        }
    }
}

/// Every shortcut the user set, at most one per target and one target per
/// set of keys.
public struct ShortcutBindings: Codable, Equatable, Sendable {
    private var byTarget: [String: KeyShortcut]

    public init() {
        byTarget = [:]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        byTarget = (try? container.decode([String: KeyShortcut].self)) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(byTarget)
    }

    public func shortcut(for target: ShortcutTarget) -> KeyShortcut? {
        byTarget[target.description]
    }

    /// The target that already uses these keys, other than `target`.
    public func conflict(for shortcut: KeyShortcut, except target: ShortcutTarget) -> ShortcutTarget? {
        for (key, existing) in byTarget where key != target.description && existing.sameKeys(as: shortcut) {
            if let other = ShortcutTarget(key: key) { return other }
        }
        return nil
    }

    public enum SetError: Error, Equatable {
        case notAllowed
        case inUse(by: ShortcutTarget)
    }

    /// Sets or, with nil, clears a target's shortcut. Keys another target
    /// uses are refused, so one press never does two things.
    public mutating func set(_ shortcut: KeyShortcut?, for target: ShortcutTarget) throws {
        guard let shortcut else {
            byTarget[target.description] = nil
            return
        }
        guard shortcut.isAllowed else { throw SetError.notAllowed }
        if let other = conflict(for: shortcut, except: target) {
            throw SetError.inUse(by: other)
        }
        byTarget[target.description] = shortcut
    }

    /// Every target with a shortcut, panel first.
    public var all: [(target: ShortcutTarget, shortcut: KeyShortcut)] {
        // "panel" sorts before "profile:" and "scene:".
        byTarget.keys.sorted().compactMap { key in
            guard let target = ShortcutTarget(key: key), let shortcut = byTarget[key] else { return nil }
            return (target, shortcut)
        }
    }

    /// Drops shortcuts for accounts and scenes that no longer exist.
    /// Returns true when something was dropped.
    @discardableResult
    public mutating func prune(profiles: Set<ProfileID>, scenes: Set<SceneID>) -> Bool {
        let before = byTarget.count
        byTarget = byTarget.filter { key, _ in
            switch ShortcutTarget(key: key) {
            case .panel: return true
            case let .profile(id): return profiles.contains(id)
            case let .scene(id): return scenes.contains(id)
            case nil: return false
            }
        }
        return byTarget.count != before
    }
}
