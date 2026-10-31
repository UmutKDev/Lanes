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
            }
        }

        /// Reminders the user turns on where they set them (a daily limit,
        /// a memory limit) have no switch of their own.
        static var switchable: [Kind] {
            allCases.filter { $0 != .dailyLimit && $0 != .memoryHigh }
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
}
