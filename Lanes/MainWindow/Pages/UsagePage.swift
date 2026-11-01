import AppKit
import Charts
import LanesCore
import SwiftUI
import UniformTypeIdentifiers

/// How much each account was used with Claude Code lately, counted from
/// session file dates. Claude's own plan limits are only visible inside
/// Claude: reading them would mean looking at sign-in data.
struct UsagePage: View {
    @Environment(AppModel.self) private var model
    @State private var activity: [Point] = []
    @State private var totals: [ProfileID: Int] = [:]
    /// False until the first load, so the page shows a placeholder of the
    /// chart's height instead of flashing the "no sessions" line.
    @State private var loaded = false

    private static let sessionsChartHeight: CGFloat = 220
    private static let frontChartHeight: CGFloat = 180

    struct Point: Identifiable {
        var profile: Profile
        var day: Date
        var sessions: Int
        var id: String { "\(profile.id.rawValue)-\(day.timeIntervalSince1970)" }
    }

    var body: some View {
        let profiles = model.library.profiles
        let front = frontPoints()
        Form {
            sessionsSection(profiles: profiles)
            frontSection(profiles: profiles, front: front)
        }
        .libraryForm()
        .animation(DS.Motion.standard, value: loaded)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: exportCSV) {
                    Label("CSV Olarak Dışa Aktar…", systemImage: "square.and.arrow.up")
                }
                .help("CSV Olarak Dışa Aktar…")
            }
        }
        .task { load() }
    }

    // MARK: Sessions per day

    private func sessionsSection(profiles: [Profile]) -> some View {
        Section {
            if !loaded {
                chartPlaceholder(height: Self.sessionsChartHeight)
            } else if activity.allSatisfy({ $0.sessions == 0 }) {
                Label("Son 14 günde Claude Code oturumu yok.", systemImage: "chart.bar.xaxis")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    // Same slot as the chart and the placeholder, so the
                    // rows below never move when the load finds nothing.
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.sessionsChartHeight)
            } else {
                sessionsChart(profiles: profiles)
            }
            // The account rows are the chart's legend: each monogram
            // carries the account's colour.
            ForEach(profiles) { profile in
                LabeledContent {
                    Text("\(totals[profile.id] ?? 0) oturum")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                } label: {
                    DSAccountLabel(profile: profile)
                }
            }
        } header: {
            Text("Son 14 gün, günlük Claude Code oturumları")
        } footer: {
            footerText("O gün yazılan oturum dosyaları sayılır. Lanes dosyaların içini açmaz, bu yüzden mesaj ya da token sayısı gösterilmez. Claude'un kullanım sınırları yalnız Claude'un kendi ayarlarında görünür.")
        }
    }

    private func sessionsChart(profiles: [Profile]) -> some View {
        let days = chartDays(activity.map(\.day))
        return Chart(activity) { point in
            BarMark(
                x: .value("Gün", point.day, unit: .day),
                y: .value("Oturum", point.sessions)
            )
            .foregroundStyle(by: .value("Hesap", point.profile.id.rawValue))
            .cornerRadius(DS.Space.xs)
        }
        .chartForegroundStyleScale(domain: profiles.map(\.id.rawValue), range: profiles.map(\.color.swatch))
        .chartLegend(.hidden)
        .chartXScale(domain: dayDomain(days))
        .chartXAxis {
            AxisMarks(values: days) { _ in
                AxisGridLine()
            }
            // Labels at each day's noon, not centred between marks: a
            // centred label needs a next mark, so the last day (today)
            // lost its label.
            AxisMarks(values: middays(days)) { _ in
                AxisValueLabel(format: .dateTime.day(), anchor: .top)
            }
        }
        .frame(height: Self.sessionsChartHeight)
    }

    // MARK: Time in front

    private func frontSection(profiles: [Profile], front: [FrontPoint]) -> some View {
        Section {
            if front.allSatisfy({ $0.minutes < 1 }) {
                Label("Son 7 günde önde geçen süre yok.", systemImage: "chart.bar.xaxis")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                frontChart(profiles: profiles, front: front)
            }
            ForEach(profiles) { profile in
                LabeledContent {
                    Text(frontSummary(for: profile))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                } label: {
                    DSAccountLabel(profile: profile)
                }
            }
        } header: {
            Text("Önde geçen süre")
        } footer: {
            footerText("Hesabın Claude'u öndeki uygulamayken geçen süre. Lanes bunu yalnız macOS'un \"uygulama öne geldi\" bildirimlerinden sayar, Claude'un içine bakmaz. Ekran kapalıyken ya da Mac uykudayken sayılmaz. Son 30 gün bu Mac'te saklanır.")
        }
    }

    private func frontChart(profiles: [Profile], front: [FrontPoint]) -> some View {
        let days = chartDays(front.map(\.day))
        return Chart(front) { point in
            BarMark(
                x: .value("Gün", point.day, unit: .day),
                y: .value("Dakika", point.minutes)
            )
            .foregroundStyle(by: .value("Hesap", point.profile.id.rawValue))
            .cornerRadius(DS.Space.xs)
        }
        .chartForegroundStyleScale(domain: profiles.map(\.id.rawValue), range: profiles.map(\.color.swatch))
        .chartLegend(.hidden)
        .chartXScale(domain: dayDomain(days))
        .chartXAxis {
            AxisMarks(values: days) { _ in
                AxisGridLine()
            }
            // Labels at each day's noon, not centred between marks: a
            // centred label needs a next mark, so the last day (today)
            // lost its label.
            AxisMarks(values: middays(days)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), anchor: .top)
            }
        }
        .chartYAxisLabel("dakika")
        .frame(height: Self.frontChartHeight)
    }

    private func frontSummary(for profile: Profile) -> String {
        String(localized: "Bugün \(FrontTimeLog.describe(seconds: model.frontSeconds(for: profile.id, days: 1))) · 7 gün \(FrontTimeLog.describe(seconds: model.frontSeconds(for: profile.id, days: 7)))")
    }

    private func chartPlaceholder(height: CGFloat) -> some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    private func footerText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The chart's days, each once and oldest first: one axis label per bar.
    private func chartDays(_ days: [Date]) -> [Date] {
        Array(Set(days)).sorted()
    }

    /// Noon of each day, where its label sits under its bar.
    private func middays(_ days: [Date]) -> [Date] {
        days.map { $0.addingTimeInterval(12 * 60 * 60) }
    }

    /// Every day of the chart, empty ones too, from the first day's start
    /// to the end of the last day, so each bar sits centred on its label.
    private func dayDomain(_ days: [Date]) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let first = days.first ?? today
        let last = days.last ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return first...max(first, end)
    }

    /// Saves the last 30 days of time in front per account, for example to
    /// bill a client.
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = String(localized: "Lanes önde geçen süre.csv")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(model.frontTimeCSV().utf8).write(to: url, options: .atomic)
        } catch {
            model.notice = AppModel.Notice(kind: .error, message: String(localized: "CSV yazılamadı: \(error.localizedDescription)"))
        }
    }

    struct FrontPoint: Identifiable {
        var profile: Profile
        var day: Date
        var minutes: Double
        var id: String { "\(profile.id.rawValue)-\(day.timeIntervalSince1970)" }
    }

    /// Minutes in front per account for the last 7 days. Today's bar
    /// includes the time the front account has been in front right now.
    private func frontPoints() -> [FrontPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var points: [FrontPoint] = []
        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for profile in model.library.profiles {
                let seconds = offset == 0
                    ? model.frontSeconds(for: profile.id, days: 1)
                    : model.frontTime.seconds(for: profile.id, on: day)
                points.append(FrontPoint(profile: profile, day: day, minutes: seconds / 60))
            }
        }
        return points
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
        loaded = true
    }
}
