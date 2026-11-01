import AppKit
import LanesCore
import SwiftUI

/// Records a global shortcut for one target. Click, then press the keys.
/// Esc cancels, Delete clears.
///
/// A fixed-size key field with a clear button whose slot is always laid
/// out, so nothing in the row moves while recording. Errors go to `message`,
/// which the row shows under its title.
struct ShortcutRecorder: View {
    @Environment(AppModel.self) private var model
    let target: ShortcutTarget
    @Binding private var message: String?
    @State private var isRecording = false
    @State private var monitor: Any?

    /// Width of the key field. Wide enough for "⌃⌥⇧⌘F12" and "Tuşlara bas…".
    private let fieldWidth: CGFloat = 140

    init(target: ShortcutTarget, message: Binding<String?>) {
        self.target = target
        self._message = message
    }

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Button {
                if isRecording { stop() } else { start() }
            } label: {
                field
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Esc ile vazgeç, Sil ile kaldır" : "Kısayol kaydetmek için tıkla")

            DSIconButton("Kısayolu kaldır", systemImage: "xmark.circle.fill") {
                try? model.setShortcut(nil, for: target)
                message = nil
            }
            .opacity(canClear ? 1 : 0)
            .disabled(!canClear)
            .accessibilityHidden(!canClear)
        }
        .animation(DS.Motion.standard, value: isRecording)
        .onDisappear { stop() }
    }

    /// Looks like a key field, not a button: a soft fill when idle, the
    /// accent colour with a pulsing record symbol while listening.
    private var field: some View {
        HStack(spacing: DS.Space.xs + 2) {
            Image(systemName: isRecording ? "record.circle" : "keyboard")
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: isRecording)
                .foregroundStyle(isRecording ? Color.white : Color.secondary)
                // VoiceOver reads only the shortcut text, as before.
                .accessibilityHidden(true)
            Text(label)
                .font(current == nil || isRecording ? DS.Typography.rowTitle : DS.Typography.rowTitle.monospacedDigit())
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs)
        .frame(width: fieldWidth)
        .background(
            isRecording ? Color.accentColor : DS.Palette.codeFill,
            in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
    }

    private var labelColor: Color {
        if isRecording { return .white }
        return current == nil ? .secondary : .primary
    }

    private var canClear: Bool {
        current != nil && !isRecording
    }

    private var current: KeyShortcut? {
        model.shortcuts.shortcut(for: target)
    }

    private var label: String {
        if isRecording { return String(localized: "Tuşlara bas…") }
        return current?.description ?? String(localized: "Kaydet")
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

/// One settings row: the title (and any recorder error or conflict under it)
/// on the left, the recorder on the right.
private struct ShortcutRow<Title: View>: View {
    @Environment(AppModel.self) private var model
    let target: ShortcutTarget
    private let title: Title
    @State private var message: String?

    init(target: ShortcutTarget, @ViewBuilder title: () -> Title) {
        self.target = target
        self.title = title()
    }

    var body: some View {
        LabeledContent {
            ShortcutRecorder(target: target, message: $message)
                .fixedSize()
        } label: {
            title
            if let message {
                problem(Text(message), tint: DS.Palette.danger)
            } else if isUnavailable {
                problem(Text("Başka bir uygulama bu tuşları kullanıyor, kısayol çalışmıyor."), tint: DS.Palette.warning)
            }
        }
        .animation(DS.Motion.standard, value: message)
    }

    private func problem(_ text: Text, tint: Color) -> some View {
        Label {
            text
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DS.Typography.caption)
                .foregroundStyle(tint)
        }
    }

    private var isUnavailable: Bool {
        guard let current = model.shortcuts.shortcut(for: target) else { return false }
        return HotKeyCenter.shared.unavailable.contains { $0.sameKeys(as: current) }
    }
}

struct ShortcutsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ShortcutRow(target: .panel) {
                    Text("Menü çubuğu paneli")
                        .lineLimit(1)
                }
                ShortcutRow(target: .nextAccount) {
                    Text("Sonraki açık hesap")
                        .lineLimit(1)
                }
                ShortcutRow(target: .previousAccount) {
                    Text("Önceki açık hesap")
                        .lineLimit(1)
                }
                ShortcutRow(target: .palette) {
                    Text("Komut Paleti")
                        .lineLimit(1)
                }
            } header: {
                Text("Kısayollar")
            } footer: {
                Text("Kısayollar her uygulamadayken çalışır. Lanes bunun için Erişilebilirlik ya da Giriş İzleme izni istemez: macOS ona yalnız burada kaydettiğin tuşlara basıldığını bildirir. Panel açıkken ⌘1–⌘9 ilk dokuz hesabı da açar.")
            }
            Section {
                if model.library.profiles.isEmpty {
                    Text("Henüz hesap yok.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.library.profiles) { profile in
                    ShortcutRow(target: .profile(profile.id)) {
                        DSAccountLabel(profile: profile, size: DS.Monogram.small)
                    }
                }
            } header: {
                Text("Hesaplar")
            } footer: {
                Text("Hesap kapalıysa açar, açıksa penceresini öne getirir.")
            }
            if !model.library.scenes.isEmpty {
                Section {
                    ForEach(model.library.scenes) { scene in
                        ShortcutRow(target: .scene(scene.id)) {
                            Label {
                                Text(scene.name)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } icon: {
                                Image(systemName: "rectangle.3.group")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Sahneler")
                }
            }
        }
        .settingsForm()
    }
}
