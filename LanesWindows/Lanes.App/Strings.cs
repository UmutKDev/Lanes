using System.Globalization;

namespace Lanes.App;

/// <summary>Lanes speaks Turkish when Windows does, English otherwise. Same wording as the Mac app.</summary>
static class L
{
    public static bool Turkish { get; } = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "tr";

    static readonly Dictionary<string, (string Tr, string En)> Table = new()
    {
        ["MainAccount"] = ("Ana hesap", "Main account"),
        ["Accounts"] = ("Hesaplar", "Accounts"),
        ["AddAccount"] = ("Hesap Ekle", "Add Account"),
        ["Open"] = ("Aç", "Open"),
        ["BringForward"] = ("Öne Getir", "Bring Forward"),
        ["ClaudeCode"] = ("Claude Code", "Claude Code"),
        ["Edit"] = ("Düzenle…", "Edit…"),
        ["Delete"] = ("Sil…", "Delete…"),
        ["MoveUp"] = ("Yukarı Taşı", "Move Up"),
        ["MoveDown"] = ("Aşağı Taşı", "Move Down"),
        ["OpenFolder"] = ("Claude Klasörünü Göster", "Show Claude Folder"),
        ["Running"] = ("Açık", "Running"),
        ["NotRunning"] = ("Kapalı", "Not running"),
        ["ShowLanes"] = ("Lanes'i Göster", "Show Lanes"),
        ["Quit"] = ("Lanes'ten Çık", "Quit Lanes"),
        ["StartWithWindows"] = ("Windows açılınca başlat", "Start with Windows"),
        ["Name"] = ("Ad", "Name"),
        ["Email"] = ("E-posta (isteğe bağlı)", "Email (optional)"),
        ["EmailHint"] = ("Yalnız hesapları ayırt etmen için. Lanes bunu Claude'dan okumaz.", "Only to tell accounts apart. Lanes never reads it from Claude."),
        ["Note"] = ("Not (isteğe bağlı)", "Note (optional)"),
        ["Color"] = ("Renk", "Color"),
        ["Letter"] = ("Harf", "Letter"),
        ["CodeFolder"] = ("Claude Code'un açılacağı klasör", "Folder Claude Code starts in"),
        ["Choose"] = ("Seç…", "Choose…"),
        ["Clear"] = ("Temizle", "Clear"),
        ["HomeFolder"] = ("Ev klasörü", "Home folder"),
        ["Save"] = ("Kaydet", "Save"),
        ["Cancel"] = ("Vazgeç", "Cancel"),
        ["NewAccount"] = ("Yeni Hesap", "New Account"),
        ["EditAccount"] = ("Hesabı Düzenle", "Edit Account"),
        ["NewAccountName"] = ("Yeni hesap", "New account"),
        ["DeleteTitle"] = ("{0} silinsin mi?", "Delete {0}?"),
        ["DeleteBody"] = ("Hesabın Claude ve Claude Code klasörleri Geri Dönüşüm Kutusu'na taşınır. Claude hesabının kendisi silinmez.",
                          "The account's Claude and Claude Code folders go to the Recycle Bin. The Claude account itself is not deleted."),
        ["CloseFirst"] = ("Önce bu hesabın Claude'unu kapat.", "Quit this account's Claude first."),
        ["ClaudeMissingTitle"] = ("Claude bulunamadı", "Claude not found"),
        ["ClaudeMissingBody"] = ("Lanes, Claude masaüstü uygulamasıyla çalışır. claude.ai/download adresinden Windows sürümünü kur.",
                                 "Lanes works with the Claude desktop app. Install the Windows version from claude.ai/download."),
        ["StoreTitle"] = ("Microsoft Store sürümü desteklenmiyor", "The Microsoft Store version is not supported"),
        ["StoreBody"] = ("Store'dan kurulan Claude, hesaplara ayrı klasör verilmesine izin vermiyor. Claude'u kaldırıp claude.ai/download adresinden ya da \"winget install Anthropic.Claude\" ile yeniden kur. Hesapların sunucuda kalır, yalnız yeniden giriş yaparsın.",
                         "Claude from the Store does not let accounts have their own folders. Uninstall it and install again from claude.ai/download or with \"winget install Anthropic.Claude\". Your accounts stay on the server; you only sign in again."),
        ["Download"] = ("İndir", "Download"),
        ["Recheck"] = ("Yeniden Denetle", "Check Again"),
        ["MainAccountHint"] = ("Claude'un kendi klasörünü kullanır", "Uses Claude's own folder"),
        ["TrayTip"] = ("Lanes · {0} açık", "Lanes · {0} running"),
        ["Empty"] = ("Henüz hesap yok.", "No accounts yet."),
        ["SignInHint"] = ("Yeni bir hesapta Google ile girişin dönüşü ana hesaba gidebilir. E-posta koduyla giriş her zaman doğru pencerede tamamlanır.",
                          "When signing in to a new account with Google, the return may land in the main account. Signing in with an email code always finishes in the right window."),
    };

    public static string T(string key) => Table.TryGetValue(key, out var v) ? (Turkish ? v.Tr : v.En) : key;
    public static string F(string key, params object[] args) => string.Format(T(key), args);
}
