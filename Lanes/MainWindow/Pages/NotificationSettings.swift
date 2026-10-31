import AppKit
import Combine
import SwiftUI
import UserNotifications

struct NotificationSettings: View {
    @State private var status: UNAuthorizationStatus?
    @State private var enabled: Set<Notifier.Kind> = Set(Notifier.Kind.allCases.filter(\.isEnabled))
    @AppStorage(Preferences.Key.memoryAlertGigabytes) private var memoryAlert: Double = 0

    var body: some View {
        Form {
            if status == .denied {
                Section {
                    LabeledContent {
                        Button("Sistem Ayarları'nda Aç") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .dsPrimaryAction()
                        .fixedSize()
                    } label: {
                        Label {
                            Text("macOS Lanes'in bildirimlerine izin vermiyor.")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "bell.slash.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(DS.Palette.warning)
                        }
                    }
                }
            }
            Section {
                ForEach(Notifier.Kind.switchable) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Text(kind.title)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("Bildirimler")
            } footer: {
                Text("Bildirimlerde bağlantı, sohbet ya da hesabın içinden bir şey yer almaz. Yalnız hesabın adı ve olayın türü yazar.")
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
            }
        }
        .settingsForm()
        .animation(DS.Motion.standard, value: status)
        .task { status = await Notifier.authorizationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { status = await Notifier.authorizationStatus() }
        }
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
