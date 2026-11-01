import LanesCore
import SwiftUI

/// Every account as a tile, with Claude's state above them.
struct OverviewPage: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @State private var isConfirmingQuitAll = false
    /// The kind of account the tiles are narrowed to; nil shows all.
    @State private var classFilter: AccountClass?

    /// Columns grow with the window; no maximum, so wide windows get more
    /// and wider tiles instead of an empty band on the right.
    private let columns = [GridItem(.adaptive(minimum: DS.Metrics.tileMinWidth), spacing: DS.Space.grid)]

    var body: some View {
        DSPage(maxWidth: pageWidth) {
            if model.isFirstLaunch {
                WelcomeBanner()
            }
            if let notice = model.notice {
                DSNoticeRow(notice: notice) { model.notice = nil }
            }
            if model.isTranslocated && !model.isTranslocationNoticeDismissed {
                DSNoticeRow(
                    kind: .warning,
                    message: String(localized: "Lanes geçici bir konumdan çalışıyor ve güncellenemez. Lanes'ten çık, Lanes.app'i Uygulamalar klasörüne taşı ve oradan aç."),
                    onDismiss: { model.isTranslocationNoticeDismissed = true }
                )
            }
            if model.claude == nil && !model.isMissingClaudeNoticeDismissed {
                DSNoticeRow(
                    kind: .warning,
                    message: String(localized: "Claude bu Mac'te bulunamadı. Hesapları açmak için Claude'u yükle."),
                    onDismiss: { model.isMissingClaudeNoticeDismissed = true }
                )
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.grid) {
                ForEach(filteredProfiles) { profile in
                    AccountTile(profile: profile)
                }
            }
        }
        .navigationSubtitle(memorySubtitle)
        .toolbar {
            if usedClasses.count > 1 {
                ToolbarItem(placement: .principal) {
                    Picker("Hesap türü", selection: $classFilter) {
                        Text("Tümü").tag(AccountClass?.none)
                        ForEach(usedClasses, id: \.self) { kind in
                            Label(kind.displayName, systemImage: kind.symbol).tag(AccountClass?.some(kind))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Tümünü Aç") { model.openAllClosedAccounts() }
                    .disabled(model.closedActiveProfiles.count <= 1)
                Button("Tümünü Kapat") { isConfirmingQuitAll = true }
                    .disabled(model.quittableOpenCount == 0)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Hesap Ekle", systemImage: "plus") {
                    navigation.isAddingProfile = true
                }
                .help("Hesap Ekle")
                .dsPrimaryAction()
            }
        }
        .confirmationDialog("Açık \(model.quittableOpenCount) hesap kapatılsın mı?", isPresented: $isConfirmingQuitAll) {
            Button("Tümünü Kapat") { model.quitAllLanesAccounts() }
        } message: {
            Text("Girişler ve sohbetler kalır. Claude uygulamasının kendi hesabı açık kalır.")
        }
        .onChange(of: usedClasses) { _, classes in
            if let classFilter, !classes.contains(classFilter) { self.classFilter = nil }
        }
    }

    /// The page grows with the number of tiles, up to the wide width, so a
    /// few accounts fill a centred column instead of sitting in the top-left
    /// corner of a wide window.
    private var pageWidth: CGFloat {
        let count = CGFloat(max(filteredProfiles.count, 1))
        let tiles = count * DS.Metrics.tileIdealWidth + (count - 1) * DS.Space.grid
        return min(DS.Metrics.wideWidth, max(DS.Metrics.readableWidth, tiles))
    }

    /// The live memory sentence, shown as the window subtitle. Empty while
    /// no account uses memory.
    private var memorySubtitle: String {
        guard model.totalMemoryBytes > 0 else { return "" }
        return String(localized: "Toplam bellek: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: model.totalMemoryBytes), countStyle: .memory))")
    }

    /// Kinds of the Lanes accounts, in their usual order. The Claude app's
    /// own account has no kind of its own, so it doesn't count.
    private var usedClasses: [AccountClass] {
        let kinds = Set(model.library.activeProfiles.filter { !$0.isDefault }.map(\.accountClass))
        return AccountClass.allCases.filter(kinds.contains)
    }

    /// The tiles to show. The Claude app's own account stays in every view.
    private var filteredProfiles: [Profile] {
        guard let classFilter else { return model.library.activeProfiles }
        return model.library.activeProfiles.filter { $0.isDefault || $0.accountClass == classFilter }
    }
}

private struct WelcomeBanner: View {
    var body: some View {
        DSCard {
            HStack(alignment: .top, spacing: DS.Space.l) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Lanes'e hoş geldin")
                        .font(DS.Typography.heroTitle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Hesap Ekle ile ilk hesabını ekle. Lanes, Claude uygulamasına ve giriş bilgilerine dokunmaz. Pencereyi kapatınca menü çubuğunda çalışmaya devam eder.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct AccountTile: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    let profile: Profile

    var body: some View {
        let isRunning = model.isRunning(profile)
        let usage = model.resourceUsage[profile.id]
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                // The identity block opens the account page with one click.
                Button {
                    navigation.navigate(to: .account(profile.id))
                } label: {
                    identity
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                HStack(spacing: DS.Space.s) {
                    // The one running indicator of the tile.
                    DSStatusBadge(isRunning: isRunning)
                    ClaudeCodePulseIcon(
                        pulse: model.claudeCodePulse[profile.id],
                        project: model.claudeCodeActiveProject(for: profile)
                    )
                    RestingIcon(profile: profile)
                    // Always laid out, so the row never reflows on launch or quit.
                    Text(verbatim: usage?.memory ?? " ")
                        .font(DS.Typography.caption)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(isRunning ? 1 : 0)
                        .help(usage?.summary ?? "")
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                    Button {
                        model.open(profile)
                    } label: {
                        // Reserves the wider title so the button never resizes.
                        ZStack {
                            Text("Öne Getir").hidden()
                            Text("Aç").hidden()
                            (isRunning ? Text("Öne Getir") : Text("Aç"))
                        }
                        .lineLimit(1)
                    }
                    .controlSize(.small)
                    .dsPrimaryAction(tint: profile.color.buttonTint)
                    .fixedSize()
                    .accessibilityLabel(isRunning ? Text("Öne Getir") : Text("Aç"))
                }
            }
            // Every line above is single-line and always present, so all
            // tiles share one height. The ideal height lets the spacer push
            // the action row to the bottom when the grid proposes no height.
            .frame(
                maxWidth: .infinity,
                minHeight: tileContentHeight,
                idealHeight: tileContentHeight,
                alignment: .topLeading
            )
        }
        .dsHoverHighlight()
        // Simultaneous, so a single click still reaches the tile's buttons.
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            navigation.navigate(to: .account(profile.id))
        })
        .animation(DS.Motion.standard, value: isRunning)
        .contextMenu {
            Button(isRunning ? "Öne Getir" : "Aç") {
                model.open(profile)
            }
            Button("Hesap Sayfası") {
                navigation.navigate(to: .account(profile.id))
            }
            Button("Claude Code'u Terminalde Aç") {
                model.openClaudeCode(profile)
            }
            LimitMenu(profile: profile)
            Divider()
            Button("Hesabı Çoğalt") {
                if let copy = model.duplicateProfile(profile) {
                    navigation.navigate(to: .account(copy.id))
                }
            }
            if !profile.isDefault {
                Button("Arşivle") {
                    model.setArchived(profile, true)
                }
                if isRunning {
                    Divider()
                    Button("Claude'dan Çık") {
                        model.quit(profile)
                    }
                }
            }
        }
    }

    private var identity: some View {
        HStack(spacing: DS.Space.m) {
            // The running state is shown once, by the status badge below.
            MonogramView(profile: profile, size: DS.Monogram.tile, isRunning: false)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(profile.name)
                    .font(DS.Typography.sectionTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(profile.name)
                Text(kindLine)
                    .font(DS.Typography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(kindLine)
                // Always laid out, so tiles with and without a note match.
                Text(verbatim: note ?? " ")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(note ?? "")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
    }

    /// Tile height inside the card padding.
    private var tileContentHeight: CGFloat {
        DS.Metrics.tileMinHeight - DS.Space.card * 2
    }

    /// The note, or the account's email when there is no note.
    private var note: String? {
        if let note = profile.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { return note }
        // The Claude app's account and accounts sharing ~/.claude get their
        // email from the shared Claude Code sign-in, which may be another
        // account than the one signed in to the app: say whose it is.
        if profile.isDefault || profile.usesSharedClaudeCode, profile.email == nil,
           let email = model.email(for: profile) {
            return String(localized: "Claude Code: \(email)")
        }
        return model.email(for: profile)
    }
}

extension AccountTile {
    /// The account's kind, with today's time in front once there is any.
    var kindLine: String {
        let kind = profile.isDefault ? String(localized: "Ana hesap") : profile.accountClass.displayName
        let today = model.frontSeconds(for: profile.id, days: 1)
        guard today >= 60 else { return kind }
        return String(localized: "\(kind) · bugün \(FrontTimeLog.describe(seconds: today))")
    }
}
