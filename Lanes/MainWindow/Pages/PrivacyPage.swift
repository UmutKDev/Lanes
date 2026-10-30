import LanesCore
import SwiftUI

/// Everything Lanes looks at, writes and sends, in one list. The README and
/// the tester guide repeat this list; change them together.
struct PrivacyPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Text("Lanes hiçbir hesabın giriş bilgisini, çerezini ya da Anahtar Zinciri kaydını okumaz, saklamaz, başka yere taşımaz. Sohbetlerini, Claude'un ayar dosyalarını ve hesap klasörlerinin içini de açmaz. Giriş her zaman Claude'un kendi penceresinde ya da claude komutunda olur.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Lanes'in baktıkları") {
                PrivacyItem(
                    title: "Çalışan Claude'ların komut satırı",
                    detail: "Her Claude'un hangi klasörle açıldığını görüp hangi hesaba ait olduğunu bulmak için. Aynı kayıtta duran ortam değişkenleri okunmadan atılır."
                )
                PrivacyItem(
                    title: "Claude'un yeri ve sürümü",
                    detail: "Uygulama paketinin kendi bilgi dosyasından."
                )
                PrivacyItem(
                    title: "claude:// bağlantılarını hangi uygulamanın açtığı",
                    detail: "macOS'un varsayılan uygulama ayarından. Normal kullanımda Lanes bu ayarı Claude'da bırakır, yalnız Faz 0 denemesi geçici olarak değiştirir."
                )
                PrivacyItem(
                    title: "Klasörlerin değişme saati",
                    detail: "Yalnız Faz 0 denemelerinde, bir hesabın kendi klasörünü kullandığını doğrulamak için. Dosyaların kendisi açılmaz."
                )
            }

            Section("Lanes'in yazdıkları") {
                LabeledContent("Hesap listesi ve hesap klasörleri") {
                    PathRow(url: model.paths.root)
                }
                Text("Hesap listesi profiles.json dosyasında, bir önceki sağlam hali profiles.backup.json dosyasında. Her hesabın klasörünü Lanes oluşturur, içine yalnız Claude yazar. Terminal klasöründe \"Claude Code'u Terminalde Aç\" için küçük komut dosyaları, Tanılama klasöründe Faz 0 sonuçları durur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Faz 0 denemelerinin klonları") {
                    PathRow(url: model.paths.clonesDirectory)
                }
                PrivacyItem(
                    title: "Sistem günlüğü",
                    detail: "Açılış, tarama, hesap açma, öne getirme ve kaydetme gibi olaylar, hesap adı, klasör ya da bağlantı olmadan. Tanılama bilgisi yalnız sen düğmeye basınca hazırlanır ve Mac'inden çıkmaz."
                )
                PrivacyItem(
                    title: "Lanes'in kendi ayarları",
                    detail: "macOS'un uygulama ayarlarında (com.umutkdev.Lanes)."
                )
            }

            Section("Lanes'in gönderdikleri") {
                PrivacyItem(
                    title: "Claude'a \"yeniden aç\" komutu",
                    detail: "Bir hesabın penceresini öne getirmek için, Dock simgesine tıklamakla aynı komut. macOS bunun için bir kez Otomasyon izni sorabilir. Lanes Claude'a bağlantı ya da metin göndermez."
                )
                PrivacyItem(
                    title: "Güncelleme denetimi",
                    detail: "Lanes'in yaptığı tek ağ isteği. GitHub'daki sürüm listesini indirir. İstekte Lanes'in sürümü dışında bir bilgi yok. Yalnız DMG ile dağıtılan sürümlerde çalışır, Ayarlar > Güncellemeler'den kapatılabilir."
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacyItem: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
