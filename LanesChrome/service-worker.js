// Lanes for Chrome and Edge: service worker entry. Loads the platform notes,
// then the background script shared with Safari.
importScripts("platform.js", "lib/core.js", "background.js");
