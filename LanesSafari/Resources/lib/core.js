// Pure helpers shared by the background script, the popup, the options page
// and the tests. No browser APIs here, so Node can test every function.
(function (root) {
  "use strict";

  const CLAUDE_HOST = "claude.ai";
  const CLAUDE_ORIGIN = "https://claude.ai";

  // Lanes's account colors (ProfileColor in LanesCore), as macOS system
  // colors in light and dark appearance.
  const COLORS = {
    blue: { light: "#0088FF", dark: "#0091FF", emoji: "🔵" },
    purple: { light: "#CB30E0", dark: "#DB34F2", emoji: "🟣" },
    pink: { light: "#FF2D55", dark: "#FF375F", emoji: "🩷" },
    red: { light: "#FF383C", dark: "#FF4245", emoji: "🔴" },
    orange: { light: "#FF8D28", dark: "#FF9230", emoji: "🟠" },
    yellow: { light: "#FFCC00", dark: "#FFD600", emoji: "🟡" },
    green: { light: "#34C759", dark: "#30D158", emoji: "🟢" },
    mint: { light: "#00C8B3", dark: "#00DAC3", emoji: "🟩" },
    teal: { light: "#00C3D0", dark: "#00D2E0", emoji: "🩵" },
    cyan: { light: "#00C0E8", dark: "#3CD3FE", emoji: "💠" },
    indigo: { light: "#6155F5", dark: "#6D7CFF", emoji: "🟪" },
    brown: { light: "#AC7F5E", dark: "#B78A66", emoji: "🟤" },
    gray: { light: "#8E8E93", dark: "#98989D", emoji: "⚪️" },
  };
  const COLOR_ORDER = ["blue", "purple", "orange", "green", "pink", "teal", "indigo", "red", "yellow", "mint", "cyan", "brown", "gray"];

  function isColor(name) {
    return Object.prototype.hasOwnProperty.call(COLORS, name);
  }

  function colorHex(name, dark) {
    const color = COLORS[isColor(name) ? name : "gray"];
    return dark ? color.dark : color.light;
  }

  /// The first color in COLOR_ORDER no account uses yet, then round robin.
  function nextColor(usedColors) {
    const used = new Set(usedColors || []);
    const free = COLOR_ORDER.find((name) => !used.has(name));
    if (free) return free;
    return COLOR_ORDER[(usedColors || []).length % COLOR_ORDER.length];
  }

  /// Whether white or black text reads better on a swatch.
  function isLightSwatch(name) {
    return name === "yellow" || name === "mint" || name === "teal" || name === "cyan";
  }

  // MARK: Names

  function upperTR(text) {
    return text.replace(/i/g, "İ").replace(/ı/g, "I").toUpperCase();
  }

  /// Up to two letters for an avatar, the way Lanes makes monograms: the
  /// first letters of the first two words, or the first letter alone.
  function monogram(name) {
    const words = String(name || "").trim().split(/\s+/).filter(Boolean);
    if (words.length === 0) return "?";
    const letters = words.length > 1 ? [...words[0]][0] + [...words[1]][0] : [...words[0]][0];
    return upperTR(letters);
  }

  /// A short name for an account found by its e-mail: the part before @,
  /// first letter capitalised.
  function nameFromEmail(email) {
    const local = String(email || "").split("@")[0].replace(/[._-]+/g, " ").trim();
    if (!local) return "";
    return upperTR(local[0]) + local.slice(1);
  }

  function normalizeEmail(email) {
    return String(email || "").trim().toLowerCase();
  }

  // MARK: Identity

  /// Reads who is signed in from claude.ai's /api/account answer. Every
  /// field is optional, so a change on Claude's side degrades to fewer
  /// details instead of a crash. Only identity fields are kept.
  function parseAccount(json) {
    if (!json || typeof json !== "object") return null;
    const account = json.account && typeof json.account === "object" ? json.account : json;
    const uuid = str(account.uuid) || str(account.id);
    const email = str(account.email_address) || str(account.email);
    if (!uuid && !email) return null;
    const memberships = Array.isArray(account.memberships) ? account.memberships : [];
    const orgs = memberships
      .map((m) => (m && typeof m === "object" ? m.organization || m : null))
      .filter((o) => o && typeof o === "object")
      .map((o) => ({ uuid: str(o.uuid), name: str(o.name), plan: planOf(o) }));
    const best = orgs.find((o) => o.plan === "max") || orgs.find((o) => o.plan === "team" || o.plan === "enterprise") || orgs.find((o) => o.plan === "pro") || orgs[0];
    return {
      uuid,
      email: normalizeEmail(email),
      name: str(account.display_name) || str(account.full_name) || nameFromEmail(email),
      fullName: str(account.full_name),
      orgName: best ? best.name : "",
      plan: best ? best.plan : "",
    };
  }

  function planOf(org) {
    const caps = Array.isArray(org.capabilities) ? org.capabilities.map(String) : [];
    const tier = str(org.rate_limit_tier) + " " + str(org.billing_type);
    if (caps.includes("claude_max") || /max/i.test(tier)) return "max";
    if (caps.includes("enterprise") || /enterprise/i.test(tier)) return "enterprise";
    if (caps.includes("raven") || /team/i.test(tier)) return "team";
    if (caps.includes("claude_pro") || /pro/i.test(tier)) return "pro";
    if (caps.length) return "free";
    return "";
  }

  function str(value) {
    return typeof value === "string" ? value.trim() : "";
  }

  /// The saved account a signed-in identity belongs to: same Claude user id
  /// first, then the same e-mail.
  function findAccount(accounts, identity) {
    if (!identity) return null;
    if (identity.uuid) {
      const byID = accounts.find((a) => a.uuid && a.uuid === identity.uuid);
      if (byID) return byID;
    }
    const email = normalizeEmail(identity.email);
    if (email) return accounts.find((a) => normalizeEmail(a.email) === email) || null;
    return null;
  }

  /// The Lanes account (from the list Lanes shares) for a web account: the
  /// one picked by hand, or the one with the same e-mail.
  function findLanesProfile(lanesAccounts, account) {
    if (!account || !Array.isArray(lanesAccounts)) return null;
    if (account.lanesId) {
      const linked = lanesAccounts.find((p) => p.id === account.lanesId);
      if (linked) return linked;
    }
    const email = normalizeEmail(account.email);
    if (!email || account.lanesId === "none") return null;
    return lanesAccounts.find((p) => normalizeEmail(p.email) === email) || null;
  }

  // MARK: Cookies

  /// Whether a cookie belongs to claude.ai (the site itself or a subdomain).
  function isClaudeCookie(cookie) {
    const domain = String(cookie && cookie.domain || "").replace(/^\./, "").toLowerCase();
    return domain === CLAUDE_HOST || domain.endsWith("." + CLAUDE_HOST);
  }

  /// The cookie that keeps someone signed in on claude.ai. Safari hides
  /// HttpOnly cookies from some extension API versions; when it is missing
  /// while the page says someone is signed in, switching can't work.
  function hasSessionCookie(cookies) {
    return (cookies || []).some((c) => c && c.name === "sessionKey" && c.value);
  }

  /// What to save from a cookie: only what cookies.set takes back.
  function snapshotCookie(cookie) {
    const out = {
      name: String(cookie.name),
      value: String(cookie.value),
      domain: String(cookie.domain || ""),
      hostOnly: cookie.hostOnly === true || !String(cookie.domain || "").startsWith("."),
      path: String(cookie.path || "/"),
      secure: cookie.secure === true,
      httpOnly: cookie.httpOnly === true,
      sameSite: ["no_restriction", "lax", "strict"].includes(cookie.sameSite) ? cookie.sameSite : null,
    };
    if (typeof cookie.expirationDate === "number" && cookie.expirationDate > 0) out.expirationDate = cookie.expirationDate;
    return out;
  }

  /// The cookies.set() argument that recreates a saved cookie. Host-only
  /// cookies must leave out `domain`, or they come back as domain cookies.
  /// Expired cookies are dropped (null).
  function cookieSetDetails(saved, nowSeconds) {
    if (saved.expirationDate && nowSeconds && saved.expirationDate <= nowSeconds) return null;
    const host = String(saved.domain || CLAUDE_HOST).replace(/^\./, "");
    const details = {
      url: (saved.secure ? "https://" : "http://") + host + (saved.path || "/"),
      name: saved.name,
      value: saved.value,
      path: saved.path || "/",
      secure: !!saved.secure,
      httpOnly: !!saved.httpOnly,
    };
    if (!saved.hostOnly && saved.domain) details.domain = saved.domain;
    if (saved.sameSite) details.sameSite = saved.sameSite;
    if (saved.expirationDate) details.expirationDate = saved.expirationDate;
    return details;
  }

  /// The cookies.remove() argument for a live cookie.
  function cookieRemoveDetails(cookie) {
    const host = String(cookie.domain || CLAUDE_HOST).replace(/^\./, "");
    const details = { url: (cookie.secure ? "https://" : "http://") + host + (cookie.path || "/"), name: cookie.name };
    if (cookie.storeId) details.storeId = cookie.storeId;
    return details;
  }

  // MARK: Pages

  function isClaudeURL(url) {
    try {
      const u = new URL(url);
      return u.protocol === "https:" && (u.hostname === CLAUDE_HOST || u.hostname.endsWith("." + CLAUDE_HOST));
    } catch (_) {
      return false;
    }
  }

  /// Where a claude.ai tab goes after a switch. Conversations and projects
  /// belong to one account, so they turn into a new chat; settings pages
  /// stay where they are.
  function urlAfterSwitch(url, draft) {
    const fresh = CLAUDE_ORIGIN + "/new" + (draft ? "?q=" + encodeURIComponent(draft) : "");
    if (draft) return fresh;
    try {
      const u = new URL(url);
      if (/^\/(settings|recents|projects)\/?$/.test(u.pathname)) return CLAUDE_ORIGIN + u.pathname;
      if (u.pathname.startsWith("/settings/")) return CLAUDE_ORIGIN + u.pathname;
    } catch (_) {
      // fall through
    }
    return fresh;
  }

  const TITLE_MARK = " · ";

  /// The tab title with the account's mark in front: "🟣 İş · Claude".
  /// Applying twice changes nothing; strip removes it.
  function titleWithMark(title, account) {
    const bare = stripTitleMark(title);
    if (!account) return bare;
    const emoji = (COLORS[account.color] || COLORS.gray).emoji;
    return emoji + " " + account.name + TITLE_MARK + bare;
  }

  function stripTitleMark(title) {
    const text = String(title || "");
    const at = text.indexOf(TITLE_MARK);
    if (at < 0 || at > 64) return text;
    const head = text.slice(0, at);
    const emojis = Object.values(COLORS).map((c) => c.emoji);
    return emojis.some((e) => head.startsWith(e + " ")) ? text.slice(at + TITLE_MARK.length) : text;
  }

  // MARK: Text

  /// "az önce", "5 dk önce", "3 sa önce", "2 gün önce" or the reverse in
  /// English. `t` is the browser.i18n lookup.
  function timeAgo(then, now, t) {
    if (!then) return "";
    const seconds = Math.max(0, Math.round((now - then) / 1000));
    if (seconds < 60) return t("timeJustNow");
    const minutes = Math.round(seconds / 60);
    if (minutes < 60) return t("timeMinutes", [String(minutes)]);
    const hours = Math.round(minutes / 60);
    if (hours < 24) return t("timeHours", [String(hours)]);
    const days = Math.round(hours / 24);
    return t("timeDays", [String(days)]);
  }

  /// Case- and Turkish-i-insensitive search over name, e-mail and org.
  function matchesSearch(account, query) {
    const fold = (s) => String(s || "").toLocaleLowerCase("tr").normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/ı/g, "i");
    const q = fold(query).trim();
    if (!q) return true;
    return [account.name, account.email, account.orgName].some((field) => fold(field).includes(q));
  }

  function newID() {
    const bytes = new Uint8Array(9);
    (root.crypto || require("crypto").webcrypto).getRandomValues(bytes);
    return "a" + Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  }

  /// Accounts in the order the popup shows them: the active one first, then
  /// pinned ones, then by last use.
  function sortAccounts(accounts, activeID) {
    return [...accounts].sort((a, b) => {
      if (a.id === activeID) return -1;
      if (b.id === activeID) return 1;
      if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1;
      return (b.lastUsedAt || 0) - (a.lastUsedAt || 0);
    });
  }

  const LanesCore = {
    CLAUDE_HOST, CLAUDE_ORIGIN, COLORS, COLOR_ORDER,
    isColor, colorHex, nextColor, isLightSwatch,
    monogram, nameFromEmail, normalizeEmail,
    parseAccount, findAccount, findLanesProfile,
    isClaudeCookie, hasSessionCookie, snapshotCookie, cookieSetDetails, cookieRemoveDetails,
    isClaudeURL, urlAfterSwitch, titleWithMark, stripTitleMark,
    timeAgo, matchesSearch, newID, sortAccounts,
  };

  if (typeof module === "object" && module.exports) module.exports = LanesCore;
  root.LanesCore = LanesCore;
})(typeof globalThis !== "undefined" ? globalThis : this);
