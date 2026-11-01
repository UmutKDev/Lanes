import LanesCore
import SwiftUI

/// "Limite Takıldı" for an account's menus: rest for a ready-made length,
/// or end the rest early.
struct LimitMenu: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let resting = profile.isResting(at: Date())
        if !profile.isDefault {
            Menu(resting ? "Dinlenme" : "Limite Takıldı") {
                if resting {
                    Button("Dinlenmeyi Bitir") {
                        model.setLimited(profile, until: nil)
                    }
                    Divider()
                }
                Section(resting ? "Yeniden ayarla" : "Ne kadar dinlensin?") {
                    ForEach(LimitWatch.presetHours, id: \.self) { hours in
                        Button(hours == 24 ? String(localized: "1 gün") : String(localized: "\(hours) saat")) {
                            model.setLimited(profile, until: LimitWatch.until(hours: hours, from: Date()))
                        }
                    }
                }
            }
        }
    }
}

/// A moon beside a resting account, with when it is back and who takes its
/// links meanwhile.
struct RestingIcon: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        if let until = profile.limitedUntil, until > Date() {
            Image(systemName: "moon.zzz.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(description(until: until))
                .accessibilityLabel(Text(description(until: until)))
        }
    }

    private func description(until: Date) -> String {
        let time = until.formatted(date: Calendar.current.isDateInToday(until) ? .omitted : .abbreviated, time: .shortened)
        if let standIn = model.limitStandIn(for: profile) {
            return String(localized: "\(time) saatine kadar dinleniyor. Bağlantılar \(standIn.name) hesabına gidiyor.")
        }
        return String(localized: "\(time) saatine kadar dinleniyor.")
    }
}
