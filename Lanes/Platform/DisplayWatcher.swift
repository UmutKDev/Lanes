import AppKit
import CoreGraphics
import LanesCore

/// The connected displays by the identifier macOS keeps for each, and a
/// callback when one is plugged in.
@MainActor
final class DisplayWatcher {
    struct Display: Hashable, Identifiable {
        var identifier: String
        var name: String
        var id: String { identifier }
    }

    /// Called with the displays that were just connected.
    var onConnect: (([Display]) -> Void)?
    private var known: Set<String> = []
    /// When each display went missing. A display that comes back within
    /// `minimumAbsence` was only re-enumerated (a mode switch, display
    /// sleep), not plugged in.
    private var goneAt: [String: Date] = [:]
    private var wokeAt: Date?
    private var observers: [NSObjectProtocol] = []

    static let minimumAbsence: TimeInterval = 60
    /// Displays reappearing this soon after the Mac wakes were there all
    /// along; macOS often drops external displays while asleep.
    static let wakeGrace: TimeInterval = 120

    static func current() -> [Display] {
        NSScreen.screens.compactMap { screen -> Display? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue(),
                  let string = CFUUIDCreateString(nil, uuid) as String? else { return nil }
            return Display(identifier: string, name: screen.localizedName)
        }
    }

    func start() {
        guard observers.isEmpty else { return }
        known = Set(Self.current().map(\.identifier))
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.wokeAt = Date()
            }
        })
    }

    private func check() {
        let now = Date()
        let displays = Self.current()
        let current = Set(displays.map(\.identifier))
        for identifier in known.subtracting(current) {
            goneAt[identifier] = now
        }
        let justWoke = wokeAt.map { now.timeIntervalSince($0) < Self.wakeGrace } ?? false
        let added = displays.filter { display in
            guard !known.contains(display.identifier) else { return false }
            if let gone = goneAt[display.identifier], now.timeIntervalSince(gone) < Self.minimumAbsence { return false }
            return !justWoke
        }
        known = current
        for identifier in current {
            goneAt[identifier] = nil
        }
        if !added.isEmpty {
            onConnect?(added)
        }
    }
}
