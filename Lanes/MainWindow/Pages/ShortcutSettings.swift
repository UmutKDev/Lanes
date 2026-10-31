import AppKit
import LanesCore
import SwiftUI

/// Records a global shortcut for one target. Click, then press the keys.
/// Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    @Environment(AppModel.self) private var model
    let target: ShortcutTarget
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    if isRecording { stop() } else { start() }
                } label: {
                    Text(label)
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 120)
                }
                .help(isRecording ? "Esc ile vazgeç, Sil ile kaldır" : "Kısayol kaydetmek için tıkla")
                if current != nil, !isRecording {
                    Button {
                        try? model.setShortcut(nil, for: target)
                        message = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Kısayolu kaldır")
                }
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isUnavailable {
                Text("Başka bir uygulama bu tuşları kullanıyor, kısayol çalışmıyor.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { stop() }
    }

    private var current: KeyShortcut? {
        model.shortcuts.shortcut(for: target)
    }

    private var label: String {
        if isRecording { return String(localized: "Tuşlara bas…") }
        return current?.description ?? String(localized: "Kaydet")
    }

    private var isUnavailable: Bool {
        guard let current else { return false }
        return HotKeyCenter.shared.unavailable.contains { $0.sameKeys(as: current) }
    }

    private func start() {
        message = nil
        isRecording = true
        // The keys must reach the recorder, not fire an existing shortcut.
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isRecording {
            isRecording = false
            HotKeyCenter.shared.resume()
        }
    }

    private func handle(_ event: NSEvent) {
        let modifiers = HotKeyCenter.modifiers(from: event.modifierFlags)
        switch event.keyCode {
        case 53 where modifiers.isEmpty: // Esc
            stop()
            return
        case 51 where modifiers.isEmpty, 117 where modifiers.isEmpty: // Delete, Forward Delete
            try? model.setShortcut(nil, for: target)
            stop()
            return
        default:
            break
        }
        let shortcut = KeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: HotKeyCenter.keyLabel(for: event))
        do {
            try model.setShortcut(shortcut, for: target)
            message = nil
            stop()
        } catch ShortcutBindings.SetError.notAllowed {
            // Keep listening: the user usually just forgot a modifier.
            message = String(localized: "\(shortcut.description) tek başına olmaz. ⌘, ⌥ ya da ⌃ ile birlikte bas.")
        } catch let ShortcutBindings.SetError.inUse(other) {
            message = String(localized: "\(shortcut.description) zaten \(model.name(of: other)) için kullanılıyor.")
            stop()
        } catch {
            message = error.localizedDescription
            stop()
        }
    }
}

struct ShortcutsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Menü çubuğu paneli") {
                    ShortcutRecorder(target: .panel)
                }
                LabeledContent("Sonraki açık hesap") {
                    ShortcutRecorder(target: .nextAccount)
                }
                LabeledContent("Önceki açık hesap") {
                    ShortcutRecorder(target: .previousAccount)
                }
            } footer: {
                Text("Kısayollar her uygulamadayken çalışır. Lanes bunun için Erişilebilirlik ya da Giriş İzleme izni istemez: macOS ona yalnız burada kaydettiğin tuşlara basıldığını bildirir. Panel açıkken ⌘1–⌘9 ilk dokuz hesabı da açar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Hesaplar") {
                ForEach(model.library.profiles) { profile in
                    LabeledContent {
                        ShortcutRecorder(target: .profile(profile.id))
                    } label: {
                        HStack(spacing: 8) {
                            MonogramView(profile: profile, size: 20)
                            Text(profile.name)
                        }
                    }
                }
                Text("Hesap kapalıysa açar, açıksa penceresini öne getirir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !model.library.scenes.isEmpty {
                Section("Sahneler") {
                    ForEach(model.library.scenes) { scene in
                        LabeledContent(scene.name) {
                            ShortcutRecorder(target: .scene(scene.id))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct WindowBadgeSettings: View {
    @AppStorage(Preferences.Key.showsFrontAccountInMenuBar) private var showsFrontAccount = true

    var body: some View {
        Form {
            Section("Menü çubuğu") {
                Toggle("Simge öndeki Claude'un hesabını göstersin", isOn: $showsFrontAccount)
                Text("Öndeki pencere Lanes'in açtığı bir hesaba aitse menü çubuğundaki simge o hesabın rengini ve harfini alır. Başka bir uygulamaya geçince simge eski hâline döner. Lanes Claude pencerelerine bir şey eklemez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
