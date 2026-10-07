import AppKit
import LanesCore
import SwiftUI

// Helpers for the Faz 0.5 checks. None of them quits a Claude window or
// opens a file under a profile's folders: they record what Lanes can see
// from the outside, and the user says the rest.

/// A yes/no answer kept in the model until the check is saved, so looking at
/// another check on the way does not lose it.
@MainActor
private func draftAnswer(_ validation: ValidationModel, _ check: ValidationCheckID, _ key: String) -> Binding<Bool?> {
    Binding(
        get: { validation.draftAnswers[check]?[key] },
        set: { validation.draftAnswers[check, default: [:]][key] = $0 }
    )
}

/// Passed when every answer is yes, failed when none is, partial otherwise.
private func outcome(for answers: [Bool]) -> ValidationOutcome {
    if answers.allSatisfy({ $0 }) { return .passed }
    if !answers.contains(true) { return .failed }
    return .partial
}

private func yesNo(_ value: Bool?) -> String {
    switch value {
    case true?: return "evet"
    case false?: return "hayır"
    case nil: return "cevaplanmadı"
    }
}

/// Reads a bundle's version from its Info.plist on every call. `Bundle`
/// caches what it read, so it can miss an update that replaced the app.
func bundleVersion(at appURL: URL) -> String? {
    let plist = appURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
    guard let data = try? Data(contentsOf: plist),
          let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return nil }
    let short = info["CFBundleShortVersionString"] as? String
    let build = info["CFBundleVersion"] as? String
    switch (short, build) {
    case let (short?, build?) where short != build: return "\(short) (\(build))"
    case let (short?, _): return short
    case let (nil, build?): return build
    default: return nil
    }
}

@MainActor
private func instanceLines(_ model: AppModel) -> [String] {
    if model.instances.isEmpty {
        return ["Açık Claude penceresi yok."]
    }
    return model.instances.map {
        "\(instanceLabel($0, model: model)): \($0.userDataDirectory ?? "Claude'un kendi klasörü")"
    }
}

private func handlerLine() -> String {
    "claude:// bağlantılarını açan: \(LinkHandlerRegistry.currentHandler()?.path ?? "yok")"
}

/// The open Claude windows and the data folder each one uses.
private struct InstanceFolders: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.instances.isEmpty {
                Text("Şu an açık Claude yok.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.instances) { instance in
                VStack(alignment: .leading, spacing: 2) {
                    Text(instanceLabel(instance, model: model))
                    Text(instance.userDataDirectory ?? String(localized: "Claude'un kendi klasörü"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct StatusText: View {
    let status: String?

    var body: some View {
        if let status {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: 0.5.1 The clone made before a Claude update

struct StaleCloneAssistant: View {
    @Environment(AppModel.self) private var model
    @State private var isWorking = false
    @State private var status: String?

    private let check = ValidationCheckID.staleClone
    private var cloneURL: URL { model.paths.cloneBundle(for: ValidationModel.cloneTestProfile) }

    var body: some View {
        let validation = model.validation
        let cloneExists = FileManager.default.fileExists(atPath: cloneURL.path)
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Deneme klonu") {
                    Text(cloneURL.path)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !cloneExists {
                    Text("Diskte deneme klonu yok. 3. denemeden bir klon oluştur ve bu denemeyi Claude'un bir sonraki güncellemesinden sonra yap.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ButtonRow {
                    Button("Klonu İncele") {
                        Task { await inspect() }
                    }
                    Button("Klonu Aç") {
                        Task { await openClone() }
                    }
                    .disabled(model.claude == nil)
                }
                .disabled(isWorking || !cloneExists)

                Text("Klonu açınca şunlara bak:")
                YesNoRow(title: String(localized: "Klon açıldı"), answer: draftAnswer(validation, check, "opened"))
                YesNoRow(title: String(localized: "Dock'ta klonun kendi simgesi duruyor"), answer: draftAnswer(validation, check, "iconKept"))
                YesNoRow(title: String(localized: "Klon güncelleme istedi ya da kendini güncelledi"), answer: draftAnswer(validation, check, "updaterActed"))
                Button("Sonucu Kaydet") {
                    save()
                }
                .disabled(["opened", "iconKept", "updaterActed"].contains { validation.draftAnswers[check]?[$0] == nil })
                StatusText(status: status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func inspect() async {
        isWorking = true
        defer { isWorking = false }
        status = String(localized: "Klon inceleniyor…")
        var lines = ["Klonun sürümü: \(bundleVersion(at: cloneURL) ?? "okunamadı")"]
        if let claude = model.claude {
            lines.append("Claude.app'in sürümü: \(bundleVersion(at: claude.url) ?? "okunamadı")")
        }
        if let created = try? cloneURL.resourceValues(forKeys: [.creationDateKey]).creationDate {
            lines.append("Klonun oluşturulduğu tarih: \(created.formatted(date: .abbreviated, time: .shortened))")
        }
        let signature = await CloneSignature.check(cloneURL)
        lines.append(contentsOf: signature.lines)
        model.validation.draftAnswers[check, default: [:]]["signatureValid"] = signature.isValid
        model.validation.appendEvidence(lines, for: check)
        status = signature.isValid
            ? String(localized: "İmza ve Gatekeeper klonu kabul ediyor. Şimdi klonu aç.")
            : String(localized: "İmza ya da Gatekeeper klonu reddetti. Ayrıntılar kayıtlarda.")
    }

    private func openClone() async {
        guard let claude = model.claude else { return }
        let profile = ValidationModel.cloneTestProfile
        let plan = LaunchPlanner.plan(for: profile, claudeApp: claude.url, cloneApp: cloneURL, paths: model.paths)
        do {
            let app = try await InstanceLauncher.launch(plan)
            model.validation.appendEvidence(["Klon açıldı, PID \(app.processIdentifier)."], for: check)
            status = String(localized: "Klon açıldı. Dock'a bak ve güncelleme isteyip istemediğini izle.")
        } catch {
            model.validation.appendEvidence(["Klon açılamadı: \(error.localizedDescription)"], for: check)
            status = error.localizedDescription
        }
        model.refreshInstances()
    }

    private func save() {
        let answers = model.validation.draftAnswers[check] ?? [:]
        model.validation.appendEvidence([
            "Klon açıldı: \(yesNo(answers["opened"]))",
            "Kendi simgesi duruyor: \(yesNo(answers["iconKept"]))",
            "Güncelleme istedi ya da kendini güncelledi: \(yesNo(answers["updaterActed"]))",
            "Klonun sürümü şimdi: \(bundleVersion(at: cloneURL) ?? "okunamadı")",
            "İmza ve Gatekeeper: \(answers["signatureValid"].map { $0 ? "geçerli" : "geçersiz" } ?? "incelenmedi")",
        ], for: check)
        var required = [answers["opened"] == true, answers["iconKept"] == true]
        if let signatureValid = answers["signatureValid"] {
            required.append(signatureValid)
        }
        model.validation.setOutcome(outcome(for: required), for: check)
        status = String(localized: "Kaydedildi.")
    }
}

// MARK: 0.5.2 A clone opened without Lanes

struct CloneOutsideLanesAssistant: View {
    @Environment(AppModel.self) private var model
    @State private var status: String?

    private let check = ValidationCheckID.cloneOutsideLanes
    private var cloneURL: URL { model.paths.cloneBundle(for: ValidationModel.cloneTestProfile) }

    var body: some View {
        let cloneExists = FileManager.default.fileExists(atPath: cloneURL.path)
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 12) {
                if !cloneExists {
                    Text("Diskte deneme klonu yok. Önce 3. denemeden bir klon oluştur.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ButtonRow {
                    Button("Finder'da Göster") {
                        NSWorkspace.shared.activateFileViewerSelecting([cloneURL])
                    }
                    .disabled(!cloneExists)
                    Button("Yenile") {
                        model.refreshInstances()
                    }
                    Button("Durumu Kaydet") {
                        record()
                    }
                }
                InstanceFolders()
                Text(handlerLine())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                StatusText(status: status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func record() {
        model.refreshInstances()
        let clonePath = InstanceMatcher.normalize(cloneURL.path)
        let clones = model.instances.filter { InstanceMatcher.normalize($0.applicationBundlePath) == clonePath }
        var lines = instanceLines(model)
        if clones.isEmpty {
            lines.append("Deneme klonu açık değil.")
        }
        let expected = model.paths.desktopDataDirectory(for: ValidationModel.cloneTestProfile).map { InstanceMatcher.normalize($0.path) }
        for clone in clones {
            let verdict: String
            if let folder = clone.userDataDirectory {
                verdict = InstanceMatcher.normalize(folder) == expected
                    ? "Lanes'in bu klon için verdiği klasörü kullanıyor."
                    : "Başka bir klasör kullanıyor: \(folder)"
            } else {
                verdict = "Claude'un kendi klasörünü, yani ana hesabın verisini kullanıyor."
            }
            lines.append("Klon (PID \(clone.pid)): \(verdict)")
        }
        let handler = LinkHandlerRegistry.currentHandler()
        lines.append(handlerLine())
        let handlerIsClone = handler.map { InstanceMatcher.normalize($0.path) == clonePath } ?? false
        lines.append(handlerIsClone ? "claude:// varsayılanı klona geçti." : "claude:// varsayılanı klona geçmedi.")
        model.validation.appendEvidence(lines, for: check)
        status = String(localized: "Kaydedildi. Sonucu aşağıdan seç.")
    }
}

// MARK: 0.5.3 Signing in a new account

struct NewAccountSignInAssistant: View {
    enum Method: String, CaseIterable, Identifiable {
        case google, emailLink, sso

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .google: return String(localized: "Google")
            case .emailLink: return String(localized: "E-posta bağlantısı")
            case .sso: return String(localized: "SSO")
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @State private var method = Method.google
    @State private var startedIn: Int32?
    @State private var status: String?

    private let check = ValidationCheckID.newAccountSignIn

    var body: some View {
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 12) {
                if LinkHandlerRegistry.lanesIsHandler {
                    Text("claude:// bağlantılarını şu an Lanes açıyor. Önce 2. denemeden Claude'u geri yükle.")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ButtonRow {
                    Button("1. Başlangıcı Kaydet") {
                        start()
                    }
                    Button("2. Hesap Ekle") {
                        navigation.isAddingProfile = true
                    }
                    Button("Yenile") {
                        model.refreshInstances()
                    }
                }
                Picker("Giriş yolu", selection: $method) {
                    ForEach(Method.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .frame(maxWidth: 320)
                Picker("Girişi başlattığın pencere", selection: $startedIn) {
                    Text("Seç").tag(Int32?.none)
                    ForEach(model.instances) { instance in
                        Text(instanceLabel(instance, model: model)).tag(Optional(instance.pid))
                    }
                }
                if startedIn != nil {
                    Text("Giriş hangi pencerede tamamlandı?")
                    FlowButtons(instances: model.instances, model: model) { finished in
                        record(finishedIn: finished)
                    }
                }
                StatusText(status: status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func start() {
        model.refreshInstances()
        model.validation.appendEvidence(["Başlangıç"] + instanceLines(model) + [handlerLine()], for: check)
        status = String(localized: "Başlangıç kaydedildi. Şimdi yeni hesabı ekle ve aç.")
    }

    private func record(finishedIn finished: RunningInstance?) {
        guard let startedIn, let started = model.instances.first(where: { $0.pid == startedIn }) else { return }
        let isSameWindow = finished?.pid == started.pid
        var lines = [
            "Giriş yolu: \(method.displayName)",
            "Başlatıldığı pencere: \(instanceLabel(started, model: model))",
            "Tamamlandığı pencere: \(finished.map { instanceLabel($0, model: model) } ?? "hiçbiri")",
            isSameWindow ? "Giriş başlatıldığı pencerede tamamlandı." : "Giriş başka bir pencerede tamamlandı ya da tamamlanmadı.",
            handlerLine(),
        ]
        if let link = model.receivedLinks.first {
            lines.append("Lanes'e gelen son bağlantı: \(link.kind) · \(link.outcome)")
        }
        let validation = model.validation
        validation.appendEvidence(lines, for: check)
        let previous = validation.result(for: check).outcome
        let outcome: ValidationOutcome
        switch (isSameWindow, previous) {
        case (true, .notRun), (true, .passed): outcome = .passed
        case (true, _): outcome = .partial
        case (false, .passed), (false, .partial): outcome = .partial
        case (false, _): outcome = .failed
        }
        validation.setOutcome(outcome, for: check)
        self.startedIn = nil
        status = String(localized: "Kaydedildi. Öbür giriş yollarıyla da dene.")
    }
}

// MARK: 0.5.4 Switching accounts in one window

struct CrossAccountSignOutAssistant: View {
    @Environment(AppModel.self) private var model
    @State private var status: String?

    private let check = ValidationCheckID.crossAccountSignOut

    var body: some View {
        let validation = model.validation
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 12) {
                InstanceFolders()
                ButtonRow {
                    Button("Durumu Kaydet") {
                        snapshot(String(localized: "Hesap değiştirmeden önce"))
                    }
                    Button("Yeniden Açınca Kaydet") {
                        snapshot(String(localized: "Pencereler Lanes'ten yeniden açıldıktan sonra"))
                    }
                    Button("Yenile") {
                        model.refreshInstances()
                    }
                }
                Text("Pencereleri Claude'un kendi menüsünden kapat. Lanes hiçbir Claude penceresini kendisi kapatmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                YesNoRow(title: String(localized: "Ana hesapta değiştirdiğin hesap, ikinci hesabın kullandığı hesaptı"), answer: draftAnswer(validation, check, "sameAccount"))
                YesNoRow(title: String(localized: "İkinci hesabın oturumu açık kaldı"), answer: draftAnswer(validation, check, "stayedSignedIn"))
                Button("Sonucu Kaydet") {
                    save()
                }
                .disabled(validation.draftAnswers[check]?["sameAccount"] == nil || validation.draftAnswers[check]?["stayedSignedIn"] == nil)
                StatusText(status: status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func snapshot(_ title: String) {
        model.refreshInstances()
        model.validation.appendEvidence([title] + instanceLines(model), for: check)
        status = String(localized: "Kaydedildi.")
    }

    private func save() {
        let answers = model.validation.draftAnswers[check] ?? [:]
        model.validation.appendEvidence([
            "Değiştirilen hesap ikinci hesabın hesabıydı: \(yesNo(answers["sameAccount"]))",
            "İkinci hesabın oturumu açık kaldı: \(yesNo(answers["stayedSignedIn"]))",
        ], for: check)
        model.validation.setOutcome(answers["stayedSignedIn"] == true ? .passed : .failed, for: check)
        status = String(localized: "Kaydedildi.")
    }
}

// MARK: 0.5.5 Claude Code's sign-in per account

struct ClaudeCodeLoginAssistant: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @State private var selectedID: ProfileID?
    @State private var status: String?

    private let check = ValidationCheckID.claudeCodeLogin

    var body: some View {
        let validation = model.validation
        let candidates = model.library.profiles.filter { !$0.isDefault }
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 12) {
                if candidates.isEmpty {
                    Text("Bu deneme için ana hesap dışında bir hesap gerekiyor.")
                        .foregroundStyle(.secondary)
                    Button("Hesap Ekle") {
                        navigation.isAddingProfile = true
                    }
                } else {
                    Picker("Hesap", selection: $selectedID) {
                        Text("Seç").tag(ProfileID?.none)
                        ForEach(candidates) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    ButtonRow {
                        Button("Ana Hesapla Terminalde Aç") {
                            open(model.library.defaultProfile)
                        }
                        .disabled(model.library.defaultProfile == nil)
                        Button("Seçili Hesapla Terminalde Aç") {
                            open(selectedProfile)
                        }
                        .disabled(selectedProfile == nil)
                    }
                    Text("İki pencerede de giriş yap. Pencereleri kapatıp yeniden aç ve her birinde /status komutuna bak.")
                        .fixedSize(horizontal: false, vertical: true)
                    YesNoRow(title: String(localized: "Ana hesabın Terminali kendi hesabında kaldı"), answer: draftAnswer(validation, check, "defaultKept"))
                    YesNoRow(title: String(localized: "Seçili hesabın Terminali kendi hesabında kaldı"), answer: draftAnswer(validation, check, "profileKept"))
                    Button("Sonucu Kaydet") {
                        save()
                    }
                    .disabled(selectedProfile == nil || validation.draftAnswers[check]?["defaultKept"] == nil || validation.draftAnswers[check]?["profileKept"] == nil)
                }
                StatusText(status: status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var selectedProfile: Profile? {
        selectedID.flatMap { model.profile(withID: $0) }
    }

    private func open(_ profile: Profile?) {
        guard let profile else { return }
        model.openClaudeCode(profile)
        model.validation.appendEvidence([
            "\(profile.name) için Terminal açıldı: \(model.paths.effectiveClaudeCodeConfigDirectory(for: profile).path)",
        ], for: check)
    }

    private func save() {
        guard let profile = selectedProfile else { return }
        let answers = model.validation.draftAnswers[check] ?? [:]
        model.validation.appendEvidence([
            "Hesap: \(profile.name)",
            "Ana hesabın Terminali kendi hesabında kaldı: \(yesNo(answers["defaultKept"]))",
            "Seçili hesabın Terminali kendi hesabında kaldı: \(yesNo(answers["profileKept"]))",
        ], for: check)
        model.validation.setOutcome(outcome(for: [answers["defaultKept"] == true, answers["profileKept"] == true]), for: check)
        status = String(localized: "Kaydedildi.")
    }
}

// MARK: 0.5.6 Cowork in standard mode

struct CoworkAssistant: View {
    @Environment(AppModel.self) private var model
    @State private var status: String?

    private let check = ValidationCheckID.coworkStandard

    var body: some View {
        let validation = model.validation
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 12) {
                YesNoRow(title: String(localized: "İkinci hesapta Cowork çalıştı"), answer: draftAnswer(validation, check, "secondAccount"))
                YesNoRow(title: String(localized: "İki hesapta aynı anda çalıştı"), answer: draftAnswer(validation, check, "bothAtOnce"))
                Button("Sonucu Kaydet") {
                    save()
                }
                .disabled(validation.draftAnswers[check]?["secondAccount"] == nil || validation.draftAnswers[check]?["bothAtOnce"] == nil)
                StatusText(status: status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func save() {
        let answers = model.validation.draftAnswers[check] ?? [:]
        model.validation.appendEvidence([
            "İkinci hesapta Cowork çalıştı: \(yesNo(answers["secondAccount"]))",
            "İki hesapta aynı anda çalıştı: \(yesNo(answers["bothAtOnce"]))",
        ], for: check)
        model.validation.setOutcome(outcome(for: [answers["secondAccount"] == true, answers["bothAtOnce"] == true]), for: check)
        status = String(localized: "Kaydedildi.")
    }
}

// MARK: 0.5.7 Claude Code's session records

struct SessionRecordsAssistant: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: ProfileID?
    @State private var folder: ClaudeCodeSessionFolder?
    @State private var status: String?

    private let check = ValidationCheckID.claudeCodeSessionRecords

    var body: some View {
        let validation = model.validation
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Hesap", selection: $selectedID) {
                    Text("Seç").tag(ProfileID?.none)
                    ForEach(model.library.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .onChange(of: selectedID) { _, _ in
                    folder = nil
                }
                ButtonRow {
                    Button("Klasör Yapısını Kaydet") {
                        scan()
                    }
                    .disabled(selectedProfile == nil)
                    Button("Komutu Kopyala") {
                        copyCommand()
                    }
                    .disabled(folder?.newestSession == nil)
                }
                if let folder {
                    Text(folder.evidenceLines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text("Komutu oturumun başladığı proje klasöründe çalıştır. Claude Code oturumları o klasöre göre arıyor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                YesNoRow(title: String(localized: "Oturum kaldığı yerden sürdü"), answer: draftAnswer(validation, check, "resumed"))
                Button("Sonucu Kaydet") {
                    save()
                }
                .disabled(validation.draftAnswers[check]?["resumed"] == nil)
                StatusText(status: status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var selectedProfile: Profile? {
        selectedID.flatMap { model.profile(withID: $0) }
    }

    private func projectsFolder(for profile: Profile) -> URL {
        model.paths.effectiveClaudeCodeConfigDirectory(for: profile).appendingPathComponent("projects", isDirectory: true)
    }

    private func scan() {
        guard let profile = selectedProfile else { return }
        let directory = projectsFolder(for: profile)
        let folder = ClaudeCodeSessionFolder.read(directory)
        self.folder = folder
        model.validation.appendEvidence(["Hesap: \(profile.name)", "Klasör: \(directory.path)"] + folder.evidenceLines, for: check)
        status = String(localized: "Kaydedildi. Lanes yalnız dosya adlarına ve tarihlerine baktı.")
    }

    private func copyCommand() {
        guard let profile = selectedProfile, let session = folder?.newestSession else { return }
        let command = ClaudeCodeCommand.command(for: profile, paths: model.paths, arguments: ["--resume", session.id])
        SystemActions.copy(command)
        model.validation.appendEvidence(["Kopyalanan komut: \(command)"], for: check)
        status = String(localized: "Komut panoya kopyalandı.")
    }

    private func save() {
        let answers = model.validation.draftAnswers[check] ?? [:]
        model.validation.appendEvidence(["Oturum kaldığı yerden sürdü: \(yesNo(answers["resumed"]))"], for: check)
        model.validation.setOutcome(answers["resumed"] == true ? .passed : .failed, for: check)
        status = String(localized: "Kaydedildi.")
    }
}
