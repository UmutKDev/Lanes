import LanesCore
import SwiftUI

/// Account Map: whether Lanes routes `claude://` links, and which account
/// each kind of link opens in.
struct AccountMapPage: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.Key.linkRoutingEnabled) private var isRouting = false

    var body: some View {
        Form {
            Section {
                Toggle("claude:// bağlantılarını hesaplara yönlendir", isOn: Binding(
                    get: { isRouting },
                    set: { enabled in
                        guard enabled else {
                            model.setLinkRouting(false)
                            return
                        }
                        // Turns on only once Lanes really holds the claude://
                        // default. If the user declines the system prompt,
                        // the toggle and rules must not look active while
                        // Claude still gets every link. takeLinks shows the
                        // warning itself.
                        Task {
                            await model.takeLinks()
                            isRouting = LinkHandlerRegistry.lanesIsHandler
                        }
                    }
                ))
            } footer: {
                footerText("Açıkken başka uygulamalardan gelen claude:// bağlantıları, aşağıdaki kurallara göre seçilen hesabın Claude'unda açılır. Hesap kapalıysa önce açılır. Giriş, OAuth ve Lanes'in tanımadığı bağlantılar hiçbir zaman yönlendirilmez: Lanes onları bırakır ve varsayılanı birkaç dakikalığına Claude'a geri verir, sen girişi bitirebilesin diye.")
            }
            SmartLinkRulesSection(isRouting: isRouting)
            Section {
                // Each picker is disabled on its own, so the label and the
                // value both dim while routing is off and none can be opened.
                Picker("Kural yoksa", selection: binding(nil)) {
                    targetOptions
                }
                .pickerStyle(.menu)
                .disabled(!isRouting)
                ForEach(LinkRules.LinkKind.allCases, id: \.self) { kind in
                    Picker(kind.title, selection: binding(kind)) {
                        Text("Genel kurala uy").tag(Optional<LinkRules.Target>.none)
                        targetOptions
                    }
                    .pickerStyle(.menu)
                    .disabled(!isRouting)
                }
            } header: {
                Text("Tür kuralları")
            } footer: {
                footerText("\"Öndeki hesap\", en son öne gelen hesabın Claude'udur. Hiçbiri öne gelmediyse bağlantı Claude uygulamasına gider.")
            }
            .foregroundStyle(isRouting ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
        }
        .libraryForm()
        .animation(DS.Motion.standard, value: isRouting)
    }

    @ViewBuilder
    private var targetOptions: some View {
        Text("Öndeki hesap").tag(Optional(LinkRules.Target.frontmost))
        ForEach(model.library.profiles) { profile in
            Text(profile.name).tag(Optional(LinkRules.Target.profile(profile.id)))
        }
    }

    private func footerText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// nil kind edits the fallback, which always has a value.
    private func binding(_ kind: LinkRules.LinkKind?) -> Binding<LinkRules.Target?> {
        Binding(
            get: {
                guard let kind else { return model.linkRules.fallback }
                return model.linkRules.byKind[kind]
            },
            set: { target in
                var rules = model.linkRules
                if let kind {
                    rules.byKind[kind] = target
                } else if let target {
                    rules.fallback = target
                }
                model.setLinkRules(rules)
            }
        )
    }
}

extension LinkRules.LinkKind {
    var title: String {
        switch self {
        case .newChat: return String(localized: "Yeni sohbet")
        case .code: return String(localized: "Claude Code oturumları")
        case .resume: return String(localized: "Sohbeti sürdür")
        case .cowork: return String(localized: "Cowork")
        case .settings: return String(localized: "Claude ayarları")
        }
    }
}

/// Links: what reached Lanes in the last 30 days, where it went and why.
/// Only the kind of link is kept, never the link itself.
struct LinksPage: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingClear = false

    var body: some View {
        // The table always exists; the empty state lies over it.
        Table(model.receivedLinks) {
            TableColumn("Zaman") { link in
                Text(Calendar.current.isDateInToday(link.receivedAt)
                     ? link.receivedAt.formatted(date: .omitted, time: .shortened)
                     : link.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 120)
            TableColumn("Tür") { link in
                Text(link.kind)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(link.kind)
            }
            TableColumn("Hesap") { link in
                // No view that reads the model from the environment here:
                // table cells being removed (clearing the log) lose it.
                if let id = link.target, let profile = model.profile(withID: id) {
                    HStack(spacing: DS.Space.xs) {
                        MonogramView(profile: profile, size: DS.Monogram.tiny)
                        Text(profile.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Kaynak") { link in
                Text(link.source ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 90)
            TableColumn("Sonuç") { link in
                Text(link.outcome)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(link.outcome)
            }
            .width(min: 80, ideal: 150)
            TableColumn("Neden") { link in
                Text(link.reason ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(link.reason ?? "")
            }
            .width(min: 140, ideal: 300)
        }
        .tableStyle(.inset)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .opacity(model.receivedLinks.isEmpty ? 0 : 1)
        .dsEmptyState(model.receivedLinks.isEmpty) {
            DSEmptyState(
                "Henüz bağlantı gelmedi",
                systemImage: Destination.links.symbol,
                description: Text(model.isLinkRoutingOn
                     ? "Başka bir uygulamadan bir claude:// bağlantısı açıldığında burada türünü, hangi hesaba gittiğini ve nedenini görürsün. Kayıtlar 30 gün tutulur."
                     : "Bağlantı yönlendirme kapalı. Hesap Haritası'ndan açabilirsin.")
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isConfirmingClear = true
                } label: {
                    Label("Günlüğü Temizle", systemImage: "trash")
                }
                .help("Günlüğü Temizle")
                .disabled(model.receivedLinks.isEmpty)
            }
        }
        .confirmationDialog("Bağlantı günlüğü temizlensin mi?", isPresented: $isConfirmingClear) {
            Button("Temizle", role: .destructive) {
                // After the dialog has gone, so the table doesn't update
                // its rows while the sheet is still dismissing.
                DispatchQueue.main.async { model.clearLinkLog() }
            }
        } message: {
            Text("Son 30 günün kayıtları silinir. Bağlantıların kendisi zaten hiç saklanmaz.")
        }
    }
}
