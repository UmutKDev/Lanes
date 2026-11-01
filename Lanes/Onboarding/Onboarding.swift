import AppKit
import LanesCore
import SwiftUI

/// "Başlarken": the first-launch tour. A presentation of what Lanes does,
/// then the pieces it needs one step at a time (Claude, Claude Code, the
/// permissions), the first account and a few features to turn on. Every
/// install or permission prompt still waits for its button; closing the
/// window at any step is fine, and Kurulum and Ayarlar hold the same
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
        UserDefaults.standard.set(true, forKey: Preferences.Key.onboardingCompleted)
        DockPresence.windowDidClose(window)
    }
}

enum OnboardingMetrics {
    static let width: CGFloat = 880
    static let height: CGFloat = 620
    static let contentWidth: CGFloat = 640
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case tour
    case claude
    case claudeCode
    case permissions
    case accounts
    case features
    case done

    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .welcome: return "sparkles"
        case .tour: return "square.stack.3d.up.fill"
        case .claude: return "macwindow.on.rectangle"
        case .claudeCode: return "terminal.fill"
        case .permissions: return "lock.shield.fill"
        case .accounts: return "person.2.fill"
        case .features: return "wand.and.stars"
        case .done: return "checkmark.seal.fill"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .welcome: return "Lanes'e hoş geldin"
        case .tour: return "Her hesap kendi şeridinde"
        case .claude: return "Claude uygulaması"
        case .claudeCode: return "Claude Code"
        case .permissions: return "İzinler"
        case .accounts: return "Hesapların"
        case .features: return "Sana uygun olanları aç"
        case .done: return "Hazırsın"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .welcome:
            return "Birden çok Claude hesabını tek Mac'te, birbirine karışmadan kullan. Kurulum birkaç dakika sürer; her adımı sonra da değiştirebilirsin."
        case .tour:
            return "Lanes her hesabı kendi Claude kopyasında, kendi renkli Dock simgesiyle açar. Girişler, sohbetler ve ayarlar hesaplar arasında hiç karışmaz."
        case .claude:
            return "Hesaplar Claude'un masaüstü uygulamasında açılır. Lanes onu Uygulamalar klasöründe bulur ve hiç değiştirmez."
        case .claudeCode:
            return "Terminalde hesap başına Claude Code, oturumları başka hesapla sürdürme ve Bitti Haberi için. İstemiyorsan bu adımı geçebilirsin."
        case .permissions:
            return "macOS her izni bir kez sorar. Lanes yalnız neden gerektiğini söylediği şey için kullanır; hiçbiri zorunlu değil."
        case .accounts:
            return "Her hesap ayrı bir Claude olarak açılır. İş, kişisel ya da her müşteri için bir hesap ekleyebilirsin."
        case .features:
            return "Bunlar isteğe bağlı. Hepsi Ayarlar'da da duruyor."
        case .done:
            return "Lanes menü çubuğunda bekler. Bir hesabı açmak, bağlantıları yönlendirmek ya da her şeyi aramak için oradan başla."
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

    var body: some View {
        ZStack {
            OnboardingBackground(step: step)
            VStack(spacing: 0) {
                header
                ZStack {
                    page(step)
                        .id(step)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
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
        let edgeIn: Edge = forward ? .trailing : .leading
        let edgeOut: Edge = forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: edgeIn).combined(with: .opacity),
            removal: .move(edge: edgeOut).combined(with: .opacity)
        )
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Spacer()
            if step != .done {
                Button("Sonra") { later() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Turu kapat. Kurulum sayfasından yeniden açabilirsin.")
            }
        }
        .padding(.horizontal, DS.Space.xxl)
        .padding(.top, DS.Space.l)
        .frame(height: 44)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.l) {
            Button {
                move(to: OnboardingStep(rawValue: step.rawValue - 1))
            } label: {
                Label("Geri", systemImage: "chevron.left")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)

            Spacer()
            OnboardingPageDots(current: step) { move(to: $0) }
            Spacer()

            if step == .done {
                Button {
                    finish()
                } label: {
                    Text("Lanes'i Aç")
                        .frame(minWidth: 96)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    move(to: OnboardingStep(rawValue: step.rawValue + 1))
                } label: {
                    Text(nextTitle)
                        .frame(minWidth: 96)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, DS.Space.xxl)
        .padding(.bottom, DS.Space.xl)
        .padding(.top, DS.Space.m)
    }

    private var nextTitle: LocalizedStringKey {
        switch step {
        case .welcome: return "Başlayalım"
        case .claudeCode where model.setup.claudeCommand == nil: return "Şimdilik Geç"
        default: return "Devam"
        }
    }

    private func move(to target: OnboardingStep?) {
        guard let target, target != step else { return }
        forward = target.rawValue > step.rawValue
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86)) {
            step = target
        }
    }

    /// Leaves the tour for the main window, on Kurulum when something
    /// is still missing, so Lanes doesn't seem to vanish into the menu bar.
    private func later() {
        UserDefaults.standard.set(true, forKey: Preferences.Key.onboardingCompleted)
        router.showMainWindow(model.unfinishedSetupCount > 0 ? .setup : .overview)
        close()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Preferences.Key.onboardingCompleted)
        router.showMainWindow(.overview)
        close()
    }

    // MARK: Pages

    @ViewBuilder
    private func page(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            OnboardingWelcome()
        case .tour:
            OnboardingPage(step: step) { OnboardingTour() }
        case .claude:
            OnboardingPage(step: step) {
                OnboardingCard { SetupClaudeAppRow() }
            }
        case .claudeCode:
            OnboardingPage(step: step) {
                VStack(spacing: DS.Space.m) {
                    OnboardingCard { SetupClaudeCodeRow() }
                    OnboardingCard { SetupGitRow() }
                }
            }
        case .permissions:
            OnboardingPage(step: step) {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        SetupAutomationRow()
                        Divider()
                        SetupAccessibilityRow()
                        Divider()
                        SetupNotificationsRow()
                    }
                }
            }
        case .accounts:
            OnboardingPage(step: step) { OnboardingAccounts() }
        case .features:
            OnboardingPage(step: step) { OnboardingFeatures() }
        case .done:
            OnboardingPage(step: step) { OnboardingDone() }
        }
    }
}

// MARK: - Layout pieces

/// A step: its symbol, title and subtitle over the step's own content.
private struct OnboardingPage<Content: View>: View {
    let step: OnboardingStep
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.xxl) {
                VStack(spacing: DS.Space.m) {
                    OnboardingSymbol(systemName: step.symbol)
                    Text(step.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(step.subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560)
                }
                content
                    .frame(maxWidth: OnboardingMetrics.contentWidth)
            }
            .padding(.horizontal, DS.Space.xxxl)
            .padding(.vertical, DS.Space.l)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// The step's symbol in a glass circle, with a soft glow behind it.
private struct OnboardingSymbol: View {
    let systemName: String
    @State private var appeared = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 34, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .frame(width: 76, height: 76)
            .glassEffect(.regular, in: .circle)
            .background {
                Circle()
                    .fill(Color.accentColor.opacity(0.35))
                    .blur(radius: 24)
                    .scaleEffect(1.3)
            }
            .symbolEffect(.bounce, value: appeared)
            .onAppear { appeared = true }
            .accessibilityHidden(true)
    }
}

/// A rounded glass panel for a step's controls.
private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
    }
}

/// One capsule per step; the current one is long and tinted. Clicking a
/// dot jumps there.
private struct OnboardingPageDots: View {
    let current: OnboardingStep
    let select: (OnboardingStep) -> Void

    var body: some View {
        HStack(spacing: DS.Space.s) {
            ForEach(OnboardingStep.allCases) { step in
                Button {
                    select(step)
                } label: {
                    Capsule()
                        .fill(step == current ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(HierarchicalShapeStyle.quaternary))
                        .frame(width: step == current ? 22 : 8, height: 8)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(step.title))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Adımlar"))
    }
}

/// A slowly drifting mesh of the account colours, softened under a
/// material so text on top stays readable in light and dark.
private struct OnboardingBackground: View {
    let step: OnboardingStep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: points(time),
                colors: colors
            )
        }
        .overlay {
            Rectangle().fill(.regularMaterial).opacity(colorScheme == .dark ? 0.55 : 0.45)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: step)
    }

    private var colors: [Color] {
        // Shifts a little with each step, so moving on feels like moving.
        let shift = step.rawValue % 3
        let base: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan, .purple]
        let alpha: Double = colorScheme == .dark ? 0.55 : 0.4
        var result: [Color] = []
        for index in 0..<9 {
            result.append(base[(index + shift) % base.count].opacity(alpha))
        }
        return result
    }

    private func points(_ time: Double) -> [SIMD2<Float>] {
        func wobble(_ phase: Double) -> Float {
            Float(sin(time * 0.25 + phase) * 0.08)
        }
        func point(_ x: Float, _ y: Float) -> SIMD2<Float> {
            SIMD2<Float>(x, y)
        }
        var result: [SIMD2<Float>] = []
        result.append(point(0, 0))
        result.append(point(0.5 + wobble(0), 0))
        result.append(point(1, 0))
        result.append(point(0, 0.5 + wobble(1)))
        result.append(point(0.5 + wobble(2), 0.5 + wobble(3)))
        result.append(point(1, 0.5 + wobble(4)))
        result.append(point(0, 1))
        result.append(point(0.5 + wobble(5), 1))
        result.append(point(1, 1))
        return result
    }
}

// MARK: - Steps

/// The opening slide: the app icon over three coloured lanes sliding in.
private struct OnboardingWelcome: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private let lanes: [(Color, CGFloat)] = [(.blue, 0), (.purple, 0.12), (.orange, 0.24)]

    var body: some View {
        VStack(spacing: DS.Space.xxl) {
            ZStack {
                VStack(spacing: DS.Space.s) {
                    ForEach(lanes.indices, id: \.self) { index in
                        let (color, delay) = lanes[index]
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: 300, height: 18)
                            .offset(x: shown ? CGFloat(index - 1) * 26 : -420)
                            .opacity(shown ? 0.9 : 0)
                            .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.8).delay(delay), value: shown)
                    }
                }
                .blur(radius: 0.3)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    .scaleEffect(shown ? 1 : 0.7)
                    .opacity(shown ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.7).delay(0.35), value: shown)
            }
            .frame(height: 170)
            .accessibilityHidden(true)

            VStack(spacing: DS.Space.m) {
                Text(OnboardingStep.welcome.title)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(OnboardingStep.welcome.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.5), value: shown)

            HStack(spacing: DS.Space.l) {
                OnboardingPromise(symbol: "lock.fill", text: "Girişlerine ve sohbetlerine dokunmaz")
                OnboardingPromise(symbol: "wifi.slash", text: "Hiçbir şey göndermez")
                OnboardingPromise(symbol: "hand.raised.fill", text: "Sen sormadan kurmaz, izin istemez")
            }
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.8), value: shown)
        }
        .padding(.horizontal, DS.Space.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { shown = true }
    }
}

private struct OnboardingPromise: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Four things Lanes does, as cards.
private struct OnboardingTour: View {
    private struct Feature: Identifiable {
        let symbol: String
        let color: Color
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        var id: String { symbol }
    }

    private let features: [Feature] = [
        Feature(symbol: "app.badge.fill", color: .blue, title: "Ayrı Claude'lar", text: "Her hesap kendi renkli simgesiyle, Dock'ta ve Cmd-Tab'da ayrı bir uygulama."),
        Feature(symbol: "arrow.triangle.branch", color: .purple, title: "Doğru hesaba bağlantı", text: "claude:// bağlantıları kurallarına göre doğru hesapta açılır."),
        Feature(symbol: "terminal.fill", color: .orange, title: "Hesap başına Claude Code", text: "Her proje klasörü kendi hesabıyla açılır; oturumu başka hesapla sürdürebilirsin."),
        Feature(symbol: "shield.lefthalf.filled", color: .green, title: "Karışmaya karşı", text: "Hesap rengi çerçevesi, Pano Bekçisi ve Kimlik Bekçisi müşterileri ayrı tutar."),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.l), GridItem(.flexible(), spacing: DS.Space.l)], spacing: DS.Space.l) {
            ForEach(features) { feature in
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image(systemName: feature.symbol)
                        .font(.title2)
                        .foregroundStyle(feature.color.gradient)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(feature.title)
                            .font(.headline)
                        Text(feature.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
        }
    }
}

/// The accounts so far and a button to add one.
private struct OnboardingAccounts: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router

    var body: some View {
        VStack(spacing: DS.Space.m) {
            OnboardingCard {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    let profiles = model.library.profiles.filter { !$0.isArchived }
                    if profiles.isEmpty {
                        Text("Henüz hesap yok.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(profiles) { profile in
                        HStack(spacing: DS.Space.m) {
                            MonogramView(profile: profile, size: 32, isRunning: model.isRunning(profile))
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(profile.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(profile.isDefault
                                     ? String(localized: "Claude uygulamasının kendi hesabı")
                                     : profile.accountClass.displayName)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Button {
                        router.showAddProfile()
                    } label: {
                        Label("Hesap Ekle…", systemImage: "plus")
                    }
                    .buttonStyle(.glass)
                }
            }
            Text("Yeni hesap ana pencerede eklenir; ad, renk ve tür seçip Claude'da bir kez giriş yaparsın. Sonra bu tura dönebilirsin.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Optional features as switches, each with one line on what it does.
private struct OnboardingFeatures: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.Key.accountFrameEnabled) private var accountFrame = false
    @AppStorage(Preferences.Key.clipboardGuardEnabled) private var clipboardGuard = false
    @AppStorage(Preferences.Key.focusModeEnabled) private var focusMode = false
    @State private var linkRouting = Preferences.linkRoutingEnabled
    @State private var loginItemError: String?

    var body: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                OnboardingToggle(symbol: "arrow.triangle.branch", title: "Bağlantı yönlendirme", text: "claude:// bağlantılarını Lanes açar ve Hesap Haritası'ndaki kurallara göre bir hesaba verir.", isOn: Binding(
                    get: { linkRouting },
                    set: { on in
                        linkRouting = on
                        model.setLinkRouting(on)
                    }
                ))
                Divider()
                OnboardingToggle(symbol: "bell.badge.fill", title: "Bitti Haberi", text: "Lanes'ten açılan Claude Code cevabını bitirince ya da onay isteyince hesabın adıyla bildirim.", isOn: Binding(
                    get: { model.doneNoticesEnabled },
                    set: { model.setDoneNotices(enabled: $0) }
                ))
                Divider()
                OnboardingToggle(symbol: "rectangle.dashed", title: "Hesap rengi çerçevesi", text: "Öndeki Claude penceresinin çevresinde hesabın renginde ince bir çerçeve.", isOn: $accountFrame)
                Divider()
                OnboardingToggle(symbol: "doc.on.clipboard", title: "Pano Bekçisi", text: "Bir hesapta kopyalayıp başka bir hesaba geçince uyarı. Panonun içi okunmaz.", isOn: Binding(
                    get: { clipboardGuard },
                    set: { on in
                        clipboardGuard = on
                        if on { Task { _ = await Notifier.requestPermission() } }
                    }
                ))
                Divider()
                OnboardingToggle(symbol: "scope", title: "Odak", text: "Bir hesap öne gelince öteki hesapların pencereleri gizlenir.", isOn: $focusMode)
                Divider()
                HStack(alignment: .top, spacing: DS.Space.m) {
                    OnboardingToggleIcon(symbol: "power")
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        LoginItemToggle(title: "Oturum açıldığında Lanes'i başlat", error: $loginItemError)
                        if let loginItemError {
                            Text(loginItemError)
                                .font(.callout)
                                .foregroundStyle(DS.Palette.danger)
                        }
                    }
                }
            }
        }
        .onChange(of: accountFrame) { model.updateAccountGuards() }
        .onChange(of: clipboardGuard) { model.updateAccountGuards() }
    }
}

private struct OnboardingToggle: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            OnboardingToggleIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.l)
            Toggle(isOn: $isOn) { Text(title) }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct OnboardingToggleIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
            .frame(width: 28, height: 28)
            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// What is ready, what is left, and where things are.
private struct OnboardingDone: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: DS.Space.l) {
            OnboardingCard {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    readiness("Claude uygulaması", ok: model.claude != nil)
                    readiness("Claude Code", ok: model.setup.claudeCommand != nil)
                    readiness("Otomasyon izni", ok: automationGranted)
                    readiness("Erişilebilirlik izni", ok: model.setup.accessibilityGranted)
                    readiness("Hesap", ok: model.library.profiles.contains { !$0.isArchived })
                }
            }
            if model.unfinishedSetupCount > 0 {
                Text("Eksikleri istediğin zaman kenar çubuğundaki Kurulum sayfasından tamamlayabilirsin.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: DS.Space.l) {
                OnboardingTip(symbol: "menubar.rectangle", text: "Menü çubuğu simgesi: hesaplar ve sahneler")
                OnboardingTip(symbol: "magnifyingglass", text: "Komut Paleti: simgeye sağ tıkla ya da kısayol ata")
                OnboardingTip(symbol: "keyboard", text: "Kısayollar: Ayarlar > Kısayollar")
            }
        }
    }

    private var automationGranted: Bool {
        if case .granted? = model.setup.automation { return true }
        return false
    }

    private func readiness(_ title: LocalizedStringKey, ok: Bool) -> some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(ok ? AnyShapeStyle(DS.Palette.success) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
            Spacer()
            Text(ok ? "Hazır" : "Sonra")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingTip: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: DS.Space.s) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, minHeight: 96)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}
