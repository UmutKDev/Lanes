# Lanes for Chrome and Edge

The Safari extension's twin for Chrome, Edge and other Chrome-based browsers:
switch claude.ai accounts with one click, each account in its own color.

Edge: [Edge Add-ons](https://microsoftedge.microsoft.com/addons/detail/lanes/oibhpcchenilokfnhhdlfbconbieibgd)
(ID `oibhpcchenilokfnhhdlfbconbieibgd`). Chrome Web Store: not listed yet.

## What's where

- `LanesSafari/Resources`: the web code both extensions share (background,
  content script, popup, settings, `lib/core.js`). Change behavior there.
- `LanesChrome`: only what differs. `manifest.json` (with a development key,
  so the unpacked extension always has the ID
  `gfddmgggahfmohadmaohjddpkhfnfaeg`), `platform.js` (native host name),
  `service-worker.js`, texts (`_locales`, made by `tools/make-assets.py` from
  the Safari table with the Safari lines rewritten) and the colored toolbar
  icon.
- `LanesBrowserHost/main.swift` + `Packages/LanesCore/.../BrowserNativeHost.swift`:
  the native messaging host `lanes-browser-host` inside Lanes.app. It keeps
  saved sessions in the Keychain (service `com.umutkdev.Lanes.Browser.sessions`),
  hands over Lanes's account list and opens `lanes://` links.
- `Lanes/Platform/BrowserExtensionBridge.swift`: Lanes writes
  `com.umutkdev.lanes.json` into the `NativeMessagingHosts` folder of every
  installed Chrome-based browser at launch, and `BrowserAccounts.json` into
  its own folder.

## Build and test

```sh
scripts/build-browser-extension.sh build/LanesBrowser       # unpacked, for Load unpacked
scripts/build-browser-extension.sh --store lanes.zip        # store upload, no key
node --test LanesSafari/Tests/*.test.js                     # shared logic
node LanesChrome/tools/e2e-test.js                          # real Chromium, fake claude.ai
node LanesChrome/tools/screenshots.js LanesChrome/store/screenshots tr
```

Lanes.app also carries the unpacked extension in
`Contents/Resources/BrowserExtension`; Settings > Integrations has a button
that shows it and opens the browser's extensions page.

## Claude in Chrome

Claude in Chrome signs in with its own OAuth flow on `claude.ai/oauth/...`
and keeps its own sign-in: switching the claude.ai web session doesn't change
or end it. But it refuses to work while claude.ai is signed in to another
account ("Claude in Chrome uses a different account"), and no extension can
change its account. Tested in Edge 156 on 2 November 2026. So the user marks
the account Claude in Chrome uses ("Claude in Chrome bu hesapta" in the
account sheet), and the popup shows a "switch back" banner while another
account is active. Besides that, the extension:

- touches only claude.ai cookies, never anthropic.com, claude.com or other
  extensions' storage,
- never reloads a `claude.ai/oauth/...` tab, and refuses to switch while
  one is open (an app is signing in and would get the wrong account),
- asks for no permission beyond `https://claude.ai/*`.

Accounts used at the same time (each with its own Claude in Chrome) belong in
separate browser profiles.

## Store IDs

The Chrome Web Store and Edge Add-ons each give the extension their own ID.
Add both to `BrowserNativeHost.storeExtensionIDs` once the listings exist,
or the store copies can't reach the Keychain (they fall back to the
extension's own storage).
