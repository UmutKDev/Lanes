import AppKit
import SafariServices
import SwiftUI

/// "Lanes for Safari": the Mac App Store app that carries the Lanes Safari
/// extension (LanesForSafariExtension). It has one window that says whether
/// the extension is on and opens Safari's settings to turn it on. Everything
/// else happens in Safari.
@main
struct LanesForSafariApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Lanes for Safari", id: "main") {
            SetupView()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

enum ExtensionState: Equatable {
    case checking
    case on
    case off
    /// Safari could not say, usually because it hasn't seen the extension
    /// yet. Opening Safari once registers it.
    case unknown
}

@MainActor
final class SetupModel: ObservableObject {
    static let extensionIdentifier = "com.umutkdev.LanesForSafari.Extension"
    /// The Lanes desktop app carries the same extension. With both turned on,
    /// Safari shows two Lanes buttons, so the window says so.
    static let lanesBundleIdentifier = "com.umutkdev.Lanes"

    @Published var state: ExtensionState = .checking
    @Published var lanesInstalled = false
    @Published var openFailed = false

    func refresh() {
        lanesInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.lanesBundleIdentifier) != nil
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Self.extensionIdentifier) { state, error in
            let next: ExtensionState
            if let state, error == nil {
                next = state.isEnabled ? .on : .off
            } else {
                next = .unknown
            }
            Task { @MainActor in self.state = next }
        }
    }

    func openSafariSettings() {
        openFailed = false
        SFSafariApplication.showPreferencesForExtension(withIdentifier: Self.extensionIdentifier) { error in
            Task { @MainActor in self.openFailed = error != nil }
        }
    }
}

struct SetupView: View {
    @StateObject private var model = SetupModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lanes for Safari")
                        .font(.title2.weight(.semibold))
                    Text("Birden çok claude.ai hesabını Safari'de tek tıkla değiştir.")
                        .foregroundStyle(.secondary)
                }
            }

            StatusRow(state: model.state)

            VStack(alignment: .leading, spacing: 10) {
                Step(number: 1, text: "Aşağıdaki düğmeyle Safari'nin Uzantılar ayarını aç ve Lanes'i işaretle.")
                Step(number: 2, text: "claude.ai için izni “Her zaman izin ver” yap.")
                Step(number: 3, text: "claude.ai'de giriş yap ve araç çubuğundaki Lanes düğmesinden hesabı ekle. Başka bir hesapla aynısını yap.")
            }

            if model.lanesInstalled {
                Label("Lanes masaüstü uygulaması da bu eklentiyi içeriyor. Safari'de iki Lanes düğmesi görmemek için ikisinden yalnız birini açık tut.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.openFailed {
                Text("Safari ayarları açılamadı. Safari'yi bir kez açıp kapat, sonra yeniden dene.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Safari Ayarlarını Aç") { model.openSafariSettings() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 480)
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

private struct StatusRow: View {
    let state: ExtensionState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var title: LocalizedStringKey {
        switch state {
        case .checking: "Eklenti denetleniyor…"
        case .on: "Eklenti Safari'de açık"
        case .off: "Eklenti Safari'de kapalı"
        case .unknown: "Safari eklentiyi henüz görmedi. Safari'yi bir kez aç."
        }
    }

    private var symbol: String {
        switch state {
        case .checking: "clock"
        case .on: "checkmark.circle.fill"
        case .off, .unknown: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .on: .green
        case .checking: .secondary
        case .off, .unknown: .orange
        }
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(Circle().fill(.tint.opacity(0.18)))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
