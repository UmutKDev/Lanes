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

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 14) {
                        MonogramView(profile: preview, size: 48)
                        TextField("Ad", text: $name, prompt: Text("Örneğin İş ya da Müşteri A"))
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                    }
                    ColorChooser(selection: $color)
                }
                Section {
                    Picker("Hesap türü", selection: $accountClass) {
                        ForEach(AccountClass.allCases, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    // New accounts open with Claude itself. Klon comes back
                    // once Lanes makes clones for real accounts, which waits
                    // on Faz 0 checks 3 and 5.
                    Text(ProfileMode.standard.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Toggle("Ekledikten sonra Claude'u bu hesapla aç", isOn: $opensAfterAdding)
                    Text("Claude boş bir pencereyle açılır. Giriş Claude'un kendi penceresinde olur, Lanes giriş bilgilerini görmez.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Yeni pencerede giriş") {
                    // Faz 0.5 check 3: the return link of a Google or email
                    // link sign-in reaches the main Claude, not the new
                    // window. Typing the emailed code works in any window.
                    SignInStep(number: 1, text: "Google ya da Apple ile değil, e-posta adresinle devam et.")
                    SignInStep(number: 2, text: "Gelen e-postadaki bağlantıya tıklama. Bağlantı ana hesabın penceresinde açılır.")
                    SignInStep(number: 3, text: "E-postadaki doğrulama kodunu yeni pencereye yaz.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Hesap Ekle") {
                    add()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 460)
        .onAppear {
            color = nextFreeColor()
        }
    }

    private var preview: Profile {
        Profile(name: name.isEmpty ? "?" : name, color: color, accountClass: accountClass)
    }

    private func nextFreeColor() -> ProfileColor {
        let used = Set(model.library.profiles.map(\.color))
        return ProfileColor.allCases.first { !used.contains($0) } ?? .blue
    }

    private func add() {
        guard let profile = model.addProfile(name: name, color: color, mode: .standard, accountClass: accountClass) else { return }
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
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

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ProfileColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.swatch.gradient)
                        .frame(width: 20, height: 20)
                        .overlay {
                            if selection == color {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.7), lineWidth: 2)
                                    .padding(-4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(color.displayName)
                .accessibilityLabel(Text(color.displayName))
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
