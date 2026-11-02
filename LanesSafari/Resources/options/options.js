// Lanes for Safari: settings page.
(function () {
  "use strict";
  const { t, localize, send, el } = globalThis.LanesUI;

  localize();
  document.title = t("optionsTitle");

  function statusRow(level, title, body, action) {
    const row = el("div", "status-row");
    row.appendChild(el("span", "dot" + (level === "ok" ? "" : " " + level)));
    const text = el("div");
    text.appendChild(el("strong", "", title));
    if (body) text.appendChild(el("p", "", body));
    row.appendChild(text);
    if (action) row.appendChild(action);
    return row;
  }

  async function load() {
    let state = await send({ type: "getState" });
    try {
      state = await send({ type: "refreshLanes" });
    } catch (_) {
      // keep the cached list
    }
    const box = document.getElementById("status");
    box.textContent = "";
    const count = state.accounts.length;
    box.appendChild(statusRow(count ? "ok" : "off", t("statusAccounts", [String(count)]), count ? "" : t("statusAccountsEmpty")));

    if (state.capability === "hidden") box.appendChild(statusRow("warn", t("hiddenTitle"), t("hiddenBody")));
    else if (state.capability === "ok") box.appendChild(statusRow("ok", t("statusSwitchOK"), t("statusSwitchOKBody")));
    else box.appendChild(statusRow("off", t("statusSwitchUnknown"), t("statusSwitchUnknownBody")));

    if (state.vault === "local") box.appendChild(statusRow("warn", t("statusVaultLocal"), t("statusVaultLocalBody")));
    else box.appendChild(statusRow("ok", t("statusVaultKeychain"), t("statusVaultKeychainBody")));

    if (state.lanes) {
      const open = el("button", "button", t("openLanesApp"));
      open.addEventListener("click", () => send({ type: "openLanes", id: null }).catch(() => {}));
      box.appendChild(statusRow("ok", t("statusLanes", [String(state.lanes.accounts.length)]), t("statusLanesBody"), open));
    } else {
      box.appendChild(statusRow("off", t("statusNoLanes"), t("statusNoLanesBody")));
    }

    document.querySelectorAll("[data-setting]").forEach((input) => {
      input.checked = !!state.settings[input.dataset.setting];
      input.onchange = () => send({ type: "settings", changes: { [input.dataset.setting]: input.checked } }).catch(() => {});
    });
  }

  load();
})();
