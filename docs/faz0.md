# Faz 0 denemeleri

Faz 0, Lanes'in temel kararlarını senin Mac'inde doğrulayan dokuz kısa deneme. Sonuçlar varsayılan açılış biçimini, bağlantı yönlendirme yöntemini ve ana pencerenin nasıl öne geleceğini belirliyor. Denemeler bitince ekrandaki raporu kopyalayıp projedeki konuşmaya yapıştırman yeterli.

## Başlamadan önce

1. `make open` ile projeyi aç ve Lanes'i çalıştır.
2. Menü çubuğundaki Lanes simgesine tıkla. Panelin altındaki üç nokta menüsünden "Faz 0 Doğrulama"yı seç.
3. Denemelerin çoğu için en az iki hesap gerekiyor. Ana pencerede "Hesap Ekle" ile ikinci bir hesap ekle ve açılan Claude penceresinde giriş yap.

Lanes ilk kez Claude'a bağlantı gönderdiğinde macOS bir Otomasyon izni sorar. Bu izin birinci denemenin konusu, "İzin Ver" demen gerekiyor.

## Denemeler

| # | Deneme | Nasıl yapılıyor |
| - | ------ | --------------- |
| 1 | Bağlantıyı belirli bir pencereye teslim etme | Lanes seçtiğin pencereye bir "yeni sohbet" bağlantısı gönderir. Sohbetin hangi pencerede açıldığını sen seçersin. Her iki pencereyle birer kez dene. |
| 2 | `claude://` varsayılanını geri alma | Lanes bağlantıları açan uygulama olmayı dener. Onay penceresi çıkıp çıkmadığını sen işaretlersin. Bitince "Claude'u Geri Yükle"ye bas. |
| 3 | İmzası korunan klonun görünüşü | Lanes Claude'un bir kopyasını kendi simgesiyle oluşturur ve imzayı kontrol eder. Kopyayı açınca Dock'ta ve Cmd-Tab'da ne gördüğünü işaretlersin. |
| 4 | Code sekmesi ve `CLAUDE_CONFIG_DIR` | Lanes bir hesabı açar. O pencerenin Code sekmesinde kısa bir oturum başlatırsın. Lanes oturum kaydının hangi klasöre yazıldığına bakar. |
| 5 | App Management izni | Üçüncü denemede bir izin penceresi çıkıp çıkmadığını işaretlersin. |
| 6 | Ayrı kimlikli klonda Cowork | Ayrı kimlik modu yazılınca yapılacak. Şimdilik atlayabilirsin. |
| 7 | Claude güncellemesinden sonra | Claude bir sonraki güncellemeyi aldığında hesapları yeniden açarsın. Ekrandaki tablo her pencerenin hangi klasörle açıldığını gösterir. |
| 8 | macOS 27 menü çubuğunda panel | Paneli açıp kapatırsın, doğru yerde açılıp açılmadığını yazarsın. macOS 27'de anlamlı. |
| 9 | Ana pencerenin öne gelmesi | Otomatik. Pencere birkaç kez kapanıp panelden yeniden açılır. Bitene kadar fareye ve klavyeye dokunma. |

## Güvenlik notları

- Lanes giriş bilgilerine, çerezlere ve Anahtar Zinciri'ne dokunmaz. Dördüncü denemede yalnız dosyaların değiştirilme saatine bakar, içeriklerini açmaz.
- İkinci deneme sırasında Lanes `claude://` bağlantılarını açan uygulama olabilir. Bu sırada bir giriş bağlantısı ya da Lanes'in tanımadığı bir bağlantı gelirse Lanes onu iletmez ve varsayılanı Claude'a geri verir. Girişi bir kez daha denemen gerekir. Lanes gelen bağlantıların yalnız türünü tutar, adresini saklamaz. Lanes her açılışta da varsayılanı Claude'a geri verir.
- Klonlar `~/Applications/Lanes Profiles` klasörüne yazılır. "Klonu Çöpe At" düğmesi deneme klonunu Çöp Sepeti'ne taşır.
