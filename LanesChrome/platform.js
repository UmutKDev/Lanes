// Lanes for Chrome and Edge: what differs from Safari. The rest of the
// extension is LanesSafari/Resources, shared as it is.
globalThis.LanesPlatform = {
  browser: "chromium",
  // Native messaging host Lanes installs into Chrome's and Edge's
  // NativeMessagingHosts folders (Lanes/Platform/BrowserExtensionBridge.swift).
  // It keeps saved sessions in the macOS Keychain and reads Lanes's account
  // list. Without it, sessions stay in the extension's own storage.
  nativeHost: "com.umutkdev.lanes",
};
