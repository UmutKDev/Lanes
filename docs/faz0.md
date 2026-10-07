# Faz 0 denemeleri

Faz 0, Lanes'in temel kararlarını senin Mac'inde doğrulayan dokuz kısa deneme. Faz 0.5 bunlara sekiz deneme daha ekliyor (aşağıda). Sonuçlar varsayılan açılış biçimini, bağlantı yönlendirme yöntemini ve ana pencerenin nasıl öne geleceğini belirliyor. Denemeler bitince ekrandaki raporu kopyalayıp projedeki konuşmaya yapıştırman yeterli.

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

Dokuzuncu denemenin bir de "Simgeye Tıklayarak Ölç" yolu var. Lanes pencereyi kapatır ve odağı Finder'a verir. Sen her seferinde menü çubuğundaki Lanes simgesine, sonra paneldeki pencere düğmesine tıklarsın. Lanes, simgeye bastığın andan panelin klavye odağını almasına kadar geçen süreyi ve pencerenin öne gelip gelmediğini kaydeder. Ölçüm sürerken yalnız kendi simgesine yapılan basışların zamanını tutar. Raporda her sürenin hangi andan ölçüldüğü de yazar. Kaçıncı denemede olduğun simgenin yanında görünür. Orada üç nokta varken tıklama, Lanes bir sonraki denemeye hazırlanıyor demektir. Ölçümü yarıda bırakmak için simgeye sağ tıklayıp "Ölçümü Durdur"u seç.

## Faz 0.5 denemeleri

Faz 0.5, Faz 0'ın denemediği Claude davranışlarını ölçüyor. Aynı ekranda, listenin ikinci bölümünde duruyor. Sıra önemli: sekizinci deneme diskteki eski klonu sildiği için en sona kalıyor.

| # | Deneme | Nasıl yapılıyor |
| - | ------ | --------------- |
| 0.5.1 | Eski klon | Lanes, Claude güncellemesinden önce oluşturulan deneme klonunu silmeden ve yeniden oluşturmadan inceler: sürümler, imza ve Gatekeeper. Klonu açınca ne gördüğünü işaretlersin. |
| 0.5.2 | Lanes'siz açılan klon | Klonu Finder, Spotlight ya da Dock'tan açarsın. Lanes klonun hangi klasörü kullandığını ve `claude://` varsayılanının klona geçip geçmediğini kaydeder. Varsayılan klona geçtiyse 0.5.3'teki "Claude'u Geri Yükle" onu geri alır. |
| 0.5.3 | Yeni hesabın girişi | Ana hesap açıkken yeni bir hesapla Google, e-posta bağlantısı ve varsa SSO ile giriş yaparsın. Girişin hangi pencerede tamamlandığını seçersin. |
| 0.5.4 | Hesaplar arası çıkış | İkinci bir hesap açıkken ana hesapta hesap değiştirirsin. İki pencereyi kapatıp Lanes'ten yeniden açarsın ve ikinci hesabın oturumunun açık kalıp kalmadığını işaretlersin. |
| 0.5.5 | Claude Code girişi | Ana hesap ve bir profil için Claude Code'u Terminalde açarsın. Yeniden açınca ikisinin de kendi hesabında kalıp kalmadığına `/status` ile bakarsın. İki ayrı hesap gerekiyor. |
| 0.5.6 | Standart modda Cowork | Cowork'ün ikinci bir hesapta ve iki hesapta aynı anda çalışıp çalışmadığını işaretlersin. |
| 0.5.7 | Claude Code oturum kayıtları | Lanes bir hesabın `projects/` klasöründeki proje klasörlerini ve oturum sayısını kaydeder. En yeni oturumu `claude --resume` ile sürdüren komutu kopyalayıp denersin. |
| 0.5.8 | Klon yeniden | Üçüncü deneme güncel kodla yapılır. Var olan klon değiştirilirken App Management izni soruluyor mu, o da işaretlenir. Klon açıksa önce ondan çıkman gerekir. |

Rapor iki aşamayı ayrı tablolarla gösterir. Başlıkta Lanes'in commit'i, imza türü ve uygulamanın yolu da var. Bir deneme başlıktakinden farklı bir Lanes ya da Claude sürümüyle kaydedildiyse, denemenin altında hangisiyle kaydedildiği yazar. Lanes bu bilgiyi tutmaya başlamadan önce kaydedilen denemelerde orada "bilinmiyor" yazar.

## Güvenlik notları

- Lanes giriş bilgilerine, çerezlere ve Anahtar Zinciri'ne dokunmaz. Dördüncü denemede yalnız dosyaların değiştirilme saatine bakar, içeriklerini açmaz.
- İkinci deneme sırasında Lanes `claude://` bağlantılarını açan uygulama olabilir. Bu sırada bir giriş bağlantısı ya da Lanes'in tanımadığı bir bağlantı gelirse Lanes onu iletmez ve varsayılanı Claude'a geri verir. Girişi bir kez daha denemen ya da bağlantıyı yeniden açman gerekir. Lanes gelen bağlantıların yalnız türünü tutar, adresini saklamaz. Lanes her açılışta da varsayılanı Claude'a geri verir.
- Klonlar `~/Applications/Lanes Profiles` klasörüne yazılır. "Klonu Çöpe At" düğmesi deneme klonunu Çöp Sepeti'ne taşır.
- Faz 0.5'in yardımcıları hiçbir Claude penceresini kapatmaz. Pencereleri sen Claude'un kendi menüsünden kapatırsın. Lanes açık bir klonu değiştirmez ya da çöpe atmaz. 0.5.7'de Lanes yalnız dosya adlarına ve tarihlerine bakar, oturum dosyalarını açmaz.
- Rapor ev klasörünü `~` olarak yazar, Claude Code'un klasör adlarındaki biçimiyle (`-Users-…`) birlikte. Kayıtlarda yine de dosya yolları ve hesap adların bulunur, paylaşmadan önce göz at.
- Sonuçlar `validation-results.json` dosyasında durur. Lanes eski `faz0-results.json` dosyasını yalnız bir kez okur ve ona hiç yazmaz, böylece daha eski bir Lanes sürümü Faz 0.5 sonuçlarını göremez ve silemez. `validation-results.json` okunamazsa Lanes onu silmez, ilk kayıtta aynı klasörde başka bir adla saklar.
