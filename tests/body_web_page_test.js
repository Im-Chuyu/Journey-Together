// Unit boundaries only: this does not launch a browser or call DeepSeek.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
let clock = 0, submitted = false;
class TextArea {
    constructor() { this.text = ""; this.disabled = false; }
    get value() { return this.text; }
    set value(value) { this.text = value; }
    getClientRects() { return [1]; }
    focus() {}
    dispatchEvent(event) { if (event.type === "keydown") { submitted = true; this.text = ""; } }
}
const box = new TextArea();
const sandbox = {
    setInterval() {}, setTimeout(fn, ms) { clock += ms; fn(); }, clearTimeout() {},
    Date: {now: () => clock}, HTMLTextAreaElement: TextArea,
    Event: class { constructor(type) { this.type = type; } },
    KeyboardEvent: class { constructor(type) { this.type = type; } },
    document: {querySelectorAll: selector => selector.startsWith("textarea") ? [box] : [], body: {innerText: ""}, addEventListener() {}},
    window: {addEventListener() {}},
    chrome: {runtime: {onMessage: {addListener() {}}, sendMessage: async () => ({rotate: false})}},
};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync("tools/companion_bridge/browser_extension/sites.js", "utf8"), sandbox);
vm.runInContext(fs.readFileSync("tools/companion_bridge/browser_extension/content.js", "utf8"), sandbox);
function parse(text, nonce = "nonce") {
    return vm.runInContext(`objectReply(${JSON.stringify(text)}, ${JSON.stringify(nonce)})`, sandbox);
}
assert.equal(parse('{"request_id":"old","skill":"engage"}'), null);
assert.equal(parse('{"request_id":"nonce","utterance":"go","tools":[]}'), null);
const current = {request_id: "nonce", text: '带有 { } 和 " 引号的台词', skill: "move_to", arguments: {target: "e1"}};
assert.deepEqual(JSON.parse(parse("prose\n```json\n" + JSON.stringify(current) + "\n```")), current);
assert.equal(parse('{"request_id":"nonce","arguments":{"target":"e1"'), null);
assert.equal(parse(JSON.stringify({request_id: "old", skill: "observe"}) + JSON.stringify(current)), JSON.stringify(current));
async function main() {
    sandbox.document.body.innerText = JSON.stringify(current);
    vm.runInContext('activeRequest="nonce"', sandbox);
    const result = await vm.runInContext('execute({request_id:"nonce",prompt:"generic model request"})', sandbox);
    assert.ok(submitted);
    assert.deepEqual(JSON.parse(result), current);
    const originalQuery = sandbox.document.querySelectorAll;
    const observed = {text: "我这就看看\u00a0周围有些什么。", skill: "observe",
        arguments: {scope: "nearby", radius: 20}, request_id: "rendered-nonce"};
    const rendered = JSON.stringify(observed).replace('"arguments":', '"arguments":\u00a0');
    const code = {textContent: rendered, getClientRects: () => [1], closest: () => null};
    const hidden = {textContent: JSON.stringify({...observed, skill: "engage"}), getClientRects: () => [], closest: () => null};
    sandbox.document.querySelectorAll = selector => selector === "pre,code" ? [code, hidden] : originalQuery(selector);
    sandbox.document.body.innerText = "Code block visual text has line breaks inside strings and cannot parse as JSON.";
    const found = vm.runInContext('readReply("rendered-nonce")', sandbox);
    assert.equal(found.source, "code"); assert.deepEqual(JSON.parse(found.reply), observed);
    assert.equal(vm.runInContext('readReply("stale-nonce").reply', sandbox), null);
    const delivered = [];
    sandbox.chrome.runtime.sendMessage = async message => {
        if (message.kind === "result") { delivered.push(message.data); return {accepted: true}; }
        return {connected: true, job: {request_id: "rendered-nonce", prompt: "observe surroundings"}};
    };
    box.value = "";
    vm.runInContext('working=false;pendingResult=null;attempted.clear()', sandbox);
    await vm.runInContext("pollOnce()", sandbox);
    assert.equal(delivered.length, 1); assert.equal(delivered[0].error, undefined);
    assert.deepEqual(JSON.parse(delivered[0].text), observed);
    assert.equal(vm.runInContext("pendingResult", sandbox), null);
    sandbox.document.querySelectorAll = originalQuery;
    console.log("PASS visible syntax-highlighted reply with final request_id returns an actual observe result; hidden/stale JSON ignored");
    const plain = {text: "我带着草和木头。", request_id: "paragraph-nonce"};
    const paragraph = {textContent: JSON.stringify(plain), getClientRects: () => [1], closest: () => null};
    sandbox.document.querySelectorAll = selector => selector === "p" ? [paragraph] : originalQuery(selector);
    sandbox.document.body.innerText = JSON.stringify(plain) + "later collapsed prompt content ".repeat(6000);
    assert.equal(parse(sandbox.document.body.innerText.slice(-120000), "paragraph-nonce"), null);
    assert.deepEqual(JSON.parse(vm.runInContext('readReply("paragraph-nonce").reply', sandbox)), plain);
    assert.equal(vm.runInContext('readReply("different-request").reply', sandbox), null);
    const message = {textContent: JSON.stringify(plain), getClientRects: () => [1], closest: () => null,
        parentElement: sandbox.document.body};
    const span = {textContent: plain.request_id, getClientRects: () => [1], closest: () => null, parentElement: message};
    const textNodes = [{nodeValue: plain.request_id, parentElement: span}];
    sandbox.NodeFilter = {SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2};
    sandbox.document.createTreeWalker = (root, type, filter) => {
        const nodes = textNodes.filter(node => filter.acceptNode(node) === 1);
        let index = nodes.length;
        return {currentNode: root,
            lastChild() { index = nodes.length - 1; this.currentNode = nodes[index]; return this.currentNode; },
            previousNode() { index--; if (index < 0) return null; this.currentNode = nodes[index]; return this.currentNode; }};
    };
    sandbox.document.querySelectorAll = originalQuery;
    assert.deepEqual(JSON.parse(vm.runInContext('readReply("paragraph-nonce").reply', sandbox)), plain);
    message.closest = () => ({hidden: true}); span.closest = () => ({hidden: true});
    assert.equal(vm.runInContext('readReply("paragraph-nonce").reply', sandbox), null);
    // The exact reported reply, split across text nodes and >6 DOM wrappers.
    // A hidden sibling must not override the visible command.
    const splitReply = {request_id:"a7da3f493f6b16098c70c387",text:"哦看到了，那个背包在附近，我把它捡起来换到身上。",
        skill:"execute_sequence",arguments:{steps:[{id:"take_pack",skill:"pickup",arguments:{target:"e67",count:1}}]}};
    const splitJSON = JSON.stringify(splitReply);
    const hiddenJSON = JSON.stringify({...splitReply,skill:"engage",arguments:{target:"wrong"}});
    const visibleLeaf = {getClientRects:()=>[1],closest:()=>null};
    const hiddenLeaf = {getClientRects:()=>[],closest:()=>({hidden:true})};
    const outer = {textContent:splitJSON+hiddenJSON,getClientRects:()=>[1],closest:()=>null,parentElement:sandbox.document.body};
    let wrapper=outer;
    for(let n=0;n<9;n++) wrapper={textContent:"fragment",getClientRects:()=>[1],closest:()=>null,parentElement:wrapper};
    visibleLeaf.parentElement=wrapper; hiddenLeaf.parentElement=outer;
    const splitAt=splitJSON.indexOf(splitReply.request_id)+12;
    const splitNodes=[{nodeValue:splitJSON.slice(0,splitAt),parentElement:visibleLeaf},
        {nodeValue:splitJSON.slice(splitAt),parentElement:visibleLeaf},
        {nodeValue:hiddenJSON,parentElement:hiddenLeaf}];
    sandbox.document.createTreeWalker=(root,type,filter)=>{
        const nodes=splitNodes.filter(node=>!filter || filter.acceptNode(node)===1);
        let index=-1;
        return {currentNode:root,
            nextNode(){index++;this.currentNode=nodes[index];return this.currentNode||null;},
            lastChild(){index=nodes.length-1;this.currentNode=nodes[index];return this.currentNode;},
            previousNode(){index--;this.currentNode=nodes[index];return this.currentNode||null;}};
    };
    sandbox.document.body.innerText="Rendered visual lines cannot form the original JSON or full request id";
    const splitFound=vm.runInContext('readReply("a7da3f493f6b16098c70c387")',sandbox);
    assert.deepEqual(JSON.parse(splitFound.reply),splitReply);
    assert.equal(splitFound.request_seen,true);
    assert.equal(vm.runInContext('readReply("old-request").reply',sandbox),null);
    const splitDelivered=[];
    sandbox.chrome.runtime.sendMessage=async message=>{
        if(message.kind==="result"){splitDelivered.push(message.data);return {accepted:true};}
        return {connected:true,job:{request_id:splitReply.request_id,prompt:"current request"}};
    };
    box.value="";
    vm.runInContext('working=false;pendingResult=null;attempted.clear()',sandbox);
    await vm.runInContext('pollOnce()',sandbox);
    assert.equal(splitDelivered.length,1);
    assert.equal(splitDelivered[0].error,undefined);
    assert.deepEqual(JSON.parse(splitDelivered[0].text),splitReply);
    assert.equal(vm.runInContext('pendingResult',sandbox),null);
    console.log("PASS split nonce and deeply nested JSON are joined without accepting a hidden sibling");
    delete sandbox.document.createTreeWalker;
    console.log("PASS prose replies and split div/span text outside the body tail are read without accepting hidden or stale data");
    box.value = "player's unsent text";
    vm.runInContext('activeRequest="next"', sandbox);
    await assert.rejects(vm.runInContext('execute({request_id:"next",prompt:"next"})', sandbox), /已有内容/);
    const popupCode = fs.readFileSync("tools/companion_bridge/browser_extension/popup.js", "utf8");
    async function popup(ready, httpOk, networkError = false, savedToken = null) {
        const controls = {connect: {}, stop: {}, token: {value: savedToken ? "" : "x".repeat(40)}, status: {textContent: ""}, autoNew: {checked: true}};
        let settings = savedToken ? {buddyToken: savedToken} : {};
        let fetches = 0, stored = false;
        const context = {document: {getElementById: id => controls[id]},
            AbortController, setTimeout, clearTimeout,
            chrome: {tabs: {query: async () => [{id: 8, url: "https://chat.deepseek.com/a/chat/s/test"}],
                sendMessage: async () => { if (!ready) throw new Error("Receiving end does not exist"); return {ready: true}; }},
                storage: {local: {get: async () => settings, set: async value => { stored = true; settings = {...settings, ...value}; },
                    remove: async keys => { for (const key of keys) delete settings[key]; }}, session: {remove: async () => {}}}},
            fetch: async () => { fetches++; if (networkError) throw new Error("Failed to fetch");
                return {ok: httpOk, json: async () => httpOk ? {} : {error: "网页连接码不正确"}}; }};
        vm.createContext(context);
        context.importScripts = () => {};
        vm.runInContext(fs.readFileSync("tools/companion_bridge/browser_extension/sites.js", "utf8"), context); vm.runInContext(popupCode, context);
        await new Promise(setImmediate);
        await controls.connect.onclick();
        return {message: controls.status.textContent, fetches, stored, token: controls.token.value,
            stop: async () => { await controls.stop.onclick(); return settings; }};
    }
    const missing = await popup(false, true);
    assert.ok(missing.stored && missing.fetches === 0 && missing.message.includes("F5"));
    assert.match((await popup(true, false)).message, /连接失败.*网页连接码不正确/);
    assert.match((await popup(true, true)).message, /网页脚本和本机助手均已连通/);
    assert.match((await popup(true, true, true)).message, /连接失败.*Failed to fetch/);
    const restored = await popup(true, true, false, "saved".repeat(8));
    assert.equal(restored.token, "saved".repeat(8));
    const stopped = await restored.stop(); assert.equal(stopped.buddyDisabled, true); assert.equal(stopped.buddyToken, undefined);
    await backgroundChecks();
    vm.runInContext('working=false;pendingResult={request_id:"pending",text:"reply"}', sandbox);
    sandbox.chrome.runtime.sendMessage = async () => ({error: "assistant offline"});
    await vm.runInContext("pollOnce()", sandbox);
    assert.equal(vm.runInContext("pendingResult.request_id", sandbox), "pending");
    sandbox.chrome.runtime.sendMessage = async message => message.kind === "result" ? {accepted: true} : {connected: true};
    await vm.runInContext("pollOnce()", sandbox);
    assert.equal(vm.runInContext("pendingResult", sandbox), null);
    let checkCalls = 0, release;
    sandbox.chrome.runtime.sendMessage = () => { checkCalls++; return new Promise(resolve => { release = resolve; }); };
    vm.runInContext('working=true;activeRequest="long-inference"', sandbox);
    const checking = vm.runInContext("pollOnce()", sandbox);
    await vm.runInContext("pollOnce();pollOnce()", sandbox);
    assert.equal(checkCalls, 1);
    release({connected: true, job: {request_id: "long-inference"}}); await checking;
    const staleCheck = vm.runInContext("pollOnce()", sandbox);
    vm.runInContext('activeRequest="new-inference"', sandbox);
    release({connected: true, job: {request_id: "long-inference"}}); await staleCheck;
    assert.equal(vm.runInContext("activeRequest", sandbox), "new-inference");
    vm.runInContext("working=false", sandbox);
    let resumed = false;
    const timers = [];
    sandbox.setTimeout = (fn, ms) => { const task = {fn, ms}; timers.push(task); return task; };
    const wait = vm.runInContext("sleep(1000)", sandbox).then(() => { resumed = true; });
    timers.at(-1).fn(); assert.equal(timers.length, 2); assert.equal(timers.at(-1).ms, 1000);
    vm.runInContext("wakeSleep()", sandbox); await Promise.resolve(); assert.equal(resumed, false);
    clock += 2000; timers.at(-1).fn(); await wait; assert.equal(resumed, true);
    console.log("PASS page JSON/submission, popup errors, transient-result retry and bounded inference heartbeat (not a live website test)");
}
async function backgroundChecks() {
    const drain = () => new Promise(setImmediate);
    async function harness(initial = {}) {
        let state = {buddyToken: "persisted-web-token-12345", buddyTab: 8, buddyUrl: "https://chat.deepseek.com/a/chat/s/original", ...initial};
        let tabs = [{id: 8, url: state.buddyUrl, active: true}], ready = true, online = true, hanging = false;
        let changed, alarm, message;
        const events = {}, posts = [], timers = [];
        const context = {AbortController,
            setTimeout(fn, ms) { const timer = {fn, ms}; timers.push(timer); return timer; },
            clearTimeout(timer) { if (timer) timer.cancelled = true; },
            chrome: {
                storage: {onChanged: {addListener(fn) { changed = fn; }},
                    local: {get: async () => ({...state}), set: async data => { state = {...state, ...data}; }},
                    session: {get: async () => ({}), remove: async () => {}}},
                alarms: {get: async () => null, create() {}, clear() {}, onAlarm: {addListener(fn) { alarm = fn; }}},
                tabs: {query: async () => tabs,
                    sendMessage: async () => ready ? {ready: true} : {ready: false},
                    onUpdated: {addListener(fn) { events.updated = fn; }},
                    onActivated: {addListener(fn) { events.activated = fn; }},
                    onRemoved: {addListener(fn) { events.removed = fn; }}},
                runtime: {id: "extension", onMessage: {addListener(fn) { message = fn; }}, onStartup: {addListener() {}}}},
            fetch: async (url, options) => {
                posts.push({url, data: JSON.parse(options.body)});
                if (!online) throw new Error("Failed to fetch");
                if (hanging) await new Promise((resolve, reject) => options.signal.addEventListener("abort", () => {
                    const failure = new Error("aborted"); failure.name = "AbortError"; reject(failure);
                }));
                return {ok: true, json: async () => ({job: null})};
            }};
        vm.createContext(context);
        context.importScripts = () => {};
        vm.runInContext(fs.readFileSync("tools/companion_bridge/browser_extension/sites.js", "utf8"), context);
        vm.runInContext(fs.readFileSync("tools/companion_bridge/browser_extension/background.js", "utf8"), context);
        await drain();
        return {
            state: () => state, posts, timers, events, context,
            setTabs(value) { tabs = value; }, setReady(value) { ready = value; },
            setOnline(value) { online = value; }, setHanging(value) { hanging = value; },
            disable() { state = {buddyDisabled: true}; changed({buddyDisabled: {}}, "local"); },
            alarm: () => alarm({name: "buddy-page-heartbeat"}),
            call(id, url, kind = "poll", data = {}) {
                return new Promise(resolve => message({kind, data}, {id: "extension", frameId: 0, url, tab: {id}}, resolve));
            }
        };
    }
    const h = await harness();
    assert.ok(h.posts.length && h.posts.every(p => p.url.endsWith("/heartbeat")));
    const token = h.state().buddyToken;
    h.setTabs([{id: 19, url: "https://chat.deepseek.com/a/chat/s/new", active: true}]);
    h.events.updated(19, {status: "complete"}, {url: "https://chat.deepseek.com/a/chat/s/new"}); await drain();
    assert.equal(h.state().buddyTab, 19); assert.equal(h.state().buddyToken, token);
    assert.equal(h.state().buddyUrl, "https://chat.deepseek.com/a/chat/s/new");
    console.log("PASS reopening a different chat automatically reuses the persisted code");
    const old = h.posts.length;
    h.setTabs([]); await h.alarm(); assert.equal(h.posts.length, old);
    h.setTabs([{id: 25, url: "https://chat.deepseek.com/a/chat/s/refresh", active: true}]);
    h.setReady(false); await h.alarm(); assert.equal(h.posts.length, old);
    h.setReady(true); h.events.activated({tabId: 25}); await drain();
    assert.equal(h.state().buddyTab, 25); assert.ok(h.posts.length > old);
    console.log("PASS closed/missing-script pages never generate invented heartbeats");
    h.setOnline(false); await h.alarm(); const beforeRestart = h.posts.length;
    h.setOnline(true); await h.alarm();
    assert.ok(h.posts.length > beforeRestart && h.state().buddyToken === token);
    console.log("PASS assistant restart retries without changing the code");
    h.setTabs([{id: 25, url: "https://chat.deepseek.com/a/chat/s/refresh", active: false},
               {id: 30, url: "https://chat.deepseek.com/a/chat/s/personal", active: true}]);
    assert.equal((await h.call(30, "https://chat.deepseek.com/a/chat/s/personal")).connected, false);
    assert.equal(h.state().buddyTab, 25);
    h.setTabs([{id: 40, url: "https://chat.deepseek.com/a/chat/s/a", active: false},
               {id: 41, url: "https://chat.deepseek.com/a/chat/s/b", active: false}]);
    const beforeAmbiguous = h.posts.length; await h.alarm(); assert.equal(h.posts.length, beforeAmbiguous);
    h.events.activated({tabId: 41}); await drain(); assert.equal(h.state().buddyTab, 41);
    console.log("PASS existing selection is retained; ambiguous multiple pages wait for activation");
    h.setHanging(true);
    const request = h.call(41, "https://chat.deepseek.com/a/chat/s/b"); await drain();
    const timeout = h.timers.filter(t => t.ms === 8000 && !t.cancelled).at(-1); assert.ok(timeout);
    timeout.fn(); assert.match((await request).error, /超时/);
    h.setHanging(false); assert.equal((await h.call(41, "https://chat.deepseek.com/a/chat/s/b")).connected, true);
    console.log("PASS stalled HTTP requests time out and subsequent requests recover");
    h.disable(); await drain(); const beforeStop = h.posts.length; await h.alarm();
    assert.equal(h.posts.length, beforeStop); assert.equal(h.state().buddyToken, undefined);
    console.log("PASS explicit disconnect keeps automatic recovery disabled");
}
main().catch(error => { console.error(error); process.exitCode = 1; });

assert.equal(JSON.parse(parse('{"request_id":"nonce","plan":{"goal":"swap","bindings":{"old":"e1","new":"e2"}},"skill":"drop","arguments":{"item":"e1"}}')).plan.bindings.old, "e1");
