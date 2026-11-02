// Small helpers for the popup and the settings page.
(function (root) {
  "use strict";
  const api = root.browser || root.chrome;
  const C = root.LanesCore;

  function t(key, subs) {
    return (api.i18n && api.i18n.getMessage(key, subs)) || key;
  }

  /// Fills [data-i18n], [data-i18n-title] and [data-i18n-placeholder].
  function localize(scope) {
    const base = scope || document;
    base.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n); });
    base.querySelectorAll("[data-i18n-title]").forEach((el) => {
      el.title = t(el.dataset.i18nTitle);
      el.setAttribute("aria-label", el.title);
    });
    base.querySelectorAll("[data-i18n-placeholder]").forEach((el) => { el.placeholder = t(el.dataset.i18nPlaceholder); });
    document.documentElement.lang = t("langCode");
  }

  async function send(message) {
    const reply = await api.runtime.sendMessage(message);
    if (reply && reply.ok === false) throw new Error(reply.error || "error");
    return reply;
  }

  const dark = () => matchMedia("(prefers-color-scheme: dark)").matches;

  function avatar(acc, size) {
    const el = document.createElement("div");
    el.className = "avatar" + (size ? " " + size : "") + (C.isLightSwatch(acc.color) ? " light-swatch" : "");
    el.style.setProperty("--c", C.colorHex(acc.color, dark()));
    el.textContent = acc.monogram || C.monogram(acc.name);
    el.setAttribute("aria-hidden", "true");
    return el;
  }

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  const PLAN_KEYS = { free: "planFree", pro: "planPro", max: "planMax", team: "planTeam", enterprise: "planEnterprise" };
  function planLabel(plan) {
    return PLAN_KEYS[plan] ? t(PLAN_KEYS[plan]) : "";
  }

  root.LanesUI = { api, t, localize, send, avatar, el, planLabel, dark };
})(globalThis);
