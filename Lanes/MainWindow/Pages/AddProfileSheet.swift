import LanesCore
import SwiftUI

/// Adds an account. Signing in then happens in Claude's own window, which
/// Lanes opens with the new account's empty folder.
struct AddProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var color: ProfileColor = .blue
    @State private var accountClass: AccountClass = .personal
    @State private var opensAfterAdding = true
    @State private var mode: ProfileMode = .signedClone

    var body: some View {
        Form {
            Section {
                TextField("Ad", text: $name, prompt: Text("Örneğin İş ya da Müşteri A"))
                    .multilineTextAlignment(.leading)
                // Label above the swatches, as on the account page, so the
                // wrapping grid gets the full row width and stays aligned.
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Renk")
                    ColorChooser(selection: $color)
                }
            } header: {
                // Hero preview of the new account's monogram, no background.
                MonogramView(profile: preview, size: DS.Monogram.hero)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s)
            }
            Section {
                Picker("Hesap türü", selection: $accountClass) {
                    ForEach(AccountClass.allCases, id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                    }
                }
                Picker("Nerede çalışsın", selection: $mode) {
                    Text("Claude uygulaması, kendi simgesiyle").tag(ProfileMode.signedClone)
                    Text("Lanes içinde, web sürümü").tag(ProfileMode.insideLanes)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(mode.explanation)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("Ekledikten sonra bu hesabı aç", isOn: $opensAfterAdding)
            } footer: {
                Text(mode == .insideLanes
                     ? "claude.ai'nin giriş sayfası Lanes'te yeni bir sekmede açılır. Lanes giriş bilgilerini görmez."
                     : "Claude boş bir pencereyle açılır. Giriş Claude'un kendi penceresinde olur, Lanes giriş bilgilerini görmez.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if mode.usesClaudeApp {
                Section("Yeni pencerede giriş") {
                    // Faz 0.5 check 3: the return link of a Google or email
                    // link sign-in reaches the main Claude, not the new
                    // window. Typing the emailed code works in any window.
                    SignInStep(number: 1, text: "Google ya da Apple ile değil, e-posta adresinle devam et.")
                    SignInStep(number: 2, text: "Gelen e-postadaki bağlantıya tıklama. Bağlantı Claude uygulamasının penceresinde açılır.")
                    SignInStep(number: 3, text: "E-postadaki doğrulama kodunu yeni pencereye yaz.")
                }
            }
        }
        .formStyle(.grouped)
        .animation(DS.Motion.standard, value: mode)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Hesap Ekle") {
                    add()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .presentationSizing(.form)
        .onAppear {
            color = nextFreeColor()
        }
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var preview: Profile {
        Profile(name: name.isEmpty ? "?" : name, color: color, accountClass: accountClass)
    }

    private func nextFreeColor() -> ProfileColor {
        let used = Set(model.library.profiles.map(\.color))
        return ProfileColor.allCases.first { !used.contains($0) } ?? .blue
    }

    private func add() {
        guard canAdd else { return }
        guard let profile = model.addProfile(name: name, color: color, mode: mode, accountClass: accountClass) else { return }
        dismiss()
        navigation.navigate(to: .account(profile.id))
        if opensAfterAdding {
            model.open(profile)
        }
    }
}

private struct SignInStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ColorChooser: View {
    @Binding var selection: ProfileColor

    /// Fixed 28-pt cells, packed from the leading edge; wraps when narrow.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: DS.Metrics.iconButton, maximum: DS.Metrics.iconButton), spacing: DS.Space.xs + 2)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.xs + 2) {
            ForEach(ProfileColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    ZStack {
                        // The selection ring is drawn inside the cell, so it
                        // never touches a neighbour or gets clipped.
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.7), lineWidth: 2)
                            .opacity(selection == color ? 1 : 0)
                        Circle()
                            .fill(color.swatch.gradient)
                            .frame(width: DS.Monogram.small, height: DS.Monogram.small)
                    }
                    .frame(width: DS.Metrics.iconButton, height: DS.Metrics.iconButton)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.displayName)
                .accessibilityLabel(Text(color.displayName))
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
        .animation(DS.Motion.hover, value: selection)
    }
}
