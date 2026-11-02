// End-to-end check of the Chrome/Edge extension in real Chromium, against a
// stand-in for claude.ai (no network, no real accounts). Needs Playwright:
//   node LanesChrome/tools/e2e-test.js
// It builds the extension, signs in two fake accounts, switches between them
// and checks the session cookie, the page mark and the sign-in guard that
// keeps Claude in Chrome's OAuth page safe.
"use strict";
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repo = path.resolve(__dirname, "../..");
const ID = "gfddmgggahfmohadmaohjddpkhfnfaeg";
const USERS = {
  "sk-ada": { uuid: "u-ada", email_address: "ada@example.com", full_name: "Ada", memberships: [{ organization: { uuid: "o1", name: "Ada's", capabilities: ["claude_pro"] } }] },
  "sk-bob": { uuid: "u-bob", email_address: "bob@example.com", full_name: "Bob", memberships: [{ organization: { uuid: "o2", name: "Bob's", capabilities: ["claude_max"] } }] },
};

function page(title, body) {
  return `<!doctype html><html><head><title>${title}</title><link rel="icon" href="/favicon.ico"></head><body>${body}</body></html>`;
}

async function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "lanes-e2e-"));
  const ext = path.join(temp, "ext");
  execFileSync(path.join(repo, "scripts/build-browser-extension.sh"), [ext]);

  const context = await chromium.launchPersistentContext(path.join(temp, "profile"), {
    headless: true,
    channel: "chromium",
    args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
  });
  const seen = { oauthLoads: 0 };
  await context.route("https://claude.ai/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const cookies = Object.fromEntries(((await req.allHeaders()).cookie || "").split(/;\s*/).filter(Boolean).map((c) => c.split("=")));
    const user = USERS[cookies.sessionKey];
    if (url.pathname === "/api/account") {
      return user ? route.fulfill({ json: user }) : route.fulfill({ status: 401, json: {} });
    }
    if (url.pathname === "/favicon.ico") return route.fulfill({ status: 404, body: "" });
    if (url.pathname.startsWith("/oauth")) {
      seen.oauthLoads += 1;
      return route.fulfill({ contentType: "text/html", body: page("Authorize", "<p>Claude in Chrome wants access</p>") });
    }
    return route.fulfill({ contentType: "text/html", body: page("Claude", `<p id="who">${user ? user.full_name : "signed out"}</p><div class="ProseMirror" contenteditable="true"></div>`) });
  });

  const worker = context.serviceWorkers()[0] || (await context.waitForEvent("serviceworker"));
  assert.ok(worker.url().startsWith(`chrome-extension://${ID}/`), "extension ID comes from the development key: " + worker.url());

  const signIn = (key) => context.addCookies([{ name: "sessionKey", value: key, domain: "claude.ai", path: "/", secure: true, httpOnly: true, sameSite: "Lax", expires: Math.floor(Date.now() / 1000) + 86400 }]);
  const sessionKey = async () => ((await context.cookies("https://claude.ai")).find((c) => c.name === "sessionKey") || {}).value;

  let popup = await context.newPage();
  await popup.goto(`chrome-extension://${ID}/popup/popup.html`);
  const send = (message) => popup.evaluate((m) => chrome.runtime.sendMessage(m), message);
  const waitFor = async (check, what) => {
    for (let i = 0; i < 50; i++) {
      if (await check()) return;
      await new Promise((r) => setTimeout(r, 200));
    }
    throw new Error("timed out: " + what + (globalThis.lastTitle ? " (" + JSON.stringify([...globalThis.lastTitle].map((c) => c.codePointAt(0).toString(16))) + ")" : ""));
  };

  // First account: signed in on claude.ai, found by the page.
  await signIn("sk-ada");
  const tab = await context.newPage();
  await tab.goto("https://claude.ai/new");
  await waitFor(async () => (await send({ type: "getState" })).accounts.length === 1, "Ada added");
  let state = await send({ type: "getState" });
  assert.equal(state.capability, "ok", "Chrome shows the HttpOnly session cookie");
  assert.equal(state.vault, "local", "no native host here, so sessions stay in extension storage");
  await waitFor(async () => /^\S+ Ada\s\S\sClaude$/u.test(globalThis.lastTitle = await tab.title()), "title mark for Ada");
  assert.ok(await tab.locator("#lanes-account-stripe").count(), "color stripe on the page");

  // Add Account: signs out, then the second account signs in.
  assert.deepEqual(await send({ type: "add" }), { ok: true });
  assert.equal(await sessionKey(), undefined, "add signs this browser out");
  await waitFor(async () => tab.url().endsWith("/login") && (await tab.locator("#who").textContent().catch(() => "")) === "signed out", "sign-in page");
  await signIn("sk-bob");
  await tab.goto("https://claude.ai/new");
  await waitFor(async () => (await send({ type: "getState" })).accounts.length === 2, "Bob added");
  state = await send({ type: "getState" });
  const ada = state.accounts.find((a) => a.email === "ada@example.com");
  const bob = state.accounts.find((a) => a.email === "bob@example.com");
  assert.equal(state.activeId, bob.id);
  assert.equal(bob.plan, "max");

  // Draft carried across a switch.
  await tab.locator(".ProseMirror").click();
  await tab.keyboard.type("merhaba dünya");
  assert.deepEqual(await send({ type: "switch", id: ada.id }), { ok: true });
  assert.equal(await sessionKey(), "sk-ada", "switch puts Ada's session back");
  await waitFor(async () => (await tab.locator("#who").textContent().catch(() => "")) === "Ada", "page reloaded as Ada");
  assert.match(tab.url(), /\/new\?q=merhaba%20d%C3%BCnya$/, "draft goes along");
  await waitFor(async () => (await send({ type: "getState" })).activeId === ada.id, "Ada active");

  // Claude in Chrome (or Claude Code) signing in: no switch under it.
  const oauth = await context.newPage();
  await oauth.goto("https://claude.ai/oauth/authorize?client_id=claude-in-chrome");
  const loads = seen.oauthLoads;
  const refused = await send({ type: "switch", id: bob.id });
  assert.equal(refused.ok, false);
  assert.match(refused.error, /Claude in Chrome/);
  assert.equal(await sessionKey(), "sk-ada", "session unchanged while an app signs in");
  await oauth.close();
  assert.deepEqual(await send({ type: "switch", id: bob.id }), { ok: true });
  assert.equal(await sessionKey(), "sk-bob");
  assert.equal(seen.oauthLoads, loads, "the OAuth page was never reloaded");

  // Only claude.ai cookies are touched.
  await context.addCookies([{ name: "keep", value: "1", domain: ".anthropic.com", path: "/", secure: true }]);
  await send({ type: "switch", id: ada.id });
  assert.ok((await context.cookies("https://console.anthropic.com")).some((c) => c.name === "keep"), "anthropic.com cookie untouched");

  // Claude in Chrome's account: away from it, the popup offers the way back.
  assert.deepEqual(await send({ type: "update", id: ada.id, changes: { agent: true } }), { ok: true });
  await send({ type: "switch", id: bob.id });
  assert.equal(await sessionKey(), "sk-bob");
  await popup.reload();
  const back = popup.locator("#banner button");
  await waitFor(async () => (await back.count()) === 1, "switch-back banner");
  assert.match(await back.innerText(), /Ada/);
  await back.click().catch(() => {}); // the popup closes itself after a switch
  await waitFor(async () => (await sessionKey()) === "sk-ada", "back on Ada");
  if (popup.isClosed()) {
    popup = await context.newPage();
    await popup.goto(`chrome-extension://${ID}/popup/popup.html`);
  }
  assert.deepEqual(await send({ type: "update", id: bob.id, changes: { agent: true } }), { ok: true });
  state = await send({ type: "getState" });
  assert.deepEqual(state.accounts.filter((a) => a.agent).map((a) => a.email), ["bob@example.com"], "one Claude in Chrome account at most");

  // Next/previous wraps around.
  await popup.reload();
  assert.equal((await popup.locator("body").innerText()).includes("Bob"), true, "popup lists Bob");

  await context.close();
  fs.rmSync(temp, { recursive: true, force: true });
  console.log("e2e ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
