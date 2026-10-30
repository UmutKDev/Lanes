import LanesCore
import SwiftUI

/// Every account as a tile, with Claude's state above them.
struct OverviewPage: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.isFirstLaunch {
                    WelcomeBanner()
                }
                if let notice = model.notice {
                    NoticeRow(notice: notice) { model.notice = nil }
                }
                if model.isTranslocated && !model.isTranslocationNoticeDismissed {
                    NoticeRow(
                        notice: AppModel.Notice(kind: .warning, message: String(localized: "Lanes geçici bir kopyadan çalışıyor, çünkü doğrudan DMG'den ya da İndirilenler'den açıldı. Lanes'ten çık, Lanes.app'i Uygulamalar klasörüne sürükle ve oradan aç. Yoksa güncellemeler yüklenemez ve macOS Otomasyon iznini yeniden sorabilir.")),
                        onDismiss: { model.isTranslocationNoticeDismissed = true }
                    )
                }
                if model.claude == nil && !model.isMissingClaudeNoticeDismissed {
                    NoticeRow(
                        notice: AppModel.Notice(kind: .warning, message: String(localized: "Claude bu Mac'te bulunamadı. Lanes, hesapları açmak için Claude'un yüklü olmasını bekliyor.")),
                        onDismiss: { model.isMissingClaudeNoticeDismissed = true }
                    )
                }

                Text("Hesaplar")
                    .font(.title2.weight(.semibold))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(model.library.profiles) { profile in
                        AccountTile(profile: profile)
                    }
                    AddAccountTile()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WelcomeBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 6) {
                Text("Lanes'e hoş geldin")
                    .font(.title3.weight(.semibold))
                Text("Claude'da şu an açık olan hesabın \"Ana hesap\" olarak eklendi ve hiçbir şeyi değişmedi. Başka bir hesap eklediğinde Lanes onu kendi klasörüyle, ayrı bir Claude penceresinde açar. Lanes giriş bilgilerine hiçbir zaman dokunmaz.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AccountTile: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    let profile: Profile

    var body: some View {
        let isRunning = model.isRunning(profile)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MonogramView(profile: profile, size: 40, isRunning: isRunning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(profile.isDefault ? String(localized: "Varsayılan · \(profile.accountClass.displayName)") : profile.accountClass.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Label(isRunning ? "Açık" : "Kapalı", systemImage: isRunning ? "circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(isRunning ? Color.green : Color.secondary)
                    .labelStyle(.titleAndIcon)
                Spacer()
                Button(isRunning ? "Öne Getir" : "Aç") {
                    model.open(profile)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(profile.color.swatch)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            navigation.navigate(to: .account(profile.id))
        }
        .contextMenu {
            Button("Hesap Sayfası") {
                navigation.navigate(to: .account(profile.id))
            }
            Button("Claude Code'u Terminalde Aç") {
                model.openClaudeCode(profile)
            }
        }
    }
}

private struct AddAccountTile: View {
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        Button {
            navigation.isAddingProfile = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 26))
                Text("Hesap Ekle")
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.tertiary)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
