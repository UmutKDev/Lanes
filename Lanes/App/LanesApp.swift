import LanesCore
import SwiftUI

@main
struct LanesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Lanes has no separate Settings window: ⌘, opens the main window on
        // the Settings page. The empty scene stops SwiftUI from adding one.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Ayarlar…") {
                    appDelegate.router.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("Hesap Ekle…") {
                    appDelegate.router.showAddProfile()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Hesaplar") {
                ProfileMenuCommands(model: appDelegate.model, router: appDelegate.router)
            }
        }
    }
}

/// ⌘1 to ⌘9 open accounts in the order of the sidebar.
private struct ProfileMenuCommands: View {
    let model: AppModel
    let router: WindowRouter

    var body: some View {
        ForEach(Array(model.library.profiles.prefix(9).enumerated()), id: \.element.id) { index, profile in
            Button(profile.name) {
                model.open(profile)
            }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        }
        Divider()
        Button("Menü Çubuğu Panelini Göster") {
            router.togglePanel()
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }
}
