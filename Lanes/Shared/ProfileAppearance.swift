import AppKit
import LanesCore
import SwiftUI

extension ProfileColor {
    var swatch: Color {
        Color(nsColor: nsColor)
    }

    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .mint: return .systemMint
        case .teal: return .systemTeal
        case .cyan: return .systemCyan
        case .indigo: return .systemIndigo
        case .brown: return .systemBrown
        case .gray: return .systemGray
        }
    }

    var displayName: String {
        switch self {
        case .blue: return String(localized: "Mavi")
        case .purple: return String(localized: "Mor")
        case .pink: return String(localized: "Pembe")
        case .red: return String(localized: "Kırmızı")
        case .orange: return String(localized: "Turuncu")
        case .yellow: return String(localized: "Sarı")
        case .green: return String(localized: "Yeşil")
        case .mint: return String(localized: "Nane")
        case .teal: return String(localized: "Çam yeşili")
        case .cyan: return String(localized: "Camgöbeği")
        case .indigo: return String(localized: "Çivit")
        case .brown: return String(localized: "Kahverengi")
        case .gray: return String(localized: "Gri")
        }
    }
}

extension ProfileMode {
    var displayName: String {
        switch self {
        case .standard: return String(localized: "Standart")
        case .signedClone: return String(localized: "Klon")
        case .separateIdentity: return String(localized: "Ayrı kimlik")
        }
    }

    var explanation: String {
        switch self {
        case .standard:
            return String(localized: "Claude'un kendisi, bu hesabın klasörüyle açılır. Dock'ta tüm hesaplar aynı simgeyi paylaşır.")
        case .signedClone:
            return String(localized: "Claude'un bir kopyası kendi simgesiyle açılır. Anthropic'in imzası korunur, kopya diskte neredeyse yer kaplamaz.")
        case .separateIdentity:
            return String(localized: "Kopya kendi kimliğini alır ve yerelde yeniden imzalanır. Deneysel, Faz 0 sonuçlarını bekliyor.")
        }
    }
}

extension ProfileMode {
    /// What "Dock'ta gösterme" costs, shown next to the switch.
    static var dockHidingCost: String {
        String(localized: "Claude Dock'ta ve Cmd-Tab'da görünmez, hesaba Lanes'ten geçersin. Bunun için kopya bu Mac'te yeniden imzalanır ve Anthropic'in imzası gider: ilk açılışta anahtarlık parolası sorulur, Claude'un menüleri menü çubuğunda görünmez, Cmd-C ve Cmd-V gibi kısayollar çalışmayabilir.")
    }
}

extension AccountClass {
    var displayName: String {
        switch self {
        case .personal: return String(localized: "Kişisel")
        case .employer: return String(localized: "İşveren")
        case .client: return String(localized: "Müşteri")
        }
    }

    var symbol: String {
        switch self {
        case .personal: return "person"
        case .employer: return "building.2"
        case .client: return "briefcase"
        }
    }
}

/// A profile's coloured monogram, with a green dot while its Claude is open.
/// The dot sits inside the monogram's bounds and is cut out of the swatch
/// with a transparent ring, so it reads on any background (glass sidebar,
/// selected row, panel) without an offset or a background-coloured stroke.
struct MonogramView: View {
    let profile: Profile
    var size: CGFloat = 28
    var isRunning = false

    var body: some View {
        Circle()
            .fill(profile.color.swatch.gradient)
            .overlay {
                Text(profile.monogram)
                    .font(.system(size: DS.Monogram.fontSize(for: size), weight: .semibold, design: .rounded))
                    .foregroundStyle(profile.color.onSwatch)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, size * 0.1)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if isRunning {
                    runningDot
                }
            }
            .compositingGroup()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(isRunning ? "\(profile.name), açık" : profile.name))
    }

    /// The green dot over a knock-out ring that clears the swatch beneath it.
    private var runningDot: some View {
        let dot = DS.Monogram.dotDiameter(for: size)
        let ring = DS.Monogram.ringWidth(for: size)
        return ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: dot + 2 * ring, height: dot + 2 * ring)
                .blendMode(.destinationOut)
            Circle()
                .fill(DS.Palette.running)
                .frame(width: dot, height: dot)
        }
    }
}

/// The panel's background: Liquid Glass.
struct PanelBackground: ViewModifier {
    var cornerRadius: CGFloat = DS.Panel.radius

    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
