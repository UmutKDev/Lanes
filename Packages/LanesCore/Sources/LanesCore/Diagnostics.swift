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
        lines.append("# Lanes tanılama")
        lines.append("")
        lines.append("- Tarih: \(ValidationReport.dateString(generatedAt))")
        lines.append("- Lanes: \(environment.lanesVersion), commit \(environment.commitDescription)")
        lines.append("- İmza: \(environment.signing ?? "bilinmiyor")")
        lines.append("- Uygulama: \(environment.appPath ?? "bilinmiyor")\(isTranslocated ? " (geçici kopya)" : "")")
        lines.append("- Güncelleme denetimi: \(updatesEnabled ? "açık" : "bu derlemede yok")")
        lines.append("- macOS: \(environment.macOSVersion) (\(environment.architecture))")
        lines.append("- Claude: \(environment.claudeVersion ?? "bulunamadı")\(claudePath.map { ", \($0)" } ?? "")")
        lines.append("- claude:// bağlantılarını açan: \(linkHandlerPath ?? "yok")")

        lines.append("")
        lines.append("## Hesaplar")
        lines.append("")
        lines.append("| Hesap | Açılış | Tür | Kendi klasörü | Durum |")
        lines.append("| ----- | ------ | --- | ------------- | ----- |")
        for (index, profile) in profiles.enumerated() {
            let folder: String
            if profile.isDefault {
                folder = "Claude'un kendi klasörü"
            } else {
                folder = folderExists[profile.id] == true ? "var" : "henüz yok"
            }
            let running = instances.filter { $0.profileID == profile.id }.map { "PID \($0.pid)" }
            let state = running.isEmpty ? "kapalı" : "açık, " + running.joined(separator: ", ")
            lines.append("| \(label(index: index, profile: profile)) | \(profile.mode.rawValue) | \(profile.accountClass.rawValue) | \(folder) | \(state) |")
        }

        lines.append("")
        lines.append("## Çalışan Claude'lar")
        lines.append("")
        if instances.isEmpty {
            lines.append("Açık Claude yok.")
        } else {
            lines.append("| PID | Hesap | Uygulama | Klasör |")
            lines.append("| --- | ----- | -------- | ------ |")
            for instance in instances {
                lines.append("| \(instance.pid) | \(owner(of: instance)) | \(application(of: instance)) | \(instance.userDataDirectory ?? "Claude'un kendi klasörü") |")
            }
        }
        let text = lines.joined(separator: "\n") + "\n"
        return ValidationReport.abbreviatingHome(homeDirectory, in: text)
    }

    private func label(index: Int, profile: Profile) -> String {
        "Hesap \(index + 1)\(profile.isDefault ? " (ana)" : "")"
    }

    private func owner(of instance: RunningInstance) -> String {
        guard let id = instance.profileID, let index = profiles.firstIndex(where: { $0.id == id }) else {
            return "Lanes dışında açılmış"
        }
        return label(index: index, profile: profiles[index])
    }

    /// Clones are named after the account, so only "klon" is written.
    private func application(of instance: RunningInstance) -> String {
        guard let claudePath else { return "klon" }
        return instance.applicationBundlePath == claudePath ? "Claude" : "klon"
    }
}
