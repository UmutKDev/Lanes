# Store listing: Lanes for Chrome and Edge

Same text for the Chrome Web Store and Edge Add-ons. Upload
`lanes-browser-extension.zip` from `scripts/build-browser-extension.sh --store`.

## Basics

- Name: Lanes
- Category: Productivity (Chrome: "Workflow & Planning"; Edge: "Productivity")
- Languages: Türkçe (default), English
- Homepage: https://github.com/UmutKDev/Lanes
- Support: https://github.com/UmutKDev/Lanes/issues
- Privacy policy: https://github.com/UmutKDev/Lanes/blob/main/docs/privacy/browser-extension.md
- Price: free
- Screenshots: `screenshots/store-1-popup-*.png`, `store-2-tab-*.png`, `store-3-settings-*.png` (1280x800)
- Icon: `LanesSafari/Resources/icons/icon-128.png`

## Short description (max 132 characters)

TR: Birden fazla Claude hesabını tek tıkla değiştir. Her hesap kendi rengini taşır, oturumlar cihazında kalır.

EN: Switch between Claude accounts with one click. Each account has its own color, and sessions stay on your device.

## Description (TR)

Lanes, claude.ai'de birden fazla hesap kullananlar için. İş, kişisel ve müşteri hesapları arasında çıkış yapıp yeniden giriş yapmadan tek tıkla geçersin.

- Tek tıkla geçiş: araç çubuğundaki listeden hesabı seç. Açık claude.ai sekmeleri o hesaba geçer.
- Her hesabın rengi: sayfanın üstünde ince bir şerit, sekme başlığında renk ve ad, sekme simgesinde renkli nokta. Hangi hesapta olduğun her an belli.
- Taslağı taşı: yazmakta olduğun mesaj diğer hesapta yeni bir sohbete taşınır.
- Seçili metni bir hesapla sor: sağ tık menüsünden.
- Kısayollar: Alt+Shift+L listeyi açar, Alt+Shift+J ve K sonraki ve önceki hesaba geçer.
- Lanes uygulamasıyla birlikte: Mac'te Lanes kuruluysa oturumlar macOS Anahtar Zinciri'nde saklanır, hesaplar Lanes'teki adını ve rengini alır.
- Claude in Chrome ile birlikte: Claude in Chrome yalnız claude.ai'de kendi hesabı açıkken çalışır. O hesabı işaretlersen başka hesaba geçince Lanes tek tıkla geri dönmeyi önerir.

Gizlilik: Eklenti yalnız claude.ai'de çalışır. Hesabı tanımak için yalnız ad, e-posta ve plan bilgisini okur, sohbetlerini okumaz. Hiçbir sunucuya veri göndermez.

## Description (EN)

Lanes is for people who use more than one account on claude.ai. Switch between work, personal and client accounts with one click, without signing out and back in.

- One-click switching: pick an account from the toolbar list. Open claude.ai tabs move to it.
- A color for every account: a thin bar at the top of the page, the color and name in the tab title, a colored dot on the tab icon. You always know which account you're in.
- Carry your draft: the message you're typing moves to a new chat in the other account.
- Ask with an account: right-click selected text.
- Shortcuts: Alt+Shift+L opens the list, Alt+Shift+J and K switch to the next and previous account.
- Works with the Lanes app: with Lanes installed on your Mac, sessions are kept in the macOS Keychain and accounts take their names and colors from Lanes.
- Works alongside Claude in Chrome: Claude in Chrome only works while claude.ai is signed in to its own account. Mark that account and Lanes offers a one-click way back when you switch away.

Privacy: the extension runs only on claude.ai. To recognize an account it reads only the name, e-mail and plan, never your chats. It sends no data to any server.

## Permission justifications (Chrome Web Store "Privacy practices" tab)

- Single purpose: Switch between the user's own claude.ai accounts and show which account a claude.ai tab uses.
- cookies: Saves and restores the claude.ai session cookies of each account the user added, which is how an account switch works. Only claude.ai cookies are read or changed.
- storage: Keeps the account list (names, colors, e-mails) and settings, and saved sessions when the Lanes app isn't installed.
- tabs: Finds open claude.ai tabs to reload them after a switch, and reads the current tab's address to carry the draft.
- contextMenus: The "Ask Claude" menu for selected text.
- nativeMessaging: Talks to the Lanes Mac app, which keeps saved sessions in the macOS Keychain and shares account names and colors.
- Host permission https://claude.ai/*: The content script reads who is signed in (name, e-mail, plan from claude.ai/api/account) and draws the account color on the page.
- Remote code: No. All code is in the package.

## Data usage disclosure

Collected: "Authentication information" (claude.ai session cookies) and "Personally identifiable information" (name and e-mail of the user's own Claude accounts). Both stay on the device (Keychain or extension storage), are never sold, never transferred, never used for anything but switching accounts.

## Edge Add-ons notes

- Same ZIP and texts. Edge Partner Center is free.
- "Notes for certification": The extension needs a claude.ai account to use. Sign in on claude.ai, then use the toolbar list; "Add Account" signs out so a second account can sign in. The native host is optional (Lanes Mac app); without it sessions are kept in extension storage.
