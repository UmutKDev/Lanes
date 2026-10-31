import AppKit
import SwiftUI
import UserNotifications

struct NotificationSettings: View {
    @State private var status: UNAuthorizationStatus?
    @State private var enabled: Set<Notifier.Kind> = Set(Notifier.Kind.allCases.filter(\.isEnabled))
    @AppStorage(Preferences.Key.memoryAlertGigabytes) private var memoryAlert: Double = 0

    var body: some View {
        Form {
            Section {
                ForEach(Notifier.Kind.switchable) { kind in
                    Toggle(kind.title, isOn: binding(for: kind))
                }
            } footer: {
                Text("Bildirimlerde bağlantı, sohbet ya da hesabın içinden bir şey yer almaz. Yalnız hesabın adı ve olayın türü yazar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Bellek uyarısı", selection: $memoryAlert) {
                    Text("Kapalı").tag(0.0)
                    ForEach([4.0, 8.0, 12.0, 16.0, 24.0], id: \.self) { gigabytes in
                        Text("\(Int(gigabytes)) GB üstünde").tag(gigabytes)
                    }
                }
                .onChange(of: memoryAlert) { _, value in
                    if value > 0 { Task { _ = await Notifier.requestPermission() } }
                }
            } footer: {
                Text("Açık hesapların Claude'ları birlikte bu kadar belleği geçince, en çok saatte bir bildirim gösterilir. Hesaplara göre günlük süre hatırlatması her hesabın Genel sekmesinde.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
