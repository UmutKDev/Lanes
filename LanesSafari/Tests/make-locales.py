#!/usr/bin/env python3
"""Writes LanesSafari/Resources/_locales/{tr,en}/messages.json from the table
below, so both languages always have the same keys. Run after editing:
python3 LanesSafari/Tests/make-locales.py"""
import json
import pathlib

M = {
    "langCode": ("tr", "en"),
    "extensionName": ("Lanes", "Lanes"),
    "extensionDescription": (
        "Birden fazla Claude hesabını Safari'de tek tıkla değiştir. Her hesap kendi rengini taşır, oturumlar Anahtar Zinciri'nde saklanır.",
        "Switch between Claude accounts in Safari with one click. Each account has its own color, and sessions are kept in the Keychain.",
    ),
    "popupTitle": ("Claude hesapları", "Claude accounts"),
    "activeLabel": ("Şu an açık", "In use"),
    "noneActiveLabel": ("Giriş yok", "Not signed in"),
    "noneActiveTitle": ("Hiçbir hesap açık değil", "No account in use"),
    "noneActiveBody": ("Aşağıdan bir hesap seç ya da yeni hesap ekle.", "Pick an account below or add a new one."),
    "otherAccounts": ("Diğer hesaplar", "Other accounts"),
    "searchPlaceholder": ("Hesap ara", "Search accounts"),
    "emptyTitle": ("İlk hesabını ekle", "Add your first account"),
    "emptyBody": (
        "claude.ai'de giriş yap. Lanes hesabını tanır ve buraya ekler.",
        "Sign in on claude.ai. Lanes recognizes the account and adds it here.",
    ),
    "openClaude": ("claude.ai'yi Aç", "Open claude.ai"),
    "addAccount": ("Hesap Ekle", "Add Account"),
    "carryDraft": ("Taslağı taşı", "Carry draft"),
    "carryDraftHelp": (
        "Hesap değiştirirken yazmakta olduğun mesaj yeni hesapta yeni bir sohbete taşınır.",
        "When you switch, the message you are typing moves to a new chat in the other account.",
    ),
    "settings": ("Ayarlar", "Settings"),
    "openLanesApp": ("Lanes'i Aç", "Open Lanes"),
    "newChat": ("Yeni Sohbet", "New Chat"),
    "openInLanes": ("Masaüstünde Aç", "Open on Desktop"),
    "openInLanesHelp": ("Bu hesabın Lanes'teki Claude uygulamasını ($1) açar.", "Opens this account's Claude app in Lanes ($1)."),
    "lanesChip": ("Lanes: $1", "Lanes: $1"),
    "expiredChip": ("Yeniden giriş gerekli", "Sign in again"),
    "editAccount": ("Hesabı düzenle", "Edit account"),
    "name": ("Ad", "Name"),
    "color": ("Renk", "Color"),
    "lanesLink": ("Lanes hesabı", "Lanes account"),
    "lanesAuto": ("E-postaya göre otomatik", "Match by e-mail"),
    "lanesNone": ("Bağlama", "Don't link"),
    "pin": ("Listenin başında tut", "Keep at the top"),
    "agentAccount": ("Claude in Chrome bu hesapta", "Claude in Chrome uses this account"),
    "agentAccountHelp": (
        "Claude in Chrome yalnız claude.ai'de kendi hesabı açıkken çalışır. Başka hesaba geçince Lanes geri dönmeyi önerir.",
        "Claude in Chrome works only while claude.ai is signed in to its own account. Lanes offers the way back when you switch away.",
    ),
    "agentAwayTitle": ("Claude in Chrome $1 hesabında", "Claude in Chrome uses $1"),
    "agentAwayBody": (
        "Bu hesap açıkken Claude in Chrome çalışmaz. İki hesabı aynı anda kullanmak için her birine ayrı bir tarayıcı profili aç.",
        "It won't work while this account is in use. To use both at once, give each account its own browser profile.",
    ),
    "agentSwitchBack": ("$1 hesabına dön", "Switch back to $1"),
    "forget": ("Hesabı Unut", "Forget Account"),
    "forgetActive": ("Unut ve Oturumu Kapat", "Forget and Sign Out"),
    "forgetConfirm": ("Emin misin? Tekrar bas", "Sure? Click again"),
    "cancel": ("Vazgeç", "Cancel"),
    "save": ("Kaydet", "Save"),
    "planFree": ("Ücretsiz", "Free"),
    "planPro": ("Pro", "Pro"),
    "planMax": ("Max", "Max"),
    "planTeam": ("Team", "Team"),
    "planEnterprise": ("Enterprise", "Enterprise"),
    "timeJustNow": ("az önce", "just now"),
    "timeMinutes": ("$1 dk önce", "$1 min ago"),
    "timeHours": ("$1 sa önce", "$1 h ago"),
    "timeDays": ("$1 gün önce", "$1 d ago"),
    "badgeTitle": ("Lanes: $1 ($2)", "Lanes: $1 ($2)"),
    "menuAsk": ("Claude'a Sor", "Ask Claude"),
    "menuCurrent": ("(açık)", "(in use)"),
    "commandOpen": ("Hesap listesini aç", "Open the account list"),
    "commandNext": ("Sonraki hesaba geç", "Switch to the next account"),
    "commandPrevious": ("Önceki hesaba geç", "Switch to the previous account"),
    "errorNoAccount": ("Bu hesap artık listede yok.", "This account is no longer in the list."),
    "errorNoSession": (
        "$1 için kayıtlı oturum yok. Hesap Ekle ile yeniden giriş yap.",
        "There is no saved session for $1. Sign in again with Add Account.",
    ),
    "errorCookiesHidden": (
        "Safari oturum çerezini eklentiye göstermiyor, bu yüzden hesap değiştirilemiyor.",
        "Safari doesn't show the session cookie to extensions, so accounts can't be switched.",
    ),
    "errorAuthFlow": (
        "Bir sekmede bir uygulama Claude hesabınla giriş yapıyor (örneğin Claude in Chrome). Giriş bitince yeniden dene.",
        "An app is signing in with your Claude account in a tab (for example Claude in Chrome). Try again when it's done.",
    ),
    "hiddenTitle": ("Safari hesap değiştirmeye izin vermiyor", "Safari doesn't allow switching"),
    "hiddenBody": (
        "Bu Safari sürümü oturum çerezini eklentilere göstermiyor. Hesap rengi ve sekme işareti çalışmaya devam eder. Hesapları aynı anda kullanmak için her hesaba ayrı bir Safari profili aç.",
        "This Safari version hides the session cookie from extensions. Account colors and tab marks still work. To use accounts side by side, give each one its own Safari profile.",
    ),
    "optionsTitle": ("Lanes Safari Eklentisi", "Lanes for Safari"),
    "optionsSubtitle": (
        "Claude hesaplarını Safari'de tek tıkla değiştir.",
        "Switch Claude accounts in Safari with one click.",
    ),
    "statusTitle": ("Durum", "Status"),
    "statusAccounts": ("$1 hesap kayıtlı", "$1 accounts saved"),
    "statusAccountsEmpty": (
        "claude.ai'de giriş yaptığında hesap buraya eklenir.",
        "An account appears here when you sign in on claude.ai.",
    ),
    "statusSwitchOK": ("Hesap değiştirme çalışıyor", "Switching works"),
    "statusSwitchOKBody": (
        "Geçiş, bu Safari profilindeki tüm claude.ai sekmelerini seçilen hesaba taşır.",
        "A switch moves every claude.ai tab in this Safari profile to the chosen account.",
    ),
    "statusSwitchUnknown": ("Henüz denenmedi", "Not checked yet"),
    "statusSwitchUnknownBody": (
        "claude.ai'yi bir kez aç, Lanes Safari'nin geçişe izin verip vermediğine baksın.",
        "Open claude.ai once so Lanes can check whether Safari allows switching.",
    ),
    "statusVaultKeychain": ("Oturumlar Anahtar Zinciri'nde", "Sessions are in the Keychain"),
    "statusVaultKeychainBody": (
        "Kayıtlı oturumlar macOS Anahtar Zinciri'nde şifreli durur.",
        "Saved sessions are kept encrypted in the macOS Keychain.",
    ),
    "statusVaultLocal": ("Oturumlar Safari'de saklanıyor", "Sessions are kept in Safari"),
    "statusVaultLocalBody": (
        "Lanes uygulamasının eklenti parçasına ulaşılamadı. Oturumlar şimdilik eklentinin kendi deposunda. Lanes'i Uygulamalar klasöründen bir kez aç.",
        "The Lanes app part of the extension couldn't be reached, so sessions are in the extension's own storage for now. Open Lanes from Applications once.",
    ),
    "statusLanes": ("Lanes'e bağlı: $1 hesap", "Connected to Lanes: $1 accounts"),
    "statusLanesBody": (
        "E-postası aynı olan web hesapları Lanes'teki adını ve rengini alır.",
        "Web accounts with the same e-mail take their name and color from Lanes.",
    ),
    "statusNoLanes": ("Lanes masaüstü uygulaması bağlı değil", "Lanes desktop app not connected"),
    "statusNoLanesBody": (
        "Eklenti onsuz da çalışır. Lanes masaüstü uygulaması açıksa hesap listesini paylaşır, böylece adlar ve renkler eşleşir.",
        "The extension works without it. When the Lanes desktop app is open, it shares its account list so names and colors match.",
    ),
    "pageMarksTitle": ("claude.ai'de hesap işareti", "Account marks on claude.ai"),
    "settingStripe": ("Renkli şerit", "Color bar"),
    "settingStripeHelp": ("Sayfanın üstünde hesabın renginde ince bir şerit.", "A thin bar in the account's color at the top of the page."),
    "settingTitle": ("Sekme başlığı", "Tab title"),
    "settingTitleHelp": ("Sekme başlığının önüne hesabın rengi ve adı gelir.", "The account's color and name go in front of the tab title."),
    "settingFavicon": ("Sekme simgesi", "Tab icon"),
    "settingFaviconHelp": ("Claude simgesinin köşesine hesabın renginde bir nokta.", "A dot in the account's color on the corner of the Claude icon."),
    "switchingTitle": ("Geçiş", "Switching"),
    "settingAutoAdd": ("Yeni hesapları otomatik ekle", "Add new accounts automatically"),
    "settingAutoAddHelp": (
        "claude.ai'de listede olmayan bir hesapla giriş yapınca hesap listeye eklenir.",
        "Signing in on claude.ai with an account that isn't listed adds it to the list.",
    ),
    "shortcutsTitle": ("Kısayollar", "Shortcuts"),
    "shortcutDigits": ("Listede hesaba geç", "Switch to an account in the list"),
    "shortcutMenu": ("Seçili metni bir hesapla sor", "Ask about selected text with an account"),
    "shortcutMenuKey": ("Sağ tık", "Right-click"),
    "privacyTitle": ("Gizlilik", "Privacy"),
    "privacy1": (
        "Eklenti yalnız claude.ai'de çalışır. Hesabı tanımak için yalnız ad, e-posta ve plan bilgisini okur. Sohbetlerini okumaz.",
        "The extension runs only on claude.ai. To recognize an account it reads only the name, e-mail and plan. It doesn't read your chats.",
    ),
    "privacy2": (
        "Her hesabın oturum çerezleri macOS Anahtar Zinciri'nde saklanır ve hiçbir sunucuya gönderilmez.",
        "Each account's session cookies are stored in the macOS Keychain and never sent to any server.",
    ),
    "privacy3": (
        "Hesabı unutmak kayıtlı oturumunu da siler. Claude'da oturumu tamamen kapatmak için claude.ai'de çıkış yap.",
        "Forgetting an account deletes its saved session too. To end the session on Claude's side, sign out on claude.ai.",
    ),
    "tipTitle": ("İki hesabı aynı anda kullanmak", "Using two accounts at once"),
    "tipBody": (
        "Bir Safari profilinde aynı anda tek Claude hesabı açık olabilir. İki hesabı yan yana kullanmak için Safari > Ayarlar > Profiller'den ikinci bir profil aç ve eklentiyi orada da aç. Her profil kendi hesap listesini tutar.",
        "A Safari profile has one Claude account signed in at a time. To use two side by side, add a second profile in Safari > Settings > Profiles and turn the extension on there too. Each profile keeps its own account list.",
    ),
}

COLOR_NAMES = {
    "blue": ("Mavi", "Blue"), "purple": ("Mor", "Purple"), "pink": ("Pembe", "Pink"), "red": ("Kırmızı", "Red"),
    "orange": ("Turuncu", "Orange"), "yellow": ("Sarı", "Yellow"), "green": ("Yeşil", "Green"), "mint": ("Nane", "Mint"),
    "teal": ("Çam yeşili", "Teal"), "cyan": ("Camgöbeği", "Cyan"), "indigo": ("Çivit", "Indigo"), "brown": ("Kahverengi", "Brown"),
    "gray": ("Gri", "Gray"),
}
for key, names in COLOR_NAMES.items():
    M["color_" + key] = names

root = pathlib.Path(__file__).resolve().parent.parent / "Resources" / "_locales"
for index, lang in enumerate(["tr", "en"]):
    out = {key: {"message": value[index]} for key, value in sorted(M.items())}
    folder = root / lang
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "messages.json").write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("ok", len(M))
