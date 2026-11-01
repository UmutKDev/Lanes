import AppKit
import Combine
import SwiftUI

/// Settings > Sekmeler: turns tab mode on and explains what it does.
struct TabSettings: View {
    @AppStorage(Preferences.Key.tabModeEnabled) private var isOn = false
    @State private var isGranted = AccessibilityPermission.isGranted

    var body: some View {
        Form {
            Section {
                Toggle("Hesapları sekme olarak göster", isOn: $isOn)
                    .onChange(of: isOn) { _, on in
                        if on, !AccessibilityPermission.isGranted {
                            AccessibilityPermission.request()
                        }
                    }
            } header: {
                Text("Sekmeler")
            } footer: {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Ekranın üstünde Chrome'daki gibi ince bir sekme çubuğu açılır. Bir sekmeye tıklayınca o hesabın Claude penceresi çubuğun hemen altına, aynı genişlikte yerleşir ve öteki hesaplar gizlenir. Gizlenen hesaplar arkada açık kalır, geri dönünce oldukları gibi gelir. Çubuğu taşıyınca ya da boyutunu değiştirince Claude da onunla gider, Claude'un penceresini taşıyınca da çubuk onu izler.")
                    Text("Sınırlar")
                        .fontWeight(.semibold)
                    Text("macOS, bir uygulamanın başka bir uygulamanın penceresini kendi içine almasına izin vermiyor. Bu yüzden her hesap yine kendi Claude penceresinde çalışır, Claude'un kendi pencere çerçevesi de görünür kalır. Tam ekrandaki ya da küçültülmüş bir pencereye dokunulmaz. Bir hesabın birden çok penceresi varsa öndeki yerleşir.")
                }
            }
            Section {
                // One stable row: the state on the left, the request button
                // on the right, kept in place (hidden) once permission is given.
                LabeledContent {
                    Button("İzin İste") {
                        AccessibilityPermission.request()
                    }
                    .fixedSize()
                    .opacity(isGranted ? 0 : 1)
                    .disabled(isGranted)
                    .accessibilityHidden(isGranted)
                } label: {
                    Label {
                        (isGranted ? Text("İzin verilmiş") : Text("İzin verilmedi"))
                            .lineLimit(1)
                    } icon: {
                        DSStatusIcon(status: isGranted ? .ok : .warning)
                    }
                }
            } header: {
                Text("Erişilebilirlik izni")
            } footer: {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Claude'un penceresini taşımak ve boyutlandırmak için gerekiyor. Lanes bu izinle yalnız etkin hesabın Claude penceresinin yerine ve boyutuna dokunur. Pencerelerin içine, başlıklarına ya da yazdıklarına bakmaz. Sekmeli modu kapatınca izni Sistem Ayarları'ndan geri alabilirsin.")
                    Button("Sistem Ayarları'nı Aç") {
                        AccessibilityPermission.openSettings()
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .settingsForm()
        .animation(DS.Motion.standard, value: isGranted)
        // Poll only while permission is missing; restart when it changes.
        .task(id: isGranted) {
            while !Task.isCancelled && !isGranted {
                try? await Task.sleep(for: .seconds(1))
                isGranted = AccessibilityPermission.isGranted
            }
        }
        // Permission can also be taken back in System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isGranted = AccessibilityPermission.isGranted
        }
    }
}
