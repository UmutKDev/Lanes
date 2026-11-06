# Lanes for Windows

Lanes'in Windows sürümü. Birden fazla Claude hesabını aynı Windows bilgisayarda yan yana açar. Her hesap Claude'u kendi klasörüyle başlatır ve görev çubuğunda kendi renkli simgesiyle ayrı bir düğme olarak durur.

## Nasıl çalışır

- **Ana hesap**, Claude'un kendi klasörünü (`%APPDATA%\Claude`) ve `~\.claude` klasörünü kullanır. Lanes bunlara dokunmaz.
- **Diğer hesaplar** Claude'u `--user-data-dir=%APPDATA%\Claude-Lanes-<id>` ile açar. Claude Code'un klasörü `CLAUDE_CONFIG_DIR` ile `%LOCALAPPDATA%\Lanes\Profiles\<id>\ClaudeCode` olur. Claude klasörü doğrudan `%APPDATA%` altında durur, çünkü Claude'un Cowork özelliği sanal makine dosyalarını orada arıyor.
- **Görev çubuğu:** Claude pencerelerine bir AppUserModelID vermiyor. Windows bu yüzden hepsini tek düğmede topluyor. Lanes her iki saniyede bir Claude pencerelerini bulur ve her birine hesabın kimliğini, renkli simgesini ve sabitlenince Lanes üzerinden o hesabı açan komutu yazar.
- **Hesap listesi** `%LOCALAPPDATA%\Lanes\profiles.json` dosyasında durur. Biçimi Mac sürümüyle aynı, bilinmeyen alanlar olduğu gibi korunur.

Desteklenen Claude, claude.ai/download adresinden ya da `winget install Anthropic.Claude` ile kurulan sürüm. Microsoft Store paketi 2.42304 sürümünden beri `--user-data-dir` ayarını yok sayıyor ([anthropics/claude-code#103068](https://github.com/anthropics/claude-code/issues/103068)). Lanes bu paketi görürse kullanıcıya yeniden kurmasını söyler.

## Derleme

Gerekenler: .NET 10 SDK.

```powershell
dotnet test LanesWindows/Lanes.Core.Tests
dotnet publish LanesWindows/Lanes.App -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o out
```

Çekirdek kitaplık (`Lanes.Core`) Windows API'si kullanmaz, Linux ve macOS'ta da derlenir ve test edilir. Uygulama da `EnableWindowsTargeting` sayesinde her yerde derlenir, ama yalnız Windows'ta çalışır.

## Uçtan uca sınama

`Lanes.exe --self-test <klasör>` gerçek Claude ile ana hesabı ve iki hesap daha açar. Her pencerenin doğru görev çubuğu kimliğini ve simgesini aldığını, her hesabın kendi klasörüne yazdığını ve açık bir hesabı yeniden açmanın yeni bir kopya başlatmadığını denetler. Rapor, kayıt ve ekran görüntüsü o klasöre düşer. GitHub Actions'taki **Windows** iş akışı bunu her değişiklikte çalıştırır.

`tools/probe.ps1`, Claude'un yeni bir sürümünün ayrı klasörlü kopyaları hâlâ açıp açmadığını Lanes olmadan denetler.

## Yapı

| Klasör | İçerik |
| ------ | ------ |
| `Lanes.Core` | Hesaplar, `profiles.json`, klasör yolları, açılış planı, çalışan Claude'ları hesaplarla eşleme, Claude Code komutu |
| `Lanes.Core.Tests` | xUnit testleri |
| `Lanes.App` | WPF uygulaması: bildirim alanı simgesi, ana pencere, hesap düzenleyici |
| `Lanes.App/Platform` | Windows ile konuşan katman: Claude süreçleri, pencere özellikleri, simgeler, Terminal, başlangıçta açılma |
| `tools` | Claude'un davranışını sınayan betik |

## Henüz yok

- `claude://` bağlantılarını doğru hesaba yönlendirme
- Chrome/Edge eklentisinin Windows'ta Lanes'le konuşması
- İmzalı kurulum dosyası ve otomatik güncelleme
