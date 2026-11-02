// Lanes for Safari, Chrome and Edge: toolbar popup.
(function () {
  "use strict";
  const { api, t, localize, send, avatar, el, planLabel } = globalThis.LanesUI;
  const C = globalThis.LanesCore;
  const $ = (id) => document.getElementById(id);

  let state = null;
  let query = "";
  let selected = 0;
  let editing = null;
  let editColor = null;

  localize();

  async function load() {
    state = await send({ type: "getState" });
    render();
    // The Lanes list can change while the browser runs; read it again quietly.
    send({ type: "refreshLanes" }).then((fresh) => {
      state = fresh;
      render();
    }).catch(() => {});
  }

  function lanesList() {
    return state && state.lanes && Array.isArray(state.lanes.accounts) ? state.lanes.accounts : [];
  }

  function render() {
    if (!state) return;
    const active = state.accounts.find((a) => a.id === state.activeId) || null;
    const others = C.sortAccounts(state.accounts.filter((a) => a.id !== state.activeId), null)
      .filter((a) => C.matchesSearch(a, query));

    renderBanner();
    renderCurrent(active);

    const many = state.accounts.length > 5;
    $("search-wrap").hidden = !many;
    $("list-title").hidden = others.length === 0 || !active;
    $("empty").hidden = state.accounts.length > 0;
    $("carry-draft").checked = !!state.settings.carryDraft;
    $("open-lanes").hidden = !state.lanes;

    const list = $("list");
    list.textContent = "";
    selected = Math.min(selected, Math.max(0, others.length - 1));
    others.forEach((acc, index) => list.appendChild(row(acc, index)));
  }

  function renderBanner() {
    const banner = $("banner");
    banner.textContent = "";
    if (state.capability !== "hidden") {
      banner.hidden = true;
      return;
    }
    banner.hidden = false;
    const text = el("div");
    text.appendChild(el("strong", "", t("hiddenTitle")));
    text.appendChild(document.createTextNode(t("hiddenBody")));
    banner.appendChild(text);
  }

  function renderCurrent(active) {
    const box = $("current");
    box.textContent = "";
    box.classList.toggle("signed-out", !active);
    if (!active) {
      box.hidden = state.accounts.length === 0;
      box.style.removeProperty("--c");
      const rowEl = el("div", "current-row");
      const who = el("div", "who");
      who.appendChild(el("div", "label", t("noneActiveLabel")));
      who.appendChild(el("div", "name", t("noneActiveTitle")));
      who.appendChild(el("div", "email", t("noneActiveBody")));
      rowEl.appendChild(who);
      box.appendChild(rowEl);
      return;
    }
    box.hidden = false;
    box.style.setProperty("--c", C.colorHex(active.color, globalThis.LanesUI.dark()));
    const top = el("div", "current-row");
    top.appendChild(avatar(active, "xl"));
    const who = el("div", "who");
    who.appendChild(el("div", "label", t("activeLabel")));
    who.appendChild(el("div", "name", active.name));
    who.appendChild(el("div", "email", active.email || ""));
    top.appendChild(who);
    const more = moreButton(active);
    top.appendChild(more);
    box.appendChild(top);

    const chips = el("div", "chips");
    const plan = planLabel(active.plan);
    if (plan) chips.appendChild(el("span", "chip plan", plan));
    if (active.orgName && !/'s Organization$|’s Organization$/.test(active.orgName)) chips.appendChild(el("span", "chip", active.orgName));
    const profile = C.findLanesProfile(lanesList(), active);
    if (profile) chips.appendChild(el("span", "chip lanes", t("lanesChip", [profile.name])));
    if (chips.childNodes.length) box.appendChild(chips);

    const actions = el("div", "actions");
    const newChat = el("button", "button", t("newChat"));
    newChat.addEventListener("click", () => openClaude("/new"));
    actions.appendChild(newChat);
    if (profile) {
      const desk = el("button", "button", t("openInLanes"));
      desk.title = t("openInLanesHelp", [profile.name]);
      desk.addEventListener("click", () => send({ type: "openLanes", id: active.id }).then(() => window.close()).catch(showError));
      actions.appendChild(desk);
    }
    box.appendChild(actions);
  }

  function row(acc, index) {
    const item = el("li", "row" + (index === selected ? " selected" : ""));
    item.setAttribute("role", "option");
    item.tabIndex = -1;
    item.dataset.id = acc.id;
    item.appendChild(avatar(acc));
    const who = el("div", "who");
    const name = el("div", "name");
    name.appendChild(el("span", "", acc.name));
    if (acc.status === "expired" || acc.status === "signedOut") name.appendChild(el("span", "chip warn", t("expiredChip")));
    else if (acc.plan && planLabel(acc.plan)) name.appendChild(el("span", "chip", planLabel(acc.plan)));
    if (acc.pinned) name.appendChild(el("span", "pin", "●"));
    who.appendChild(name);
    const used = acc.lastUsedAt ? C.timeAgo(acc.lastUsedAt, Date.now(), t) : "";
    who.appendChild(el("div", "detail", [acc.email, used].filter(Boolean).join(" · ")));
    item.appendChild(who);
    if (index < 9) item.appendChild(el("span", "key", String(index + 1)));
    item.appendChild(moreButton(acc));
    item.addEventListener("click", (event) => {
      if (event.target.closest(".more")) return;
      switchTo(acc, item);
    });
    item.addEventListener("mousemove", () => {
      if (selected !== index) {
        selected = index;
        document.querySelectorAll(".row").forEach((r, i) => r.classList.toggle("selected", i === index));
      }
    });
    return item;
  }

  function moreButton(acc) {
    const more = el("button", "icon-button more");
    more.title = t("editAccount");
    more.setAttribute("aria-label", more.title);
    more.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="5" cy="10" r="1.1"/><circle cx="10" cy="10" r="1.1"/><circle cx="15" cy="10" r="1.1"/></svg>';
    more.addEventListener("click", (event) => {
      event.stopPropagation();
      openSheet(acc);
    });
    return more;
  }

  async function switchTo(acc, item) {
    if (state.capability === "hidden") return showError(new Error(t("errorCookiesHidden")));
    if (item) item.classList.add("busy");
    try {
      await send({ type: "switch", id: acc.id });
      window.close();
    } catch (error) {
      if (item) item.classList.remove("busy");
      showError(error);
      state = await send({ type: "getState" });
      render();
    }
  }

  async function openClaude(path) {
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    const url = C.CLAUDE_ORIGIN + path;
    if (tab && tab.url && C.isClaudeURL(tab.url)) await api.tabs.update(tab.id, { url });
    else await api.tabs.create({ url });
    window.close();
  }

  // MARK: Edit sheet

  function openSheet(acc) {
    editing = acc;
    editColor = acc.color;
    $("sheet-title").textContent = acc.name;
    $("sheet-email").textContent = acc.email || "";
    $("sheet-name").value = acc.name;
    $("sheet-pin").checked = !!acc.pinned;
    $("sheet-remove").textContent = t(acc.id === state.activeId ? "forgetActive" : "forget");
    $("sheet-remove").dataset.confirm = "";
    paintSheetAvatar();

    const colors = $("sheet-colors");
    colors.textContent = "";
    for (const name of Object.keys(C.COLORS)) {
      const swatch = el("button", "swatch");
      swatch.style.setProperty("--c", C.colorHex(name, globalThis.LanesUI.dark()));
      swatch.setAttribute("role", "radio");
      swatch.setAttribute("aria-checked", String(name === editColor));
      swatch.setAttribute("aria-label", t("color_" + name));
      swatch.title = t("color_" + name);
      swatch.addEventListener("click", () => {
        editColor = name;
        colors.querySelectorAll(".swatch").forEach((s) => s.setAttribute("aria-checked", String(s === swatch)));
        paintSheetAvatar();
      });
      colors.appendChild(swatch);
    }

    const lanes = lanesList();
    $("sheet-lanes-field").hidden = lanes.length === 0;
    const select = $("sheet-lanes");
    select.textContent = "";
    const auto = el("option", "", t("lanesAuto"));
    auto.value = "";
    select.appendChild(auto);
    for (const profile of lanes) {
      const option = el("option", "", profile.name + (profile.email ? " · " + profile.email : ""));
      option.value = profile.id;
      select.appendChild(option);
    }
    const none = el("option", "", t("lanesNone"));
    none.value = "none";
    select.appendChild(none);
    select.value = acc.lanesId || "";

    $("sheet").hidden = false;
    $("sheet-name").focus();
    $("sheet-name").select();
  }

  function paintSheetAvatar() {
    const holder = $("sheet-avatar");
    const fresh = avatar({ name: $("sheet-name").value || editing.name, color: editColor }, "large");
    fresh.id = "sheet-avatar";
    holder.replaceWith(fresh);
  }

  function closeSheet() {
    $("sheet").hidden = true;
    editing = null;
  }

  $("sheet-name").addEventListener("input", paintSheetAvatar);
  $("sheet-cancel").addEventListener("click", closeSheet);
  $("sheet").addEventListener("click", (event) => {
    if (event.target === $("sheet")) closeSheet();
  });
  $("sheet-save").addEventListener("click", async () => {
    if (!editing) return;
    const changes = { pinned: $("sheet-pin").checked };
    const name = $("sheet-name").value.trim();
    if (name && name !== editing.name) changes.name = name;
    if (editColor !== editing.color) changes.color = editColor;
    const link = $("sheet-lanes").value;
    if (link !== (editing.lanesId || "")) changes.lanesId = link;
    try {
      await send({ type: "update", id: editing.id, changes });
      closeSheet();
      state = await send({ type: "getState" });
      render();
    } catch (error) {
      showError(error);
    }
  });
  $("sheet-remove").addEventListener("click", async () => {
    const button = $("sheet-remove");
    if (!button.dataset.confirm) {
      button.dataset.confirm = "1";
      button.textContent = t("forgetConfirm");
      return;
    }
    try {
      await send({ type: "remove", id: editing.id });
      closeSheet();
      state = await send({ type: "getState" });
      render();
    } catch (error) {
      showError(error);
    }
  });

  // MARK: Footer, header, keys

  $("add").addEventListener("click", async () => {
    try {
      await send({ type: "add" });
      window.close();
    } catch (error) {
      showError(error);
    }
  });
  $("carry-draft").addEventListener("change", (event) => {
    send({ type: "settings", changes: { carryDraft: event.target.checked } }).catch(showError);
  });
  $("open-settings").addEventListener("click", () => {
    api.runtime.openOptionsPage();
    window.close();
  });
  $("open-lanes").addEventListener("click", () => {
    send({ type: "openLanes", id: null }).then(() => window.close()).catch(showError);
  });
  $("open-claude").addEventListener("click", () => openClaude("/login"));
  $("search").addEventListener("input", (event) => {
    query = event.target.value;
    selected = 0;
    render();
  });

  document.addEventListener("keydown", (event) => {
    if (!$("sheet").hidden) {
      if (event.key === "Escape") closeSheet();
      if (event.key === "Enter" && event.target.tagName !== "SELECT") $("sheet-save").click();
      return;
    }
    const rows = [...document.querySelectorAll(".row")];
    const typing = event.target === $("search");
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!rows.length) return;
      selected = (selected + (event.key === "ArrowDown" ? 1 : -1) + rows.length) % rows.length;
      rows.forEach((r, i) => r.classList.toggle("selected", i === selected));
      rows[selected].scrollIntoView({ block: "nearest" });
    } else if (event.key === "Enter" && rows[selected]) {
      event.preventDefault();
      rows[selected].click();
    } else if (!typing && /^[1-9]$/.test(event.key) && rows[Number(event.key) - 1]) {
      rows[Number(event.key) - 1].click();
    } else if (!typing && event.key.length === 1 && !event.metaKey && !event.ctrlKey && !$("search-wrap").hidden) {
      $("search").focus();
    }
  });

  let toastTimer = null;
  function showError(error) {
    const toast = $("toast");
    toast.textContent = String(error && error.message || error);
    toast.className = "toast error show";
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toast.className = "toast error"; }, 4200);
  }

  load().catch(showError);
})();
