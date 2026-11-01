import AppKit
import LanesCore
import SwiftUI

/// The "Akıllı kurallar" section of the Account Map: rules by hour, day and
/// the app a link was clicked in, tried in order before the kind rules.
struct SmartLinkRulesSection: View {
    @Environment(AppModel.self) private var model
    let isRouting: Bool
    @State private var editing: LinkRule?
    @State private var isAdding = false

    var body: some View {
        Section {
            ForEach(Array(model.linkRules.rules.enumerated()), id: \.element.id) { index, rule in
                HStack(alignment: .center, spacing: DS.Space.m) {
                    Toggle("", isOn: enabledBinding(rule.id))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(rule.name.isEmpty ? String(localized: "Adsız kural") : rule.name)
                            .lineLimit(1)
                        Text(Self.summary(of: rule, model: model))
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Button("Düzenle…") { editing = rule }
                        Button("Yukarı Taşı") { move(rule.id, by: -1) }
                            .disabled(index == 0)
                        Button("Aşağı Taşı") { move(rule.id, by: 1) }
                            .disabled(index == model.linkRules.rules.count - 1)
                        Divider()
                        Button("Sil", role: .destructive) { remove(rule.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(Text("Kural seçenekleri"))
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editing = rule }
            }
            Button("Kural Ekle…") { isAdding = true }
        } header: {
            Text("Akıllı kurallar")
        } footer: {
            Text("Kurallar yukarıdan aşağı denenir; ilk uyan kural bağlantıyı alır. Hiçbiri uymazsa aşağıdaki tür kuralları geçerlidir. Kaynak uygulama, bağlantı geldiğinde önde olan uygulamadır. Açık bir odak filtresi hesap seçtiyse o önce gelir.")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!isRouting)
        .sheet(isPresented: $isAdding) {
            LinkRuleEditor(rule: nil)
        }
        .sheet(item: $editing) { rule in
            LinkRuleEditor(rule: rule)
        }
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.linkRules.rules.first { $0.id == id }?.isEnabled ?? false },
            set: { isOn in
                var rules = model.linkRules
                guard let index = rules.rules.firstIndex(where: { $0.id == id }) else { return }
                rules.rules[index].isEnabled = isOn
                model.setLinkRules(rules)
            }
        )
    }

    private func move(_ id: UUID, by offset: Int) {
        var rules = model.linkRules
        guard let index = rules.rules.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard rules.rules.indices.contains(target) else { return }
        rules.rules.swapAt(index, target)
        model.setLinkRules(rules)
    }

    private func remove(_ id: UUID) {
        var rules = model.linkRules
        rules.rules.removeAll { $0.id == id }
        model.setLinkRules(rules)
    }

    /// "Slack · Yeni sohbet · Pzt–Cum 09:00–18:00 → İş"
    static func summary(of rule: LinkRule, model: AppModel) -> String {
        var parts: [String] = []
        if !rule.sourceApps.isEmpty {
            parts.append(rule.sourceApps.map(\.name).joined(separator: ", "))
        }
        if !rule.kinds.isEmpty {
            parts.append(LinkRules.LinkKind.allCases.filter(rule.kinds.contains).map(\.title).joined(separator: ", "))
        }
        if let window = rule.window {
            parts.append(describe(window))
        }
        if parts.isEmpty {
            parts.append(String(localized: "Her bağlantı"))
        }
        let target: String
        switch rule.target {
        case .frontmost: target = String(localized: "Öndeki hesap")
        case let .profile(id): target = model.profile(withID: id)?.name ?? String(localized: "Silinmiş hesap")
        }
        return parts.joined(separator: " · ") + " → " + target
    }

    static func describe(_ window: LinkTimeWindow) -> String {
        func time(_ minute: Int) -> String {
            String(format: "%02d:%02d", minute / 60, minute % 60)
        }
        let hours = window.startMinute == window.endMinute
            ? String(localized: "tüm gün")
            : "\(time(window.startMinute))–\(time(window.endMinute))"
        guard !window.weekdays.isEmpty else { return hours }
        let symbols = Calendar.current.shortWeekdaySymbols
        let days = [2, 3, 4, 5, 6, 7, 1].filter(window.weekdays.contains).map { symbols[$0 - 1] }.joined(separator: " ")
        return "\(days) \(hours)"
    }
}

/// Adds or edits one rule.
private struct LinkRuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let rule: LinkRule?
    @State private var name = ""
    @State private var kinds: Set<LinkRules.LinkKind> = []
    @State private var sourceApps: [LinkSourceApp] = []
    @State private var usesWindow = false
    @State private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var end = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var target: LinkRules.Target = .frontmost

    var body: some View {
        Form {
            Section {
                TextField("Ad", text: $name, prompt: Text("Örneğin Mesai"))
                Picker("Hesap", selection: $target) {
                    Text("Öndeki hesap").tag(LinkRules.Target.frontmost)
                    ForEach(model.library.profiles) { profile in
                        Text(profile.isArchived ? String(localized: "\(profile.name) (arşivde)") : profile.name)
                            .tag(LinkRules.Target.profile(profile.id))
                    }
                }
            }
            Section {
                ForEach(LinkRules.LinkKind.allCases, id: \.self) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { kinds.contains(kind) },
                        set: { isOn in
                            if isOn { kinds.insert(kind) } else { kinds.remove(kind) }
                        }
                    ))
                }
            } header: {
                Text("Bağlantı türleri")
            } footer: {
                caption("Hiçbiri seçilmezse her tür bağlantıya uyar.")
            }
            Section {
                ForEach(sourceApps, id: \.bundleIdentifier) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Button {
                            sourceApps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("\(app.name) uygulamasını çıkar"))
                    }
                }
                Menu("Uygulama Ekle") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.name) { add(app) }
                    }
                    Divider()
                    Button("Başka Bir Uygulama Seç…") { chooseApp() }
                }
            } header: {
                Text("Kaynak uygulama")
            } footer: {
                caption("Bağlantıya tıkladığın uygulama. Hiçbiri eklenmezse her uygulamadan gelen bağlantıya uyar.")
            }
            Section {
                Toggle("Yalnız belli saatlerde", isOn: $usesWindow)
                if usesWindow {
                    DatePicker("Başlangıç", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Bitiş", selection: $end, displayedComponents: .hourAndMinute)
                    WeekdayPicker(selection: $weekdays)
                }
            } footer: {
                if usesWindow {
                    caption("Bitiş başlangıçtan önceyse gece yarısını geçer (22:00–02:00). Günler, aralığın başladığı gündür; hiçbiri seçilmezse her gün.")
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(rule == nil ? "Ekle" : "Kaydet") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .presentationSizing(.form)
        .onAppear {
            guard let rule else { return }
            name = rule.name
            kinds = rule.kinds
            sourceApps = rule.sourceApps
            target = rule.target
            if let window = rule.window {
                usesWindow = true
                start = Self.date(forMinute: window.startMinute)
                end = Self.date(forMinute: window.endMinute)
                weekdays = window.weekdays
            }
        }
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Regular apps that are running, without Lanes and Claude windows.
    private var runningApps: [LinkSourceApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let claudePIDs = Set(model.instances.map(\.pid))
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !claudePIDs.contains($0.processIdentifier) }
            .compactMap { app -> LinkSourceApp? in
                guard let id = app.bundleIdentifier, id != ClaudeInstallation.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return LinkSourceApp(bundleIdentifier: id, name: app.localizedName ?? id)
            }
            .filter { app in !sourceApps.contains { $0.bundleIdentifier == app.bundleIdentifier } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func add(_ app: LinkSourceApp) {
        guard !sourceApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        sourceApps.append(app)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = String(localized: "Seç")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        add(LinkSourceApp(bundleIdentifier: id, name: name))
    }

    private static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func date(forMinute minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    private func save() {
        let window = usesWindow ? LinkTimeWindow(startMinute: Self.minute(of: start), endMinute: Self.minute(of: end), weekdays: weekdays) : nil
        let edited = LinkRule(
            id: rule?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            isEnabled: rule?.isEnabled ?? true,
            kinds: kinds,
            sourceApps: sourceApps,
            window: window,
            target: target
        )
        var rules = model.linkRules
        if let index = rules.rules.firstIndex(where: { $0.id == edited.id }) {
            rules.rules[index] = edited
        } else {
            rules.rules.append(edited)
        }
        model.setLinkRules(rules)
    }
}
