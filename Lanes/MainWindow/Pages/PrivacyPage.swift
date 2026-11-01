import LanesCore
import SwiftUI

/// Everything Lanes looks at, writes and sends, in one list. The README and
/// the tester guide repeat this list; change them together.
struct PrivacyPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image(systemName: "hand.raised.fill")
                        .font(.largeTitle)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Lanes hiçbir hesabın giriş bilgisini, çerezini ya da Anahtar Zinciri kaydını okumaz, saklamaz, başka yere taşımaz. Sohbetlerini ve hesap klasörlerinin içini de açmaz; tek istisna aşağıda yazan Claude Code hesap adıdır. Giriş her zaman Claude'un kendi penceresinde ya da claude komutunda olur.")
                        .font(DS.Typography.rowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, DS.Space.xs)
            }

            Section {
                PrivacyItem(
                    systemImage: "terminal",
                    title: "Çalışan Claude'ların komut satırı",
                    detail: "Her Claude'un hangi klasörle açıldığını görüp hangi hesaba ait olduğunu bulmak için. Aynı kayıtta duran ortam değişkenleri okunmadan atılır."
                )
                PrivacyItem(
                    systemImage: "info.circle",
                    title: "Claude'un yeri ve sürümü",
                    detail: "Uygulama paketinin kendi bilgi dosyasından."
                )
                PrivacyItem(
                    systemImage: "link",
                    title: "claude:// bağlantılarını hangi uygulamanın açtığı",
                    detail: "macOS'un varsayılan uygulama ayarından. Lanes bu ayarı yalnız Hesap Haritası'nda yönlendirmeyi açınca kendine alır, kapatınca Claude'a geri verir."
                )
                PrivacyItem(
                    systemImage: "clock",
                    title: "Klasörlerin değişme saati",
                    detail: "Bir hesap açıldıktan sonraki 30 saniyede ve Faz 0 denemelerinde, o hesabın Claude'unun kendi klasörünü kullandığını doğrulamak için. Yalnız klasörün ve doğrudan içindekilerin saatine bakılır, dosyaların kendisi açılmaz."
                )
                PrivacyItem(
                    systemImage: "doc.text",
                    title: "Claude Code oturum dosyalarının adı ve tarihi",
                    detail: "Oturumlar, Projeler ve Kullanım sayfaları ile Claude Code'un o an çalışıp çalışmadığını gösteren terminal simgesi için, her hesabın Claude Code klasöründeki projects altında. Lanes bu klasördeki değişiklikleri macOS'un dosya olaylarıyla izler; yalnız hangi dosyanın ne zaman değiştiğine bakar. Dosyaların içi, yani sohbetler, hiç açılmaz. \"Başka Hesapla Sürdür\" dediğinde oturum dosyası, açılmadan, öteki hesabın Claude Code klasöründe aynı yere kopyalanır ve orada yeni bir oturum olarak sürer; asıl dosya değişmez."
                )
                PrivacyItem(
                    systemImage: "person.text.rectangle",
                    title: "Claude Code'un giriş yaptığı hesap",
                    detail: "Genel Bakış kartlarında, hesabın Kimlik sekmesinde ve aramada göstermek için. Her hesabın Claude Code klasöründeki .claude.json dosyasından (Claude uygulamasının kendi hesabında ~/.claude.json) yalnız oauthAccount altındaki e-posta, ad ve kuruluş adı okunur. Giriş anahtarları bu dosyada değil, Anahtar Zinciri'nde durur ve okunmaz. Dosyanın geri kalanına ve Claude uygulamasının verilerine bakılmaz. Okunan değerler saklanmaz, her seferinde dosyadan yeniden okunur."
                )
                PrivacyItem(
                    systemImage: "internaldrive",
                    title: "Hesap klasörlerinin boyutu",
                    detail: "Yalnız Bakım sayfası ya da hesabın Depolama sekmesi açıkken, dosyaların kapladığı yerden. Dosyalar açılmaz. \"Önbelleği Temizle\" yalnız Claude'un yeniden oluşturduğu önbellek klasörlerini siler, hesap kapalıyken ve sen onaylayınca."
                )
                PrivacyItem(
                    systemImage: "macwindow",
                    title: "Öndeki uygulama",
                    detail: "Menü çubuğu simgesinin öndeki Claude'un hesabını göstermesi ve Kullanım sayfasında her hesabın önde geçen süresini saymak için. Süreler yalnız bu Mac'te, son 30 gün için saklanır. Yalnız öndeki uygulamanın süreç numarası Lanes'in bildiği hesaplarla karşılaştırılır. Ayarlar > Menü Çubuğu ve Dock'taki ayar yalnız menü çubuğu simgesindeki gösterimi kapatır. Önde geçen süre her zaman, yalnız bu Mac'te sayılır."
                )
                PrivacyItem(
                    systemImage: "rectangle.on.rectangle",
                    title: "Sekmeli modda etkin Claude penceresinin yeri ve boyutu",
                    detail: "Yalnız sekmeli mod açıkken ve Erişilebilirlik izniyle. Lanes pencereyi sekme çubuğunun altına taşır ve öteki hesapları gizler. Pencerelerin içine, başlıklarına ya da yazılanlara bakmaz."
                )
                PrivacyItem(
                    systemImage: "memorychip",
                    title: "Açık Claude'ların bellek ve işlemci kullanımı",
                    detail: "On saniyede bir, macOS'un süreç sayaçlarından, Genel Bakış'ta göstermek ve \"Kullanılmayınca kapat\" seçili hesapları kapatmak için. Claude'un içine bakılmaz."
                )
                PrivacyItem(
                    systemImage: "square.grid.2x2",
                    title: "Sahne pencerelerinin yeri ve boyutu",
                    detail: "Yalnız bir sahnenin yerleşimini kaydettiğinde ya da yerleşimi kayıtlı bir sahneyi açtığında, Erişilebilirlik izniyle."
                )
                PrivacyItem(
                    systemImage: "stethoscope",
                    title: "Sağlık sayfasındaki denetimler",
                    detail: "Otomasyon izninin durumu (izin sorulmadan), claude komutunun yeri ve Profiles klasöründeki klasörlerin adları. Klasörlerin içi açılmaz. Klonların imzası yalnız \"İmzaları Denetle\" düğmesine basınca, macOS'un codesign ve spctl araçlarıyla denetlenir."
                )
                PrivacyItem(
                    systemImage: "checklist",
                    title: "Kurulum sayfasındaki denetimler",
                    detail: "Claude uygulamasının ve claude komutunun yeri, claude komutunun sürümü, Otomasyon, Erişilebilirlik ve bildirim izinlerinin durumu. İzinler yalnız ilgili düğmeye basınca istenir."
                )
            } header: {
                PrivacySectionHeader(title: "Lanes'in baktıkları", systemImage: "eye")
            }

            Section {
                PrivacyItem(
                    systemImage: "folder",
                    title: "Hesap listesi ve hesap klasörleri",
                    detail: "Hesap listesi profiles.json dosyasında, bir önceki sağlam hali profiles.backup.json dosyasında. Her hesabın klasörünü Lanes oluşturur, içine Claude yazar. Lanes yalnız Araç Kutusu'nda paylaştığın öğeler için hesabın Claude Code klasörüne bağlantı (symlink) ekler. Terminal klasöründe \"Claude Code'u Terminalde Aç\" ve Kurulum'daki \"Terminalde Kur\" için küçük komut dosyaları, Tanılama klasöründe Faz 0 sonuçları durur. cli-accounts.tsv, lanes komut satırı aracı için yalnız hesap adlarını, kimliklerini ve klasör yollarını tutar; araç kurulursa ~/.local/bin/lanes dosyasına yazılır.",
                    path: model.paths.root
                )
                PrivacyItem(
                    systemImage: "square.on.square",
                    title: "Klonlar",
                    detail: "Lanes'te eklediğin her hesap için Claude.app'in bir kopyası ve hangi Claude sürümünden yapıldığını yazan küçük bir clone.json dosyası. Kopyaya hesabın simgesi eklenir. \"Dock'ta gösterme\" açıksa kopyanın Info.plist dosyası değiştirilir ve kopya bu Mac'te yeniden imzalanır. Claude'un öteki dosyalarına dokunulmaz. Hesap kaldırılınca klon Çöp Sepeti'ne gider.",
                    path: model.paths.clonesDirectory
                )
                PrivacyItem(
                    systemImage: "list.bullet.rectangle",
                    title: "Sistem günlüğü",
                    detail: "Açılış, tarama, hesap açma, öne getirme ve kaydetme gibi olaylar, hesap adı, klasör ya da bağlantı olmadan. Tanılama bilgisi yalnız sen düğmeye basınca hazırlanır ve Mac'inden çıkmaz."
                )
                PrivacyItem(
                    systemImage: "wrench.and.screwdriver",
                    title: "Araç Kutusu",
                    detail: "Toolbox klasöründe paylaşılan CLAUDE.md, komutlar, ajanlar, beceriler ve mcp.json. Paylaştığın hesabın Claude Code klasörüne yalnız bir bağlantı (symlink) eklenir. Hesabın kendi dosyaları okunmaz, değiştirilmez."
                )
                PrivacyItem(
                    systemImage: "bell.badge",
                    title: "Bitti Haberi kancası",
                    detail: "Yalnız Entegrasyonlar'da Bitti Haberi'ni açarsan. ClaudeCodeHooks klasöründe küçük bir kanca betiği ve her hesap için yalnız bu kancayı içeren bir ayar dosyası durur. Lanes'in başlattığı Claude Code oturumları bu dosyayı --settings ile alır; hesabın kendi settings.json dosyası okunmaz, değiştirilmez. Kanca, Claude Code'un ona gönderdiği veriyi okumadan atar ve Events klasörüne yalnız hesap kimliğini, olayı (bitti ya da onay bekliyor), terminalin adını ve proje klasörünün yolunu yazar. Lanes bu dosyayı bildirimi gösterince siler. Özellik kapatılınca klasörün tamamı silinir.",
                    path: model.paths.root.appendingPathComponent(ClaudeCodeHooks.folderName, isDirectory: true)
                )
                PrivacyItem(
                    systemImage: "gearshape",
                    title: "Lanes'in kendi ayarları",
                    detail: "macOS'un uygulama ayarlarında (com.umutkdev.Lanes). Kısayollar ve her hesabın Claude Code'u açtığı son beş klasör de burada durur. Sahneler hesap listesiyle birlikte profiles.json dosyasında."
                )
                PrivacyItem(
                    systemImage: "magnifyingglass",
                    title: "Spotlight dizini",
                    detail: "Hesapların adı, harf simgesi ve kısa bir açıklama, Spotlight'ta aranabilsin diye macOS'un arama dizinine yazılır. Hesap kaldırılınca ya da adı değişince dizin yenilenir."
                )
            } header: {
                PrivacySectionHeader(title: "Lanes'in yazdıkları", systemImage: "square.and.pencil")
            }

            Section {
                PrivacyItem(
                    systemImage: "arrow.down.circle",
                    title: "lanes:// adresleri ve Kestirmeler eylemleri",
                    detail: "Yalnız bir hesabı ya da sahneyi açar, bir sayfayı gösterir. Hiçbiri bir şeyi silmez, kapatmaz ya da ayar değiştirmez. Kestirmeler'e hesapların ve sahnelerin yalnız adı verilir."
                )
            } header: {
                PrivacySectionHeader(title: "Lanes'e gelenler", systemImage: "arrow.down.circle")
            }

            Section {
                PrivacyItem(
                    systemImage: "macwindow.on.rectangle",
                    title: "Claude'a \"yeniden aç\" komutu",
                    detail: "Bir hesabın penceresini öne getirmek için, Dock simgesine tıklamakla aynı komut. macOS bunun için bir kez Otomasyon izni sorabilir."
                )
                PrivacyItem(
                    systemImage: "arrowshape.turn.up.right",
                    title: "Yönlendirilen claude:// bağlantıları",
                    detail: "Hesap Haritası'nda yönlendirme açıkken, başka bir uygulamadan gelen bağlantı kurala göre seçilen hesabın Claude'una gönderilir. Hesabın Kimlik sekmesindeki \"Claude Ayarlarını Aç\" düğmesi de o hesabın Claude'una ayarlar bağlantısını gönderir. Giriş ve OAuth bağlantıları hiçbir zaman gönderilmez. Bağlantıların kendisi saklanmaz, Bağlantılar sayfasında yalnız türü ve gittiği hesap görünür."
                )
                PrivacyItem(
                    systemImage: "bell",
                    title: "macOS bildirimleri",
                    detail: "Yalnız Ayarlar > Bildirimler'de açtığın türler ve kendin kurduğun hatırlatmalar (hesabın günlük süresi, bellek uyarısı) için. Bildirimde hesabın adı ve olayın türü yazar, bağlantı ya da hesabın içinden bir şey yazmaz. Bildirimler Mac'inden çıkmaz."
                )
                PrivacyItem(
                    systemImage: "arrow.triangle.2.circlepath",
                    title: "Güncelleme denetimi",
                    detail: "Aşağıdaki Claude Code kurulumu dışında Lanes'in yaptığı tek ağ isteği. GitHub'daki sürüm listesini indirir. İstekte Lanes'in sürümü dışında bir bilgi yok. Yalnız DMG ile dağıtılan sürümlerde çalışır, Ayarlar > Güncellemeler'den kapatılabilir."
                )
                PrivacyItem(
                    systemImage: "arrow.down.app",
                    title: "Claude Code kurulumu",
                    detail: "Yalnız Kurulum sayfasında \"Kur\" düğmesine bastığında. Lanes Claude Code'un resmî kurulum betiğini claude.ai'dan indirir ve senin yetkilerinle çalıştırır. Betiği yalnız claude.ai adreslerinden kabul eder. İstekte çerez ya da giriş bilgisi yok, başka hiçbir şey gönderilmez. Claude Code'u betiğin kendisi Anthropic'in sunucularından indirip kurar, Lanes kurulan dosyalara dokunmaz."
                )
            } header: {
                PrivacySectionHeader(title: "Lanes'in gönderdikleri", systemImage: "paperplane")
            }
        }
        .systemForm()
    }
}

/// A section title with its symbol, so the five groups are easy to find.
private struct PrivacySectionHeader: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// One thing Lanes touches: a symbol, a title, what and why in a caption,
/// and, for folders, the path on its own line under the title.
private struct PrivacyItem: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var path: URL?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(DS.Typography.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if let path {
                    PathRow(url: path)
                }
                Text(detail)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: DS.Metrics.statusIcon)
        }
        .padding(.vertical, DS.Space.xxs)
    }
}
