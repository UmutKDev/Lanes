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
struct MonogramView: View {
    let profile: Profile
    var size: CGFloat = 28
    var isRunning = false

    var body: some View {
        Circle()
            .fill(profile.color.swatch.gradient)
            .overlay {
                Text(profile.monogram)
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if isRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: max(8, size * 0.3), height: max(8, size * 0.3))
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(isRunning ? "\(profile.name), açık" : profile.name))
    }
}

/// The panel's background: Liquid Glass on macOS 26, a vibrant material before.
struct PanelBackground: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        content
            .background(VisualEffectBackground(material: .popover))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
