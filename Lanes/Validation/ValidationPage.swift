import LanesCore
import SwiftUI

/// Faz 0 and Faz 0.5: the checks, each with its steps, a helper that does the
/// work where Lanes can, and a place to record what happened. The report the
/// toolbar copies is what the user pastes back into the project.
struct ValidationPage: View {
    @Environment(AppModel.self) private var model
    @State private var copiedReport = false
    /// Shows the checkmark on the toolbar button for a moment after a copy.
    @State private var justCopied = false

    var body: some View {
        let validation = model.validation
        HSplitView {
            VStack(spacing: 0) {
                List(selection: checkBinding) {
                    ForEach(ValidationPhase.allCases) { phase in
                        let checks = ValidationCheck.checks(in: phase)
                        Section {
                            ForEach(checks) { check in
                                CheckRow(check: check, outcome: validation.result(for: check.id).outcome)
                                    .tag(check.id)
                            }
                        } header: {
                            Text("\(phase.title) · \(validation.completedCount(in: phase))/\(checks.count) deneme kaydedildi")
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .listStyle(.sidebar)
                // The note below the list, not in its safe area inset: with
                // the inset the list asks for its full height and the page
                // grows taller than the window. Both texts are laid out, so
                // copying does not change the note's height.
                ZStack(alignment: .topLeading) {
                    Text(Self.copiedNote).hidden()
                    Text(Self.reportNote).hidden()
                    Text(copiedReport ? Self.copiedNote : Self.reportNote)
                }
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.m)
            }
            .frame(minWidth: DS.Metrics.paneListMin, idealWidth: 260, maxWidth: 300)

            DSPage {
                ForEach(problems, id: \.self) { problem in
                    DSNoticeRow(kind: .warning, message: problem)
                }
                CheckDetail(check: ValidationCheck.check(validation.selectedCheck))
                    .id(validation.selectedCheck)
            }
            .frame(minWidth: DS.Metrics.paneContentMin, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    validation.copyReport()
                    copiedReport = true
                    justCopied = true
                } label: {
                    Label("Raporu Kopyala", systemImage: justCopied ? "checkmark" : "doc.on.clipboard")
                        .contentTransition(.symbolEffect(.replace))
                }
                .help("Raporu Kopyala")
            }
        }
        .task(id: justCopied) {
            guard justCopied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            justCopied = false
        }
    }

    private static var reportNote: String {
        String(localized: "Rapor sonuçları, sürüm bilgilerini ve kayıtları içerir. Kayıtlarda dosya yolları ve hesap adların da var. Ev klasörün ~ olarak yazılır.")
    }

    private static var copiedNote: String {
        String(localized: "Rapor panoya kopyalandı. Projedeki konuşmaya yapıştırman yeterli.")
    }

    /// The save and file problems, each once.
    private var problems: [String] {
        [model.validation.saveProblem, model.validation.fileProblem]
            .compactMap { $0 }
            .reduce(into: [String]()) { unique, problem in
                if !unique.contains(problem) {
                    unique.append(problem)
                }
            }
    }

    private var checkBinding: Binding<ValidationCheckID?> {
        Binding(
            get: { model.validation.selectedCheck },
            set: { if let id = $0 { model.validation.selectedCheck = id } }
        )
    }
}

/// A titled group on the Validation page: a section header over a soft
/// card. Used instead of GroupBox by every check's steps, helper and result.
struct ValidationCard<Content: View>: View {
    private let title: LocalizedStringKey
    private let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.headerToContent) {
            DSSectionHeader(title)
            DSCard {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct CheckRow: View {
    let check: ValidationCheck
    let outcome: ValidationOutcome

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            OutcomeIcon(outcome: outcome)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(verbatim: "\(check.label). \(check.title)")
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(check.isDeferred ? String(localized: "\(check.mode.displayName) · Sonraya kalabilir") : check.mode.displayName)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, DS.Space.xxs)
    }
}

/// A check's outcome as a symbol in a fixed slot, so titles line up.
struct OutcomeIcon: View {
    let outcome: ValidationOutcome

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: DS.Metrics.statusIcon, height: DS.Metrics.statusIcon)
            .accessibilityLabel(Text(outcome.reportLabel))
    }

    private var symbol: String {
        switch outcome {
        case .notRun: return "circle.dashed"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .skipped: return "arrow.uturn.forward.circle"
        }
    }

    private var color: Color {
        switch outcome {
        case .notRun: return DS.Palette.inactive
        case .passed: return DS.Palette.success
        case .failed: return DS.Palette.danger
        case .partial: return DS.Palette.warning
        case .skipped: return DS.Palette.inactive
        }
    }
}

extension ValidationMode {
    var displayName: String {
        switch self {
        case .automated: return String(localized: "Otomatik")
        case .assisted: return String(localized: "Yardımlı")
        case .manual: return String(localized: "Elle")
        }
    }
}

private struct CheckDetail: View {
    @Environment(AppModel.self) private var model
    let check: ValidationCheck
    @State private var notes = ""

    var body: some View {
        let validation = model.validation
        let result = validation.result(for: check.id)
        VStack(alignment: .leading, spacing: DS.Space.section) {
            VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
                Text(verbatim: "\(check.phase.title) · Deneme \(check.label)")
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(check.title)
                    .font(DS.Typography.heroTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(check.question)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ValidationCard("Adımlar") {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(Array(check.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                            Text(verbatim: "\(index + 1).")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(verbatim: step)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            assistant

            ValidationCard("Sonuç") {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    // Five segments need about 510 pt, more than the page has
                    // in a default-sized window, so a narrow page gets a menu.
                    ViewThatFits(in: .horizontal) {
                        outcomePicker
                            .pickerStyle(.segmented)
                            .fixedSize()
                        outcomePicker
                            .pickerStyle(.menu)
                            .fixedSize()
                    }
                    Text("Gördüklerin")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $notes)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80, maxHeight: 200)
                        .padding(DS.Space.s)
                        .background(DS.Palette.codeFill, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
                        .onChange(of: notes) { _, newValue in
                            validation.setNotes(newValue, for: check.id)
                        }
                }
            }

            if !result.evidence.isEmpty {
                ValidationCard("Kayıtlar") {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text(verbatim: result.evidence.joined(separator: "\n"))
                            .font(DS.Typography.path)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Bu denemenin kayıtlarını sil") {
                            validation.clear(check.id)
                            notes = ""
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .onAppear {
            notes = validation.result(for: check.id).notes
        }
    }

    private var outcomeBinding: Binding<ValidationOutcome> {
        Binding(
            get: { model.validation.result(for: check.id).outcome },
            set: { model.validation.setOutcome($0, for: check.id) }
        )
    }

    private var outcomePicker: some View {
        Picker("Sonuç", selection: outcomeBinding) {
            ForEach(ValidationOutcome.allCases, id: \.self) { outcome in
                Text(outcome.reportLabel).tag(outcome)
            }
        }
        .labelsHidden()
    }

    @ViewBuilder
    private var assistant: some View {
        switch check.id {
        case .linkToSpecificInstance:
            LinkDeliveryAssistant()
        case .reclaimLinkHandler:
            LinkHandlerAssistant()
        case .signedCloneIdentity:
            CloneAssistant(checkID: .signedCloneIdentity)
        case .claudeCodeConfigDirectory:
            ConfigDirectoryAssistant()
        case .appManagementPrompt:
            AppManagementAssistant()
        case .afterClaudeUpdate:
            InstanceTable()
        case .panelOnNewMenuBar:
            MenuBarAssistant()
        case .mainWindowActivation:
            ActivationAssistant()
        case .separateIdentityCowork:
            EmptyView()
        case .staleClone:
            StaleCloneAssistant()
        case .cloneOutsideLanes:
            CloneOutsideLanesAssistant()
        case .newAccountSignIn:
            NewAccountSignInAssistant()
        case .crossAccountSignOut:
            CrossAccountSignOutAssistant()
        case .claudeCodeLogin:
            ClaudeCodeLoginAssistant()
        case .coworkStandard:
            CoworkAssistant()
        case .claudeCodeSessionRecords:
            SessionRecordsAssistant()
        case .cloneRecheck:
            CloneAssistant(checkID: .cloneRecheck)
        }
    }
}

/// Names a running instance for people: its profile, or where it came from.
@MainActor
func instanceLabel(_ instance: RunningInstance, model: AppModel) -> String {
    if let id = instance.profileID, let profile = model.profile(withID: id) {
        return "\(profile.name) (PID \(instance.pid))"
    }
    if instance.applicationBundlePath.hasSuffix("Lanes Deneme.app") {
        return "Lanes Deneme klonu (PID \(instance.pid))"
    }
    return String(localized: "Lanes dışında açılmış (PID \(String(instance.pid)))")
}
