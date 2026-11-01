# Lanes

Lanes, birden fazla Claude hesabını aynı Mac'te yan yana kullanmanı sağlayan bir menü çubuğu uygulaması. Her hesap kendi klasörüyle, ayrı bir Claude penceresinde açılır. Yerel Claude Code oturumları da hesap başına ayrı kalır, istersen aynı anda farklı hesaplarla çalışabilirsin.

Lanes hiçbir hesabın giriş bilgisini, çerezini ya da Anahtar Zinciri kaydını okumaz, saklamaz, başka yere taşımaz. Giriş her zaman Claude'un kendi penceresinde ya da `claude` komutunda olur.

## Özellikler

- **Hesap başına ayrı Claude:** Her hesap kendi klasörüyle ayrı bir Claude penceresinde açılır. İstersen hesabın Claude kopyası kendi rengini ve simgesini taşır.
- **Menü çubuğu paneli ve ana pencere:** Bütün hesaplar tek bakışta, bir tıkla açılır ya da öne gelir. Öndeki Claude'un hesabı menü çubuğu simgesinde görünür.
- **Claude Code hesap başına:** Claude Code'u o hesapla Terminalde, istersen seçtiğin klasörde ya da yeni bir worktree'de başlatma. Oturumlar ve projeler hesap hesap listelenir, bir oturum başka bir hesapla sürdürülebilir. Claude Code bitince ya da onay isteyince bildirim gelir.
- **Bağlantı yönlendirme:** `claude://` bağlantıları saat, gün ve kaynak uygulamaya göre kurduğun kurallarla seçilen hesabın Claude'una gider. Giriş bağlantıları hiçbir zaman yönlendirilmez.
- **Günlük kolaylıklar:** Her uygulamada çalışan kısayollar (yeni bir izin istemez), Komut Paleti, birkaç hesabı tek tıkla açan sahneler, hesap ve proje başına Zaman Çizelgesi.
- **Kurulum ve Sağlık:** Eksik olanı uygulamanın içinden tamamlama (Claude uygulaması, Claude Code ve izinler) ve her şeyin yerinde olup olmadığını gösteren Sağlık sayfası. Lanes sen bir düğmeye basmadan hiçbir şey kurmaz.
- **Başlarken turu:** İlk açılışta kurulumu, izinleri ve ilk hesabı adım adım gösterir.
- **Türkçe ve English:** Lanes Türkçe ve İngilizce kullanılabilir. Dil Ayarlar'dan değiştirilir.

Kurulum ve kullanım için: [docs/kullanim-kilavuzu.md](docs/kullanim-kilavuzu.md)

## Derleme

Gerekenler: macOS 26 ya da üstü, Xcode 26 ya da 27 ve XcodeGen. CI her değişikliği Xcode 27.0, 27.1 ve 26.6 ile derliyor.

```sh
brew install xcodegen
make open
```

`make open` Xcode projesini `project.yml` dosyasından oluşturur ve Xcode'da açar. Proje dosyası depoda tutulmuyor, `project.yml` tek kaynak.

Kendi ekip kimliğinle imzalamak için `Config/Local.xcconfig.example` dosyasını `Config/Local.xcconfig` olarak kopyala ve ekip kimliğini yaz. Ekip kimliği olmadan da derlenir, ama macOS o durumda her derlemeden sonra Otomasyon iznini yeniden sorar. Bu dosyayı yalnız Debug derlemesi okur.

## Sürüm

Kullanıcılara giden DMG'yi tek komut hazırlar:

```sh
LANES_TEAM_ID=ABCDE12345 make release
```

Komut uygulamayı Developer ID ile imzalar, Apple'ın onay taramasından (notarization) geçirir ve onayı pakete ekler. Ardından aynısını DMG için yapar. Her adımdan sonra imzayı ve `spctl` sonucunu denetler. Bir denetim geçmezse DMG oluşmaz. Sonuç `build/release/<sürüm>-<derleme>/` klasörüne düşer. Derleme numarası commit sayısıdır, bu yüzden komut yalnız temiz ve tam bir klondan çalışır.

Bir Mac'te bir kez hazırlanması gerekenler:

- Xcode 27. Xcode 26 ile yapılan derleme macOS 27'ye özel menü çubuğu kodunu dışarıda bırakıyor.
- Anahtar Zinciri'nde ekibin "Developer ID Application" sertifikası.
- Onay taraması için kaydedilmiş giriş bilgisi: `xcrun notarytool store-credentials lanes-notary`. Başka bir ad için `LANES_NOTARY_PROFILE` kullanılır.
- Sparkle'ın güncelleme anahtarı. Sparkle'ın `generate_keys` aracı gizli anahtarı Anahtar Zinciri'ne yazar ve açık anahtarı gösterir. Açık anahtar `Config/Release.xcconfig` dosyasında `LANES_SPARKLE_PUBLIC_KEY` olarak durur.

Komut DMG'nin yanında Sparkle'ın güncelleme kaydını (`appcast.xml`) da hazırlar. Güncelleme penceresindeki ve GitHub'daki sürüm notu `docs/release-notes/<sürüm>.md` dosyasından gelir. Bu dosya yoksa not, bir önceki sürüm etiketinden bu yana yapılan commit'lerin başlıklarından oluşur. Komut ayrıca GitHub'da yayınlama komutunu yazdırır. `LANES_PUBLISH=1` ile sürümü `gh` üzerinden kendisi yayınlar. Lanes güncellemeleri bu deponun GitHub Releases sayfasındaki son sürümden öğrenir. Debug derlemeleri hiç güncelleme denetlemez.

Release derlemesi `Config/Local.xcconfig` dosyasını okumaz. CI her değişiklikte Release'i Xcode 27 ile imzasız derler.

## Yapı

| Klasör | İçerik |
| ------ | ------ |
| `Packages/LanesCore` | AppKit'e bağlı olmayan mantık: profiller, açılış planı, işlem argümanları, `claude://` bağlantı kuralları ve tanılama raporu. Linux'ta da derlenir ve test edilir. |
| `Lanes/App` | Uygulamanın girişi, ortak durum, pencere yönlendirmesi ve eski deneme sürümlerinden kalanları bir kez temizleyen kod. |
| `Lanes/Tray` | Menü çubuğu simgesi ve paneli. |
| `Lanes/MainWindow` | Ana pencere: kenar çubuğu, hesap sayfası, ayarlar. |
| `Lanes/Platform` | macOS ile konuşan katman: Claude'u açma, çalışan pencereleri bulma, Apple Event, klon, Lanes'in imza türü. |
| `Lanes/Shared` | Ekranların ortak kullandığı parçalar: ayar anahtarları ve hesap renklerinin karşılıkları. |
| `Config` | İmza ayarları (Debug ve Release ayrı) ve Developer ID dışa aktarma ayarları. |
| `scripts` | `make release` betiği ve uygulama simgesini çizen `make-icon.py`. |

Testler: `make core-test`

## Gizlilik

Lanes'in neye baktığı, neyi yazdığı ve neyi gönderdiği uygulamadaki Gizlilik sayfasında tek listede duruyor. Kısaca:

- **Baktıkları:** Çalışan Claude'ların komut satırı (ortam değişkenleri atılır), Claude'un yeri ve sürümü, `claude://` bağlantılarını hangi uygulamanın açtığı, öndeki uygulamanın süreç numarası. Bir hesap açıldıktan sonra, o hesabın klasörünün yalnız değişme saati. Sağlık sayfasında Otomasyon izninin durumu (izin sorulmadan), `claude` komutunun yeri ve Profiles altındaki klasörlerin adları. Kurulum sayfasında ayrıca `claude` komutunun sürümü ve Erişilebilirlik ile bildirim izinlerinin durumu.
- **Yazdıkları:** `~/Library/Application Support/Lanes` altında hesap listesi ve yedeği, hesap klasörleri (içine Claude yazar, Lanes yalnız Araç Kutusu'nda paylaştığın öğeler için Claude Code klasörüne bağlantı ekler), Terminal komut dosyaları, tanılama raporu ve her hesabın klonu (`Clones/<hesap kimliği>/`). Hesapların adı ve kısa bir açıklaması Spotlight dizinine yazılır. Eski sürümlerden kalan Claude kopyaları `~/Applications/Lanes Profiles` altında durabilir, Sağlık sayfası onları Çöp Sepeti'ne taşıyabilir. Deneme sürümlerinin deneme klonunu ve sonuç dosyalarını Lanes ilk açılışta bir kez kaldırır, klonu Çöp Sepeti'ne taşır.
- **Günlük ve tanılama:** Sistem günlüğüne hesap adı, klasör ya da bağlantı içermeyen olaylar yazılır. Ayarlar > Gelişmiş'teki "Tanılama Bilgisini Hazırla" sürümleri, hesapları numarayla ve çalışan Claude'ların klasörlerini panoya ve Tanılama klasörüne yazar.
- **Gönderdikleri:** Claude'a pencereyi öne getiren "yeniden aç" komutu, yönlendirme açıkken kurala göre seçilen hesaba `claude://` bağlantıları (giriş bağlantıları asla), Kimlik sekmesindeki "Claude Ayarlarını Aç" düğmesiyle o hesabın Claude'una ayarlar bağlantısı ve GitHub'daki sürüm listesini indiren güncelleme denetimi. Kurulum sayfasında "Kur" düğmesine basınca Lanes Claude Code'un resmî kurulum betiğini claude.ai'dan indirip çalıştırır. Bunun dışında Lanes'in yaptığı tek ağ isteği güncelleme denetimi.
- **Dokunmadıkları:** Giriş bilgileri, çerezler, Anahtar Zinciri, sohbetler, Claude'un ayar dosyaları ve hesap klasörlerinin içi.

## Lisans

Lanes [MIT lisansıyla](LICENSE) dağıtılıyor. Lanes bir Anthropic ürünü değil, Anthropic ile bir bağı yok. Claude, Anthropic'in ticari markası.
