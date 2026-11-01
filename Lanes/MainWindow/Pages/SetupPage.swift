import AppKit
import LanesCore
import SwiftUI
import UserNotifications

/// Kurulum: what Lanes needs, and a button for each missing piece. Nothing
/// is installed, downloaded or asked for until the user presses a button.
struct SetupPage: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @State private var loginItemError: String?

    private var setup: SetupStatus { model.setup }

    var body: some View {
        Form {
            introSection

            Section {
                SetupClaudeAppRow()
            } header: {
                Text("Gerekli")
            }

            Section {
                SetupClaudeCodeRow()
                SetupAutomationRow()
                SetupAccessibilityRow()
            } header: {
                Text("Önerilen")
            }

            Section {
                SetupNotificationsRow()
                SetupGitRow()
                LoginItemToggle(title: "Oturum açıldığında Lanes'i başlat", error: $loginItemError)
            } header: {
                Text("İsteğe bağlı")
            } footer: {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    if let loginItemError {
                        Label {
                            Text(loginItemError)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DS.Palette.danger)
                        }
                    }
                }
                .animation(DS.Motion.standard, value: loginItemError)
            }
        }
        .systemForm()
        .onAppear {
            UserDefaults.standard.set(true, forKey: Preferences.Key.setupShown)
        }
        .task {
            model.refreshInstances()
            await setup.refresh()
            // Permissions change in System Settings, outside Lanes: check
            // them every two seconds while the page is open, so a row turns
            // green by itself. The task ends when the page goes away.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                // Claude dragged into Applications shows up without a click.
                if model.claude == nil { model.refreshInstances() }
                await setup.refreshPermissions()
            }
        }
    }

    // MARK: Intro

    private var introSection: some View {
        Section {
            HStack(alignment: .top, spacing: DS.Space.m) {
                Image(systemName: "checklist")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Lanes için gerekenler burada.")
                        .font(DS.Typography.rowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .help("Sen bir düğmeye basmadan Lanes hiçbir şey kurmaz, indirmez ya da izin istemez.")
                    Button("Başlarken Turunu Aç") { router.showOnboarding() }
                        .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, DS.Space.xs)
        }
    }
}
