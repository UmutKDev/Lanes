// Tests for LanesSafari/Resources/lib/core.js. Run: node --test LanesSafari/Tests
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const C = require("../Resources/lib/core.js");

test("monogram follows Lanes, Turkish i included", () => {
  assert.equal(C.monogram("iş"), "İ");
  assert.equal(C.monogram("Müşteri Ali"), "MA");
  assert.equal(C.monogram("  "), "?");
  assert.equal(C.monogram("ılık"), "I");
});

test("parseAccount keeps only identity fields and picks the best plan", () => {
  const parsed = C.parseAccount({
    uuid: "u-1",
    email_address: "Ada@Example.com ",
    full_name: "Ada Lovelace",
    display_name: "Ada",
    secret: "x",
    memberships: [
      { organization: { uuid: "o1", name: "ada's Organization", capabilities: ["chat"] } },
      { organization: { uuid: "o2", name: "Acme", capabilities: ["chat", "claude_max"] } },
    ],
  });
  assert.deepEqual(parsed, { uuid: "u-1", email: "ada@example.com", name: "Ada", fullName: "Ada Lovelace", orgName: "Acme", plan: "max" });
});

test("parseAccount survives missing or odd fields", () => {
  assert.equal(C.parseAccount(null), null);
  assert.equal(C.parseAccount({}), null);
  assert.equal(C.parseAccount({ memberships: "nope" }), null);
  const parsed = C.parseAccount({ account: { email: "deniz.kaya@x.io" } });
  assert.equal(parsed.name, "Deniz kaya");
  assert.equal(parsed.plan, "");
});

test("findAccount prefers the Claude user id, then the e-mail", () => {
  const accounts = [{ id: "a", uuid: "u1", email: "a@x.io" }, { id: "b", email: "b@x.io" }];
  assert.equal(C.findAccount(accounts, { uuid: "u1", email: "other@x.io" }).id, "a");
  assert.equal(C.findAccount(accounts, { uuid: "u9", email: "B@x.io" }).id, "b");
  assert.equal(C.findAccount(accounts, { uuid: "u9", email: "c@x.io" }), null);
});

test("findLanesProfile: manual link, e-mail match, or none", () => {
  const lanes = [{ id: "p1", name: "İş", email: "work@x.io" }, { id: "p2", name: "Kişisel", email: "me@x.io" }];
  assert.equal(C.findLanesProfile(lanes, { email: "ME@x.io" }).id, "p2");
  assert.equal(C.findLanesProfile(lanes, { email: "me@x.io", lanesId: "p1" }).id, "p1");
  assert.equal(C.findLanesProfile(lanes, { email: "me@x.io", lanesId: "none" }), null);
  assert.equal(C.findLanesProfile(null, { email: "me@x.io" }), null);
});

test("cookies round-trip into cookies.set details", () => {
  const live = { name: "sessionKey", value: "sk", domain: ".claude.ai", hostOnly: false, path: "/", secure: true, httpOnly: true, sameSite: "lax", expirationDate: 2000000000, storeId: "0" };
  const saved = C.snapshotCookie(live);
  assert.equal(saved.storeId, undefined);
  const details = C.cookieSetDetails(saved, 1700000000);
  assert.deepEqual(details, { url: "https://claude.ai/", name: "sessionKey", value: "sk", path: "/", secure: true, httpOnly: true, domain: ".claude.ai", sameSite: "lax", expirationDate: 2000000000 });
});

test("host-only cookies leave out domain; session cookies leave out expiry", () => {
  const saved = C.snapshotCookie({ name: "lastActiveOrg", value: "o", domain: "claude.ai", path: "/", secure: true, httpOnly: false, sameSite: "unspecified" });
  assert.equal(saved.hostOnly, true);
  const details = C.cookieSetDetails(saved, 1);
  assert.equal(details.domain, undefined);
  assert.equal(details.sameSite, undefined);
  assert.equal(details.expirationDate, undefined);
});

test("expired cookies are not restored", () => {
  const saved = C.snapshotCookie({ name: "a", value: "b", domain: ".claude.ai", path: "/", secure: true, expirationDate: 100 });
  assert.equal(C.cookieSetDetails(saved, 200), null);
});

test("cookie helpers", () => {
  assert.ok(C.isClaudeCookie({ domain: ".claude.ai" }));
  assert.ok(C.isClaudeCookie({ domain: "claude.ai" }));
  assert.ok(!C.isClaudeCookie({ domain: "notclaude.ai" }));
  assert.ok(C.hasSessionCookie([{ name: "sessionKey", value: "x" }]));
  assert.ok(!C.hasSessionCookie([{ name: "sessionKey", value: "" }]));
  assert.deepEqual(C.cookieRemoveDetails({ name: "a", domain: ".claude.ai", path: "/x", secure: true, storeId: "1" }), { url: "https://claude.ai/x", name: "a", storeId: "1" });
});

test("urlAfterSwitch: chats become a new chat, settings stay, drafts travel", () => {
  assert.equal(C.urlAfterSwitch("https://claude.ai/chat/123"), "https://claude.ai/new");
  assert.equal(C.urlAfterSwitch("https://claude.ai/settings/billing"), "https://claude.ai/settings/billing");
  assert.equal(C.urlAfterSwitch("https://claude.ai/projects"), "https://claude.ai/projects");
  assert.equal(C.urlAfterSwitch("https://claude.ai/chat/1", "merhaba dünya & co"), "https://claude.ai/new?q=merhaba%20d%C3%BCnya%20%26%20co");
  assert.equal(C.urlAfterSwitch("garbage"), "https://claude.ai/new");
});

test("isClaudeURL", () => {
  assert.ok(C.isClaudeURL("https://claude.ai/new"));
  assert.ok(!C.isClaudeURL("http://claude.ai/new"));
  assert.ok(!C.isClaudeURL("https://claude.ai.evil.com/"));
  assert.ok(!C.isClaudeURL("not a url"));
});

test("title mark applies once and strips cleanly", () => {
  const acc = { name: "İş", color: "purple" };
  const once = C.titleWithMark("Claude", acc);
  assert.equal(once, "🟣 İş · Claude");
  assert.equal(C.titleWithMark(once, acc), once);
  assert.equal(C.titleWithMark(once, { name: "Ev", color: "green" }), "🟢 Ev · Claude");
  assert.equal(C.stripTitleMark(once), "Claude");
  assert.equal(C.stripTitleMark("A · B"), "A · B");
});

test("colors", () => {
  assert.equal(C.nextColor([]), "blue");
  assert.equal(C.nextColor(["blue", "purple"]), "orange");
  assert.ok(C.isColor(C.nextColor(C.COLOR_ORDER)));
  assert.equal(C.colorHex("nope", false), C.COLORS.gray.light);
  assert.deepEqual(Object.keys(C.COLORS).sort(), [...C.COLOR_ORDER].sort());
});

test("Lanes's ProfileColor and the extension's colors are the same set", () => {
  const swift = fs.readFileSync(path.join(__dirname, "../../Packages/LanesCore/Sources/LanesCore/Profile.swift"), "utf8");
  const line = swift.match(/enum ProfileColor[^{]*\{\s*case ([^\n]+)/)[1];
  const names = line.split(",").map((s) => s.trim());
  assert.deepEqual([...names].sort(), Object.keys(C.COLORS).sort());
});

test("timeAgo and search", () => {
  const t = (key, subs) => key + (subs ? ":" + subs.join(",") : "");
  assert.equal(C.timeAgo(0, 1000, t), "");
  assert.equal(C.timeAgo(1000, 30000, t), "timeJustNow");
  assert.equal(C.timeAgo(1, 5 * 60000, t), "timeMinutes:5");
  assert.equal(C.timeAgo(1, 3 * 3600000, t), "timeHours:3");
  assert.equal(C.timeAgo(1, 2 * 86400000, t), "timeDays:2");
  assert.ok(C.matchesSearch({ name: "İŞ", email: "" }, "iş"));
  assert.ok(C.matchesSearch({ name: "Kişisel", email: "me@x.io" }, "ME@"));
  assert.ok(!C.matchesSearch({ name: "A", email: "b" }, "zzz"));
});

test("sortAccounts: active, pinned, then recent", () => {
  const list = [{ id: "a", lastUsedAt: 1 }, { id: "b", lastUsedAt: 5 }, { id: "c", pinned: true, lastUsedAt: 0 }, { id: "d", lastUsedAt: 9 }];
  assert.deepEqual(C.sortAccounts(list, "a").map((a) => a.id), ["a", "c", "d", "b"]);
});

test("newID is unique and safe as a Keychain key", () => {
  const ids = new Set(Array.from({ length: 200 }, () => C.newID()));
  assert.equal(ids.size, 200);
  for (const id of ids) assert.match("session." + id, /^session\.[a-z0-9]+$/);
});

test("both locales have the same keys, and every key in use exists", () => {
  const root = path.join(__dirname, "../Resources");
  const tr = JSON.parse(fs.readFileSync(path.join(root, "_locales/tr/messages.json"), "utf8"));
  const en = JSON.parse(fs.readFileSync(path.join(root, "_locales/en/messages.json"), "utf8"));
  assert.deepEqual(Object.keys(tr).sort(), Object.keys(en).sort());
  const files = ["background.js", "content.js", "popup/popup.html", "popup/popup.js", "options/options.html", "options/options.js", "ui/ui.js", "manifest.json"];
  const used = new Set();
  for (const file of files) {
    const text = fs.readFileSync(path.join(root, file), "utf8");
    for (const m of text.matchAll(/data-i18n(?:-title|-placeholder)?="([A-Za-z_]+)"/g)) used.add(m[1]);
    for (const m of text.matchAll(/\bt\("([A-Za-z_]+)"[,)]/g)) used.add(m[1]);
    for (const m of text.matchAll(/__MSG_([A-Za-z_]+)__/g)) used.add(m[1]);
  }
  for (const key of used) assert.ok(tr[key], "missing locale key " + key);
  for (const name of Object.keys(C.COLORS)) assert.ok(tr["color_" + name], "missing color name " + name);
});

test("manifest version follows Lanes's MARKETING_VERSION", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "../Resources/manifest.json"), "utf8"));
  const yml = fs.readFileSync(path.join(__dirname, "../../project.yml"), "utf8");
  const version = yml.match(/MARKETING_VERSION: "([^"]+)"/)[1];
  assert.equal(manifest.version, version);
});

test("sign-in pages of other apps are left alone", () => {
  assert.equal(C.isAuthFlowURL("https://claude.ai/oauth/authorize?client_id=x"), true);
  assert.equal(C.isAuthFlowURL("https://claude.ai/oauth"), true);
  assert.equal(C.isAuthFlowURL("https://claude.ai/oauthx"), false);
  assert.equal(C.isAuthFlowURL("https://claude.ai/new"), false);
  assert.equal(C.isAuthFlowURL("https://example.com/oauth/authorize"), false);
});

test("empty new tabs are recognized in every browser", () => {
  for (const url of ["", "about:blank", "favorites://", "chrome://newtab/", "edge://newtab/", "brave://newtab/", "chrome-search://local-ntp/local-ntp.html"]) {
    assert.equal(C.isBlankTabURL(url), true, url);
  }
  assert.equal(C.isBlankTabURL("chrome://extensions/"), false);
  assert.equal(C.isBlankTabURL("https://claude.ai/new"), false);
});
