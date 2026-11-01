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
                Text("Öteki hesaplar gizlenir ama açık kalır. Tam ekrandaki ya da küçültülmüş pencerelere dokunulmaz.")
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
                    Text("Claude penceresini taşımak ve boyutlandırmak için gerekir. Sekmeli modu kapatınca izni geri alabilirsin.")
                        .help("Lanes pencerelerin içine ve başlıklarına bakmaz. İzni Sistem Ayarları'ndan geri alabilirsin.")
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
