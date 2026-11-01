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
    private var observer: NSObjectProtocol?

    static func current() -> [Display] {
        NSScreen.screens.compactMap { screen -> Display? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue(),
                  let string = CFUUIDCreateString(nil, uuid) as String? else { return nil }
            return Display(identifier: string, name: screen.localizedName)
        }
    }

    func start() {
        guard observer == nil else { return }
        known = Set(Self.current().map(\.identifier))
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
            }
        }
    }

    private func check() {
        let displays = Self.current()
        let added = displays.filter { !known.contains($0.identifier) }
        known = Set(displays.map(\.identifier))
        if !added.isEmpty {
            onConnect?(added)
        }
    }
}
