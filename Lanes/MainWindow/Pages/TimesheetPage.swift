import AppKit
import LanesCore
import SwiftUI
import UniformTypeIdentifiers

/// "Zaman Çizelgesi": one week per account (the customer) and its Claude
/// Code projects, for billing or a weekly report. Time in front comes
/// from macOS's "app became active" events; Claude Code time from when
/// its session files were written. Nothing inside Claude is read.
struct TimesheetPage: View {
    @Environment(AppModel.self) private var model
    /// Weeks back from this one: 0 is this week.
    @State private var weeksBack = 0
    @State private var expanded: Set<ProfileID> = []
    @AppStorage(Notifier.Kind.weeklySummary.preferenceKey) private var weeklySummary = false

    /// Time in front is kept for 30 days, so four weeks back is the end.
    private static let maximumWeeksBack = 4

    var body: some View {
        let sheet = model.timesheet(forWeekContaining: weekDate)
        Form {
            Section {
                HStack {
                    Button {
                        weeksBack += 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(weeksBack >= Self.maximumWeeksBack)
                    .accessibilityLabel(Text("Önceki hafta"))
                    Text(Self.title(for: sheet))
                        .font(DS.Typography.rowTitle)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                    Button {
                        weeksBack -= 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(weeksBack == 0)
                    .accessibilityLabel(Text("Sonraki hafta"))
                    Button("Bu Hafta") { weeksBack = 0 }
                        .disabled(weeksBack == 0)
                }
                .buttonStyle(.borderless)
            }
            if sheet.usedAccounts.isEmpty {
                Section {
                    Label("Bu hafta hiçbir hesap kullanılmadı.", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    TimesheetGrid(sheet: sheet, expanded: $expanded)
                } footer: {
                    caption("\"Claude Code\" süresi tahminidir. İki süre çakışabilir, toplanmaz.")
                }
            }
            Section {
                Toggle("Pazartesi özeti", isOn: Binding(
                    get: { weeklySummary },
                    set: { isOn in
                        weeklySummary = isOn
                        if isOn {
                            Task { _ = await Notifier.requestPermission() }
                        }
                    }
                ))
            } footer: {
                caption("Geçen haftanın süreleri pazartesi sabahı bildirimle gelir.")
            }
        }
        .libraryForm()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("CSV Olarak Dışa Aktar…") { exportCSV(sheet) }
                    Button("PDF Olarak Dışa Aktar…") { exportPDF(sheet) }
                } label: {
                    Label("Dışa Aktar", systemImage: "square.and.arrow.up")
                }
                .help("Dışa Aktar")
                .disabled(sheet.usedAccounts.isEmpty)
            }
        }
    }

    private var weekDate: Date {
        Calendar.current.date(byAdding: .day, value: -7 * weeksBack, to: Date()) ?? Date()
    }

    static func title(for sheet: Timesheet) -> String {
        guard let first = sheet.days.first, let last = sheet.days.last else { return "" }
        let format = Date.FormatStyle().day().month(.abbreviated)
        return "\(first.formatted(format)) – \(last.formatted(format.year()))"
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileName(_ sheet: Timesheet, ext: String) -> String {
        "Lanes zaman çizelgesi \(FrontTimeLog.dayKey(sheet.weekStart)).\(ext)"
    }

    private func exportCSV(_ sheet: Timesheet) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = fileName(sheet, ext: "csv")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(sheet.csv().utf8).write(to: url, options: .atomic)
        } catch {
            model.notice = AppModel.Notice(kind: .error, message: String(localized: "CSV yazılamadı: \(error.localizedDescription)"))
        }
    }

    /// An A4 landscape page drawn from the same grid, always in light mode.
    private func exportPDF(_ sheet: Timesheet) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = fileName(sheet, ext: "pdf")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report = TimesheetReport(sheet: sheet)
            .environment(model)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: report)
        renderer.proposedSize = ProposedViewSize(width: 842 - 72, height: nil)
        var written = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 842, height: max(595, size.height + 72))
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            context.translateBy(x: 36, y: box.height - 36 - size.height)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            written = true
        }
        if !written {
            model.notice = AppModel.Notice(kind: .error, message: String(localized: "PDF yazılamadı."))
        }
    }
}

/// Accounts with their front and Claude Code time per day; a disclosure
/// shows each account's projects.
private struct TimesheetGrid: View {
    @Environment(AppModel.self) private var model
    let sheet: Timesheet
    @Binding var expanded: Set<ProfileID>
    var isPrinting = false

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: DS.Space.m, verticalSpacing: DS.Space.s) {
            GridRow {
                Text("")
                    .gridColumnAlignment(.leading)
                ForEach(sheet.days, id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                }
                Text("Toplam")
            }
            .font(DS.Typography.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(sheet.usedAccounts) { account in
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                GridRow {
                    accountLabel(account)
                    ForEach(0..<7, id: \.self) { day in
                        cell(account.front[day])
                    }
                    cell(account.frontTotal, bold: true)
                }
                if account.codeTotal >= 60 {
                    GridRow {
                        Text("Claude Code")
                            .foregroundStyle(.secondary)
                            .padding(.leading, DS.Space.l)
                        ForEach(0..<7, id: \.self) { day in
                            cell(account.code[day], secondary: true)
                        }
                        cell(account.codeTotal, bold: true, secondary: true)
                    }
                    if isPrinting || expanded.contains(account.id) {
                        ForEach(account.projects.filter { $0.total >= 60 }) { project in
                            GridRow {
                                Text(project.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, DS.Space.xl)
                                ForEach(0..<7, id: \.self) { day in
                                    cell(project.seconds[day], secondary: true)
                                }
                                cell(project.total, secondary: true)
                            }
                            .font(DS.Typography.caption)
                        }
                    }
                }
            }
        }
        .monospacedDigit()
    }

    @ViewBuilder
    private func accountLabel(_ account: Timesheet.Account) -> some View {
        let label = HStack(spacing: DS.Space.xs) {
            if let profile = model.profile(withID: account.id) {
                DSAccountLabel(profile: profile, size: DS.Monogram.tiny)
            } else {
                Text(account.name)
            }
        }
        if isPrinting || account.codeTotal < 60 {
            label
        } else {
            Button {
                if expanded.contains(account.id) {
                    expanded.remove(account.id)
                } else {
                    expanded.insert(account.id)
                }
            } label: {
                HStack(spacing: DS.Space.xxs) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(expanded.contains(account.id) ? 90 : 0))
                        .foregroundStyle(.secondary)
                    label
                }
            }
            .buttonStyle(.plain)
            .help(expanded.contains(account.id) ? "Projeleri gizle" : "Projeleri göster")
        }
    }

    private func cell(_ seconds: Double, bold: Bool = false, secondary: Bool = false) -> some View {
        Text(Timesheet.duration(seconds))
            .fontWeight(bold ? .semibold : .regular)
            .foregroundStyle(secondary || seconds < 60 ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
            .lineLimit(1)
    }
}

/// The printable page: a title and the grid with every project shown.
private struct TimesheetReport: View {
    let sheet: Timesheet

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            Text("Zaman Çizelgesi · \(TimesheetPage.title(for: sheet))")
                .font(.title2.weight(.semibold))
            TimesheetGrid(sheet: sheet, expanded: .constant([]), isPrinting: true)
            Text("Lanes ile hazırlandı. \"Claude önde\": Claude penceresinin önde olduğu süre. \"Claude Code\": tahmini çalışma süresi.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DS.Space.s)
        .frame(width: 842 - 72, alignment: .leading)
        .background(Color.white)
    }
}
