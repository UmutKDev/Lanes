// Lanes for Safari: runs on claude.ai. Tells the background who is signed
// in (only the identity fields of /api/account), and marks the page with the
// account's color: a thin bar, the tab title and the tab icon.
(function () {
  "use strict";
  if (window.__lanesContent) return;
  window.__lanesContent = true;

  const api = globalThis.browser || globalThis.chrome;
  const C = globalThis.LanesCore;
  let current = null; // { name, color, monogram }
  let settings = {};
  let lastProbe = 0;

  // MARK: Identity

  async function probe() {
    lastProbe = Date.now();
    let response;
    try {
      response = await fetch("/api/account", { credentials: "include", headers: { accept: "application/json" } });
    } catch (_) {
      return; // offline: say nothing rather than "signed out"
    }
    let report;
    if (response.status === 401 || response.status === 403) {
      report = { type: "identity", signedIn: false };
    } else if (response.ok) {
      let identity = null;
      try {
        identity = C.parseAccount(await response.json());
      } catch (_) {
        identity = null;
      }
      if (!identity) return;
      report = { type: "identity", signedIn: true, identity };
    } else {
      return;
    }
    try {
      apply(await api.runtime.sendMessage(report));
    } catch (_) {
      // background restarting; the next probe tries again
    }
  }

  function apply(reply) {
    if (!reply || reply.ok === false) return;
    current = reply.account || null;
    settings = reply.settings || {};
    paintStripe();
    paintTitle();
    paintFavicon();
  }

  // MARK: Stripe

  function paintStripe() {
    let bar = document.getElementById("lanes-account-stripe");
    if (!current || !settings.stripe) {
      if (bar) bar.remove();
      return;
    }
    if (!bar) {
      bar = document.createElement("div");
      bar.id = "lanes-account-stripe";
      bar.setAttribute("aria-hidden", "true");
      document.documentElement.appendChild(bar);
    }
    const dark = matchMedia("(prefers-color-scheme: dark)").matches;
    bar.style.setProperty("--lanes-color", C.colorHex(current.color, dark));
    bar.title = current.name;
  }

  // MARK: Title

  let titleObserver = null;
  function paintTitle() {
    const want = current && settings.titleMark ? C.titleWithMark(document.title, current) : C.stripTitleMark(document.title);
    if (document.title !== want) document.title = want;
    if (!titleObserver) {
      titleObserver = new MutationObserver(() => {
        const next = current && settings.titleMark ? C.titleWithMark(document.title, current) : C.stripTitleMark(document.title);
        if (document.title !== next) document.title = next;
      });
      const target = document.querySelector("head") || document.documentElement;
      titleObserver.observe(target, { subtree: true, childList: true, characterData: true });
    }
  }

  // MARK: Tab icon

  let iconLink = null;
  let iconKey = "";
  let originalIcon = null;

  function siteIconURL() {
    const links = [...document.querySelectorAll('link[rel~="icon"]')].filter((l) => l !== iconLink);
    return (links[0] && links[0].href) || location.origin + "/favicon.ico";
  }

  function paintFavicon() {
    if (!current || !settings.favicon) {
      if (iconLink) {
        iconLink.remove();
        iconLink = null;
        iconKey = "";
      }
      return;
    }
    const key = current.color + "|" + current.monogram;
    if (key === iconKey && iconLink && iconLink.isConnected) return;
    iconKey = key;
    const color = C.colorHex(current.color, false);
    const draw = (image) => {
      const size = 64;
      const canvas = document.createElement("canvas");
      canvas.width = canvas.height = size;
      const ctx = canvas.getContext("2d");
      if (image) {
        ctx.drawImage(image, 0, 0, size, size);
      } else {
        ctx.fillStyle = color;
        roundRect(ctx, 0, 0, size, size, 14);
        ctx.fill();
        ctx.fillStyle = C.isLightSwatch(current.color) ? "#000" : "#fff";
        ctx.font = "600 30px -apple-system, system-ui, sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(current.monogram, size / 2, size / 2 + 2);
      }
      if (image) {
        ctx.beginPath();
        ctx.arc(size - 15, size - 15, 14, 0, Math.PI * 2);
        ctx.fillStyle = "#fff";
        ctx.fill();
        ctx.beginPath();
        ctx.arc(size - 15, size - 15, 10.5, 0, Math.PI * 2);
        ctx.fillStyle = color;
        ctx.fill();
      }
      let url;
      try {
        url = canvas.toDataURL("image/png");
      } catch (_) {
        if (image) return draw(null);
        return;
      }
      if (!iconLink || !iconLink.isConnected) {
        iconLink = document.createElement("link");
        iconLink.rel = "icon";
        iconLink.type = "image/png";
        iconLink.dataset.lanes = "1";
      }
      iconLink.href = url;
      // Last icon wins in Safari, so ours goes to the end of <head>.
      (document.head || document.documentElement).appendChild(iconLink);
    };
    const image = new Image();
    image.onload = () => draw(image);
    image.onerror = () => draw(null);
    originalIcon = originalIcon || siteIconURL();
    image.src = originalIcon;
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  // Claude swaps its own icon on some pages; keep ours last.
  const headObserver = new MutationObserver(() => {
    if (iconLink && document.head && document.head.lastElementChild !== iconLink && settings.favicon && current) {
      document.head.appendChild(iconLink);
    }
  });

  // MARK: Draft

  function composer() {
    return (
      document.querySelector('div.ProseMirror[contenteditable="true"]') ||
      document.querySelector('[contenteditable="true"][role="textbox"]') ||
      document.querySelector("fieldset [contenteditable='true']") ||
      document.querySelector("textarea")
    );
  }

  function readDraft() {
    const box = composer();
    if (!box) return "";
    return (box.value !== undefined && box.tagName === "TEXTAREA" ? box.value : box.innerText || "").trim();
  }

  /// claude.ai fills /new?q= by itself. If it ever stops, put the text in
  /// the message box ourselves, once.
  function fillDraftFromURL() {
    const params = new URLSearchParams(location.search);
    const text = params.get("q");
    if (!text || location.pathname !== "/new") return;
    let tries = 0;
    const timer = setInterval(() => {
      tries += 1;
      const box = composer();
      if (box && !readDraft()) {
        box.focus();
        if (box.tagName === "TEXTAREA") {
          box.value = text;
          box.dispatchEvent(new Event("input", { bubbles: true }));
        } else {
          document.execCommand("insertText", false, text);
        }
        clearInterval(timer);
      } else if ((box && readDraft()) || tries > 20) {
        clearInterval(timer);
      }
    }, 400);
  }

  // MARK: Wiring

  api.runtime.onMessage.addListener((message) => {
    if (!message) return;
    if (message.type === "getDraft") return Promise.resolve({ draft: readDraft() });
    if (message.type === "appearance") apply(message);
  });

  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", paintStripe);

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && Date.now() - lastProbe > 120000) probe();
  });

  // claude.ai is a single-page app: after signing in it moves on without a
  // page load, so look again when the address changes.
  let lastPath = location.pathname;
  setInterval(() => {
    if (location.pathname !== lastPath) {
      const wasAuth = /^\/(login|magic-link|onboarding)/.test(lastPath);
      lastPath = location.pathname;
      if (wasAuth || Date.now() - lastProbe > 120000) probe();
    }
  }, 1000);

  api.runtime.sendMessage({ type: "hello" }).then(apply).catch(() => {});
  if (document.head) headObserver.observe(document.head, { childList: true });
  probe();
  fillDraftFromURL();
})();
