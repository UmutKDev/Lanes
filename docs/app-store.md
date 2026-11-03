# Mac App Store

Lanes Mac App Store'a çıkmıyor. App Store'daki her uygulama sandbox (kum havuzu) içinde çalışmak zorunda ve Lanes'in asıl işi orada yapılamıyor:

- Hesap kopyaları için Claude.app'i kopyalayıp `codesign` ile yeniden imzalıyor. Başka bir şirketin uygulamasını değiştirmek inceleme kurallarına da (2.5.2 ve 5.2) takılıyor.
- Sekmeler Erişilebilirlik API'siyle başka uygulamaların pencerelerini yönetiyor.
- Claude'un veri klasörlerini, `~/.claude`'u ve `~/.claude.json`'u okuyup yazıyor.
- Chrome ve Edge için yerel köprü dosyasını o tarayıcıların klasörüne yazıyor.
- Claude Code'u `curl | bash` ile kuruyor ve kendini Sparkle ile güncelliyor.

Lanes bu yüzden Developer ID ile imzalanıp Apple'ın onay taramasından geçirilmiş bir DMG olarak GitHub'dan ve Homebrew'dan dağıtılıyor (README'deki "Kurulum" bölümü).

Mağazaya yalnız Safari eklentisi çıkıyor. Bunun için ayrı ve küçük bir uygulama var: **Lanes for Safari** (`LanesForSafari`, paket kimliği `com.umutkdev.LanesForSafari`). Eklentinin kodu ve web dosyaları Lanes'in içindekiyle aynı (`LanesSafari`), yalnız paket kimliği farklı (`com.umutkdev.LanesForSafari.Extension`). Uygulamanın tek penceresi eklentinin açık olup olmadığını gösteriyor ve Safari'nin Uzantılar ayarını açıyor. Lanes masaüstü uygulaması da kuruluysa eklenti onun paylaştığı hesap listesini okuyor, böylece adlar ve renkler eşleşiyor. Lanes kurulu değilse eklenti onsuz çalışıyor.

## İlk yükleme

1. **API anahtarı:** App Store Connect > Kullanıcılar ve Erişim > Entegrasyonlar > App Store Connect API > Ekip Anahtarları > "+". Rolü **Admin** seç (Xcode'un Apple'ın bulutta tuttuğu dağıtım sertifikasını kullanabilmesi için gerekli). `.p8` dosyasını indir ve Mac'te `scripts/setup-app-store-secrets.sh` komutunu çalıştır.
2. **Paket kimliği:** Actions > App Store > Run workflow'u "App Store Connect'e yükle" kapalıyken bir kez çalıştır. Xcode iki paket kimliğini ve mağaza profillerini kendisi kaydediyor.
3. **Uygulama kaydı:** App Store Connect > Uygulamalar > "+" > Yeni Uygulama. Platform macOS, ad "Lanes for Safari", ana dil Türkçe, paket kimliği `com.umutkdev.LanesForSafari`, SKU `lanes-for-safari`. API yeni uygulama kaydı açamıyor, bu adım elle yapılıyor.
4. **Yükleme:** Run workflow'u bu kez "yükle" açıkken çalıştır. Derleme birkaç dakika içinde App Store Connect'te görünür.
5. **Sayfa ve inceleme:** Aşağıdaki metinleri gir, derlemeyi sürüme ekle ve incelemeye gönder.

Sonraki sürümlerde yalnız 4. ve 5. adımlar var. Derleme numarası commit sayısı olduğu için her yeni commit'ten yapılan yükleme kabul ediliyor.

## Sayfa bilgileri

| Alan | Değer |
| --- | --- |
| Ad | Lanes for Safari |
| Alt başlık (TR) | claude.ai hesapları arasında geçiş |
| Alt başlık (EN) | Switch claude.ai accounts |
| Kategori | Üretkenlik (ikincil: Geliştirici Araçları) |
| Fiyat | Ücretsiz, tüm ülkeler |
| Telif | 2026 Umut Kızıloğlu |
| Destek adresi | https://github.com/UmutKDev/Lanes/issues |
| Pazarlama adresi | https://github.com/UmutKDev/Lanes |
| Gizlilik politikası | https://github.com/UmutKDev/Lanes/blob/main/docs/privacy/browser-extension.md |
| Yaş derecelendirmesi | Bütün sorulara "Yok" (4+) |
| Uygulama gizliliği | "Veri toplanmıyor" (Data Not Collected) |
| Şifreleme | Uygulama `ITSAppUsesNonExemptEncryption = NO` diyor, ek belge gerekmiyor |
| Ekran görüntüleri | Chrome ve Edge mağazası için hazırlananlardan `store-1` (açılır pencere) ve `store-3` (ayarlar), 1280x800, TR ve EN |

**Anahtar kelimeler (TR):** claude,hesap,çoklu hesap,safari,oturum,geçiş,yapay zeka,profil,iş,kişisel

**Anahtar kelimeler (EN):** claude,accounts,multiple accounts,safari,switch,session,ai,profile,work,personal

**Açıklama (TR):**

> Lanes for Safari, birden çok claude.ai hesabını Safari'de tek tıkla değiştirmeni sağlar. İş, kişisel ve müşteri hesapları arasında çıkış yapıp yeniden giriş yapmak zorunda kalmazsın.
>
> - Araç çubuğundaki Lanes düğmesinden hesabı seç, sayfa o hesapla yeniden açılır.
> - Her hesabın kendi adı ve rengi olur. Sayfanın üstündeki ince şerit ve sekme başlığı hangi hesapta olduğunu gösterir.
> - Yazmakta olduğun mesaj, istersen geçtiğin hesaba taşınır.
> - Her hesabın oturumu macOS Anahtar Zinciri'nde saklanır.
> - Klavye kısayollarıyla sıradaki ya da önceki hesaba geç.
>
> Eklenti yalnız claude.ai'de çalışır. Hiçbir sunucuya veri göndermez, analiz ya da takip kodu içermez. Lanes masaüstü uygulaması da kuruluysa hesaplar oradaki adını ve rengini alır.
>
> Lanes, Anthropic'in resmî bir ürünü değildir ve Anthropic ile bağlantılı değildir.

**Açıklama (EN):**

> Lanes for Safari lets you switch between several claude.ai accounts in Safari with one click, without signing out and back in between work, personal and client accounts.
>
> - Pick an account from the Lanes button in the toolbar and the page reopens with it.
> - Every account gets its own name and color. A thin bar at the top of the page and the tab title show which account you're in.
> - The message you're typing can move with you to the account you switch to.
> - Each account's session is kept in the macOS Keychain.
> - Switch to the next or previous account with keyboard shortcuts.
>
> The extension runs only on claude.ai. It sends no data to any server and has no analytics or tracking. If the Lanes desktop app is installed too, accounts take their names and colors from it.
>
> Lanes is not an official Anthropic product and is not affiliated with Anthropic.

**İnceleme notu (App Review Information > Notes, EN):**

> Lanes for Safari is a container app for a Safari Web Extension. The app window only shows whether the extension is enabled and opens Safari's Extensions settings.
>
> To test: open the app, click "Open Safari Settings", enable Lanes and allow it on claude.ai. Sign in on https://claude.ai with any free Claude account and click the Lanes toolbar button > Add Account. Sign out, sign in with a second account and add it too. Clicking an account in the popup switches claude.ai between them without signing in again.
>
> The extension only accesses claude.ai. It saves each account's claude.ai session cookies in the user's own Keychain so it can restore them on switch; nothing is sent to us or any third party. No demo account is needed beyond a free claude.ai account, which anyone can create.
