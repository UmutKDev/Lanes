// Lanes for Safari, Chrome and Edge: background script. Keeps the account list, saves and
// restores claude.ai sessions, and keeps the toolbar badge and menus in step.
"use strict";

if (typeof importScripts === "function" && typeof LanesCore === "undefined") importScripts("lib/core.js");

const api = globalThis.browser || globalThis.chrome;
const C = globalThis.LanesCore;
// Safari ignores the name and talks to the app the extension came in. Chrome
// and Edge look it up among the native hosts Lanes installs (platform.js).
const PLATFORM = globalThis.LanesPlatform || { browser: "safari", nativeHost: "com.umutkdev.Lanes" };
const NATIVE_APP = PLATFORM.nativeHost;
const STATE_KEY = "lanes.state.v1";
const DEFAULT_SETTINGS = {
  stripe: true, // thin bar in the account color at the top of claude.ai
  titleMark: true, // "🟣 İş · " in front of the tab title
  favicon: true, // colored dot on the tab icon
  carryDraft: true, // take the half-written message along when switching
  autoAdd: true, // save every account signed in on claude.ai
};

const t = (key, subs) => (api.i18n && api.i18n.getMessage(key, subs)) || key;

// MARK: State

let stateCache = null;

async function loadState() {
  if (stateCache) return stateCache;
  const stored = (await api.storage.local.get(STATE_KEY))[STATE_KEY] || {};
  stateCache = {
    accounts: Array.isArray(stored.accounts) ? stored.accounts : [],
    activeId: stored.activeId || null,
    settings: Object.assign({}, DEFAULT_SETTINGS, stored.settings || {}),
    capability: stored.capability || "unknown", // "ok" | "hidden" | "unknown"
    vault: stored.vault || "unknown", // "keychain" | "local" | "unknown"
    lanes: stored.lanes || null, // { accounts: [...], updatedAt }
    pendingCheck: stored.pendingCheck || null,
  };
  return stateCache;
}

async function saveState() {
  if (!stateCache) return;
  await api.storage.local.set({ [STATE_KEY]: stateCache });
  refreshBadge();
  rebuildMenus();
  broadcastAppearance();
}

function account(state, id) {
  return state.accounts.find((a) => a.id === id) || null;
}

// One change at a time: a switch must not interleave with an identity
// report or another switch.
let queue = Promise.resolve();
function serial(task) {
  const run = queue.then(task, task);
  queue = run.catch(() => {});
  return run;
}

// MARK: Native bridge (Keychain and Lanes)

async function native(message) {
  if (!api.runtime.sendNativeMessage) throw new Error("no native messaging");
  const reply = await Promise.race([
    api.runtime.sendNativeMessage(NATIVE_APP, message),
    new Promise((_, reject) => setTimeout(() => reject(new Error("native timeout")), 4000)),
  ]);
  if (!reply || reply.ok !== true) throw new Error((reply && reply.error) || "native error");
  return reply;
}

async function vaultSet(id, cookies) {
  const key = "session." + id;
  const value = JSON.stringify({ savedAt: Date.now(), cookies });
  const state = await loadState();
  try {
    await native({ type: "vaultSet", key, value });
    if (state.vault !== "keychain") {
      state.vault = "keychain";
      await api.storage.local.remove("vault." + key);
    }
  } catch (_) {
    // Lanes's native part is missing (for example a development build that
    // Safari runs unsigned). Keep the session in the extension's own storage
    // and say so in Settings.
    state.vault = "local";
    await api.storage.local.set({ ["vault." + key]: value });
  }
}

async function vaultGet(id) {
  const key = "session." + id;
  let value = null;
  try {
    value = (await native({ type: "vaultGet", key })).value || null;
  } catch (_) {
    value = null;
  }
  if (!value) value = (await api.storage.local.get("vault." + key))["vault." + key] || null;
  if (!value) return null;
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed.cookies) ? parsed : null;
  } catch (_) {
    return null;
  }
}

async function vaultDelete(id) {
  const key = "session." + id;
  try {
    await native({ type: "vaultDelete", key });
  } catch (_) {
    // nothing saved there
  }
  await api.storage.local.remove("vault." + key);
}

/// Reads the account list Lanes shares and applies its names and colors to
/// matching web accounts the user has not renamed or recolored.
async function refreshLanes() {
  const state = await loadState();
  try {
    const reply = await native({ type: "lanesAccounts" });
    const list = reply.lanes && Array.isArray(reply.lanes.accounts) ? reply.lanes.accounts : null;
    state.lanes = list ? { accounts: list, updatedAt: reply.lanes.updatedAt || null } : null;
  } catch (_) {
    state.lanes = null;
  }
  applyLanes(state);
  await saveState();
  return state.lanes;
}

function applyLanes(state) {
  const list = state.lanes ? state.lanes.accounts : [];
  for (const acc of state.accounts) {
    const profile = C.findLanesProfile(list, acc);
    acc.lanesName = profile ? profile.name : null;
    if (!profile) continue;
    if (!acc.customColor && C.isColor(profile.color)) acc.color = profile.color;
    if (!acc.customName && profile.name) acc.name = profile.name;
  }
}

// MARK: Cookies

async function claudeCookies(storeId) {
  const query = { domain: C.CLAUDE_HOST };
  if (storeId) query.storeId = storeId;
  const all = await api.cookies.getAll(query);
  return all.filter(C.isClaudeCookie);
}

async function clearClaudeCookies(storeId) {
  for (const cookie of await claudeCookies(storeId)) {
    const details = C.cookieRemoveDetails(cookie);
    try {
      await api.cookies.remove(details);
    } catch (_) {
      // already gone
    }
  }
}

async function restoreCookies(saved, storeId) {
  const now = Date.now() / 1000;
  for (const cookie of saved) {
    const details = C.cookieSetDetails(cookie, now);
    if (!details) continue;
    if (storeId) details.storeId = storeId;
    await api.cookies.set(details);
  }
}

// MARK: Tabs

async function claudeTabs() {
  const tabs = await api.tabs.query({});
  return tabs.filter((tab) => tab.url && C.isClaudeURL(tab.url));
}

async function activeTab() {
  const [tab] = await api.tabs.query({ active: true, currentWindow: true });
  return tab || null;
}

async function draftFrom(tab) {
  if (!tab || !tab.url || !C.isClaudeURL(tab.url)) return "";
  try {
    const reply = await api.tabs.sendMessage(tab.id, { type: "getDraft" });
    return reply && typeof reply.draft === "string" ? reply.draft.trim() : "";
  } catch (_) {
    return "";
  }
}

// MARK: Identity reports from claude.ai pages

async function onIdentity(report) {
  return serial(async () => {
    const state = await loadState();
    const now = Date.now();
    // A switch is checked by the first page that loads after it; adding an
    // account waits up to ten minutes for the sign-in.
    const pending = state.pendingCheck;
    const ttl = pending && pending.adding ? 600000 : 60000;
    const check = pending && now - pending.at < ttl ? pending : null;

    if (!report.signedIn) {
      if (check && check.adding) {
        // Still on the sign-in page.
      } else if (check) {
        // The session we just put back no longer works.
        const target = account(state, check.id);
        if (target) target.status = "expired";
        state.pendingCheck = null;
      } else if (state.activeId) {
        const current = account(state, state.activeId);
        if (current) current.status = "signedOut";
      }
      state.activeId = null;
      await saveState();
      return { account: null, settings: state.settings };
    }

    const identity = report.identity;
    const cookies = await claudeCookies();
    const hasSession = C.hasSessionCookie(cookies);
    state.capability = hasSession ? "ok" : "hidden";

    let acc = C.findAccount(state.accounts, identity);
    if (!acc) {
      if (!state.settings.autoAdd && !(check && check.adding)) {
        await saveState();
        return { account: null, settings: state.settings };
      }
      acc = {
        id: C.newID(),
        uuid: identity.uuid,
        email: identity.email,
        name: identity.name || C.nameFromEmail(identity.email) || "Claude",
        color: C.nextColor(state.accounts.map((a) => a.color)),
        addedAt: now,
      };
      state.accounts.push(acc);
      applyLanes(state);
    }
    if (check && check.id && check.id !== acc.id) {
      // We restored one account and the page shows another: the restored
      // session belongs to someone else now, or was replaced.
      const target = account(state, check.id);
      if (target) target.status = "expired";
    }
    state.pendingCheck = null;
    acc.uuid = identity.uuid || acc.uuid;
    acc.email = identity.email || acc.email;
    acc.orgName = identity.orgName || acc.orgName || "";
    acc.plan = identity.plan || acc.plan || "";
    acc.status = "ok";
    acc.lastSeenAt = now;
    if (state.activeId !== acc.id) {
      state.activeId = acc.id;
      acc.lastUsedAt = now;
    }
    if (hasSession && (!acc.savedAt || now - acc.savedAt > 30000)) {
      await vaultSet(acc.id, cookies.map(C.snapshotCookie));
      acc.savedAt = now;
    }
    await saveState();
    return { account: appearance(acc), settings: state.settings };
  });
}

function appearance(acc) {
  if (!acc) return null;
  return { id: acc.id, name: acc.name, color: acc.color, monogram: C.monogram(acc.name), email: acc.email };
}

// MARK: Switching

async function switchTo(id, options) {
  return serial(async () => {
    const state = await loadState();
    const target = account(state, id);
    if (!target) throw new Error(t("errorNoAccount"));
    if (state.capability === "hidden") throw new Error(t("errorCookiesHidden"));
    const saved = await vaultGet(id);
    if (!saved || !C.hasSessionCookie(saved.cookies)) {
      target.status = "expired";
      await saveState();
      throw new Error(t("errorNoSession", [target.name]));
    }

    // Another app may be signing in with claude.ai in a tab (Claude in
    // Chrome, Claude Code). Swapping the session under it would hand that
    // app the wrong account, so wait until it is done.
    if ((await claudeTabs()).some((tab) => C.isAuthFlowURL(tab.url))) throw new Error(t("errorAuthFlow"));

    const tab = await activeTab();
    const draft = options && typeof options.draft === "string" ? options.draft : state.settings.carryDraft ? await draftFrom(tab) : "";

    // Save the current account's session as it is now: claude.ai renews
    // its cookies, and the saved copy has to be the newest one.
    const current = await claudeCookies();
    if (state.activeId && state.activeId !== id && C.hasSessionCookie(current)) {
      await vaultSet(state.activeId, current.map(C.snapshotCookie));
      const prev = account(state, state.activeId);
      if (prev) prev.savedAt = Date.now();
    }

    await clearClaudeCookies();
    await restoreCookies(saved.cookies);
    const back = await claudeCookies();
    if (!C.hasSessionCookie(back)) {
      state.capability = "hidden";
      await saveState();
      throw new Error(t("errorCookiesHidden"));
    }

    const now = Date.now();
    state.activeId = id;
    target.lastUsedAt = now;
    target.switches = (target.switches || 0) + 1;
    state.pendingCheck = { id, at: now };
    await saveState();
    await moveTabs(tab, draft);
    return { ok: true };
  });
}

/// Sends every claude.ai tab to a page that works for the new account. The
/// tab the user is in gets the draft; with no claude.ai tab open, one opens.
async function moveTabs(current, draft) {
  const tabs = await claudeTabs();
  const focused = current && tabs.find((tab) => tab.id === current.id);
  for (const tab of tabs) {
    if (C.isAuthFlowURL(tab.url)) continue;
    const url = C.urlAfterSwitch(tab.url, tab === focused ? draft : "");
    await api.tabs.update(tab.id, { url });
  }
  if (!focused) {
    const url = C.urlAfterSwitch(C.CLAUDE_ORIGIN + "/new", draft);
    if (current && (C.isBlankTabURL(current.url))) {
      await api.tabs.update(current.id, { url });
    } else {
      await api.tabs.create({ url });
    }
  }
}

/// Saves the current session, signs this browser out of claude.ai and opens
/// the sign-in page, so the next account can be added. The current account
/// stays saved and one click brings it back.
async function addAccount() {
  return serial(async () => {
    const state = await loadState();
    const current = await claudeCookies();
    if (state.activeId && C.hasSessionCookie(current)) {
      await vaultSet(state.activeId, current.map(C.snapshotCookie));
      const prev = account(state, state.activeId);
      if (prev) prev.savedAt = Date.now();
    }
    await clearClaudeCookies();
    state.activeId = null;
    state.pendingCheck = { id: null, at: Date.now(), adding: true };
    await saveState();
    const tab = await activeTab();
    const url = C.CLAUDE_ORIGIN + "/login";
    if (tab && tab.url && C.isClaudeURL(tab.url)) await api.tabs.update(tab.id, { url });
    else await api.tabs.create({ url });
    for (const other of await claudeTabs()) {
      if (C.isAuthFlowURL(other.url)) continue;
      if (!tab || other.id !== tab.id) await api.tabs.update(other.id, { url });
    }
    return { ok: true };
  });
}

async function updateAccount(id, changes) {
  return serial(async () => {
    const state = await loadState();
    const acc = account(state, id);
    if (!acc) throw new Error(t("errorNoAccount"));
    if (typeof changes.name === "string" && changes.name.trim()) {
      acc.name = changes.name.trim().slice(0, 40);
      acc.customName = true;
    }
    if (typeof changes.color === "string" && C.isColor(changes.color)) {
      acc.color = changes.color;
      acc.customColor = true;
    }
    if (typeof changes.pinned === "boolean") acc.pinned = changes.pinned;
    if (typeof changes.agent === "boolean") {
      // One account at most: Claude in Chrome is signed in to one.
      for (const other of state.accounts) other.agent = false;
      acc.agent = changes.agent;
    }
    if (typeof changes.lanesId === "string") {
      acc.lanesId = changes.lanesId || null;
      if (acc.lanesId) {
        acc.customName = false;
        acc.customColor = false;
      }
      applyLanes(state);
    }
    await saveState();
    return { ok: true };
  });
}

/// Forgets an account. For the account in use it also signs this browser
/// out, or the page would add it straight back.
async function removeAccount(id) {
  return serial(async () => {
    const state = await loadState();
    await vaultDelete(id);
    state.accounts = state.accounts.filter((a) => a.id !== id);
    const wasActive = state.activeId === id;
    if (wasActive) {
      await clearClaudeCookies();
      state.activeId = null;
    }
    await saveState();
    if (wasActive) {
      for (const tab of await claudeTabs()) await api.tabs.update(tab.id, { url: C.CLAUDE_ORIGIN + "/login" });
    }
    return { ok: true };
  });
}

async function updateSettings(changes) {
  const state = await loadState();
  for (const key of Object.keys(DEFAULT_SETTINGS)) {
    if (typeof changes[key] === "boolean") state.settings[key] = changes[key];
  }
  await saveState();
  return { ok: true, settings: state.settings };
}

/// The next account after the active one in popup order, for the shortcut.
async function switchNext(step) {
  const state = await loadState();
  const order = C.sortAccounts(state.accounts, null).sort((a, b) => (a.addedAt || 0) - (b.addedAt || 0));
  if (order.length < 2) return;
  const at = order.findIndex((a) => a.id === state.activeId);
  const next = order[(at + (step || 1) + order.length) % order.length];
  await switchTo(next.id, {});
}

async function openInLanes(id) {
  const state = await loadState();
  const acc = account(state, id);
  const profile = acc ? C.findLanesProfile(state.lanes ? state.lanes.accounts : [], acc) : null;
  await native({ type: "openLanes", account: profile ? profile.name : "" });
  return { ok: true };
}

// MARK: Badge, menus, pages

async function refreshBadge() {
  const state = await loadState();
  const acc = account(state, state.activeId);
  const action = api.action || api.browserAction;
  if (!action) return;
  try {
    await action.setBadgeText({ text: acc ? C.monogram(acc.name) : "" });
    if (acc && action.setBadgeBackgroundColor) await action.setBadgeBackgroundColor({ color: C.colorHex(acc.color, false) });
    if (acc && action.setBadgeTextColor) await action.setBadgeTextColor({ color: C.isLightSwatch(acc.color) ? "#000000" : "#FFFFFF" });
    await action.setTitle({ title: acc ? t("badgeTitle", [acc.name, acc.email || ""]) : t("extensionName") });
  } catch (_) {
    // Safari versions without badge colors still show the text.
  }
}

let menuBuild = Promise.resolve();
function rebuildMenus() {
  if (!api.contextMenus) return;
  menuBuild = menuBuild.then(async () => {
    const state = await loadState();
    await api.contextMenus.removeAll();
    if (state.accounts.length === 0 || state.capability === "hidden") return;
    api.contextMenus.create({ id: "ask", title: t("menuAsk"), contexts: ["selection"] });
    for (const acc of C.sortAccounts(state.accounts, state.activeId)) {
      const emoji = (C.COLORS[acc.color] || C.COLORS.gray).emoji;
      const suffix = acc.id === state.activeId ? " " + t("menuCurrent") : "";
      api.contextMenus.create({ id: "ask:" + acc.id, parentId: "ask", title: emoji + " " + acc.name + suffix, contexts: ["selection"] });
    }
  }).catch(() => {});
}

async function broadcastAppearance() {
  const state = await loadState();
  const payload = { type: "appearance", account: appearance(account(state, state.activeId)), settings: state.settings };
  for (const tab of await claudeTabs()) {
    api.tabs.sendMessage(tab.id, payload).catch(() => {});
  }
}

async function publicState() {
  const state = await loadState();
  return {
    accounts: state.accounts.map((a) => Object.assign({}, a, { monogram: C.monogram(a.name) })),
    activeId: state.activeId,
    settings: state.settings,
    capability: state.capability,
    vault: state.vault,
    lanes: state.lanes,
  };
}

// MARK: Wiring

// Replies go through sendResponse: Chrome and Edge ignore a returned
// promise, Safari takes both.
api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const run = async () => {
    switch (message && message.type) {
      case "identity": return onIdentity(message);
      case "hello": {
        const state = await loadState();
        return { account: appearance(account(state, state.activeId)), settings: state.settings };
      }
      case "getState": return publicState();
      case "switch": return switchTo(message.id, { draft: message.draft });
      case "add": return addAccount();
      case "update": return updateAccount(message.id, message.changes || {});
      case "remove": return removeAccount(message.id);
      case "settings": return updateSettings(message.changes || {});
      case "refreshLanes": return refreshLanes().then(publicState);
      case "openLanes": return openInLanes(message.id);
      case "openOptions": return api.runtime.openOptionsPage();
      default: return { ok: false, error: "unknown" };
    }
  };
  run()
    .catch((error) => ({ ok: false, error: String(error && error.message || error) }))
    .then(sendResponse);
  return true;
});

if (api.contextMenus) {
  api.contextMenus.onClicked.addListener((info) => {
    const id = String(info.menuItemId || "");
    if (id.startsWith("ask:")) switchTo(id.slice(4), { draft: info.selectionText || "" }).catch(() => {});
  });
}

if (api.commands) {
  api.commands.onCommand.addListener((command) => {
    if (command === "switch-next") switchNext(1).catch(() => {});
    if (command === "switch-previous") switchNext(-1).catch(() => {});
  });
}

api.runtime.onInstalled && api.runtime.onInstalled.addListener(() => {
  refreshLanes().catch(() => {});
});
api.runtime.onStartup && api.runtime.onStartup.addListener(() => {
  refreshLanes().catch(() => {});
});

loadState().then(() => {
  refreshBadge();
  rebuildMenus();
});
