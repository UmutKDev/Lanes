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
                    detail: "macOS'un varsayılan uygulama ayarından. Lanes bu ayarı yalnız Hesap Haritası'nda yönlendirmeyi açınca kendine alır, kapatınca Claude'a geri verir."
                )
                PrivacyItem(
                    title: "Klasörlerin değişme saati",
                    detail: "Bir hesap açıldıktan sonraki 30 saniyede ve Faz 0 denemelerinde, o hesabın Claude'unun kendi klasörünü kullandığını doğrulamak için. Yalnız klasörün ve doğrudan içindekilerin saatine bakılır, dosyaların kendisi açılmaz."
                )
                PrivacyItem(
                    title: "Claude Code oturum dosyalarının adı ve tarihi",
                    detail: "Oturumlar ve Kullanım sayfaları için, her hesabın Claude Code klasöründeki projects altında. Dosyaların içi, yani sohbetler, hiç açılmaz."
                )
                PrivacyItem(
                    title: "Hesap klasörlerinin boyutu",
                    detail: "Yalnız Bakım sayfası ya da hesabın Depolama sekmesi açıkken, dosyaların kapladığı yerden. Dosyalar açılmaz. \"Önbelleği Temizle\" yalnız Claude'un yeniden oluşturduğu önbellek klasörlerini siler, hesap kapalıyken ve sen onaylayınca."
                )
                PrivacyItem(
                    title: "Öndeki uygulama",
                    detail: "Menü çubuğu simgesinin öndeki Claude'un hesabını göstermesi için. Yalnız öndeki uygulamanın süreç numarası Lanes'in bildiği hesaplarla karşılaştırılır. Ayarlar > Pencere Göstergeleri'nden kapatılabilir."
                )
                PrivacyItem(
                    title: "Sekmeli modda etkin Claude penceresinin yeri ve boyutu",
                    detail: "Yalnız sekmeli mod açıkken ve Erişilebilirlik izniyle. Lanes pencereyi sekme çubuğunun altına taşır ve öteki hesapları gizler. Pencerelerin içine, başlıklarına ya da yazılanlara bakmaz."
                )
                PrivacyItem(
                    title: "Sağlık sayfasındaki denetimler",
                    detail: "Otomasyon izninin durumu (izin sorulmadan), claude komutunun yeri ve Profiles klasöründeki klasörlerin adları. Klasörlerin içi açılmaz. Klonların imzası yalnız \"İmzaları Denetle\" düğmesine basınca, macOS'un codesign ve spctl araçlarıyla denetlenir."
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
                LabeledContent("Klonlar") {
                    PathRow(url: model.paths.clonesDirectory)
                }
                Text("Klon biçimindeki her hesap için Claude.app'in bir kopyası ve hangi Claude sürümünden yapıldığını yazan küçük bir clone.json dosyası. Kopyaya yalnız hesabın simgesi eklenir, Claude'un dosyalarına dokunulmaz. Hesap kaldırılınca ya da Standart'a dönünce klon Çöp Sepeti'ne gider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrivacyItem(
                    title: "Sistem günlüğü",
                    detail: "Açılış, tarama, hesap açma, öne getirme ve kaydetme gibi olaylar, hesap adı, klasör ya da bağlantı olmadan. Tanılama bilgisi yalnız sen düğmeye basınca hazırlanır ve Mac'inden çıkmaz."
                )
                PrivacyItem(
                    title: "Lanes'in kendi ayarları",
                    detail: "macOS'un uygulama ayarlarında (com.umutkdev.Lanes). Kısayollar ve her hesabın Claude Code'u açtığı son beş klasör de burada durur. Sahneler hesap listesiyle birlikte profiles.json dosyasında."
                )
            }

            Section("Lanes'e gelenler") {
                PrivacyItem(
                    title: "lanes:// adresleri ve Kestirmeler eylemleri",
                    detail: "Yalnız bir hesabı ya da sahneyi açar, bir sayfayı gösterir. Hiçbiri bir şeyi silmez, kapatmaz ya da ayar değiştirmez. Kestirmeler'e hesapların ve sahnelerin yalnız adı verilir."
                )
            }

            Section("Lanes'in gönderdikleri") {
                PrivacyItem(
                    title: "Claude'a \"yeniden aç\" komutu",
                    detail: "Bir hesabın penceresini öne getirmek için, Dock simgesine tıklamakla aynı komut. macOS bunun için bir kez Otomasyon izni sorabilir."
                )
                PrivacyItem(
                    title: "Yönlendirilen claude:// bağlantıları",
                    detail: "Yalnız Hesap Haritası'nda yönlendirme açıkken: başka bir uygulamadan gelen bağlantı, kurala göre seçilen hesabın Claude'una gönderilir. Giriş ve OAuth bağlantıları hiçbir zaman gönderilmez. Bağlantıların kendisi saklanmaz, Bağlantılar sayfasında yalnız türü ve gittiği hesap görünür."
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
