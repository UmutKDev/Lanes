import AppKit
import LanesCore
import SwiftUI

// MARK: - Tokens

/// Lanes design tokens. Page code uses these instead of literal numbers.
enum DS {

    /// 4-pt based spacing scale.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32

        /// Horizontal inset of scrolling pages. Matches the grouped Form inset
        /// so DSPage cards and Form cards share one leading edge.
        static let page: CGFloat = 20
        /// Vertical gap between page sections.
        static let section: CGFloat = 24
        /// Gap between a DSSectionHeader and its content.
        static let headerToContent: CGFloat = 10
        /// Inner padding of a DSCard.
        static let card: CGFloat = 16
        /// Gap between cards in a grid.
        static let grid: CGFloat = 16
    }

    /// Corner radii. Nested shapes use `concentric(outer:inset:)`.
    enum Radius {
        /// Tiny chips, swatch rings.
        static let small: CGFloat = 6
        /// Code blocks, text editors, fills nested inside a card.
        static let inner: CGFloat = 8
        /// Inline notice rows.
        static let notice: CGFloat = 12
        /// DSCard, overview tiles.
        static let card: CGFloat = 16
        /// Floating glass (page notice bar).
        static let floating: CGFloat = 18
        /// Menu bar panel.
        static let panel: CGFloat = 20

        /// Radius of a shape inset by `inset` inside a shape of radius `outer`.
        static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
            max(outer - inset, small)
        }
    }

    /// Typography roles. Always text styles, so Dynamic Type sizes apply.
    enum Typography {
        static let heroTitle: Font = .title2.weight(.semibold)
        static let sectionTitle: Font = .headline
        static let rowTitle: Font = .body
        static let rowSubtitle: Font = .subheadline
        static let caption: Font = .caption
        static let metricSmall: Font = .callout.weight(.semibold)
        static let code: Font = .system(.callout, design: .monospaced)
        static let path: Font = .system(.caption, design: .monospaced)
        static let shortcut: Font = .caption.monospacedDigit()
    }

    /// Semantic colours. System colours only; all adapt to dark mode.
    enum Palette {
        static var running: Color { .green }
        static var success: Color { .green }
        static var warning: Color { .orange }
        static var danger: Color { .red }
        static var info: Color { .accentColor }
        static var inactive: Color { Color(nsColor: .tertiaryLabelColor) }
        /// Resting fill of content cards. No stroke, no shadow.
        static var cardFill: Color { Color(nsColor: .quaternarySystemFill) }
        /// Hover fill for rows, tiles, icon buttons.
        static var hoverFill: Color { Color(nsColor: .tertiarySystemFill) }
        /// Pressed fill.
        static var pressedFill: Color { Color(nsColor: .secondarySystemFill) }
        /// Code blocks and text editors.
        static var codeFill: Color { Color(nsColor: .quaternarySystemFill) }
        /// Soft tinted background for in-content notices.
        static func tintedFill(_ tint: Color) -> Color { tint.opacity(0.12) }
    }

    /// Layout metrics shared across windows.
    enum Metrics {
        /// A page and the inspector side by side (the sidebar steps aside
        /// when all three do not fit). At 920 pt the account forms clipped.
        static let windowMinWidth: CGFloat = 1000
        /// Detail width the window keeps for a page while the sidebar and the
        /// inspector are both open; below it the sidebar steps aside.
        static let threeColumnDetailWidth: CGFloat = 680
        static let windowMinHeight: CGFloat = 580
        static let sidebarMin: CGFloat = 200
        static let sidebarIdeal: CGFloat = 230
        static let sidebarMax: CGFloat = 300
        static let inspectorMin: CGFloat = 240
        static let inspectorIdeal: CGFloat = 280
        static let inspectorMax: CGFloat = 340
        /// Narrowest detail column every page must lay out in.
        static let detailMinWidth: CGFloat = 440
        /// Max width of reading content (forms, cards, text pages).
        static let readableWidth: CGFloat = 760
        /// Max width of grid pages (overview).
        static let wideWidth: CGFloat = 1200
        /// Bottom scroll margin so the floating notice never covers content.
        static let noticeClearance: CGFloat = 80
        static let tileMinWidth: CGFloat = 260
        /// Width the overview budgets per tile when it sizes its column.
        static let tileIdealWidth: CGFloat = 340
        static let tileMinHeight: CGFloat = 128
        static let iconButton: CGFloat = 28
        static let statusIcon: CGFloat = 18
        /// In-page list columns (Settings panes, Validation checks).
        static let paneListMin: CGFloat = 180
        static let paneListIdeal: CGFloat = 200
        static let paneListMax: CGFloat = 240
        static let paneContentMin: CGFloat = 420
    }

    /// Monogram sizes. Only these sizes are used.
    enum Monogram {
        /// Tab strip, menu bar panel, link table rows.
        static let tiny: CGFloat = 16
        /// Sidebar, settings, lists, inline labels.
        static let small: CGFloat = 20
        /// Session rows.
        static let row: CGFloat = 24
        /// Menu bar panel rows.
        static let panel: CGFloat = 32
        /// Overview tiles.
        static let tile: CGFloat = 40
        /// Add-profile sheet, account identity row.
        static let hero: CGFloat = 56

        static func fontSize(for size: CGFloat) -> CGFloat { (size * 0.44).rounded() }
        static func dotDiameter(for size: CGFloat) -> CGFloat { max(5, (size * 0.28).rounded()) }
        static func ringWidth(for size: CGFloat) -> CGFloat { size < 24 ? 1.5 : 2 }
    }

    /// Animations.
    enum Motion {
        static var hover: Animation { .easeOut(duration: 0.12) }
        static var standard: Animation { .smooth(duration: 0.25) }
        static var notice: Animation { .smooth(duration: 0.3) }
    }

    /// Menu bar panel metrics.
    enum Panel {
        static let width: CGFloat = 360
        static let radius: CGFloat = DS.Radius.panel
        /// Horizontal inset of header, search, captions, footer, dividers.
        static let contentInset: CGFloat = 14
        /// Inset of hover rows from the panel edge.
        static let rowInset: CGFloat = 8
        static let rowRadius: CGFloat = DS.Radius.concentric(outer: DS.Radius.panel, inset: 8)
        static let rowPaddingH: CGFloat = 6
        static let rowPaddingV: CGFloat = 6
        /// Leading icon slot shared by account and scene rows.
        static let leadingSlot: CGFloat = 32
        /// Fraction of the screen's visible height the panel may use.
        static let maxHeightFraction: CGFloat = 0.8
        /// Max avatars in an overlapping strip before "+N".
        static let maxStackedAvatars = 4
    }

    /// Floating tab strip metrics.
    enum TabStrip {
        static let height: CGFloat = 40
        static let tabHeight: CGFloat = 28
        static let tabMinWidth: CGFloat = 44
        static let tabMaxWidth: CGFloat = 200
        static let spacing: CGFloat = 6
        static let inset: CGFloat = 6
    }
}

// MARK: - Profile colour contrast

extension ProfileColor {
    /// Light swatches get dark foreground text.
    var isLightSwatch: Bool {
        switch self {
        case .yellow, .mint, .cyan: return true
        default: return false
        }
    }

    /// Foreground colour for text or symbols drawn on the swatch.
    var onSwatch: Color {
        isLightSwatch ? Color.black.opacity(0.78) : Color.white
    }

    /// Tint for prominent buttons. Nil (accent colour) for light swatches,
    /// whose white button text would be unreadable.
    var buttonTint: Color? {
        isLightSwatch ? nil : swatch
    }
}

// MARK: - Page scaffold

/// A scrolling page: readable width, centred, consistent insets, soft edge
/// under the glass toolbar, room at the bottom for the floating notice.
/// The page title is the window title (navigationTitle). Put the subtitle in
/// `.navigationSubtitle`, not in the content.
struct DSPage<Content: View>: View {
    private let maxWidth: CGFloat
    private let spacing: CGFloat
    private let content: Content

    init(
        maxWidth: CGFloat = DS.Metrics.readableWidth,
        spacing: CGFloat = DS.Space.section,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, DS.Space.page)
            .padding(.top, DS.Space.l)
            .padding(.bottom, DS.Metrics.noticeClearance)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

// MARK: - Section header (DSPage only; inside a Form use Section("…"))

struct DSSectionHeader<Accessory: View>: View {
    private let title: Text
    private let subtitle: Text?
    private let accessory: Accessory

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
        self.accessory = accessory()
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                title
                    .font(DS.Typography.sectionTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    subtitle
                        .font(DS.Typography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: DS.Space.s)
            accessory
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

extension DSSectionHeader where Accessory == EmptyView {
    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Card (content layer: soft fill, never glass)

struct DSCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = DS.Space.card, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                DS.Palette.cardFill,
                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

/// Hover highlight that changes only a fill: no size or layout change.
struct DSHoverHighlight: ViewModifier {
    var cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.Palette.hoverFill)
                    .opacity(isHovered ? 1 : 0)
            }
            .onHover { isHovered = $0 }
            .animation(DS.Motion.hover, value: isHovered)
    }
}

// MARK: - Metric pill

struct DSStatPill: View {
    private let title: Text
    private let value: Text
    private let systemImage: String?

    init(_ title: LocalizedStringKey, value: Text, systemImage: String? = nil) {
        self.title = Text(title)
        self.value = value
        self.systemImage = systemImage
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, value: Text, systemImage: String? = nil) {
        self.title = Text(title)
        self.value = value
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: DS.Space.xs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            value
                .font(DS.Typography.metricSmall)
                .monospacedDigit()
                .contentTransition(.numericText())
            title
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.xs + 2)
        .background(DS.Palette.cardFill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Running status (Açık / Kapalı)

/// Dot plus "Açık"/"Kapalı". Always as wide as the wider word, so nothing
/// beside it moves when the state flips.
struct DSStatusBadge: View {
    let isRunning: Bool
    var font: Font = DS.Typography.caption

    var body: some View {
        HStack(spacing: DS.Space.xs + 1) {
            Circle()
                .fill(isRunning ? DS.Palette.running : DS.Palette.inactive)
                .frame(width: 7, height: 7)
            ZStack(alignment: .leading) {
                Text("Açık").hidden()
                Text("Kapalı").hidden()
                (isRunning ? Text("Açık") : Text("Kapalı"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(font)
        .lineLimit(1)
        .animation(DS.Motion.standard, value: isRunning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRunning ? Text("Açık") : Text("Kapalı"))
    }
}

// MARK: - Status row (icon column + title + detail + trailing action)

enum DSStatus: Equatable {
    case ok, info, warning, error, loading, neutral

    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .loading: return "circle.dotted"
        case .neutral: return "circle"
        }
    }

    var tint: Color {
        switch self {
        case .ok: return DS.Palette.success
        case .info: return DS.Palette.info
        case .warning: return DS.Palette.warning
        case .error: return DS.Palette.danger
        case .loading, .neutral: return DS.Palette.inactive
        }
    }
}

/// Fixed-size status icon slot. Loading shows a spinner in the same slot.
struct DSStatusIcon: View {
    let status: DSStatus

    var body: some View {
        ZStack {
            if status == .loading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: status.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(status.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: DS.Metrics.statusIcon, height: DS.Metrics.statusIcon)
    }
}

/// Never put buttons in `detail`; use `accessory`.
struct DSStatusRow<Detail: View, Accessory: View>: View {
    let status: DSStatus
    private let title: Text
    private let detail: Detail
    private let accessory: Accessory

    init(
        _ status: DSStatus,
        title: Text,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.status = status
        self.title = title
        self.detail = detail()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            DSStatusIcon(status: status)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                title
                    .font(DS.Typography.rowTitle)
                    .lineLimit(2)
                detail
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .animation(DS.Motion.standard, value: status)
    }
}

extension DSStatusRow where Accessory == EmptyView {
    init(_ status: DSStatus, title: Text, @ViewBuilder detail: () -> Detail) {
        self.init(status, title: title, detail: detail, accessory: { EmptyView() })
    }
}

extension DSStatusRow where Detail == EmptyView, Accessory == EmptyView {
    init(_ status: DSStatus, title: Text) {
        self.init(status, title: title, detail: { EmptyView() }, accessory: { EmptyView() })
    }
}

// MARK: - Empty state

struct DSEmptyState<Actions: View>: View {
    private let title: Text
    private let systemImage: String
    private let description: Text?
    private let actions: Actions

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: Text? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            if let description {
                description
            }
        } actions: {
            actions
                .buttonStyle(.glassProminent)
        }
    }
}

extension DSEmptyState where Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.init(title, systemImage: systemImage, description: description) { EmptyView() }
    }
}

// MARK: - Notices

enum DSNoticeKind: Equatable {
    case info, warning, error

    init(_ kind: AppModel.Notice.Kind) {
        switch kind {
        case .info: self = .info
        case .warning: self = .warning
        case .error: self = .error
        }
    }

    var symbol: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info: return DS.Palette.info
        case .warning: return DS.Palette.warning
        case .error: return DS.Palette.danger
        }
    }
}

/// In-content notice (soft tinted fill) or floating notice (glass).
struct DSNoticeRow: View {
    let kind: DSNoticeKind
    let message: String
    var isFloating = false
    var onDismiss: (() -> Void)?

    init(kind: DSNoticeKind, message: String, isFloating: Bool = false, onDismiss: (() -> Void)? = nil) {
        self.kind = kind
        self.message = message
        self.isFloating = isFloating
        self.onDismiss = onDismiss
    }

    init(notice: AppModel.Notice, isFloating: Bool = false, onDismiss: (() -> Void)? = nil) {
        self.init(kind: DSNoticeKind(notice.kind), message: notice.message, isFloating: isFloating, onDismiss: onDismiss)
    }

    var body: some View {
        if isFloating {
            row.glassEffect(.regular.tint(kind.tint.opacity(0.12)), in: shape)
        } else {
            row.background(DS.Palette.tintedFill(kind.tint), in: shape)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isFloating ? DS.Radius.floating : DS.Radius.notice, style: .continuous)
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s + 2) {
            Image(systemName: kind.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(kind.tint)
            Text(verbatim: message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(message)
            if let onDismiss {
                DSIconButton("Kapat", systemImage: "xmark", action: onDismiss)
            }
        }
        .padding(.leading, DS.Space.m)
        .padding(.trailing, onDismiss == nil ? DS.Space.m : DS.Space.xs)
        .padding(.vertical, onDismiss == nil ? DS.Space.m : DS.Space.xs)
    }
}

/// Wrapping explanatory text outside a Form. Inside a Form, use a plain
/// `Text` in the Section footer instead.
struct DSHint: View {
    private let text: Text

    init(_ key: LocalizedStringKey) { text = Text(key) }

    @_disfavoredOverload
    init<S: StringProtocol>(_ string: S) { text = Text(string) }

    var body: some View {
        text
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

/// 28-pt circular hit target, hover fill, secondary symbol.
struct DSIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DSIconButtonBody(configuration: configuration)
    }
}

struct DSIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(isEnabled ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary)
            .background {
                Circle()
                    .fill(configuration.isPressed ? DS.Palette.pressedFill : DS.Palette.hoverFill)
                    .opacity(isEnabled && (isHovered || configuration.isPressed) ? 1 : 0)
            }
            .onHover { isHovered = $0 }
            .animation(DS.Motion.hover, value: isHovered)
    }
}

/// Icon-only button. The title is the accessibility label and the tooltip.
struct DSIconButton: View {
    private let title: Text
    private let systemImage: String
    private let role: ButtonRole?
    private let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
            .labelStyle(.iconOnly)
            .frame(width: DS.Metrics.iconButton, height: DS.Metrics.iconButton)
            .contentShape(Circle())
        }
        .buttonStyle(DSIconButtonStyle())
        .help(title)
    }
}

/// Copy button that shows a checkmark for 1.5 s. Fixed size.
struct DSCopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            SystemActions.copy(text)
            copied = true
        } label: {
            Label("Kopyala", systemImage: copied ? "checkmark" : "doc.on.doc")
                .labelStyle(.iconOnly)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: DS.Metrics.iconButton, height: DS.Metrics.iconButton)
                .contentShape(Circle())
        }
        .buttonStyle(DSIconButtonStyle())
        .help("Kopyala")
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// The one "reveal in Finder" affordance.
struct DSRevealButton: View {
    let url: URL

    var body: some View {
        DSIconButton("Finder'da Göster", systemImage: "folder") {
            SystemActions.reveal(url)
        }
    }
}

/// Row style for the menu bar panel and other hover lists: hover and
/// pressed fills, concentric radius, full-width hit area.
struct DSRowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = DS.Panel.rowRadius

    func makeBody(configuration: Configuration) -> some View {
        DSRowButtonBody(configuration: configuration, cornerRadius: cornerRadius)
    }
}

struct DSRowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, DS.Panel.rowPaddingH)
            .padding(.vertical, DS.Panel.rowPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? DS.Palette.pressedFill : DS.Palette.hoverFill)
                    .opacity(isHovered || configuration.isPressed ? 1 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(DS.Motion.hover, value: isHovered)
    }
}

// MARK: - Paths and code

/// A path abbreviated with "~", middle-truncated, selectable, full path in the tooltip.
struct DSPathText: View {
    let url: URL
    var font: Font = DS.Typography.path

    var body: some View {
        Text(verbatim: abbreviated)
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            // No text selection here: selectable text takes the hover, and
            // the help with the whole path then never shows.
            .help(fullPath)
    }

    private var fullPath: String { url.path(percentEncoded: false) }

    private var abbreviated: String {
        (fullPath as NSString).abbreviatingWithTildeInPath
    }
}

/// Monospaced command or snippet on a soft fill, with an optional copy button.
struct DSCodeBlock: View {
    let text: String
    var showsCopyButton = true

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Text(verbatim: text)
                .font(DS.Typography.code)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.xs + 2)
            if showsCopyButton {
                DSCopyButton(text: text)
            }
        }
        .padding(.leading, DS.Space.m)
        .padding(.trailing, showsCopyButton ? DS.Space.xs : DS.Space.m)
        .padding(.vertical, DS.Space.xs)
        .background(DS.Palette.codeFill, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
    }
}

// MARK: - Account label

/// Monogram plus name, aligned like any Label (sidebar, lists, settings).
struct DSAccountLabel: View {
    let profile: Profile
    var size: CGFloat = DS.Monogram.small
    var isRunning = false
    /// The account's estimated Claude Code state, shown after the name.
    var pulse: ClaudeCodePulse?
    var pulseProject: String?
    /// The address Claude Code signed in with when it is not one the
    /// account expects (Kimlik Bekçisi).
    var identityMismatch: String?

    var body: some View {
        Label {
            HStack(spacing: DS.Space.xs) {
                Text(profile.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                ClaudeCodePulseIcon(pulse: pulse, project: pulseProject)
                RestingIcon(profile: profile)
                if let identityMismatch {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.danger)
                        .help("Kimlik Bekçisi: Claude Code \(identityMismatch) ile giriş yapmış")
                        .accessibilityLabel(Text("Beklenmeyen hesap"))
                }
            }
            .animation(DS.Motion.standard, value: pulse)
        } icon: {
            MonogramView(profile: profile, size: size, isRunning: isRunning)
        }
    }
}

/// Shortcut hint such as "⌘3" outside a List (inside a List use `.badge`).
struct DSShortcutHint: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(DS.Typography.shortcut)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - View helpers

extension View {
    /// Every grouped Form in the app: grouped style, soft top edge, bottom
    /// margin so the floating notice never covers the last row.
    func dsForm() -> some View {
        formStyle(.grouped)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .contentMargins(.bottom, DS.Metrics.noticeClearance, for: .scrollContent)
    }

    func dsHoverHighlight(cornerRadius: CGFloat = DS.Radius.card) -> some View {
        modifier(DSHoverHighlight(cornerRadius: cornerRadius))
    }

    /// The one prominent action of a context (toolbar, card, panel footer).
    func dsPrimaryAction(tint: Color? = nil) -> some View {
        buttonStyle(.glassProminent).tint(tint)
    }

    /// Overlays an empty state instead of swapping the root view.
    func dsEmptyState<Empty: View>(_ isEmpty: Bool, @ViewBuilder empty: () -> Empty) -> some View {
        let emptyView = empty()
        return overlay {
            if isEmpty {
                emptyView
            }
        }
    }
}
