import LanesCore
import SwiftUI

/// Everything Lanes looks at, writes and sends, in one list. The README
/// repeats this list and the user guide (docs/kullanim-kilavuzu.md) points
/// to it; change them together.
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
                    Text("Lanes giriş bilgilerine, çerezlere, Anahtar Zinciri'ne ve sohbetlere dokunmaz.")
                        .font(DS.Typography.rowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help("Hesap klasörlerinin içini de açmaz; tek istisna aşağıdaki Claude Code hesap adıdır.")
                }
                .padding(.vertical, DS.Space.xs)
            }

            Section {
                PrivacyItem(
                    systemImage: "terminal",
                    title: "Çalışan Claude'ların komut satırı",
                    detail: "Her Claude'un hangi hesaba ait olduğunu bulmak için.",
                    help: "Ortam değişkenleri okunmadan atılır."
                )
                PrivacyItem(
                    systemImage: "info.circle",
                    title: "Claude'un yeri ve sürümü",
                    detail: "Uygulama paketinin bilgi dosyasından."
                )
                PrivacyItem(
                    systemImage: "link",
                    title: "claude:// bağlantılarını hangi uygulamanın açtığı",
                    detail: "macOS'un varsayılan uygulama ayarından.",
                    help: "Lanes bu ayarı yalnız Hesap Haritası'nda yönlendirme açıkken kendine alır, kapatınca Claude'a geri verir."
                )
                PrivacyItem(
                    systemImage: "clock",
                    title: "Klasörlerin değişme saati",
                    detail: "Claude'un kendi klasörünü kullandığını doğrulamak için; dosyalar açılmaz.",
                    help: "Bir hesap açıldıktan sonraki 30 saniyede."
                )
                PrivacyItem(
                    systemImage: "doc.text",
                    title: "Claude Code oturum dosyalarının adı ve tarihi",
                    detail: "Yalnız değişme zamanlarına bakılır; sohbetler açılmaz.",
                    help: "Oturumlar, Projeler ve Kullanım sayfaları için. \"Başka Hesapla Sürdür\" oturum dosyasını açmadan öteki hesaba kopyalar, asıl dosya değişmez."
                )
                PrivacyItem(
                    systemImage: "person.text.rectangle",
                    title: "Claude Code'un giriş yaptığı hesap",
                    detail: "Yalnız e-posta, ad ve kuruluş adı okunur, saklanmaz.",
                    help: "Her hesabın .claude.json dosyasından okunur. Giriş anahtarları Anahtar Zinciri'nde durur ve okunmaz."
                )
                PrivacyItem(
                    systemImage: "internaldrive",
                    title: "Hesap klasörlerinin boyutu",
                    detail: "Yalnız Bakım sayfası ya da Depolama sekmesi açıkken; dosyalar açılmaz.",
                    help: "\"Önbelleği Temizle\" yalnız Claude'un yeniden oluşturduğu önbellek klasörlerini, hesap kapalıyken ve sen onaylayınca siler."
                )
                PrivacyItem(
                    systemImage: "macwindow",
                    title: "Öndeki uygulama",
                    detail: "Önde geçen süre için; yalnız bu Mac'te, 30 gün saklanır.",
                    help: "Menü çubuğu simgesi ve Kullanım sayfası için yalnız öndeki uygulamanın süreç numarasına bakılır. Menü çubuğu ayarı yalnız simgedeki gösterimi kapatır, süre yine sayılır."
                )
                PrivacyItem(
                    systemImage: "rectangle.dashed",
                    title: "Öndeki Claude penceresinin yeri",
                    detail: "Yalnız Hesap Rengi Çerçevesi açıkken; hiçbir şey saklanmaz.",
                    help: "Pencerenin yalnız sahibi ve sınırları okunur."
                )
                PrivacyItem(
                    systemImage: "doc.on.clipboard",
                    title: "Panonun değişip değişmediği",
                    detail: "Yalnız Pano Bekçisi açıkken; içeriği okunmaz.",
                    help: "Diske bir şey yazılmaz."
                )
                PrivacyItem(
                    systemImage: "calendar.badge.clock",
                    title: "Projelerde geçen Claude Code süresi",
                    detail: "Zaman Çizelgesi için; yalnız bu Mac'te, 62 gün saklanır.",
                    help: "Yalnız oturum dosyalarının değişme zamanına bakılır. Hesap, proje klasörü adı ve günlük süre saklanır."
                )
                PrivacyItem(
                    systemImage: "rectangle.on.rectangle",
                    title: "Sekmeli modda etkin Claude penceresinin yeri ve boyutu",
                    detail: "Yalnız sekmeli mod açıkken, Erişilebilirlik izniyle.",
                    help: "Pencerelerin içine ve başlıklarına bakılmaz."
                )
                PrivacyItem(
                    systemImage: "memorychip",
                    title: "Açık Claude'ların bellek ve işlemci kullanımı",
                    detail: "Genel Bakış ve \"Kullanılmayınca kapat\" için.",
                    help: "On saniyede bir ölçülür. Claude'un içine bakılmaz."
                )
                PrivacyItem(
                    systemImage: "square.grid.2x2",
                    title: "Sahne pencerelerinin yeri ve boyutu",
                    detail: "Yalnız sahne kaydedilirken ya da açılırken, Erişilebilirlik izniyle."
                )
                PrivacyItem(
                    systemImage: "stethoscope",
                    title: "Sağlık sayfasındaki denetimler",
                    detail: "Klasörlerin yalnız adlarına bakılır, içleri açılmaz.",
                    help: "Otomasyon izninin durumu (izin sorulmadan), claude komutunun yeri ve Profiles içindeki klasör adları."
                )
                PrivacyItem(
                    systemImage: "checklist",
                    title: "Kurulum sayfasındaki denetimler",
                    detail: "İzinler yalnız ilgili düğmeye basınca istenir.",
                    help: "Claude'un ve claude komutunun yeri, sürümü ve izinlerin durumu."
                )
            } header: {
                PrivacySectionHeader(title: "Lanes'in baktıkları", systemImage: "eye")
            }

            Section {
                PrivacyItem(
                    systemImage: "folder",
                    title: "Hesap listesi ve hesap klasörleri",
                    detail: "Hesap klasörlerini Lanes oluşturur, içine Claude yazar.",
                    help: "Hesap listesi profiles.json'da, yedeği profiles.backup.json'da durur. Lanes hesap klasörlerine yalnız Araç Kutusu için bağlantı (symlink) ekler. cli-accounts.tsv, lanes komut satırı aracı için yalnız hesap adlarını, kimliklerini ve klasör yollarını tutar; araç kurulursa ~/.local/bin/lanes dosyasına yazılır.",
                    path: model.paths.root
                )
                PrivacyItem(
                    systemImage: "square.on.square",
                    title: "Klonlar",
                    detail: "Her hesap için Claude.app'in bir kopyası.",
                    help: "Kopyaya hesabın simgesi eklenir; \"Dock'ta gösterme\" açıksa kopya bu Mac'te yeniden imzalanır. Hesap kaldırılınca klon Çöp Sepeti'ne gider. Deneme sürümlerinden kalan deneme klonunu ve sonuç dosyalarını Lanes ilk açılışta bir kez kaldırır, klonu Çöp Sepeti'ne taşır.",
                    path: model.paths.clonesDirectory
                )
                PrivacyItem(
                    systemImage: "list.bullet.rectangle",
                    title: "Sistem günlüğü",
                    detail: "Hesap adı, klasör ya da bağlantı içermez.",
                    help: "Tanılama bilgisi yalnız sen isteyince hazırlanır ve Mac'inden çıkmaz."
                )
                PrivacyItem(
                    systemImage: "wrench.and.screwdriver",
                    title: "Araç Kutusu",
                    detail: "Hesaplara yalnız bağlantı (symlink) eklenir; hesabın dosyaları değişmez.",
                    help: "Paylaşılan öğeler Toolbox klasöründe durur. Hesabın kendi dosyaları okunmaz. Hesaba özel MCP ayarları yalnız senin okuyabildiğin bir dosyaya yazılır. Ekip Paketi'ne ortam değişkenlerinin ve başlıkların değerleri girmez."
                )
                PrivacyItem(
                    systemImage: "bell.badge",
                    title: "Bitti Haberi kancası",
                    detail: "Yalnız Bitti Haberi açıkken; hesabın settings.json dosyası değişmez.",
                    help: "Hesabın settings.json dosyası okunmaz. Kanca, Claude Code'un verisini okumadan atar ve bir olay dosyasına yalnız hesabı, olayı, terminal adını ve proje yolunu yazar; Lanes bu dosyayı bildirimi gösterince siler. Özellik kapatılınca klasör silinir.",
                    path: model.paths.root.appendingPathComponent(ClaudeCodeHooks.folderName, isDirectory: true)
                )
                PrivacyItem(
                    systemImage: "gearshape",
                    title: "Lanes'in kendi ayarları",
                    detail: "macOS'un uygulama ayarlarında (com.umutkdev.Lanes).",
                    help: "Kısayollar ve her hesabın son beş Claude Code klasörü de burada durur."
                )
                PrivacyItem(
                    systemImage: "magnifyingglass",
                    title: "Spotlight dizini",
                    detail: "Hesapların adı ve kısa bir açıklaması.",
                    help: "Spotlight'ta aranabilsin diye macOS'un arama dizinine yazılır. Hesap kaldırılınca ya da adı değişince dizin yenilenir."
                )
            } header: {
                PrivacySectionHeader(title: "Lanes'in yazdıkları", systemImage: "square.and.pencil")
            }

            Section {
                PrivacyItem(
                    systemImage: "arrow.down.circle",
                    title: "lanes:// adresleri ve Kestirmeler eylemleri",
                    detail: "Yalnız açar ve gösterir; hiçbir şeyi silmez ya da değiştirmez.",
                    help: "Bir hesabı ya da sahneyi açar, bir sayfayı gösterir. Kestirmeler'e yalnız hesap ve sahne adları verilir."
                )
            } header: {
                PrivacySectionHeader(title: "Lanes'e gelenler", systemImage: "arrow.down.circle")
            }

            Section {
                PrivacyItem(
                    systemImage: "macwindow.on.rectangle",
                    title: "Claude'a \"yeniden aç\" komutu",
                    detail: "Bir hesabın penceresini öne getirmek için.",
                    help: "macOS bir kez Otomasyon izni sorabilir."
                )
                PrivacyItem(
                    systemImage: "arrowshape.turn.up.right",
                    title: "Yönlendirilen claude:// bağlantıları",
                    detail: "Kurala göre seçilen hesaba gider; bağlantının kendisi saklanmaz.",
                    help: "Yalnız Hesap Haritası'nda yönlendirme açıkken. Giriş ve OAuth bağlantıları hiç gönderilmez. LinkLog.json son 30 gün için yalnız türünü, zamanını, geldiği uygulamayı, gittiği hesabı ve nedenini tutar. Akıllı kurallar için yalnız öndeki uygulamanın kimliğine bakılır."
                )
                PrivacyItem(
                    systemImage: "bell",
                    title: "macOS bildirimleri",
                    detail: "Yalnız hesap adı ve olay türü yazar; Mac'inden çıkmaz.",
                    help: "Yalnız açtığın bildirim türleri ve hatırlatmalar için."
                )
                PrivacyItem(
                    systemImage: "arrow.triangle.2.circlepath",
                    title: "Güncelleme denetimi",
                    detail: "GitHub'a yalnız Lanes'in sürümü gider.",
                    help: "Claude Code kurulumu dışında Lanes'in yaptığı tek ağ isteği. GitHub'daki sürüm listesini indirir. Ayarlar > Güncellemeler'den kapatılabilir."
                )
                PrivacyItem(
                    systemImage: "arrow.down.app",
                    title: "Claude Code kurulumu",
                    detail: "Yalnız Kurulum sayfasında \"Kur\" düğmesine basınca.",
                    help: "Lanes resmî kurulum betiğini yalnız claude.ai'dan indirip senin yetkilerinle çalıştırır; çerez ya da giriş bilgisi göndermez."
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

/// One thing Lanes touches: a symbol, a title, a one-line caption with the
/// fact that matters, the rest in the row's tooltip, and, for folders, the
/// path on its own line under the title.
private struct PrivacyItem: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var help: LocalizedStringKey?
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
        .help(help.map { Text($0) } ?? Text(verbatim: ""))
    }
}
