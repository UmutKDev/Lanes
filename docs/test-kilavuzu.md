# Test kılavuzu

Lanes'i deneyen herkes için kısa bir kılavuz. Lanes bir Anthropic ürünü değil, Anthropic ile bir bağı yok.

## Kurulum

1. [GitHub Releases](https://github.com/UmutKDev/Lanes/releases/latest) sayfasından son DMG'yi indir.
2. DMG'yi aç ve Lanes'i Uygulamalar klasörüne sürükle.
3. Lanes'i Uygulamalar klasöründen aç. DMG'nin içinden ya da İndirilenler'den açarsan Lanes güncellenemez, DMG çıkarılınca da kapanır. Lanes bunu fark eder ve Genel Bakış'ta uyarır.

Gerekenler: macOS 26 ya da üstü ve Claude masaüstü uygulaması.

## İkinci hesabı eklemek

1. Lanes'te "Hesap Ekle"ye bas, bir ad ve renk seç.
2. Lanes Claude'u yeni hesabın boş klasörüyle, ayrı bir pencerede açar.
3. Yeni pencerede Google ya da Apple ile değil, e-posta adresinle devam et.
4. Gelen e-postadaki bağlantıya tıklama. Bağlantı ana hesabın penceresinde açılır.
5. E-postadaki doğrulama kodunu yeni pencereye yaz.

Giriş tamamen Claude'un kendi penceresinde olur. Lanes giriş bilgilerini görmez.

## Güncellemeler

Lanes güncellemeleri kendisi denetler. Elle denetlemek için menü çubuğu panelinde "Güncellemeleri Denetle…" ya da Ayarlar > Güncellemeler. Lanes'in yaptığı tek ağ isteği bu denetim.

## Sorun bildirmek

1. Ayarlar > Gelişmiş > "Tanılama Bilgisini Hazırla"ya bas.
2. Rapor panoya kopyalanır ve Tanılama klasörüne yazılır. Raporda hesap adları yerine "Hesap 1, Hesap 2" yazar, ev klasörü "~" olarak görünür.
3. Raporu okuyup GitHub'da bir [issue](https://github.com/UmutKDev/Lanes/issues/new) açarak yapıştır. Ne yaptığını ve ne beklediğini birkaç cümleyle ekle.

Lanes'in neye baktığı ve neyi yazdığı uygulamadaki Gizlilik sayfasında duruyor.

## Kaldırmak

1. Lanes'ten çık ve Uygulamalar klasöründen sil.
2. İstersen `~/Library/Application Support/Lanes` klasörünü de sil. Hesap klasörleri buradadır, içlerindeki girişler de onlarla birlikte silinir.

Claude'un ana hesabına ve ayarlarına Lanes hiç dokunmaz, kaldırınca bir şey değişmez.
