"use strict";
importScripts("sites.js");
const HEARTBEAT = "buddy-page-heartbeat";
const PAGE = {test: url => Boolean(BuddySites.identify(url))};
async function pairing() {
    let state = await chrome.storage.local.get(["buddyToken", "buddyTab", "buddyUrl", "buddyDisabled", "buddyProvider", "buddyAutoNew"]);
    if (state.buddyDisabled) return {};
    if (!state.buddyToken) {
        const old = await chrome.storage.session.get(["buddyToken", "buddyTab"]);
        if (old.buddyToken) {
            await chrome.storage.local.set(old);
            await chrome.storage.session.remove(["buddyToken", "buddyTab"]);
            state = old;
        }
    }
    if (!state.buddyProvider && state.buddyUrl) state.buddyProvider = BuddySites.identify(state.buddyUrl)?.id;
    return state;
}
async function bounded(promise, ms, message) {
    let timer;
    try { return await Promise.race([promise, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(message)), ms);
    })]); }
    finally { clearTimeout(timer); }
}
async function post(kind, token, data = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    try {
        const response = await fetch("http://127.0.0.1:18766/v1/model/" + kind, {
            method: "POST", signal: controller.signal, headers: {"Content-Type": "application/json"},
            body: JSON.stringify({...data, model_token: token})
        });
        const body = await response.json();
        if (!response.ok) throw new Error(body.error || "本机助手拒绝连接");
        return {connected: true, ...body};
    } finally { clearTimeout(timer); }
}
// Serialize rebinding, and recheck storage before writing: explicit disconnect
// or a new manual pairing must win over any in-flight recovery.
let selection = Promise.resolve();
function recover(preferredId) {
    const next = selection.then(async () => {
        const state = await pairing();
        if (!state.buddyToken) return null;
        const tabs = await chrome.tabs.query({url: BuddySites.patterns});
        const eligible = tabs.filter(tab => PAGE.test(tab.url || "") && (!state.buddyProvider || BuddySites.identify(tab.url).id === state.buddyProvider));
        const exact = eligible.filter(tab => (tab.url || "").split("#")[0] === state.buddyUrl);
        const active = eligible.filter(tab => tab.active);
        const selected = eligible.find(tab => tab.id === state.buddyTab)
            || exact.find(tab => tab.id === preferredId) || exact[0]
            || eligible.find(tab => tab.id === preferredId)
            || (active.length === 1 ? active[0] : eligible.length === 1 ? eligible[0] : null);
        if (!selected) return null;
        const current = await pairing();
        if (current.buddyToken !== state.buddyToken || current.buddyTab !== state.buddyTab) return null;
        const url = selected.url.split("#")[0];
        if (state.buddyTab !== selected.id || state.buddyUrl !== url)
            await chrome.storage.local.set({buddyTab: selected.id, buddyUrl: url});
        return {...state, buddyTab: selected.id, buddyUrl: url};
    });
    selection = next.catch(() => {});
    return next;
}
async function ping(preferredId) {
    try {
        const state = await recover(preferredId);
        if (!state) return;
        const page = await bounded(chrome.tabs.sendMessage(state.buddyTab, {kind: "buddy_ping"}), 4000, "网页未响应");
        const current = await pairing();
        // A real page response is required. An open tab entry alone is not a
        // heartbeat. This HTTP call does not consume or submit a model job.
        if (page && page.ready && current.buddyToken === state.buddyToken && current.buddyTab === state.buddyTab)
            await post("heartbeat", state.buddyToken);
    } catch (_) { /* Code persists; another page event or alarm will retry. */ }
}
async function ensureHeartbeat() {
    const state = await pairing();
    if (state.buddyToken) {
        if (!await chrome.alarms.get(HEARTBEAT)) chrome.alarms.create(HEARTBEAT, {periodInMinutes: .5});
    }
    else chrome.alarms.clear(HEARTBEAT);
}
chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local" || !("buddyTab" in changes || "buddyToken" in changes || "buddyDisabled" in changes)) return;
    void ensureHeartbeat().catch(() => {});
});
chrome.alarms.onAlarm.addListener(alarm => {
    if (alarm.name === HEARTBEAT) return ping();
});
chrome.tabs.onUpdated.addListener((id, change, tab) => {
    if ((change.status === "complete" || change.url) && PAGE.test((tab && tab.url) || change.url || "")) void ping(id);
});
chrome.tabs.onActivated.addListener(info => { void ping(info.tabId); });
chrome.tabs.onRemoved.addListener(() => { void ping(); });
chrome.runtime.onStartup.addListener(() => {
    void ensureHeartbeat().catch(() => {});
    void ping();
});
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (sender.id !== chrome.runtime.id || !sender.tab || sender.frameId !== 0 ||
        !PAGE.test(sender.url || "") || !["poll", "result", "prepare_chat"].includes(message.kind)) return;
    (async () => {
        const state = await pairing();
        // Tab events/startup/alarm handle discovery. Unselected pages must not
        // scan every browser tab on each 1.2-second content-script poll.
        if (!state.buddyToken || state.buddyTab !== sender.tab.id) return {connected: false};
        const url = sender.url.split("#")[0];
        if (url !== state.buddyUrl) await chrome.storage.local.set({buddyUrl: url});
        if (message.kind === "prepare_chat") {
            const check = await post("poll", state.buddyToken);
            const current = await pairing();
            if (current.buddyToken !== state.buddyToken || current.buddyTab !== sender.tab.id) return {superseded: true};
            if (!check.job || check.job.request_id !== message.data.request_id) return {superseded: true};
            const saved = await chrome.storage.session.get(["buddyUsage"]);
            const usage = saved.buddyUsage && saved.buddyUsage.tab === sender.tab.id ? saved.buddyUsage : {tab: sender.tab.id};
            const rotate = state.buddyAutoNew !== false && message.data.reason === "context_limit";
            if (!rotate) return {rotate: false};
            const attempts = usage.request === check.job.request_id ? usage.attempts : 0;
            if (attempts >= 2) return {error: "新对话仍无法继续，请检查页面、登录或限制提示。"};
            await chrome.storage.session.set({buddyUsage: {...usage, request: check.job.request_id, attempts: attempts + 1}});
            return {rotate: true};
        }
        const result = await post(message.kind, state.buddyToken, message.data);
        return result;
    })().then(sendResponse, error => sendResponse({error: error.name === "AbortError" ? "本机助手连接超时，正在自动重试" : error.message}));
    return true;
});
void ensureHeartbeat().catch(() => {});
void ping();
