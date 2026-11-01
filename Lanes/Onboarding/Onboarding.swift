import AppKit
import LanesCore
import SwiftUI

/// "Başlarken": the first-launch tour. Each step is a short text on the
/// left and, on the right, a small working model of the Lanes piece it
/// talks about, drawn with the user's own accounts when there are any.
/// Every install or permission prompt still waits for its button; closing
/// the window at any step is fine, and Kurulum and Ayarlar hold the same
/// controls afterwards.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    init(model: AppModel, router: WindowRouter) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: OnboardingMetrics.width, height: OnboardingMetrics.height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = String(localized: "Lanes'e Hoş Geldin")
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        let root = OnboardingView(close: { [weak window] in window?.performClose(nil) })
            .environment(model)
            .environment(router)
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: OnboardingMetrics.width, height: OnboardingMetrics.height))
        window.center()
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func windowWillClose(_ notification: Notification) {
        // Closed at any step counts as seen: it never comes back by itself.
        // A tour cut short by a crash or a quit keeps its pending mark and
        // comes back on the next launch.
        Preferences.finishOnboarding()
        DockPresence.windowDidClose(window)
    }
}

enum OnboardingMetrics {
    static let width: CGFloat = 980
    static let height: CGFloat = 640
    static let margin: CGFloat = 40
    static let textWidth: CGFloat = 392
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case dock
    case claude
    case claudeCode
    case permissions
    case accounts
    case features
    case done

    var id: Int { rawValue }

    var eyebrow: LocalizedStringKey {
        switch self {
        case .welcome: return "Başlarken"
        case .dock: return "Nasıl çalışır"
        case .claude: return "Gerekenler"
        case .claudeCode: return "Terminal"
        case .permissions: return "İzinler"
        case .accounts: return "Hesaplar"
        case .features: return "İsteğe bağlı"
        case .done: return "Hazır"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .welcome: return "Bir Mac.\nBirçok Claude hesabı."
        case .dock: return "Her hesap ayrı bir Claude"
        case .claude: return "Önce Claude uygulaması"
        case .claudeCode: return "Terminalde de doğru hesap"
        case .permissions: return "Üç izin, üç iş"
        case .accounts: return "Şeritlerin"
        case .features: return "Sana uyanları aç"
        case .done: return "Menü çubuğundayım"
        }
    }

    var text: LocalizedStringKey {
        switch self {
        case .welcome:
            return "Lanes her hesabını ayrı bir Claude olarak açar: kendi simgesi, kendi rengi, kendi girişi. İş ile kişisel, bir müşteri ile ötekisi birbirine karışmaz."
        case .dock:
            return "Lanes, Claude uygulamasının hesap başına bir kopyasını yapar. Her kopya Dock'ta ve Cmd-Tab'da kendi renkli simgesiyle durur ve girişini kendisi saklar."
        case .claude:
            return "Hesaplar Claude'un masaüstü uygulamasında açılır. Lanes onu Uygulamalar klasöründe bulur, kopyaları ondan yapar ve asıl uygulamaya dokunmaz."
        case .claudeCode:
            return "Claude Code kuruluysa bir proje klasörü hep kendi hesabıyla açılır; bir oturumu başka hesapla da sürdürebilirsin. Kullanmıyorsan bu adımı geç."
        case .permissions:
            return "macOS her birini bir kez sorar. Hiçbiri zorunlu değil; vermediğin iznin işi yalnızca çalışmaz."
        case .accounts:
            return "Her hesap bir şerit: iş, kişisel ya da her müşteri için bir tane. Ad ve renk seçer, Claude'da bir kez giriş yaparsın."
        case .features:
            return "Burada açtıkların Ayarlar'da da durur, istediğin zaman kapatabilirsin."
        case .done:
            return "Lanes menü çubuğunda bekler. Öndeki hesabın rengini orada görürsün; hesap açmak ya da her şeyi aramak için simgeye tıkla."
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let close: () -> Void

    @State private var step: OnboardingStep = .welcome
    /// Which way the last move went, for the slide direction.
    @State private var forward = true
    @State private var leaving = false

    var body: some View {
        let accounts = StageAccount.list(model)
        ZStack {
            OnboardingBackdrop(colors: accounts.map(\.color), step: step)
            VStack(spacing: 0) {
                topBar
                ZStack {
                    page(step, accounts: accounts)
                        .id(step)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar(accounts)
            }
        }
        .frame(width: OnboardingMetrics.width, height: OnboardingMetrics.height)
        .task {
            await model.setup.refresh()
            // Permissions and installs happen outside Lanes; follow them
            // while the tour is open so each row turns green by itself.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                if model.claude == nil { model.refreshInstances() }
                await model.setup.refreshPermissions()
            }
        }
        .onAppear {
            // The tour covers Kurulum; the page needn't open by itself too.
            UserDefaults.standard.set(true, forKey: Preferences.Key.setupShown)
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let inset: CGFloat = forward ? 36 : -36
        return .asymmetric(
            insertion: .offset(x: inset).combined(with: .opacity),
            removal: .offset(x: -inset * 0.6).combined(with: .opacity)
        )
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: String(format: "%02d", step.rawValue + 1))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(step.rawValue)))
            Text(step.eyebrow)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            if step != .done {
                Button("Sonra") { leave() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .focusEffectDisabled()
                    .keyboardShortcut(.cancelAction)
                    .help("Turu kapat. Kurulum sayfasından yeniden açabilirsin.")
            }
        }
        // Clear of the close button in the corner.
        .padding(.leading, 84)
        .padding(.trailing, OnboardingMetrics.margin)
        .padding(.top, 14)
        .frame(height: 44)
        .animation(.snappy(duration: 0.3), value: step)
    }

    private func bottomBar(_ accounts: [StageAccount]) -> some View {
        HStack(spacing: DS.Space.xl) {
            ProgressLanes(current: step, colors: accounts.map(\.color)) { move(to: $0) }
            Button("Geri") { move(to: OnboardingStep(rawValue: step.rawValue - 1)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .focusEffectDisabled()
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
            Spacer()
            Button {
                if step == .done {
                    leave()
                } else {
                    move(to: OnboardingStep(rawValue: step.rawValue + 1))
                }
            } label: {
                Text(nextTitle)
                    .frame(minWidth: 92)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(leaving)
        }
        .padding(.horizontal, OnboardingMetrics.margin)
        .padding(.top, DS.Space.l)
        .padding(.bottom, 26)
    }

    private var nextTitle: LocalizedStringKey {
        switch step {
        case .welcome: return "Başlayalım"
        case .claudeCode where model.setup.claudeCommand == nil: return "Şimdilik Geç"
        case .done: return "Lanes'i Aç"
        default: return "Devam"
        }
    }

    private func move(to target: OnboardingStep?) {
        guard let target, target != step else { return }
        forward = target.rawValue > step.rawValue
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88)) {
            step = target
        }
    }

    /// Leaves the tour for the main window: on Kurulum when something is
    /// still missing and the tour was cut short, so Lanes doesn't seem to
    /// vanish into the menu bar. The tour closes only once the main window
    /// is up, so Lanes keeps its Dock icon and stays in front between them.
    private func leave() {
        guard !leaving else { return }
        leaving = true
        Preferences.finishOnboarding()
        let destination: Destination = step != .done && model.unfinishedSetupCount > 0 ? .setup : .overview
        guard Preferences.showsDockIconWithWindow else {
            // Without the Dock icon setting, the tour (which always shows
            // one) goes first so Lanes drops back to the menu bar, and the
            // main window then opens the way the setting asks.
            close()
            router.showMainWindow(destination)
            return
        }
        let shown = router.showMainWindow(destination)
        Task { @MainActor in
            _ = await shown.value
            close()
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func page(_ step: OnboardingStep, accounts: [StageAccount]) -> some View {
        switch step {
        case .welcome:
            WelcomeScene(accounts: accounts)
        case .dock:
            StepPage(step: step) {
                EmptyView()
            } stage: {
                DockStage(accounts: accounts, claudeIcon: claudeIcon)
            }
        case .claude:
            StepPage(step: step) {
                SetupClaudeAppRow()
            } stage: {
                ClaudeAppStage(accounts: accounts, claudeIcon: claudeIcon)
            }
        case .claudeCode:
            StepPage(step: step) {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    SetupClaudeCodeRow()
                    SetupGitRow()
                }
            } stage: {
                TerminalStage(accounts: accounts)
            }
        case .permissions:
            StepPage(step: step) {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    SetupAutomationRow()
                    SetupAccessibilityRow()
                    SetupNotificationsRow()
                }
            } stage: {
                WindowsStage(accounts: accounts)
            }
        case .accounts:
            StepPage(step: step) {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    Button("Hesap Ekle…") { router.showAddProfile() }
                        .controlSize(.large)
                    Text("Ana pencerede açılır. Ekledikten sonra bu tura dönebilirsin.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } stage: {
                LanesStage(accounts: accounts)
            }
        case .features:
            StepPage(step: step) {
                OnboardingFeatures()
            } stage: {
                RoutingStage(accounts: accounts)
            }
        case .done:
            StepPage(step: step) {
                OnboardingReadiness()
            } stage: {
                MenuBarStage(accounts: accounts)
            }
        }
    }

    private var claudeIcon: NSImage? {
        model.claude.map { NSWorkspace.shared.icon(forFile: $0.url.path) }
    }
}

// MARK: - Accounts on stage

/// An account as the stages draw it: the user's own, or an example while
/// there are fewer than three.
struct StageAccount: Identifiable {
    let id: String
    let name: String
    let monogram: String
    let color: Color
    let detail: String
    let isExample: Bool

    @MainActor
    static func list(_ model: AppModel) -> [StageAccount] {
        var result: [StageAccount] = []
        for profile in model.library.profiles where !profile.isArchived && !profile.isDefault {
            guard result.count < 4 else { break }
            result.append(StageAccount(
                id: profile.id.rawValue,
                name: profile.name,
                monogram: profile.monogram,
                color: profile.color.swatch,
                detail: profile.accountClass.displayName,
                isExample: false
            ))
        }
        let example = String(localized: "örnek")
        let examples: [StageAccount] = [
            StageAccount(id: "example-work", name: String(localized: "İş"), monogram: "İ", color: ProfileColor.blue.swatch, detail: example, isExample: true),
            StageAccount(id: "example-client", name: String(localized: "Müşteri A"), monogram: "MA", color: ProfileColor.orange.swatch, detail: example, isExample: true),
            StageAccount(id: "example-personal", name: String(localized: "Kişisel"), monogram: "K", color: ProfileColor.green.swatch, detail: example, isExample: true),
        ]
        // The user's own accounts alone once there is one; examples, marked
        // as such, only while there are none.
        return result.isEmpty ? examples : result
    }
}

/// The clone's Dock icon, drawn the way Lanes draws it for the real copy:
/// a rounded square in the account's colour with its letters.
struct CloneIcon: View {
    let account: StageAccount
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(account.color)
                .frame(width: size * 0.8, height: size * 0.8)
                .shadow(color: .black.opacity(0.2), radius: size * 0.05, y: size * 0.03)
            Text(verbatim: account.monogram)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: size * 0.66)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Layout

/// A step: its text and controls on the left, its stage on the right.
private struct StepPage<Controls: View, Stage: View>: View {
    let step: OnboardingStep
    @ViewBuilder let controls: Controls
    @ViewBuilder let stage: Stage
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(step.title)
                        .font(.system(size: 30, weight: .bold))
                        .kerning(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .reveal(shown, delay: 0)
                    Text(step.text)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.m)
                        .reveal(shown, delay: 0.07)
                    controls
                        .padding(.top, 28)
                        .reveal(shown, delay: 0.16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.s)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: OnboardingMetrics.textWidth)

            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07))
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .scaleEffect(shown || reduceMotion ? 1 : 0.965)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.7, dampingFraction: 0.9).delay(0.05), value: shown)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, OnboardingMetrics.margin)
        .padding(.top, DS.Space.s)
        .onAppear { shown = true }
    }
}

/// Reveals a piece a moment after the one above it.
private struct Reveal: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.86).delay(delay), value: shown)
    }
}

private extension View {
    func reveal(_ shown: Bool, delay: Double) -> some View {
        modifier(Reveal(shown: shown, delay: delay))
    }
}

/// Short facts, each with a thin bar in an account colour.
private struct FactList: View {
    let facts: [LocalizedStringKey]
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            ForEach(facts.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                    Capsule()
                        .fill(colors.isEmpty ? Color.accentColor : colors[index % colors.count])
                        .frame(width: 3, height: 14)
                    Text(facts[index])
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One thin lane per step, filled in account colours up to the current
/// one. Clicking a lane jumps there.
private struct ProgressLanes: View {
    let current: OnboardingStep
    let colors: [Color]
    let select: (OnboardingStep) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.allCases) { step in
                Button {
                    select(step)
                } label: {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule()
                            .fill(color(for: step))
                            .scaleEffect(x: step.rawValue <= current.rawValue ? 1 : 0, anchor: .leading)
                    }
                    .frame(width: step == current ? 34 : 18, height: 4)
                    .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel(Text(step.eyebrow))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: current)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Adımlar"))
    }

    private func color(for step: OnboardingStep) -> Color {
        guard !colors.isEmpty else { return .accentColor }
        return colors[step.rawValue % colors.count]
    }
}

/// The window's backdrop: a few soft lanes in the account colours drifting
/// slowly behind everything, faint enough to keep text readable.
private struct OnboardingBackdrop: View {
    let colors: [Color]
    let step: OnboardingStep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
                let time: Double = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                Canvas { canvas, size in
                    draw(in: &canvas, size: size, time: time)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let alpha: Double = colorScheme == .dark ? 0.2 : 0.12
        canvas.addFilter(.blur(radius: 50))
        canvas.translateBy(x: size.width / 2, y: size.height / 2)
        canvas.rotate(by: .degrees(-9))
        canvas.translateBy(x: -size.width / 2, y: -size.height / 2)
        let shift = Double(step.rawValue) * 14
        for (index, color) in colors.prefix(3).enumerated() {
            let lane = Double(index)
            let wave: Double = sin(time * 0.17 + lane * 1.9) * 26
            let drift: Double = cos(time * 0.11 + lane) * 70
            let y: Double = Double(size.height) * (0.22 + 0.28 * lane) + wave - shift
            let rect = CGRect(x: -160 + drift, y: y, width: Double(size.width) + 320, height: 64)
            canvas.fill(Path(roundedRect: rect, cornerRadius: 32), with: .color(color.opacity(alpha)))
        }
    }
}

/// Sleeps; false once the task is cancelled.
private func pause(_ milliseconds: Int) async -> Bool {
    do {
        try await Task.sleep(for: .milliseconds(milliseconds))
        return true
    } catch {
        return false
    }
}

// MARK: - Welcome

private struct WelcomeScene: View {
    let accounts: [StageAccount]
    @State private var shown = false

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.xxl) {
            VStack(alignment: .leading, spacing: 0) {
                Text(OnboardingStep.welcome.title)
                    .font(.system(size: 44, weight: .bold))
                    .kerning(-1.2)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(shown, delay: 0.3)
                Text(OnboardingStep.welcome.text)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.l)
                    .reveal(shown, delay: 0.45)
                FactList(facts: [
                    "Girişlerine ve sohbetlerine dokunmaz.",
                    "Hiçbir yere veri göndermez.",
                    "Sen basmadan bir şey kurmaz, izin istemez.",
                ], colors: accounts.map(\.color))
                .padding(.top, 28)
                .reveal(shown, delay: 0.6)
            }
            .frame(width: 420, alignment: .leading)

            LaneRace(accounts: accounts, shown: shown)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
        .padding(.leading, OnboardingMetrics.margin + DS.Space.s)
        .onAppear { shown = true }
    }
}

/// The accounts' lanes racing in from the left, each carrying its clone
/// icon. A light runs along whichever lane is "in front".
private struct LaneRace: View {
    let accounts: [StageAccount]
    let shown: Bool
    @State private var active = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rest: [CGFloat] = [8, 46, 20, 58]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                lane(account, index: index)
            }
        }
        .task {
            guard !reduceMotion, accounts.count > 1 else { return }
            guard await pause(1400) else { return }
            while await pause(1900) {
                active = (active + 1) % accounts.count
            }
        }
    }

    private func lane(_ account: StageAccount, index: Int) -> some View {
        let isActive = index == active
        let response: Double = 0.7 + 0.13 * Double(index)
        return HStack(spacing: DS.Space.m) {
            CloneIcon(account: account, size: 50)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(account.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 7)
        .frame(height: 64)
        .background {
            ZStack {
                Capsule().fill(account.color.opacity(isActive ? 0.2 : 0.09))
                if isActive && !reduceMotion {
                    LaneLight(color: account.color)
                        .clipShape(Capsule())
                        .transition(.opacity)
                }
            }
        }
        // Room for the furthest resting offset, so every lane's end stays
        // inside the window.
        .padding(.trailing, OnboardingMetrics.margin + 60)
        .offset(x: shown || reduceMotion ? rest[index % rest.count] : -640)
        .opacity(shown ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: response, dampingFraction: 0.78).delay(0.08 * Double(index)), value: shown)
        .animation(.easeInOut(duration: 0.45), value: active)
    }
}

/// A soft light running along a lane, left to right.
private struct LaneLight: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                let width = proxy.size.width
                let span: Double = Double(width) + 160
                let time = context.date.timeIntervalSinceReferenceDate
                let x: Double = (time * 220).truncatingRemainder(dividingBy: span) - 160
                LinearGradient(colors: [.clear, color.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 160)
                    .offset(x: x)
            }
        }
    }
}

// MARK: - Stages

/// A Dock and a Cmd-Tab switcher with the real Claude icon and one clone
/// per account; the selection moves and the chosen clone bounces open.
private struct DockStage: View {
    let accounts: [StageAccount]
    let claudeIcon: NSImage?
    @State private var shown = false
    @State private var selected = 0
    @State private var bouncing: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            switcher
            Spacer(minLength: 0)
            Text(verbatim: accounts.isEmpty ? "" : String(localized: "\(accounts[selected % accounts.count].name) açılıyor"))
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, 5)
                .background(Capsule().fill(.regularMaterial))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: selected)
                .padding(.bottom, DS.Space.s)
            dock
                .padding(.bottom, 26)
        }
        .onAppear { shown = true }
        .task {
            guard !reduceMotion, !accounts.isEmpty else { return }
            guard await pause(1300) else { return }
            var next = 1
            while !Task.isCancelled {
                selected = next % accounts.count
                bouncing = selected
                guard await pause(280) else { return }
                bouncing = nil
                guard await pause(1700) else { return }
                next += 1
            }
        }
    }

    private var switcher: some View {
        HStack(spacing: DS.Space.s) {
            claudeTile(size: 54)
                .padding(6)
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                CloneIcon(account: account, size: 54)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(index == selected ? 0.22 : 0))
                    )
            }
        }
        .padding(DS.Space.m)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .environment(\.colorScheme, .dark)
        .scaleEffect(shown ? 1 : 0.9)
        .opacity(shown ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.15), value: shown)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }

    private var dock: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(spacing: 4) {
                claudeTile(size: 50)
                runningDot
            }
            Rectangle()
                .fill(Color.primary.opacity(0.18))
                .frame(width: 1, height: 42)
                .padding(.bottom, 10)
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                VStack(spacing: 4) {
                    CloneIcon(account: account, size: 50)
                        .offset(y: bouncing == index ? -16 : 0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.45), value: bouncing)
                    runningDot
                }
                .scaleEffect(shown || reduceMotion ? 1 : 0.2, anchor: .bottom)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.6).delay(0.35 + 0.12 * Double(index)), value: shown)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 5)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private var runningDot: some View {
        Circle()
            .fill(Color.primary.opacity(0.55))
            .frame(width: 4, height: 4)
    }

    @ViewBuilder
    private func claudeTile(size: CGFloat) -> some View {
        if let claudeIcon {
            Image(nsImage: claudeIcon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: size * 0.8, height: size * 0.8)
                .frame(width: size, height: size)
        }
    }
}

/// The real Claude icon feeding one copy per account. While Claude is
/// missing its place is a dashed outline and the copies wait, dimmed.
private struct ClaudeAppStage: View {
    let accounts: [StageAccount]
    let claudeIcon: NSImage?
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let installed = claudeIcon != nil
        HStack(spacing: 0) {
            VStack(spacing: DS.Space.s) {
                ZStack(alignment: .bottomTrailing) {
                    if let claudeIcon {
                        Image(nsImage: claudeIcon)
                            .resizable()
                            .frame(width: 104, height: 104)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, DS.Palette.success)
                            .offset(x: 2, y: 2)
                    } else {
                        MissingApp()
                    }
                }
                Text(verbatim: "Claude.app")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 150)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: installed)

            FlowLine(color: accounts.first?.color ?? .accentColor, running: installed && !reduceMotion)
                .frame(width: 70, height: 2)
                .opacity(installed ? 1 : 0.35)

            VStack(alignment: .leading, spacing: DS.Space.m) {
                ForEach(Array(accounts.prefix(3).enumerated()), id: \.element.id) { index, account in
                    HStack(spacing: DS.Space.s) {
                        CloneIcon(account: account, size: 40)
                        Text(verbatim: "Claude · \(account.name)")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                    .opacity(shown ? (installed ? 1 : 0.4) : 0)
                    .offset(x: shown || reduceMotion ? 0 : -18)
                    .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.25 + 0.1 * Double(index)), value: shown)
                }
            }
            .padding(.leading, DS.Space.m)
        }
        .padding(DS.Space.xl)
        .onAppear { shown = true }
    }
}

/// A dashed outline with an arrow bobbing into it: "put Claude here".
private struct MissingApp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .frame(width: 88, height: 88)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let bob: Double = reduceMotion ? 0 : sin(time * 3.2) * 5
                Image(systemName: "arrow.down")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .offset(y: bob)
            }
        }
        .frame(width: 104, height: 104)
    }
}

/// A dotted line whose dots flow left to right while `running`.
private struct FlowLine: View {
    let color: Color
    let running: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase: Double = running ? -(time * 28).truncatingRemainder(dividingBy: 9) : 0
            HorizontalLine()
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 8], dashPhase: phase))
        }
    }
}

private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// A terminal typing `lanes claude` in a few project folders, each
/// answered with the account that folder belongs to.
private struct TerminalStage: View {
    let accounts: [StageAccount]

    private struct Line: Identifiable {
        let id: Int
        let prompt: String
        let text: String
        let color: Color?
    }

    @State private var lines: [Line] = []
    @State private var typed = ""
    @State private var prompt = "site %"
    @State private var cursorOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let folders = ["site", "musteri-a", "notlar", "api"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach([Color.red, Color.yellow, Color.green], id: \.self) { color in
                    Circle().fill(color.opacity(0.85)).frame(width: 11, height: 11)
                }
                Spacer()
                Text(verbatim: "zsh — ~/Projeler")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                Spacer()
                Color.clear.frame(width: 47, height: 1)
            }
            .padding(.horizontal, DS.Space.m)
            .frame(height: 30)
            .background(Color.white.opacity(0.05))

            VStack(alignment: .leading, spacing: 5) {
                ForEach(lines) { line in
                    row(line)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
                HStack(spacing: 6) {
                    Text(verbatim: prompt).foregroundStyle(Color.white.opacity(0.45))
                    HStack(spacing: 0) {
                        Text(verbatim: typed).foregroundStyle(Color.white.opacity(0.92))
                        Text(verbatim: cursorOn ? "▍" : " ").foregroundStyle(Color.white.opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(DS.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
        .environment(\.colorScheme, .dark)
        .padding(28)
        .task { await run() }
        .task {
            guard !reduceMotion else { return }
            while await pause(530) {
                cursorOn.toggle()
            }
        }
    }

    private func row(_ line: Line) -> some View {
        HStack(spacing: 6) {
            if !line.prompt.isEmpty {
                Text(verbatim: line.prompt).foregroundStyle(Color.white.opacity(0.45))
            }
            Text(verbatim: line.text)
                .foregroundStyle(line.color ?? Color.white.opacity(0.92))
        }
        .lineLimit(1)
    }

    private func answer(for account: StageAccount) -> String {
        String(localized: "lanes: \(account.name) hesabıyla (klasöre bağlı)")
    }

    private func run() async {
        guard !accounts.isEmpty else { return }
        var count = 0
        if reduceMotion {
            for index in 0..<min(accounts.count, 3) {
                let account = accounts[index]
                lines.append(Line(id: count, prompt: "\(folders[index]) %", text: "lanes claude", color: nil))
                lines.append(Line(id: count + 1, prompt: "", text: answer(for: account), color: account.color))
                count += 2
            }
            return
        }
        var turn = 0
        while !Task.isCancelled {
            let account = accounts[turn % accounts.count]
            let folder = folders[turn % folders.count]
            prompt = "\(folder) %"
            guard await pause(500) else { return }
            for character in "lanes claude" {
                typed.append(character)
                guard await pause(Int.random(in: 40...95)) else { return }
            }
            guard await pause(260) else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                lines.append(Line(id: count, prompt: prompt, text: typed, color: nil))
                typed = ""
            }
            guard await pause(220) else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                lines.append(Line(id: count + 1, prompt: "", text: answer(for: account), color: account.color))
                if lines.count > 8 { lines.removeFirst(lines.count - 8) }
            }
            count += 2
            turn += 1
            guard await pause(1500) else { return }
        }
    }
}

/// Two accounts' windows trading places. The one in front gets its
/// account-colour frame, and now and then a "done" notice slides in: the
/// three things the permissions are for.
private struct WindowsStage: View {
    let accounts: [StageAccount]
    @State private var front = 0
    @State private var notice: StageAccount?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pair = Array(accounts.prefix(2))
        ZStack {
            ForEach(Array(pair.enumerated()), id: \.element.id) { index, account in
                let isFront = index == front
                MockWindow(account: account, framed: isFront)
                    .frame(width: 290, height: 200)
                    .offset(x: index == 0 ? -46 : 46, y: index == 0 ? -26 : 30)
                    .scaleEffect(isFront ? 1 : 0.95)
                    .zIndex(isFront ? 1 : 0)
                    .opacity(isFront ? 1 : 0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if let notice {
                StageNotice(account: notice)
                    .padding(DS.Space.l)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: front)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: notice?.id)
        .task {
            guard !reduceMotion, pair.count > 1 else { return }
            var turn = 0
            while await pause(2400) {
                front = 1 - front
                turn += 1
                if turn % 2 == 0 {
                    notice = pair[front]
                    guard await pause(1800) else { return }
                    notice = nil
                }
            }
        }
    }
}

private struct MockWindow: View {
    let account: StageAccount
    let framed: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.primary.opacity(0.18)).frame(width: 9, height: 9)
                }
                Spacer()
                CloneIcon(account: account, size: 20)
                Text(verbatim: account.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Color.clear.frame(width: 39, height: 1)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            VStack(alignment: .leading, spacing: 9) {
                bar(0.7)
                bar(0.9)
                bar(0.55)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 28)
            }
            .padding(DS.Space.m)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .padding(4)
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(account.color, lineWidth: 3)
                .opacity(framed ? 1 : 0)
        )
    }

    private func bar(_ fraction: CGFloat) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.1))
                .frame(width: proxy.size.width * fraction, height: 7)
        }
        .frame(height: 7)
    }
}

private struct StageNotice: View {
    let account: StageAccount

    var body: some View {
        HStack(spacing: DS.Space.s) {
            CloneIcon(account: account, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: account.name)
                    .font(.system(size: 12, weight: .semibold))
                Text("Claude Code cevabını bitirdi")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

/// The account lanes and an empty one waiting for the next account.
private struct LanesStage: View {
    let accounts: [StageAccount]
    @State private var shown = false
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                HStack(spacing: DS.Space.m) {
                    CloneIcon(account: account, size: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: account.name)
                            .font(.system(size: 14, weight: .semibold))
                        Text(verbatim: account.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.leading, 6)
                .padding(.vertical, 4)
                .background(Capsule().fill(account.color.opacity(0.12)))
                .offset(x: shown || reduceMotion ? 0 : -420)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.6 + 0.1 * Double(index), dampingFraction: 0.8).delay(0.1 * Double(index)), value: shown)
            }
            HStack(spacing: DS.Space.m) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                Text("Yeni hesap")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
            .padding(.vertical, 4)
            .background(
                Capsule().strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .opacity(shown ? (breathe ? 1 : 0.5) : 0)
            .animation(.easeOut(duration: 0.4).delay(0.5), value: shown)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear {
            shown = true
            guard !reduceMotion else {
                breathe = true
                return
            }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true).delay(0.9)) {
                breathe = true
            }
        }
    }
}

/// A claude:// link coming from another app and dropping into the lane
/// of the account its rule picks.
private struct RoutingStage: View {
    let accounts: [StageAccount]

    private let sources = ["Safari", "Terminal", "Mail"]
    @State private var turn = 0
    @State private var flying = false
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let laneCount = min(accounts.count, 3)
            let source = turn % sources.count
            let target = laneCount == 0 ? 0 : turn % laneCount
            let start = CGPoint(x: 70, y: sourceY(source, height: height))
            let end = CGPoint(x: width - 150, y: laneY(target, count: laneCount, height: height))
            ZStack(alignment: .topLeading) {
                ForEach(sources.indices, id: \.self) { index in
                    Text(verbatim: sources[index])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(index == source ? .primary : .secondary)
                        .frame(width: 86, height: 28)
                        .background(Capsule().fill(Color.primary.opacity(index == source ? 0.1 : 0.05)))
                        .position(x: 70, y: sourceY(index, height: height))
                }
                ForEach(Array(accounts.prefix(laneCount).enumerated()), id: \.element.id) { index, account in
                    let lit = landed && index == target
                    HStack(spacing: DS.Space.s) {
                        CloneIcon(account: account, size: 34)
                        Text(verbatim: account.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 4)
                    .frame(width: 180, height: 44)
                    .background(Capsule().fill(account.color.opacity(lit ? 0.3 : 0.1)))
                    .overlay(Capsule().strokeBorder(account.color.opacity(lit ? 0.8 : 0), lineWidth: 1.5))
                    .scaleEffect(lit ? 1.04 : 1)
                    .position(x: width - 110, y: laneY(index, count: laneCount, height: height))
                }
                Text(verbatim: "claude://claude.ai/new")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .scaleEffect(landed ? 0.6 : 1)
                    .opacity(landed ? 0 : 1)
                    .position(flying ? end : start)
            }
        }
        .padding(DS.Space.l)
        .animation(.spring(response: 0.7, dampingFraction: 0.82), value: flying)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: landed)
        .task {
            guard !accounts.isEmpty else { return }
            if reduceMotion {
                landed = true
                return
            }
            while await pause(700) {
                flying = true
                guard await pause(650) else { return }
                landed = true
                guard await pause(1300) else { return }
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) {
                    flying = false
                    landed = false
                    turn += 1
                }
            }
        }
    }

    private func sourceY(_ index: Int, height: CGFloat) -> CGFloat {
        height / 2 + CGFloat(index - 1) * 48
    }

    private func laneY(_ index: Int, count: Int, height: CGFloat) -> CGFloat {
        let middle = CGFloat(count - 1) / 2
        return height / 2 + (CGFloat(index) - middle) * 60
    }
}

/// The menu bar with Lanes's icon taking the front account's colour and
/// letter, and its menu below.
private struct MenuBarStage: View {
    let accounts: [StageAccount]
    @State private var front = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Space.s) {
            HStack(spacing: 14) {
                Spacer()
                if let account = current {
                    ZStack {
                        Circle().fill(account.color)
                        Text(verbatim: String(account.monogram.prefix(1)))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 17, height: 17)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))
                    .id(account.id)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(verbatim: "14:30")
                    .font(.system(size: 12, weight: .medium))
            }
            .font(.system(size: 12))
            .padding(.horizontal, DS.Space.l)
            .frame(height: 28)
            .background(Rectangle().fill(.regularMaterial))

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    HStack(spacing: DS.Space.s) {
                        Circle().fill(account.color).frame(width: 9, height: 9)
                        Text(verbatim: account.name)
                            .font(.system(size: 13))
                        Spacer()
                        if index == front {
                            Text("önde")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, DS.Space.s)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(index == front ? account.color.opacity(0.18) : Color.clear)
                    )
                }
                Divider().padding(.vertical, 4)
                HStack {
                    Text("Her şeyi ara…").font(.system(size: 13))
                    Spacer()
                    Text(verbatim: "⌥Space").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 5)
            }
            .padding(6)
            .frame(width: 240)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
            .padding(.trailing, 58)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : -8)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: shown)
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: front)
        .onAppear { shown = true }
        .task {
            guard !reduceMotion, accounts.count > 1 else { return }
            while await pause(1800) {
                front = (front + 1) % accounts.count
            }
        }
    }

    private var current: StageAccount? {
        accounts.isEmpty ? nil : accounts[front % accounts.count]
    }
}

// MARK: - Controls

/// Optional features as compact switches, one line each.
private struct OnboardingFeatures: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.Key.linkRoutingEnabled) private var linkRouting = false
    @AppStorage(Preferences.Key.accountFrameEnabled) private var accountFrame = false
    @AppStorage(Preferences.Key.clipboardGuardEnabled) private var clipboardGuard = false
    @AppStorage(Preferences.Key.focusModeEnabled) private var focusMode = false
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureSwitch(title: "Bağlantı yönlendirme", detail: "claude:// bağlantıları kurala göre doğru hesapta açılır.", isOn: Binding(
                get: { linkRouting },
                set: { enabled in
                    guard enabled else {
                        model.setLinkRouting(false)
                        return
                    }
                    // On only once Lanes really holds the claude:// default;
                    // declining the system prompt leaves it off.
                    Task {
                        await model.takeLinks()
                        let held = LinkHandlerRegistry.lanesIsHandler
                        UserDefaults.standard.set(held, forKey: Preferences.Key.linkRoutingEnabled)
                        linkRouting = held
                    }
                }
            ))
            FeatureSwitch(title: "Bitti Haberi", detail: "Claude Code işini bitirince hesabın adıyla bildirim.", isOn: Binding(
                get: { model.doneNoticesEnabled },
                set: { model.setDoneNotices(enabled: $0) }
            ))
            FeatureSwitch(title: "Hesap rengi çerçevesi", detail: "Öndeki Claude penceresinin çevresinde hesabın rengi.", isOn: $accountFrame)
            FeatureSwitch(title: "Pano Bekçisi", detail: "Başka hesaba kopyalanmış bir şeyi yapıştırmadan önce uyarı.", isOn: Binding(
                get: { clipboardGuard },
                set: { on in
                    clipboardGuard = on
                    if on { Task { _ = await Notifier.requestPermission() } }
                }
            ))
            FeatureSwitch(title: "Odak", detail: "Bir hesap öne gelince ötekilerin pencereleri gizlenir.", isOn: $focusMode)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                LoginItemToggle(title: "Oturum açılınca Lanes'i başlat", error: $loginItemError)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.callout)
                        .foregroundStyle(DS.Palette.danger)
                }
            }
        }
        .onChange(of: accountFrame) { model.updateAccountGuards() }
        .onChange(of: clipboardGuard) { model.updateAccountGuards() }
    }
}

private struct FeatureSwitch: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.m)
            Toggle(isOn: $isOn) { Text(title) }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// What is ready and what is left.
private struct OnboardingReadiness: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            item("Claude uygulaması", ok: model.claude != nil)
            item("Claude Code", ok: model.setup.claudeCommand != nil)
            item("Otomasyon izni", ok: automationGranted)
            item("Erişilebilirlik izni", ok: model.setup.accessibilityGranted)
            item("En az bir hesap", ok: model.library.profiles.contains { !$0.isArchived && !$0.isDefault })
            if model.unfinishedSetupCount > 0 {
                Text("Eksikleri kenar çubuğundaki Kurulum sayfasından tamamlayabilirsin.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s)
            }
        }
    }

    private var automationGranted: Bool {
        if case .granted? = model.setup.automation { return true }
        return false
    }

    private func item(_ title: LocalizedStringKey, ok: Bool) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? AnyShapeStyle(DS.Palette.success) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
            Spacer()
            Text(ok ? "Hazır" : "Sonra")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
