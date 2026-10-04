import LanesCore
import SwiftUI

/// Faz 0: the nine checks, each with its steps, a helper that does the work
/// where Lanes can, and a place to record what happened. The report at the
/// bottom is what the user pastes back into the project.
struct ValidationPage: View {
    @Environment(AppModel.self) private var model
    @State private var copiedReport = false

    var body: some View {
        let validation = model.validation
        HStack(spacing: 0) {
            List(selection: checkBinding) {
                Section {
                    ForEach(ValidationCheck.all) { check in
                        CheckRow(check: check, outcome: validation.result(for: check.id).outcome)
                            .tag(check.id)
                    }
                } header: {
                    Text("\(validation.completedCount)/\(ValidationCheck.all.count) deneme kaydedildi")
                }
            }
            .listStyle(.sidebar)
            .frame(width: 290)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        validation.copyReport(claude: model.claude)
                        copiedReport = true
                    } label: {
                        Label("Raporu Kopyala", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Text(copiedReport
                         ? String(localized: "Rapor panoya kopyalandı. Projedeki konuşmaya yapıştırman yeterli.")
                         : String(localized: "Rapor yalnız deneme sonuçlarını ve sürüm bilgilerini içerir."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
            Divider()
            ScrollView {
                CheckDetail(check: ValidationCheck.check(validation.selectedCheck))
                    .id(validation.selectedCheck)
                    .padding(24)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

private struct CheckRow: View {
    let check: ValidationCheck
    let outcome: ValidationOutcome

    var body: some View {
        HStack(spacing: 8) {
            OutcomeIcon(outcome: outcome)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(check.number). \(check.title)")
                    .lineLimit(2)
                Text(check.isDeferred ? String(localized: "\(check.mode.displayName) · Sonraya kalabilir") : check.mode.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct OutcomeIcon: View {
    let outcome: ValidationOutcome

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
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
        case .notRun: return .secondary
        case .passed: return .green
        case .failed: return .red
        case .partial: return .orange
        case .skipped: return .gray
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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "Deneme \(check.number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(check.title)
                    .font(.title2.weight(.semibold))
                Text(check.question)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox("Adımlar") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(check.steps.enumerated()), id: \.offset) { index, step in
                        Text(verbatim: "\(index + 1). \(step)")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            assistant

            GroupBox("Sonuç") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Sonuç", selection: outcomeBinding) {
                        ForEach(ValidationOutcome.allCases, id: \.self) { outcome in
                            Text(outcome.reportLabel).tag(outcome)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("Gördüklerin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(minHeight: 70)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .onChange(of: notes) { _, newValue in
                            validation.setNotes(newValue, for: check.id)
                        }
                }
                .padding(4)
            }

            if !result.evidence.isEmpty {
                GroupBox("Kayıtlar") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.evidence.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Bu denemenin kayıtlarını sil") {
                            validation.clear(check.id)
                            notes = ""
                        }
                        .controlSize(.small)
                    }
                    .padding(4)
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

    @ViewBuilder
    private var assistant: some View {
        switch check.id {
        case .linkToSpecificInstance:
            LinkDeliveryAssistant()
        case .reclaimLinkHandler:
            LinkHandlerAssistant()
        case .signedCloneIdentity:
            CloneAssistant()
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
