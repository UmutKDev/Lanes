import Combine
import SwiftUI

/// Settings > Sekmeler: turns tab mode on and explains what it does.
struct TabSettings: View {
    @AppStorage(Preferences.Key.tabModeEnabled) private var isOn = false
    @State private var isGranted = AccessibilityPermission.isGranted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Hesapları sekme olarak göster", isOn: $isOn)
                    .onChange(of: isOn) { _, on in
                        if on, !AccessibilityPermission.isGranted {
                            AccessibilityPermission.request()
                        }
                    }
                Text("Ekranın üstünde Chrome'daki gibi ince bir sekme çubuğu açılır. Bir sekmeye tıklayınca o hesabın Claude penceresi çubuğun hemen altına, aynı genişlikte yerleşir ve öteki hesaplar gizlenir. Gizlenen hesaplar arkada açık kalır, geri dönünce oldukları gibi gelir. Çubuğu taşıyınca ya da boyutunu değiştirince Claude da onunla gider, Claude'un penceresini taşıyınca da çubuk onu izler.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Erişilebilirlik izni") {
                if isGranted {
                    Label("İzin verilmiş", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("İzin verilmedi", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    HStack {
                        Button("İzin İste") {
                            AccessibilityPermission.request()
                        }
                        Button("Sistem Ayarları'nı Aç") {
                            AccessibilityPermission.openSettings()
                        }
                    }
                }
                Text("Claude'un penceresini taşımak ve boyutlandırmak için gerekiyor. Lanes bu izinle yalnız etkin hesabın Claude penceresinin yerine ve boyutuna dokunur. Pencerelerin içine, başlıklarına ya da yazdıklarına bakmaz. Sekmeli modu kapatınca izni Sistem Ayarları'ndan geri alabilirsin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Sınırlar") {
                Text("macOS, bir uygulamanın başka bir uygulamanın penceresini kendi içine almasına izin vermiyor. Bu yüzden her hesap yine kendi Claude penceresinde çalışır, Claude'un kendi pencere çerçevesi de görünür kalır. Tam ekrandaki ya da küçültülmüş bir pencereye dokunulmaz. Bir hesabın birden çok penceresi varsa öndeki yerleşir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            isGranted = AccessibilityPermission.isGranted
        }
    }
}
