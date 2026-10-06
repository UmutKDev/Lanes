import AppKit
import LanesCore
import SwiftUI

// MARK: 1. Link to a specific instance

struct LinkDeliveryAssistant: View {
    @Environment(AppModel.self) private var model
    @State private var targetPID: Int32?
    @State private var pendingTarget: RunningInstance?
    @State private var attempt = 1
    @State private var status: String?
    @State private var isSending = false

    var body: some View {
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 12) {
                if model.instances.count < 2 {
                    Text("Bu deneme için en az iki hesap açık olmalı. Şu an \(model.instances.count) Claude penceresi açık.")
                        .foregroundStyle(.secondary)
                }
                ButtonRow {
                    Picker("Hedef pencere", selection: $targetPID) {
                        Text("Seç").tag(Int32?.none)
                        ForEach(model.instances) { instance in
                            Text(instanceLabel(instance, model: model)).tag(Optional(instance.pid))
                        }
                    }
                    Button("Yenile") {
                        model.refreshInstances()
                    }
                }
                Button("Bağlantıyı Gönder") {
                    send()
                }
                .disabled(targetPID == nil || isSending || pendingTarget != nil)

                if let pendingTarget {
                    Text("Yeni sohbet hangi pencerede açıldı? Lanes onu \(instanceLabel(pendingTarget, model: model)) penceresine gönderdi.")
                        .fixedSize(horizontal: false, vertical: true)
                    FlowButtons(instances: model.instances, model: model) { observed in
                        record(observed: observed)
                    }
                }
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func send() {
        guard let pid = targetPID, let instance = model.instances.first(where: { $0.pid == pid }) else { return }
        let url = URL(string: "claude://claude.ai/new?q=Lanes%20Faz%200%20denemesi%20\(attempt)")!
        isSending = true
        status = nil
        Task {
            do {
                try await AppleEvents.sendURL(url, to: pid)
                pendingTarget = instance
                status = String(localized: "Bağlantı gönderildi. Claude pencerelerine bak.")
            } catch {
                status = error.localizedDescription
                model.validation.appendEvidence(["Gönderilemedi: \(error.localizedDescription)"], for: .linkToSpecificInstance)
            }
            isSending = false
        }
    }

    private func record(observed: RunningInstance?) {
        guard let target = pendingTarget else { return }
        let isCorrect = observed?.pid == target.pid
        let validation = model.validation
        validation.appendEvidence([
            "Deneme \(attempt): hedef \(instanceLabel(target, model: model))",
            "Açıldığı pencere: \(observed.map { instanceLabel($0, model: model) } ?? "hiçbiri")",
            isCorrect ? "Doğru pencere." : "Yanlış pencere.",
        ], for: .linkToSpecificInstance)

        let previous = validation.result(for: .linkToSpecificInstance).outcome
        let outcome: ValidationOutcome
        switch (isCorrect, previous) {
        case (true, .notRun), (true, .passed): outcome = .passed
        case (true, _): outcome = .partial
        case (false, .passed), (false, .partial): outcome = .partial
        case (false, _): outcome = .failed
        }
        validation.setOutcome(outcome, for: .linkToSpecificInstance)
        pendingTarget = nil
        attempt += 1
        status = String(localized: "Kaydedildi. Öbür pencereyle de bir kez dene.")
    }
}

private struct FlowButtons: View {
    let instances: [RunningInstance]
    let model: AppModel
    var onPick: (RunningInstance?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(instances) { instance in
                Button(instanceLabel(instance, model: model)) {
                    onPick(instance)
                }
            }
            Button("Hiçbirinde açılmadı") {
                onPick(nil)
            }
        }
    }
}

// MARK: 2. Reclaim the claude:// default

struct LinkHandlerAssistant: View {
    @Environment(AppModel.self) private var model
    @State private var handler = LinkHandlerRegistry.currentHandler()
    @State private var tookOver: Bool?
    @State private var isWorking = false

    var body: some View {
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("claude:// bağlantılarını açan") {
                    Text(handler?.path ?? String(localized: "Yok"))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if model.instances.isEmpty {
                    Text("Soru Claude açıkken soruluyor. Önce bir hesabı aç.")
                        .foregroundStyle(.secondary)
                }
                ButtonRow {
                    Button("Lanes'i Varsayılan Yap") {
                        Task { await takeOver() }
                    }
                    Button("Claude'u Geri Yükle") {
                        Task { await restore() }
                    }
                    .disabled(model.claude == nil)
                    Button("Yenile") {
                        handler = LinkHandlerRegistry.currentHandler()
                    }
                }
                .disabled(isWorking)

                if tookOver != nil {
                    Text("Lanes'i varsayılan yaparken bir onay penceresi çıktı mı?")
                    HStack {
                        Button("Çıktı") { record(prompted: true) }
                        Button("Çıkmadı") { record(prompted: false) }
                    }
                }
                Text("Deneme bitince Claude'u geri yüklemeyi unutma. Lanes yeniden açıldığında bunu kendisi de yapar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.receivedLinks.isEmpty {
                    Divider()
                    Text("Lanes'e gelen bağlantılar")
                        .font(.caption.weight(.semibold))
                    ForEach(model.receivedLinks.prefix(5)) { link in
                        Text(verbatim: "\(link.url.absoluteString.prefix(80)) · \(link.outcome)")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func takeOver() async {
        isWorking = true
        defer { isWorking = false }
        let before = LinkHandlerRegistry.currentHandler()?.path ?? "yok"
        let start = Date()
        var lines = ["Lanes'i varsayılan yapma denemesi", "Önce: \(before)"]
        do {
            try await LinkHandlerRegistry.setHandler(Bundle.main.bundleURL)
            lines.append("İstek başarılı, \(Int(Date().timeIntervalSince(start) * 1000)) ms.")
        } catch {
            lines.append("Hata: \(error.localizedDescription)")
        }
        handler = LinkHandlerRegistry.currentHandler()
        lines.append("Sonra: \(handler?.path ?? "yok")")
        tookOver = LinkHandlerRegistry.lanesIsHandler
        model.validation.appendEvidence(lines, for: .reclaimLinkHandler)
    }

    private func restore() async {
        guard let claude = model.claude else { return }
        isWorking = true
        defer { isWorking = false }
        var lines = ["Claude'u geri yükleme"]
        do {
            try await LinkHandlerRegistry.setHandler(claude.url)
            lines.append("İstek başarılı.")
        } catch {
            lines.append("Hata: \(error.localizedDescription)")
        }
        handler = LinkHandlerRegistry.currentHandler()
        lines.append("Sonra: \(handler?.path ?? "yok")")
        model.validation.appendEvidence(lines, for: .reclaimLinkHandler)
    }

    private func record(prompted: Bool) {
        let validation = model.validation
        validation.appendEvidence([prompted ? "Onay penceresi çıktı." : "Onay penceresi çıkmadı."], for: .reclaimLinkHandler)
        let outcome: ValidationOutcome
        if tookOver != true {
            outcome = .failed
        } else {
            outcome = prompted ? .partial : .passed
        }
        validation.setOutcome(outcome, for: .reclaimLinkHandler)
        tookOver = nil
    }
}

// MARK: 3. Signed clone identity

struct CloneAssistant: View {
    @Environment(AppModel.self) private var model
    @State private var isWorking = false
    @State private var status: String?

    private var profile: Profile { ValidationModel.cloneTestProfile }
    private var cloneURL: URL { model.paths.cloneBundle(for: profile) }

    var body: some View {
        @Bindable var validation = model.validation
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Deneme klonu") {
                    Text(cloneURL.path)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ButtonRow {
                    Button("Klonu Oluştur") {
                        Task { await makeClone() }
                    }
                    .disabled(model.claude == nil)
                    Button("Klonu Aç") {
                        Task { await openClone() }
                    }
                    Button("Klonu Çöpe At") {
                        removeClone()
                    }
                }
                .disabled(isWorking)

                Text("Klonu açınca şunlara bak:")
                YesNoRow(title: String(localized: "Dock'ta klonun kendi simgesi görünüyor"), answer: $validation.cloneProgress.dockIcon)
                YesNoRow(title: String(localized: "Dock'ta fareyle üstüne gelince \"Claude – Lanes Deneme\" yazıyor"), answer: $validation.cloneProgress.dockName)
                YesNoRow(title: String(localized: "Cmd-Tab'da klonun kendi simgesi görünüyor"), answer: $validation.cloneProgress.switcherIcon)
                Button("Sonucu Kaydet") {
                    save()
                }
                .disabled(validation.cloneProgress.dockIcon == nil || validation.cloneProgress.dockName == nil || validation.cloneProgress.switcherIcon == nil)

                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func makeClone() async {
        guard let claude = model.claude else { return }
        isWorking = true
        defer { isWorking = false }
        status = String(localized: "Klon oluşturuluyor…")
        var lines: [String] = ["Kaynak: \(claude.url.path) (\(claude.version ?? "?"))"]
        do {
            let result = try CloneMaker.makeClone(
                of: claude.url,
                at: cloneURL,
                icon: MonogramIcon.image(for: profile),
                paths: model.paths
            )
            lines.append("Kopyalama \(Int(result.copySeconds * 1000)) ms sürdü.")
            lines.append(result.iconApplied ? "Simge uygulandı." : "Simge uygulanamadı.")
            let codesign = await ShellRunner.run("/usr/bin/codesign", ["--verify", "--deep", "--verbose=2", cloneURL.path])
            lines.append(contentsOf: ["$ codesign --verify --deep --verbose=2", codesign.text, "çıkış kodu: \(codesign.status)"])
            let gatekeeper = await ShellRunner.run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", cloneURL.path])
            lines.append(contentsOf: ["$ spctl --assess --type execute --verbose=4", gatekeeper.text, "çıkış kodu: \(gatekeeper.status)"])
            model.validation.cloneProgress.signatureValid = codesign.status == 0 && gatekeeper.status == 0
            // The custom icon adds an Icon\r file and Finder info to the bundle
            // root. Only strict mode rejects that, so it is kept as a note and
            // does not decide the outcome.
            lines.append(contentsOf: await ShellRunner.transcript("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", cloneURL.path]))
            lines.append(contentsOf: await ShellRunner.transcript("/usr/bin/codesign", ["-dv", cloneURL.path]))
            status = String(localized: "Klon hazır. Şimdi aç ve Dock'a bak.")
        } catch {
            lines.append("Klon oluşturulamadı: \(error.localizedDescription)")
            status = error.localizedDescription
        }
        model.validation.appendEvidence(lines, for: .signedCloneIdentity)
    }

    private func openClone() async {
        guard let claude = model.claude else { return }
        guard FileManager.default.fileExists(atPath: cloneURL.path) else {
            status = String(localized: "Önce klonu oluştur.")
            return
        }
        let plan = LaunchPlanner.plan(for: profile, claudeApp: claude.url, cloneApp: cloneURL, paths: model.paths)
        do {
            let app = try await InstanceLauncher.launch(plan)
            model.validation.appendEvidence(["Klon açıldı, PID \(app.processIdentifier)."], for: .signedCloneIdentity)
            status = String(localized: "Klon açıldı.")
        } catch {
            model.validation.appendEvidence(["Klon açılamadı: \(error.localizedDescription)"], for: .signedCloneIdentity)
            status = error.localizedDescription
        }
        model.refreshInstances()
    }

    private func removeClone() {
        do {
            try CloneMaker.removeClone(at: cloneURL, paths: model.paths)
            status = String(localized: "Klon çöpe atıldı.")
        } catch {
            status = error.localizedDescription
        }
    }

    private func save() {
        let progress = model.validation.cloneProgress
        let answers = [progress.dockIcon, progress.dockName, progress.switcherIcon].compactMap { $0 }
        let yesCount = answers.filter { $0 }.count
        model.validation.appendEvidence([
            "Dock simgesi: \(progress.dockIcon == true ? "evet" : "hayır")",
            "Dock adı: \(progress.dockName == true ? "evet" : "hayır")",
            "Cmd-Tab simgesi: \(progress.switcherIcon == true ? "evet" : "hayır")",
            "İmza ve Gatekeeper: \(progress.signatureValid.map { $0 ? "geçerli" : "geçersiz" } ?? "çalıştırılmadı")",
        ], for: .signedCloneIdentity)
        let outcome: ValidationOutcome
        if yesCount == answers.count, progress.signatureValid == true {
            outcome = .passed
        } else if yesCount == 0 {
            outcome = .failed
        } else {
            outcome = .partial
        }
        model.validation.setOutcome(outcome, for: .signedCloneIdentity)
        status = String(localized: "Kaydedildi.")
    }
}

/// Buttons side by side, or stacked when the page is too narrow for one line.
struct ButtonRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { content }
            VStack(alignment: .leading) { content }
        }
    }
}

struct YesNoRow: View {
    let title: String
    @Binding var answer: Bool?

    var body: some View {
        HStack {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Picker(title, selection: $answer) {
                Text("Evet").tag(Bool?.some(true))
                Text("Hayır").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)
        }
    }
}

// MARK: 4. CLAUDE_CONFIG_DIR in the Code tab

struct ConfigDirectoryAssistant: View {
    private struct Snapshot {
        var profile: Date?
        var shared: Date?
    }

    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @State private var selectedID: ProfileID?
    @State private var snapshot: Snapshot?
    @State private var status: String?

    var body: some View {
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
                    Button("1. Başlangıcı Kaydet ve Hesabı Aç") {
                        start()
                    }
                    .disabled(selectedID == nil)
                    Text("2. Açılan pencerede Code sekmesine geç, bir klasör seç ve kısa bir oturum başlat.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("3. Kontrol Et") {
                        check()
                    }
                    .disabled(snapshot == nil)
                }
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Lanes yalnız dosyaların değiştirilme saatine bakar, içeriklerini açmaz.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var selectedProfile: Profile? {
        selectedID.flatMap { model.profile(withID: $0) }
    }

    private func projectsFolder(_ base: URL) -> URL {
        base.appendingPathComponent("projects", isDirectory: true)
    }

    private func start() {
        guard let profile = selectedProfile else { return }
        if model.isRunning(profile) {
            status = String(localized: "\(profile.name) zaten açık. Ayar yalnız açılışta verilir: önce Claude'dan çık, sonra yeniden dene.")
            return
        }
        snapshot = Snapshot(
            profile: FolderActivity.newestModification(in: projectsFolder(model.paths.effectiveClaudeCodeConfigDirectory(for: profile))),
            shared: FolderActivity.newestModification(in: projectsFolder(model.paths.claudeCodeDefaultConfigDirectory))
        )
        model.open(profile)
        status = String(localized: "Başlangıç kaydedildi, \(profile.name) açılıyor.")
    }

    private func check() {
        guard let profile = selectedProfile, let snapshot else { return }
        let profileNow = FolderActivity.newestModification(in: projectsFolder(model.paths.effectiveClaudeCodeConfigDirectory(for: profile)))
        let sharedNow = FolderActivity.newestModification(in: projectsFolder(model.paths.claudeCodeDefaultConfigDirectory))
        let profileChanged = changed(from: snapshot.profile, to: profileNow)
        let sharedChanged = changed(from: snapshot.shared, to: sharedNow)

        guard profileChanged || sharedChanged else {
            status = String(localized: "Henüz yeni bir oturum kaydı yok. Code sekmesinde bir oturum başlattığından emin ol ve yeniden kontrol et.")
            return
        }
        model.validation.appendEvidence([
            "Hesap: \(profile.name)",
            "Hesabın klasöründe yeni oturum kaydı: \(profileChanged ? "var" : "yok")",
            "~/.claude altında yeni oturum kaydı: \(sharedChanged ? "var" : "yok")",
        ], for: .claudeCodeConfigDirectory)
        let outcome: ValidationOutcome
        switch (profileChanged, sharedChanged) {
        case (true, false): outcome = .passed
        case (true, true): outcome = .partial
        default: outcome = .failed
        }
        model.validation.setOutcome(outcome, for: .claudeCodeConfigDirectory)
        status = outcome == .partial
            ? String(localized: "İki klasör de değişti. Başka bir Claude Code oturumu açık olabilir. Onu kapatıp yeniden dene.")
            : String(localized: "Kaydedildi.")
    }

    private func changed(from before: Date?, to after: Date?) -> Bool {
        guard let after else { return false }
        guard let before else { return true }
        return after > before
    }
}

// MARK: 5. App Management prompt

struct AppManagementAssistant: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Üçüncü denemede klonu oluştururken macOS bir izin penceresi gösterdi mi? Pencere \"Lanes başka uygulamaları değiştirmek istiyor\" gibi bir şey söyler.")
                    .fixedSize(horizontal: false, vertical: true)
                ButtonRow {
                    Button("İzin istenmedi") { record(.passed, "İzin istenmedi.") }
                    Button("İzin istendi") { record(.partial, "İzin istendi, verilince klon oluştu.") }
                    Button("Klon izin yüzünden oluşmadı") { record(.failed, "Klon izin yüzünden oluşmadı.") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func record(_ outcome: ValidationOutcome, _ line: String) {
        model.validation.appendEvidence([line], for: .appManagementPrompt)
        model.validation.setOutcome(outcome, for: .appManagementPrompt)
    }
}

// MARK: 7. After a Claude update

struct InstanceTable: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GroupBox("Çalışan Claude pencereleri") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Claude sürümü", value: model.claude?.version ?? String(localized: "Bulunamadı"))
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
                ButtonRow {
                    Button("Yenile") {
                        model.refreshInstances()
                    }
                    Button("Tabloyu Kayıtlara Ekle") {
                        let lines = ["Claude \(model.claude?.version ?? "?")"] + model.instances.map {
                            "\(instanceLabel($0, model: model)): \($0.userDataDirectory ?? "Claude'un kendi klasörü")"
                        }
                        model.validation.appendEvidence(lines, for: .afterClaudeUpdate)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

// MARK: 8. The panel on the new menu bar

struct MenuBarAssistant: View {
    @Environment(WindowRouter.self) private var router

    /// On macOS 27 only a click on the icon starts the menu bar session. A
    /// panel opened from code has none, so the icon does not look pressed.
    private var panelNeedsIconClick: Bool {
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            return true
        }
        #endif
        return false
    }

    var body: some View {
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 10) {
                let version = ProcessInfo.processInfo.operatingSystemVersion
                Text("Bu Mac'te macOS \(version.majorVersion).\(version.minorVersion) çalışıyor. Deneme asıl olarak macOS 27'de anlamlı.")
                    .fixedSize(horizontal: false, vertical: true)
                if panelNeedsIconClick {
                    Text("Paneli menü çubuğundaki Lanes simgesine tıklayarak aç. Buradan açılan panelde simge basılı görünmez, bu yüzden bu deneme için sayılmaz.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button("Paneli Aç") {
                        router.togglePanel()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

// MARK: 9. Main window activation

struct ActivationAssistant: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @State private var count = 10

    var body: some View {
        GroupBox("Deneme") {
            VStack(alignment: .leading, spacing: 10) {
                Stepper("Deneme sayısı: \(count)", value: $count, in: 5...30, step: 5)
                    .frame(maxWidth: 260)
                Text("Pencere birkaç kez kapanıp panelden yeniden açılacak. Bitene kadar fareye ve klavyeye dokunma.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.validation.isRunningActivationTrials ? "Sürüyor…" : "Denemeyi Başlat") {
                    let count = count
                    Task { await router.runActivationTrials(count: count) }
                }
                .disabled(model.validation.isRunningActivationTrials)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}
