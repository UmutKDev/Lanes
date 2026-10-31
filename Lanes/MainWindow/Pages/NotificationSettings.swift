import AppKit
import SwiftUI
import UserNotifications

struct NotificationSettings: View {
    @State private var status: UNAuthorizationStatus?
    @State private var enabled: Set<Notifier.Kind> = Set(Notifier.Kind.allCases.filter(\.isEnabled))

    var body: some View {
        Form {
            Section {
                ForEach(Notifier.Kind.allCases) { kind in
                    Toggle(kind.title, isOn: binding(for: kind))
                }
            } footer: {
                Text("Bildirimlerde bağlantı, sohbet ya da hesabın içinden bir şey yer almaz. Yalnız hesabın adı ve olayın türü yazar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if status == .denied {
                Section {
                    Text("macOS Lanes'in bildirimlerine izin vermiyor.")
                    Button("Sistem Ayarları'nda Aç") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { status = await Notifier.authorizationStatus() }
    }

    private func binding(for kind: Notifier.Kind) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(kind) },
            set: { isOn in
                UserDefaults.standard.set(isOn, forKey: kind.preferenceKey)
                if isOn {
                    enabled.insert(kind)
                    Task {
                        _ = await Notifier.requestPermission()
                        status = await Notifier.authorizationStatus()
                    }
                } else {
                    enabled.remove(kind)
                }
            }
        )
    }
}
