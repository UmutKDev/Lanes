# Lanes

Lanes, birden fazla Claude hesabını aynı Mac'te yan yana kullanmanı sağlayan bir menü çubuğu uygulaması. Her hesap kendi klasörüyle, ayrı bir Claude penceresinde açılır. Yerel Claude Code oturumları da hesap başına ayrı kalır, istersen aynı anda farklı hesaplarla çalışabilirsin.

Lanes hiçbir hesabın giriş bilgisini, çerezini ya da Anahtar Zinciri kaydını okumaz, saklamaz, başka yere taşımaz. Giriş her zaman Claude'un kendi penceresinde ya da `claude` komutunda olur.

## Durum

Bu ilk sürüm iki şey içeriyor:

- Uygulamanın iskeleti: menü çubuğu paneli, ana pencere, hesap ekleme, hesabı kendi klasörüyle açma ve Claude Code'u o hesapla Terminalde başlatma.
- Faz 0 doğrulama ekranı: Lanes'in nasıl çalışacağını belirleyen dokuz kısa deneme. Ayrıntılar [docs/faz0.md](docs/faz0.md) dosyasında.

## Derleme

Gerekenler: macOS 14 ya da üstü, Xcode 26 ve XcodeGen.

```sh
brew install xcodegen
make open
```

`make open` Xcode projesini `project.yml` dosyasından oluşturur ve Xcode'da açar. Proje dosyası depoda tutulmuyor, `project.yml` tek kaynak.

Kendi ekip kimliğinle imzalamak için `Config/Local.xcconfig.example` dosyasını `Config/Local.xcconfig` olarak kopyala ve ekip kimliğini yaz. Ekip kimliği olmadan da derlenir, ama macOS o durumda her derlemeden sonra Otomasyon iznini yeniden sorar.

## Yapı

| Klasör | İçerik |
| ------ | ------ |
| `Packages/LanesCore` | AppKit'e bağlı olmayan mantık: profiller, açılış planı, işlem argümanları, `claude://` bağlantı kuralları ve Faz 0 raporu. Linux'ta da derlenir ve test edilir. |
| `Lanes/App` | Uygulamanın girişi, ortak durum ve pencere yönlendirmesi. |
| `Lanes/Tray` | Menü çubuğu simgesi ve paneli. |
| `Lanes/MainWindow` | Ana pencere: kenar çubuğu, hesap sayfası, ayarlar. |
| `Lanes/Validation` | Faz 0 doğrulama ekranı. |
| `Lanes/Platform` | macOS ile konuşan katman: Claude'u açma, çalışan pencereleri bulma, Apple Event, klon. |

Testler: `make core-test`
