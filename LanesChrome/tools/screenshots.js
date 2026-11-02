// Store screenshots (1280x800) of the popup and a marked claude.ai tab, with
// made-up accounts on a stand-in claude.ai. Needs Playwright and Pillow:
//   node LanesChrome/tools/screenshots.js <out-folder> [tr|en]
"use strict";
const { chromium } = require("playwright");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repo = path.resolve(__dirname, "../..");
const ID = "gfddmgggahfmohadmaohjddpkhfnfaeg";
const out = path.resolve(process.argv[2] || "screenshots");
const lang = process.argv[3] || "tr";
const people = lang === "tr"
  ? [["sk-1", "İş", "is@ornek.com", "claude_max"], ["sk-2", "Kişisel", "ben@ornek.com", "claude_pro"], ["sk-3", "Müşteri", "musteri@ornek.com", "raven"]]
  : [["sk-1", "Work", "work@example.com", "claude_max"], ["sk-2", "Personal", "me@example.com", "claude_pro"], ["sk-3", "Client", "client@example.com", "raven"]];
const USERS = Object.fromEntries(people.map(([key, name, email, cap]) => [key, { uuid: "u-" + key, email_address: email, full_name: name, memberships: [{ organization: { uuid: "o-" + key, name, capabilities: [cap] } }] }]));

const claudePage = (name) => `<!doctype html><html><head><meta charset="utf-8"><title>Claude</title><style>
body{margin:0;font:15px/1.5 -apple-system,system-ui,sans-serif;background:#faf9f5;color:#3d3929;display:flex;height:100vh}
aside{width:250px;background:#f0eee6;padding:20px;box-sizing:border-box}aside div{height:12px;border-radius:6px;background:#e3e0d5;margin:14px 0}
main{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center}h1{font:400 34px Georgia,serif;margin:0 0 28px}
.box{width:640px;min-height:110px;background:#fff;border:1px solid #e3e0d5;border-radius:18px;padding:18px;box-sizing:border-box;color:#8a8577}
</style></head><body><aside><div></div><div style="width:70%"></div><div style="width:85%"></div><div style="width:60%"></div></aside>
<main><h1>${lang === "tr" ? "Merhaba" : "Hello"}, ${name}</h1><div class="box ProseMirror" contenteditable="true"></div></main></body></html>`;

async function main() {
  fs.mkdirSync(out, { recursive: true });
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "lanes-shots-"));
  const ext = path.join(temp, "ext");
  execFileSync(path.join(repo, "scripts/build-browser-extension.sh"), [ext]);
  const context = await chromium.launchPersistentContext(path.join(temp, "profile"), {
    headless: true,
    channel: "chromium",
    locale: lang === "tr" ? "tr-TR" : "en-US",
    args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`, `--lang=${lang}`],
    viewport: { width: 1280, height: 800 },
    env: { ...process.env, LANGUAGE: lang, LANG: lang === "tr" ? "tr_TR.UTF-8" : "en_US.UTF-8" },
    deviceScaleFactor: 1,
  });
  await context.route("https://claude.ai/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const cookies = Object.fromEntries(((await req.allHeaders()).cookie || "").split(/;\s*/).filter(Boolean).map((c) => c.split("=")));
    const user = USERS[cookies.sessionKey];
    if (url.pathname === "/api/account") return user ? route.fulfill({ json: user }) : route.fulfill({ status: 401, json: {} });
    if (url.pathname === "/favicon.ico") return route.fulfill({ status: 404, body: "" });
    return route.fulfill({ contentType: "text/html", body: claudePage(user ? user.full_name : "") });
  });
  const worker = context.serviceWorkers()[0] || (await context.waitForEvent("serviceworker"));
  void worker;
  const tab = await context.newPage();
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${ID}/popup/popup.html`);
  const send = (m) => popup.evaluate((x) => chrome.runtime.sendMessage(x), m);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  for (const [key] of [...people].reverse()) {
    await context.clearCookies();
    await context.addCookies([{ name: "sessionKey", value: key, domain: "claude.ai", path: "/", secure: true, httpOnly: true, sameSite: "Lax", expires: Math.floor(Date.now() / 1000) + 86400 }]);
    await tab.goto("https://claude.ai/new");
    await sleep(1500);
  }
  await tab.bringToFront();
  await sleep(800);
  await tab.screenshot({ path: path.join(temp, "tab.png") });
  await popup.setViewportSize({ width: 344, height: 600 });
  await popup.reload();
  await sleep(1200);
  const box = await popup.evaluate(() => ({ h: document.body.scrollHeight }));
  await popup.setViewportSize({ width: 344, height: box.h });
  await popup.screenshot({ path: path.join(temp, "popup.png"), omitBackground: false });
  await popup.goto(`chrome-extension://${ID}/options/options.html`);
  await sleep(1200);
  await popup.setViewportSize({ width: 1280, height: 800 });
  await popup.screenshot({ path: path.join(out, `store-3-settings-${lang}.png`) });
  await context.close();

  execFileSync("python3", ["-c", `
import sys
from PIL import Image, ImageDraw, ImageFilter
tab = Image.open(sys.argv[1]).convert("RGB")
pop = Image.open(sys.argv[2]).convert("RGB")
canvas = tab.copy()
x, y = 1280 - pop.width - 24, 12
shadow = Image.new("RGBA", (pop.width + 40, pop.height + 40), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([20, 24, pop.width + 20, pop.height + 20], 14, fill=(0, 0, 0, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(10))
canvas.paste(shadow, (x - 20, y - 20), shadow)
mask = Image.new("L", pop.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, pop.width - 1, pop.height - 1], 12, fill=255)
canvas.paste(pop, (x, y), mask)
canvas.save(sys.argv[3])
tab.save(sys.argv[4])
`, path.join(temp, "tab.png"), path.join(temp, "popup.png"), path.join(out, `store-1-popup-${lang}.png`), path.join(out, `store-2-tab-${lang}.png`)]);
  fs.rmSync(temp, { recursive: true, force: true });
  console.log("screenshots in", out);
}

main().catch((e) => { console.error(e); process.exit(1); });
