import Charts
import LanesCore
import SwiftUI

/// How much each account was used with Claude Code lately, counted from
/// session file dates. Claude's own plan limits are only visible inside
/// Claude: reading them would mean looking at sign-in data.
struct UsagePage: View {
    @Environment(AppModel.self) private var model
    @State private var activity: [Point] = []
    @State private var totals: [ProfileID: Int] = [:]

    struct Point: Identifiable {
        var profile: Profile
        var day: Date
        var sessions: Int
        var id: String { "\(profile.id.rawValue)-\(day.timeIntervalSince1970)" }
    }

    var body: some View {
        Form {
            Section {
                if activity.allSatisfy({ $0.sessions == 0 }) {
                    Text("Son 14 günde Claude Code oturumu yok.")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(activity) { point in
                        BarMark(
                            x: .value("Gün", point.day, unit: .day),
                            y: .value("Oturum", point.sessions)
                        )
                        .foregroundStyle(by: .value("Hesap", point.profile.name))
                    }
                    .chartForegroundStyleScale(domain: model.library.profiles.map(\.name), range: model.library.profiles.map(\.color.swatch))
                    .frame(height: 220)
                }
            } header: {
                Text("Son 14 gün, günlük Claude Code oturumları")
            } footer: {
                Text("O gün yazılan oturum dosyaları sayılır. Lanes dosyaların içini açmaz, bu yüzden mesaj ya da token sayısı gösterilmez. Claude'un kullanım sınırları yalnız Claude'un kendi ayarlarında görünür.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Hesaplar") {
                ForEach(model.library.profiles) { profile in
                    LabeledContent {
                        Text("\(totals[profile.id] ?? 0) oturum")
                            .monospacedDigit()
                    } label: {
                        HStack(spacing: 8) {
                            MonogramView(profile: profile, size: 20)
                            Text(profile.name)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { load() }
    }

    private func load() {
        var points: [Point] = []
        var totals: [ProfileID: Int] = [:]
        for profile in model.library.profiles {
            let days = model.claudeCodeSessions(for: profile).activity(days: 14, now: Date())
            totals[profile.id] = days.reduce(0) { $0 + $1.sessions }
            points += days.map { Point(profile: profile, day: $0.day, sessions: $0.sessions) }
        }
        activity = points
        self.totals = totals
    }
}
