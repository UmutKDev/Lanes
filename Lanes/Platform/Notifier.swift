import Foundation
import UserNotifications

/// macOS notifications for the few things worth knowing while Lanes sits in
/// the menu bar. Each kind is off until the user turns it on in Settings,
/// and macOS asks for permission the first time.
@MainActor
enum Notifier {
    enum Kind: String, CaseIterable, Identifiable {
        case claudeUpdated
        case strayClone
        case cloneRenewed
        case linkRouted
        case idleQuit
        case dailyLimit
        case memoryHigh
        case launchFailed
        case limitReset
        case claudeCodeDone
        case weeklySummary
        case identityMismatch

        var id: String { rawValue }

        var preferenceKey: String { "notify.\(rawValue)" }

        var title: String {
            switch self {
            case .claudeUpdated: return String(localized: "Claude güncellendi")
            case .strayClone: return String(localized: "Bir klon Lanes dışından açıldı")
            case .cloneRenewed: return String(localized: "Bir klon yenilendi ya da yenilenemedi")
            case .linkRouted: return String(localized: "Bir bağlantı bir hesaba yönlendirildi")
            case .idleQuit: return String(localized: "Kullanılmayan bir hesap kapatıldı")
            case .dailyLimit: return String(localized: "Bir hesap günlük süresini doldurdu")
            case .memoryHigh: return String(localized: "Açık hesaplar çok bellek kullanıyor")
            case .launchFailed: return String(localized: "Bir hesap açılamadı")
            case .limitReset: return String(localized: "Bir hesabın dinlenmesi bitti")
            case .claudeCodeDone: return String(localized: "Claude Code bitirdi ya da onay bekliyor")
            case .weeklySummary: return String(localized: "Pazartesi özeti")
            case .identityMismatch: return String(localized: "Kimlik Bekçisi: beklenmeyen hesap")
            }
        }

        /// Reminders the user turns on where they set them (a daily limit,
        /// a memory limit) have no switch of their own, and neither does a
        /// failed open, which shows only when no Lanes window could show it.
        static var switchable: [Kind] {
            allCases.filter { $0 != .dailyLimit && $0 != .memoryHigh && $0 != .launchFailed && $0 != .limitReset && $0 != .claudeCodeDone && $0 != .identityMismatch }
        }

        var isEnabled: Bool {
            UserDefaults.standard.bool(forKey: preferenceKey)
        }
    }

    /// Asks macOS for permission. Returns whether notifications may show.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Shows a notification when its kind is on. The text never holds a
    /// link or anything from inside an account.
    /// `force` is for reminders the user set up on purpose, such as a daily
    /// limit, which show whether or not their kind is on.
    static func post(_ kind: Kind, body: String, force: Bool = false) {
        guard force || kind.isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("Notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Shows a reminder the user set up at a later time, under an
    /// identifier that `cancel` takes back. macOS shows it even while
    /// Lanes is not running.
    static func schedule(_ kind: Kind, identifier: String, body: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = body
        let interval = max(date.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("Scheduling a notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func cancel(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: Claude Code

    nonisolated static let claudeCodeCategory = "claudeCode"
    nonisolated static let showTerminalAction = "showTerminal"

    /// Registers the "Terminale Git" button and answers clicks on it.
    static func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationResponder.shared
        let show = UNNotificationAction(identifier: showTerminalAction, title: String(localized: "Terminale Git"), options: [])
        let category = UNNotificationCategory(identifier: claudeCodeCategory, actions: [show], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    /// A "Bitti Haberi". Each session keeps one notification: a newer one
    /// replaces the one before, so a long conversation does not pile up.
    static func postClaudeCode(title: String, body: String, tty: String?, terminalProgram: String?, threadID: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = claudeCodeCategory
        content.threadIdentifier = threadID
        var info: [String: String] = [:]
        if let tty { info["tty"] = tty }
        if let terminalProgram { info["terminalProgram"] = terminalProgram }
        content.userInfo = info
        // One notification per terminal; without one, each stands alone.
        let identifier = "claudeCode-" + (tty ?? UUID().uuidString)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("Notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Shows Lanes's notifications while Lanes is in front too, and takes a
/// click on a Claude Code one to its terminal.
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationResponder()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let action = response.actionIdentifier
        if content.categoryIdentifier == Notifier.claudeCodeCategory,
           action == Notifier.showTerminalAction || action == UNNotificationDefaultActionIdentifier {
            let tty = content.userInfo["tty"] as? String
            let program = content.userInfo["terminalProgram"] as? String
            // A click on the notification itself brings Lanes forward
            // first; the terminal comes after it, so it ends up in front.
            // macOS also sends Lanes "reopen" for a click on the
            // notification itself, which would show Lanes's window.
            TerminalFocus.ignoreReopenUntil = Date().addingTimeInterval(2)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                TerminalFocus.show(tty: tty, terminalProgram: program)
            }
        }
        completionHandler()
    }
}
