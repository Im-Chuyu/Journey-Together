"use strict";
const assert = require("node:assert/strict"), fs = require("node:fs"), vm = require("node:vm");
const root = "tools/companion_bridge/browser_extension/";
const code = name => fs.readFileSync(root + name + ".js", "utf8");
async function page(host, rich = false, blocked = false, clickOnly = false, variant = "") {
    let time = 0, submissions = 0, rotations = 0, limited = false, text = "", filled = "", clicks = 0;
    class TextArea {
        get value() { return filled; } set value(v) { filled = v; }
        get textContent() { return filled; } set textContent(v) { filled = v; }
        getClientRects() { return [1]; } focus() {}
        dispatchEvent(e) {
            if (e.type !== "keydown") return;
            if (clickOnly && !e.manual) return;
            submissions++;
            limited = submissions === 1;
            text = limited ? (variant === "alternate" ? "对话太长，请开始一个新对话" : "当前对话已达到长度上限，请开启新对话") : '{"text":"好了。","request_id":"same-nonce"}';
            filled = "";
        }
    }
    const box = rich ? new (class { constructor() { this.textContent = ""; } })() : new TextArea();
    if (rich) {
        box.getClientRects = () => [1]; box.focus = () => {};
        box.dispatchEvent = e => { if (e.type === "keydown" && !clickOnly) { box.textContent = ""; TextArea.prototype.dispatchEvent.call({}, e); } };
    }
    const arrow = {getClientRects: () => [1], getAttribute: () => null, closest: () => null, innerText: "",
        click() { clicks++; box.textContent = ""; TextArea.prototype.dispatchEvent.call({}, {type: "keydown", manual: true}); }};
    if (variant === "composer") box.parentElement = {querySelectorAll: () => [arrow]};
    const button = {getClientRects: () => [1], getAttribute: () => null, innerText: variant === "alternate" ? "新建对话（Ctrl+K）" : host === "doubao" ? "新对话 Ctrl Shift K" : "开启新对话",
        click() { rotations++; limited = false; text = ""; context.location.href += "/new"; }};
    const alert = {getClientRects: () => [1], closest: () => null, get innerText() { return text; }};
    const context = {location: {href: host === "doubao" ? "https://www.doubao.com/chat/1" : "https://chat.deepseek.com/a/chat/s/1"},
        setInterval() {}, setTimeout(fn, ms) { time += ms; fn(); }, clearTimeout() {}, Date: {now: () => time},
        HTMLTextAreaElement: TextArea, Event: class {constructor(type) {this.type = type;}}, KeyboardEvent: class {constructor(type) {this.type = type;}},
        window: {addEventListener() {}},
        document: {addEventListener() {}, body: {get innerText() {return text;}},
            execCommand(command, _, value) { if (command === "insertText") box.textContent = value; else box.textContent = ""; return true; },
            querySelectorAll(selector) {
                if (selector.startsWith("#input-engine")) return variant === "composer" ? [] : [box];
                if (selector.startsWith("textarea")) return [box];
                if (selector.startsWith("button,a")) return variant === "fallback" ? [] : [button];
                if (clickOnly && variant !== "composer" && selector.startsWith('[data-testid="chat_input_send_button"]')) return [arrow];
                if (selector.startsWith('[role="alert"]')) return limited ? [alert] : [];
                return [];
            }},
        chrome: {runtime: {id: "extension", onMessage: {addListener() {}}, sendMessage: async message => {
            if (message.kind === "prepare_chat") {
                assert.equal(message.data.reason, "context_limit");
                assert.equal(message.data.request_id, "same-nonce");
                return {rotate: !blocked};
            }
            return {connected: false};
        }}}};
    context.location.assign = url => { assert.equal(url, "https://chat.deepseek.com/"); rotations++; limited=false; text=""; context.location.href=url; };
    vm.createContext(context); vm.runInContext(code("sites"), context); vm.runInContext(code("content"), context);
    await new Promise(setImmediate);
    vm.runInContext('activeRequest="same-nonce"', context);
    const task = vm.runInContext('execute({request_id:"same-nonce",prompt:"complete current state and actual results"})', context);
    if (blocked) await assert.rejects(task, /会话已达上限/);
    else assert.equal(JSON.parse(await task).request_id, "same-nonce");
    assert.equal(submissions, blocked ? 1 : 2);
    assert.equal(rotations, blocked ? 0 : 1);
    if (clickOnly) assert.equal(clicks, 2, "exactly one actual send click per attempt, including after renewal");
    return context;
}
async function worker() {
    let message;
    const state = {buddyToken: "secret", buddyTab: 8, buddyUrl: "https://www.doubao.com/chat/1", buddyProvider: "doubao"};
    let session = {};
    const context = {AbortController, setTimeout, clearTimeout, importScripts() {},
        chrome: {storage: {local: {get: async () => ({...state}), set: async v => Object.assign(state, v)},
            session: {get: async () => ({...session}), set: async v => Object.assign(session, v)}, onChanged: {addListener() {}}},
            tabs: {query: async () => [{id: 8, url: state.buddyUrl}], sendMessage: async () => ({ready: true}),
                onUpdated: {addListener() {}}, onActivated: {addListener() {}}, onRemoved: {addListener() {}}},
            alarms: {get: async () => null, create() {}, clear() {}, onAlarm: {addListener() {}}},
            runtime: {id: "ext", onStartup: {addListener() {}}, onMessage: {addListener(fn) {message = fn;}}}},
        fetch: async () => ({ok: true, json: async () => ({job: {request_id: "n"}, accepted: true})})};
    vm.createContext(context); vm.runInContext(code("sites"), context); vm.runInContext(code("background"), context);
    await new Promise(setImmediate);
    const call = (reason, nonce = "n") => new Promise(resolve => message({kind: "prepare_chat", data: {reason, request_id: nonce}},
        {id: "ext", frameId: 0, url: state.buddyUrl, tab: {id: 8}}, resolve));
    for (let n = 0; n < 20; n++) assert.equal((await call("before_request")).rotate, false);
    assert.equal((await call("context_limit")).rotate, true);
    assert.equal((await call("context_limit")).rotate, true);
    assert.match((await call("context_limit")).error, /新对话/);
    assert.equal((await call("context_limit", "stale")).superseded, true);
    state.buddyAutoNew = false;
    assert.equal((await call("context_limit")).rotate, false);
    assert.equal(context.BuddySites.identify("https://www.doubao.com/chat/1").id, "doubao");
    assert.equal(context.BuddySites.identify("https://doubao.com/chat/2").id, "doubao");
    assert.equal(context.BuddySites.identify("https://doubao.com.evil.test/chat/2"), null);
    assert.equal(context.BuddySites.identify("https://www.doubao.com/chat/skills"), null);
    context.chrome.tabs.query = async () => [{id: 99, url: "https://chat.deepseek.com/a/chat/s/other", active: true}];
    assert.equal(await vm.runInContext("recover(99)", context), null);
    assert.equal(state.buddyTab, 8);
}
(async () => {
    await page("deepseek"); await page("doubao", true); await page("doubao", true, false, true);
    await page("deepseek", false, false, false, "alternate");
    await page("deepseek", false, false, false, "fallback");
    await page("doubao", true, false, true, "composer");
    await page("deepseek", false, true); await worker();
    console.log("PASS DeepSeek/Doubao composer and limit-only conversation renewal, same nonce continuation, disabled renewal, stale requests and bounded failed restarts");
})().catch(error => {console.error(error); process.exitCode = 1;});
