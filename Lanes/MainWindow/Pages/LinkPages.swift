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
                    set: { model.setLinkRouting($0) }
                ))
            } footer: {
                footerText("Açıkken başka uygulamalardan gelen claude:// bağlantıları, aşağıdaki kurallara göre seçilen hesabın Claude'unda açılır. Hesap kapalıysa önce açılır. Giriş, OAuth ve Lanes'in tanımadığı bağlantılar hiçbir zaman yönlendirilmez: Lanes onları bırakır ve varsayılanı birkaç dakikalığına Claude'a geri verir, sen girişi bitirebilesin diye.")
            }
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
                Text("Kurallar")
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

/// Links: what reached Lanes in this session and where it went. Only the
/// kind of link is kept, never the link itself.
struct LinksPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The table always exists; the empty state lies over it.
        Table(model.receivedLinks) {
            TableColumn("Saat") { link in
                Text(link.receivedAt.formatted(date: .omitted, time: .standard))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Tür") { link in
                Text(link.kind)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(link.kind)
            }
            TableColumn("Hesap") { link in
                if let id = link.target, let profile = model.profile(withID: id) {
                    DSAccountLabel(profile: profile, size: DS.Monogram.tiny)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Sonuç") { link in
                Text(link.outcome)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(link.outcome)
            }
        }
        .tableStyle(.inset)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .opacity(model.receivedLinks.isEmpty ? 0 : 1)
        .dsEmptyState(model.receivedLinks.isEmpty) {
            DSEmptyState(
                "Henüz bağlantı gelmedi",
                systemImage: Destination.links.symbol,
                description: Text(model.isLinkRoutingOn
                     ? "Başka bir uygulamadan bir claude:// bağlantısı açıldığında burada türünü ve hangi hesaba gittiğini görürsün."
                     : "Bağlantı yönlendirme kapalı. Hesap Haritası'ndan açabilirsin.")
            )
        }
    }
}
