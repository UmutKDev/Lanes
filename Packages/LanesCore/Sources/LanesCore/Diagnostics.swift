import Foundation

/// What "Tanılama bilgisini hazırla" exports: versions, the accounts and every
/// running Claude with the folder it uses. Account names never appear, they
/// are numbered in the sidebar's order. The home folder is written as "~".
/// Nothing is read from inside a profile folder; whether a folder exists is
/// all Lanes checks.
public struct DiagnosticsReport: Sendable {
    public var environment: ValidationEnvironment
    public var claudePath: String?
    public var linkHandlerPath: String?
    public var isTranslocated: Bool
    public var updatesEnabled: Bool
    public var profiles: [Profile]
    public var folderExists: [ProfileID: Bool]
    public var instances: [RunningInstance]
    public var generatedAt: Date
    public var homeDirectory: String

    public init(
        environment: ValidationEnvironment,
        claudePath: String?,
        linkHandlerPath: String?,
        isTranslocated: Bool,
        updatesEnabled: Bool,
        profiles: [Profile],
        folderExists: [ProfileID: Bool],
        instances: [RunningInstance],
        generatedAt: Date,
        homeDirectory: String
    ) {
        self.environment = environment
        self.claudePath = claudePath
        self.linkHandlerPath = linkHandlerPath
        self.isTranslocated = isTranslocated
        self.updatesEnabled = updatesEnabled
        self.profiles = profiles
        self.folderExists = folderExists
        self.instances = instances
        self.generatedAt = generatedAt
        self.homeDirectory = homeDirectory
    }

    public func markdown() -> String {
        var lines: [String] = []
        lines.append(L("# Lanes tanılama", "# Lanes Diagnostics"))
        lines.append("")
        lines.append(L("- Tarih: ", "- Date: ") + ValidationReport.dateString(generatedAt))
        lines.append("- Lanes: \(environment.lanesVersion), commit \(environment.commitDescription)")
        lines.append(L("- İmza: ", "- Signature: ") + (environment.signing ?? unknown))
        lines.append(L("- Uygulama: ", "- App: ") + (environment.appPath ?? unknown) + (isTranslocated ? L(" (geçici kopya)", " (translocated copy)") : ""))
        lines.append(L("- Güncelleme denetimi: ", "- Update checks: ") + (updatesEnabled ? L("açık", "on") : L("bu derlemede yok", "not in this build")))
        lines.append("- macOS: \(environment.macOSVersion) (\(environment.architecture))")
        lines.append("- Claude: " + (environment.claudeVersion ?? L("bulunamadı", "not found")) + (claudePath.map { ", \($0)" } ?? ""))
        lines.append(L("- claude:// bağlantılarını açan: ", "- Opens claude:// links: ") + (linkHandlerPath ?? L("yok", "none")))

        lines.append("")
        lines.append(L("## Hesaplar", "## Accounts"))
        lines.append("")
        lines.append(L("| Hesap | Açılış | Tür | Kendi klasörü | Durum |", "| Account | Launch Mode | Kind | Own Folder | Status |"))
        lines.append(L("| ----- | ------ | --- | ------------- | ----- |", "| ------- | ----------- | ---- | ---------- | ------ |"))
        for (index, profile) in profiles.enumerated() {
            let folder: String
            if profile.isDefault {
                folder = claudeOwnFolder
            } else {
                folder = folderExists[profile.id] == true ? L("var", "exists") : L("henüz yok", "not yet created")
            }
            let running = instances.filter { $0.profileID == profile.id }.map { "PID \($0.pid)" }
            let state = running.isEmpty ? L("kapalı", "closed") : L("açık, ", "open, ") + running.joined(separator: ", ")
            lines.append("| \(label(index: index, profile: profile)) | \(profile.mode.rawValue) | \(profile.accountClass.rawValue) | \(folder) | \(state) |")
        }

        lines.append("")
        lines.append(L("## Çalışan Claude'lar", "## Running Claude Instances"))
        lines.append("")
        if instances.isEmpty {
            lines.append(L("Açık Claude yok.", "No Claude instances are open."))
        } else {
            lines.append(L("| PID | Hesap | Uygulama | Klasör |", "| PID | Account | App | Folder |"))
            lines.append(L("| --- | ----- | -------- | ------ |", "| --- | ------- | --- | ------ |"))
            for instance in instances {
                lines.append("| \(instance.pid) | \(owner(of: instance)) | \(application(of: instance)) | \(instance.userDataDirectory ?? claudeOwnFolder) |")
            }
        }
        let text = lines.joined(separator: "\n") + "\n"
        return ValidationReport.abbreviatingHome(homeDirectory, in: text)
    }

    private var unknown: String { L("bilinmiyor", "unknown") }
    private var claudeOwnFolder: String { L("Claude'un kendi klasörü", "Claude’s own folder") }

    private func label(index: Int, profile: Profile) -> String {
        L("Hesap \(index + 1)", "Account \(index + 1)") + (profile.isDefault ? L(" (ana)", " (main)") : "")
    }

    private func owner(of instance: RunningInstance) -> String {
        guard let id = instance.profileID, let index = profiles.firstIndex(where: { $0.id == id }) else {
            return L("Lanes dışında açılmış", "Opened outside Lanes")
        }
        return label(index: index, profile: profiles[index])
    }

    /// Clones are named after the account, so only "klon" ("clone") is written.
    private func application(of instance: RunningInstance) -> String {
        guard let claudePath else { return L("klon", "clone") }
        return instance.applicationBundlePath == claudePath ? "Claude" : L("klon", "clone")
    }
}
