#!/usr/bin/env python3
"""Writes the Chrome and Edge parts that differ from Safari:

- _locales/{tr,en}/messages.json: the Safari table (LanesSafari/Tests/
  make-locales.py) with the lines that name Safari or its settings rewritten.
- icons/toolbar-*.png: Chrome doesn't tint toolbar icons the way Safari does,
  so the toolbar shows the colored app icon.

Run after editing either table: python3 LanesChrome/tools/make-assets.py
(icons need Pillow; locales alone run without it)."""
import importlib.util
import json
import pathlib
import sys

sys.dont_write_bytecode = True

here = pathlib.Path(__file__).resolve().parent
chrome = here.parent
repo = chrome.parent

# The Safari script writes its own files when loaded; that is harmless (same
# output) and keeps the two tables from drifting apart.
spec = importlib.util.spec_from_file_location("safari_locales", repo / "LanesSafari" / "Tests" / "make-locales.py")
safari = importlib.util.module_from_spec(spec)
spec.loader.exec_module(safari)
M = dict(safari.M)

OVERRIDES = {
    "extensionDescription": (
        "Birden fazla Claude hesabını Chrome ve Edge'de tek tıkla değiştir. Her hesap kendi rengini taşır, oturumlar Lanes ile Anahtar Zinciri'nde saklanır.",
        "Switch between Claude accounts in Chrome and Edge with one click. Each account has its own color, and with Lanes installed sessions are kept in the Keychain.",
    ),
    "errorCookiesHidden": (
        "Tarayıcı oturum çerezini eklentiye göstermiyor, bu yüzden hesap değiştirilemiyor.",
        "The browser doesn't show the session cookie to the extension, so accounts can't be switched.",
    ),
    "hiddenTitle": ("Tarayıcı hesap değiştirmeye izin vermiyor", "The browser doesn't allow switching"),
    "hiddenBody": (
        "Oturum çerezi eklentiye görünmüyor. Hesap rengi ve sekme işareti çalışmaya devam eder. Hesapları aynı anda kullanmak için her hesaba ayrı bir tarayıcı profili aç.",
        "The session cookie is hidden from the extension. Account colors and tab marks still work. To use accounts side by side, give each one its own browser profile.",
    ),
    "optionsTitle": ("Lanes Tarayıcı Eklentisi", "Lanes for Chrome and Edge"),
    "optionsSubtitle": (
        "Claude hesaplarını Chrome ve Edge'de tek tıkla değiştir.",
        "Switch Claude accounts in Chrome and Edge with one click.",
    ),
    "statusSwitchOKBody": (
        "Geçiş, bu tarayıcı profilindeki tüm claude.ai sekmelerini seçilen hesaba taşır.",
        "A switch moves every claude.ai tab in this browser profile to the chosen account.",
    ),
    "statusSwitchUnknownBody": (
        "claude.ai'yi bir kez aç, Lanes geçişin çalışıp çalışmadığına baksın.",
        "Open claude.ai once so Lanes can check that switching works.",
    ),
    "statusVaultLocal": ("Oturumlar tarayıcıda saklanıyor", "Sessions are kept in the browser"),
    "statusVaultLocalBody": (
        "Lanes uygulamasına ulaşılamadı. Oturumlar şimdilik eklentinin kendi deposunda. Lanes 1.1 ya da sonrasını kurup bir kez aç, oturumlar Anahtar Zinciri'ne taşınır.",
        "The Lanes app couldn't be reached, so sessions are in the extension's own storage for now. Install Lanes 1.1 or later and open it once to move them to the Keychain.",
    ),
    "statusNoLanesBody": (
        "Lanes'i kurup aç. Hesap listesini eklentiyle paylaşır, böylece adlar ve renkler eşleşir.",
        "Install and open Lanes. It shares its account list with the extension so names and colors match.",
    ),
    "privacy2": (
        "Her hesabın oturum çerezleri Lanes kuruluysa macOS Anahtar Zinciri'nde, değilse eklentinin kendi deposunda saklanır. Hiçbir sunucuya gönderilmez.",
        "Each account's session cookies are kept in the macOS Keychain when Lanes is installed, otherwise in the extension's own storage. They are never sent to any server.",
    ),
    "tipTitle": ("İki hesabı aynı anda kullanmak", "Using two accounts at once"),
    "tipBody": (
        "Bir tarayıcı profilinde aynı anda tek Claude hesabı açık olabilir. İki hesabı yan yana kullanmak için ikinci bir Chrome ya da Edge profili aç ve eklentiyi orada da kur. Claude in Chrome kendi girişini tutar, geçişten etkilenmez.",
        "A browser profile has one Claude account signed in at a time. To use two side by side, add a second Chrome or Edge profile and install the extension there too. Claude in Chrome keeps its own sign-in and isn't affected by switching.",
    ),
}
for key in OVERRIDES:
    if key not in M:
        sys.exit(f"unknown key {key}: the Safari table changed")
M.update(OVERRIDES)

for key, (tr, en) in M.items():
    if "Safari" in tr or "Safari" in en:
        sys.exit(f"{key} still names Safari: add it to OVERRIDES")

for index, lang in enumerate(["tr", "en"]):
    out = {key: {"message": value[index]} for key, value in sorted(M.items())}
    folder = chrome / "_locales" / lang
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "messages.json").write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

try:
    from PIL import Image
except ImportError:
    print("locales ok, icons skipped (no Pillow)")
    sys.exit(0)
app = Image.open(repo / "scripts" / "AppIcon-1024.png").convert("RGBA")
icons = chrome / "icons"
icons.mkdir(exist_ok=True)
for size in (16, 32):
    app.resize((size, size), Image.LANCZOS).save(icons / f"toolbar-{size}.png", optimize=True)
print("ok", len(M))
