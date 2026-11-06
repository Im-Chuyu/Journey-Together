"use strict";
globalThis.__buddyContentLoaded = true;
chrome.runtime.onMessage.addListener((message, sender, reply) => {
    if (sender.id === chrome.runtime.id && message.kind === "buddy_ping") {
        reply({ready: true});
        if (wakeSleep) wakeSleep();
        void pollOnce();
    }
});
// Only visible DOM is used. No site internals, cookies or unofficial endpoints.
let working = false;
let checking = false;
let pendingResult = null;
let activeRequest = null;
let pageProgress = null;
let ownedComposer = null;
const attempted = new Set();
let wakeSleep = null;
const sleep = ms => new Promise(resolve => {
    const due = Date.now() + ms;
    let timer;
    const finish = () => {
        if (timer !== undefined) clearTimeout(timer);
        const remaining = due - Date.now();
        // A timer can fire before the wall-clock deadline (or a ping can wake
        // us early). Re-arm it instead of leaving this Promise unresolved.
        if (remaining > 0) { timer = setTimeout(finish, remaining); return; }
        if (wakeSleep === finish) wakeSleep = null;
        resolve();
    };
    wakeSleep = finish;
    timer = setTimeout(finish, ms);
});
// Observe only while waiting for a reply. Coalesce streaming mutations to at
// most four DOM reads/second; the timer also works on quiet/background pages.
function waitReplyChange(ms) {
    return new Promise(resolve => {
        const started = Date.now();
        let timer, wakeTimer, observer;
        const finish = () => {
            clearTimeout(timer);
            if (wakeTimer !== undefined) clearTimeout(wakeTimer);
            if (observer) observer.disconnect();
            if (wakeSleep === wake) wakeSleep = null;
            resolve();
        };
        const wake = () => {
            if (wakeTimer === undefined)
                wakeTimer = setTimeout(finish, Math.max(0, 250 - (Date.now() - started)));
        };
        wakeSleep = wake;
        if (typeof MutationObserver !== "undefined" && document.body) {
            observer = new MutationObserver(wake);
            observer.observe(document.body, {childList: true, characterData: true, subtree: true});
        }
        timer = setTimeout(finish, ms);
    });
}
function inputBox() {
    const doubao = typeof location !== "undefined" && BuddySites.identify(location.href)?.id === "doubao";
    if (doubao) {
        const box = [...document.querySelectorAll('#input-engine-container textarea,#input-engine-container [contenteditable="true"],#input-engine-container[contenteditable="true"]')]
            .find(node => node.getClientRects().length && !node.disabled);
        if (box) return box;
    }
    const selector = doubao ? 'textarea,[contenteditable="true"]'
        : 'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"][data-lexical-editor="true"]';
    return [...document.querySelectorAll(selector)]
        .find(node => node.getClientRects().length && !node.disabled);
}
function contextLimited() {
    // Do not interpret text inside a player's prompt as a website limit alert.
    const skip = 'textarea,[contenteditable="true"],pre,code';
    const nodes = [...document.querySelectorAll('[role="alert"],[role="status"],dialog,p,[class*="toast"],[class*="limit"],[data-testid*="limit"]')];
    if (nodes.some(node => node.getClientRects().length && !node.closest(skip)
        && (node.innerText || node.textContent || "").length < 500
        && !(node.innerText || node.textContent || "").includes('"request_id"')
        && BuddySites.limit(node.innerText || node.textContent || ""))) return true;
    // DeepSeek can render the notice as plain div/span text, without alert
    // semantics. Inspect short visible text near the end, never a giant prompt.
    if (!document.createTreeWalker || typeof NodeFilter === "undefined") return false;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    if (!walker.lastChild()) return false;
    let scanned=0;
    do {
        let node=walker.currentNode.parentElement;
        for (let n=0;n<3 && node && node!==document.body;n++,node=node.parentElement) {
            if (!node.getClientRects().length || node.closest(skip+',script,style,[hidden],[aria-hidden="true"]')) continue;
            const text=(node.textContent || "").trim();
            if (text.length>500) break;
            if (!text.includes('"request_id"') && BuddySites.limit(text)) return true;
        }
    } while (++scanned<6000 && walker.previousNode());
    return false;
}
function newChatButton() {
    const label=/^(?:(?:开启|开始|新建|创建)(?:一个)?新?对话|新对话|New chat|New conversation)(?:$|\s*[（(]?\s*(?:Ctrl|⌘))/i;
    const usable=node => node && node.getClientRects().length && !node.disabled
        && node.getAttribute("aria-disabled")!=="true" && typeof node.click==="function";
    const selector='button,a,[role="button"],[class~="ds-button"]';
    const direct=[...document.querySelectorAll(selector)].find(node => usable(node) && label.test(
        (node.getAttribute("aria-label") || node.getAttribute("title") || node.innerText || "").trim()));
    if (direct) return direct;
    // The sidebar entry may have no button role. Click its exact visible
    // label, allowing the event to bubble to the site's own parent handler.
    if (!document.createTreeWalker || typeof NodeFilter === "undefined") return null;
    const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
    let textNode,scanned=0;
    while ((textNode=walker.nextNode()) && scanned++<6000) {
        const text=(textNode.nodeValue || "").trim();
        if (!label.test(text)) continue;
        const node=textNode.parentElement;
        if (!node || node.closest('textarea,[contenteditable="true"],pre,code,[hidden],[aria-hidden="true"]')) continue;
        const control=node.closest(selector) || node;
        if (usable(control)) return control;
    }
    return null;
}
async function prepareChat(job, reason) {
    const answer = await chrome.runtime.sendMessage({kind: "prepare_chat", data: {request_id: job.request_id, reason}});
    if (answer?.superseded || activeRequest !== job.request_id) throw pageError("request_superseded", "request_superseded");
    if (answer?.error) throw pageError("new_chat_failed", answer.error);
    if (!answer?.rotate) return false;
    const button = newChatButton();
    const oldUrl = location.href;
    const oldBox = inputBox();
    if (oldBox && (oldBox.value || oldBox.textContent || "").trim()) {
        const text = oldBox.value || oldBox.textContent || "";
        if (reason !== "context_limit" || !ownedComposer || ownedComposer.box !== oldBox
            || ownedComposer.request !== job.request_id || text !== ownedComposer.text)
            throw pageError("composer_not_empty", "输入框仍有内容，自动换对话已停止，避免丢失未发送的文字。");
        oldBox.focus();
        if (oldBox instanceof HTMLTextAreaElement) Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set.call(oldBox, "");
        else if (document.execCommand) { document.execCommand("selectAll"); document.execCommand("delete"); }
        else oldBox.textContent = "";
        oldBox.dispatchEvent(new Event("input", {bubbles: true}));
    }
    if (button) button.click();
    else {
        // Collapsed sidebars and limit dialogs can hide the normal control.
        // Navigate only to this provider's public new-chat landing page, after
        // the worker authorized renewal and the composer ownership check.
        const site = BuddySites.identify(location.href);
        if (!site || typeof location.assign !== "function")
            throw pageError("new_chat_unavailable", "没有找到新对话入口，请手动开启普通聊天页后重试。");
        location.assign(site.home);
    }
    // SPA routes keep this script alive; full navigation reloads the script and
    // the same pending nonce is fetched again. The worker bounds restart count.
    for (let n = 0; n < 24; n++) {
        await sleep(500);
        if (activeRequest !== job.request_id) throw pageError("request_superseded", "request_superseded");
        if (inputBox() && !contextLimited() && (location.href !== oldUrl || !document.body.innerText.includes(job.request_id))) return true;
        if (n === 11 && button && contextLimited()) {
            const currentBox = inputBox();
            const site = BuddySites.identify(location.href);
            if (currentBox && !(currentBox.value || currentBox.textContent || "").trim()
                && site && typeof location.assign === "function") location.assign(site.home);
        }
    }
    throw pageError("new_chat_failed", "新对话尚未准备好，请检查页面是否需要手动确认。");
}
function renderWhitespace(text) {
    let quoted = false, escaped = false, out = "";
    for (const char of text) {
        if (quoted) {
            out += char;
            if (escaped) escaped = false;
            else if (char === "\\") escaped = true;
            else if (char === '"') quoted = false;
        } else {
            out += "\u00a0\u202f\u200b\ufeff".includes(char) ? " " : char;
            if (char === '"') quoted = true;
        }
    }
    return out;
}
function objectReply(text, request) {
    if (!text.includes(request)) return null;
    // A balanced JSON object containing the unique request id. Quoted braces
    // and escape characters must not prematurely terminate the object.
    for (let start = text.lastIndexOf('"request_id"'); start >= 0; start = text.lastIndexOf('"request_id"', start - 1)) {
        if (!text.slice(start, start + 120).includes(request)) { if (start === 0) break; continue; }
        for (let pos = text.lastIndexOf("{", start); pos >= 0; pos = text.lastIndexOf("{", pos - 1)) {
            let depth = 0, quoted = false, escaped = false;
            for (let end = pos; end < text.length; end++) {
                const char = text[end];
                if (quoted) { if (escaped) escaped = false; else if (char === "\\") escaped = true; else if (char === '"') quoted = false; }
                else if (char === '"') quoted = true;
                else if (char === "{") depth++;
                else if (char === "}" && --depth === 0) {
                    try { const data = JSON.parse(renderWhitespace(text.slice(pos, end + 1)));
                        if (data.request_id === request && Object.keys(data).every(key =>
                            ["request_id", "text", "skill", "arguments", "plan"].includes(key))) return JSON.stringify(data);
                    } catch (_) { /* wait for a complete JSON reply */ }
                    break;
                }
            }
            if (pos === 0) break;
        }
        if (start === 0) break;
    }
    return null;
}
const replySkip = 'script,style,textarea,input,[contenteditable="true"],[hidden],[aria-hidden="true"]';
function visibleReplyText(node) {
    if (document.createTreeWalker && typeof NodeFilter !== "undefined") {
        const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT, {
            acceptNode(textNode) {
                const parent = textNode.parentElement;
                return parent && parent.getClientRects().length && !parent.closest(replySkip)
                    ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
        });
        if (typeof walker.nextNode === "function") {
            const chunks = [];
            let child, scanned = 0;
            while ((child = walker.nextNode()) && scanned++ < 20000)
                chunks.push(child.nodeValue || "");
            return chunks.join("").slice(-120000);
        }
    }
    return (node.innerText || node.textContent || "").slice(-120000);
}
function readReply(request) {
    const skip = replySkip;
    let requestSeen = false;
    // textContent joins syntax/renderer spans without injecting visual line
    // breaks. Filter hidden descendants before accepting executable JSON.
    function parseNode(node) {
        if (!(node.textContent || node.innerText || "").includes(request)) return null;
        const text = visibleReplyText(node);
        if (!text.includes(request)) return null;
        requestSeen = true;
        return objectReply(text, request);
    }
    // Syntax-highlighted code can have visual line breaks or spacing that
    // differs from its actual text. Read visible code first, preserving strings.
    const blocks = [...document.querySelectorAll("pre,code")].slice(-16).reverse();
    let inspected = 0;
    for (const node of blocks) {
        if (!node.getClientRects().length || node.closest(skip)) continue;
        inspected++;
        const reply = parseNode(node);
        if (reply) return {reply, blocks: inspected, source: "code", request_seen: true};
    }
    // A JSON-only model reply is normally rendered as prose, not a code block.
    // Read each message paragraph independently: a later collapsed prompt or
    // other page section can push that reply outside the body text tail.
    const visible = node => node && node.getClientRects().length && !node.closest(skip);
    const paragraphs = [...document.querySelectorAll("p")].slice(-64).reverse();
    for (const node of paragraphs) {
        if (!visible(node)) continue;
        const reply = parseNode(node);
        if (reply) return {reply, blocks: inspected, source: "page", request_seen: true};
    }
    // Some renderers use div/span message trees. Start at the newest visible
    // text nodes and join their nearest parents without reading hidden state.
    if (document.createTreeWalker && typeof NodeFilter !== "undefined") {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode(node) { return node.parentElement && !node.parentElement.closest(skip)
                ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT; }
        });
        const seen = new Set();
        if (walker.lastChild()) {
            let scanned = 0;
            do {
                const text = walker.currentNode;
                let parent = text.parentElement;
                for (let depth = 0; depth < 24 && parent && parent !== document.body; depth++, parent = parent.parentElement) {
                    if (seen.has(parent)) continue;
                    seen.add(parent);
                    if (!visible(parent)) continue;
                    const content = parent.textContent || "";
                    if (content.length > 120000) continue;
                    const reply = parseNode(parent);
                    if (reply) return {reply, blocks: inspected, source: "page", request_seen: true};
                }
            } while (++scanned < 20000 && walker.previousNode());
        }
    }
    const tail = visibleReplyText(document.body);
    const reply = objectReply(tail, request);
    return {reply, blocks: inspected, source: reply ? "page" : "none", request_seen: requestSeen || tail.includes(request)};
}
function pageError(code, message) {
    const error = new Error(message); error.code = code; return error;
}
function sendButton(box) {
    const usable = node => node && node.getClientRects().length && !node.disabled
        && node.getAttribute("aria-disabled") !== "true"
        && node.getAttribute("data-disabled") !== "true"
        && !/(?:^|[-_\s])disabled(?:[-_\s]|$)/i.test(typeof node.className === "string" ? node.className : "")
        && !(node.closest && node.closest('[disabled],[aria-disabled="true"]'));
    // Doubao's arrow can be an unlabeled div rather than a button. Its
    // composer test id is the action identity; never guess by screen position.
    const explicit = document.querySelectorAll('[data-testid="chat_input_send_button"],[data-testid="send_button"],[data-testid="send-message-button"],[data-testid="send_message_button"]');
    for (const node of explicit) if (usable(node) && typeof node.click === "function") return node;
    let root = box.parentElement;
    for (let depth=0; root && root!==document.body && depth<5; depth++,root=root.parentElement) {
        const arrows = root.querySelectorAll('[data-testid*="send"],[class*="send-button"],[class*="send-btn"],[class*="sendButton"],[class*="send_btn"],[class*="sendBtn"]');
        for (const node of arrows) {
            const control = typeof node.click === "function" ? node : node.closest('button,[role="button"],div');
            if (usable(control) && typeof control.click === "function") return control;
        }
    }
    return [...document.querySelectorAll('button,[role="button"]')].find(node => usable(node) &&
        /^(发送|发送消息|send|send message)(?:\s*[（(]?(?:Enter|回车)[）)]?)?$/i.test(
            (node.getAttribute("aria-label") || node.getAttribute("title") || node.innerText || "").trim()));
}
async function execute(job, prepared = false, deadline = Date.now() + 280000) {
    if (activeRequest !== job.request_id) throw pageError("request_superseded", "request_superseded");
    pageProgress = {request_id: job.request_id, phase: "preparing", blocks: 0};
    if (!prepared && contextLimited() && !await prepareChat(job, "context_limit"))
        throw pageError("context_limit", "会话已达上限，请开启自动新对话或手动新建后重试。");
    const box = inputBox();
    if (!box) throw pageError("no_input", "没有找到聊天输入框；请完成登录并打开普通文字聊天页。");
    if ((box.value || box.textContent || "").trim()) throw pageError("composer_not_empty", "聊天输入框已有内容，请清空或使用专用聊天标签页。");
    box.focus();
    if (box instanceof HTMLTextAreaElement) {
        Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set.call(box, job.prompt);
    } else {
        // Rich editors (including Doubao) need a native editing transaction so
        // their application state receives the text, not just a DOM replacement.
        const inserted = document.execCommand && document.execCommand("insertText", false, job.prompt);
        if (!inserted) box.textContent = job.prompt;
    }
    box.dispatchEvent(typeof InputEvent === "function"
        ? new InputEvent("input", {bubbles: true, inputType: "insertText", data: job.prompt})
        : new Event("input", {bubbles: true}));
    ownedComposer = {box, request: job.request_id, text: box.value || box.textContent || ""};
    function unsentComposer() {
        // The first DeepSeek submission can replace the landing-page editor.
        // Its detached node may retain the already-sent prompt indefinitely.
        // Inspect the current visible editor; never resend from a stale node.
        const current = inputBox();
        const editor = current || (box.isConnected === false ? null : box);
        return editor && (editor.value || editor.textContent || "").trim() ? editor : null;
    }
    await sleep(400);
    if (activeRequest !== job.request_id) throw pageError("request_superseded", "request_superseded");
    const doubao = typeof location !== "undefined" && BuddySites.identify(location.href)?.id === "doubao";
    let clicked = false;
    if (doubao) {
        // Wait briefly for the rich editor to enable its actual send control.
        for (let n = 0; n < 12; n++) {
            if (activeRequest !== job.request_id) throw pageError("request_superseded", "request_superseded");
            const send = sendButton(box);
            if (send) { send.click(); clicked = true; break; }
            await sleep(100);
        }
    }
    if (!clicked) {
        for (const type of ["keydown", "keypress", "keyup"])
            box.dispatchEvent(new KeyboardEvent(type, {key: "Enter", code: "Enter", keyCode: 13, which: 13,
                charCode: type === "keypress" ? 13 : 0, bubbles: true, cancelable: true}));
    }
    await sleep(1400);
    if (activeRequest !== job.request_id) throw pageError("request_superseded", "request_superseded");
    if (!clicked && unsentComposer() === box && !readReply(job.request_id).request_seen) {
        const send = sendButton(box);
        if (send) { send.click(); clicked = true; }
    }
    // DeepSeek's first route transition can leave a visible editor containing
    // the sent prompt. The current nonce in the visible transcript also proves
    // submission; the editor and hidden DOM never count as that evidence.
    for (let n=0; n<30 && unsentComposer() && !contextLimited()
        && !readReply(job.request_id).request_seen; n++) {
        await sleep(400);
        if (activeRequest !== job.request_id) throw pageError("request_superseded", "request_superseded");
    }
    if (unsentComposer() && !contextLimited() && !readReply(job.request_id).request_seen)
        throw pageError("send_not_confirmed", "输入仍停留在网页编辑框，发送未确认。请检查发送控件或输入法状态；为避免重复发送，本轮没有再次点击。");
    pageProgress.phase = "waiting_reply";
    while (Date.now() < deadline) {
        if (activeRequest !== job.request_id) throw pageError("request_superseded", "request_superseded");
        // Exclude the composer. Only a JSON object with this request's nonce
        // may cross back into the game; prose/reasoning is never executed.
        const found = readReply(job.request_id);
        const reply = found.reply;
        if (!reply && contextLimited()) {
            if (await prepareChat(job, "context_limit")) return execute(job, true, deadline);
            throw pageError("context_limit", "会话已达上限，请开启自动新对话或手动新建后重试。");
        }
        pageProgress = {request_id: job.request_id, phase: reply ? "reply_detected" : "waiting_reply",
            blocks: found.blocks, source: found.source, request_seen: found.request_seen};
        if (reply) return reply;
        await waitReplyChange(750);
    }
    throw pageError("reply_timeout", pageProgress?.request_seen
        ? "扩展读取网页回复超时：页面出现本轮 request_id，但尚未拼接出完整有效的 JSON。请检查回复是否完整或被页面格式拆分。"
        : "扩展读取网页回复超时：页面尚未发现匹配本轮 request_id 的 JSON。请检查回复编号、消息是否显示在当前页面及网页加载状态。");
}
async function pollOnce() {
    if (working) {
        // Inference can take minutes. Keep the page heartbeat alive while the
        // same request is running; do not submit its prompt a second time.
        if (checking) return;
        checking = true;
        const checkedRequest = activeRequest;
        try {
            const state = await chrome.runtime.sendMessage({kind: "poll", data: {progress: pageProgress}});
            if (working && activeRequest === checkedRequest && state && (state.connected === false || state.connected
                && (!state.job || state.job.request_id !== activeRequest))) {
                activeRequest = null;
                if (wakeSleep) wakeSleep();
            }
        } catch (_) {}
        finally { checking = false; }
        return;
    }
    working = true;
    try {
        if (pendingResult) {
            const ack = await chrome.runtime.sendMessage({kind: "result", data: pendingResult});
            if (ack && ack.accepted) pendingResult = null;
        }
        const reply = await chrome.runtime.sendMessage({kind: "poll", data: {}});
        const job = reply && reply.job;
        if (pendingResult && reply && reply.connected && (!job || job.request_id !== pendingResult.request_id)) pendingResult = null;
        if (!reply || !reply.connected || !job || attempted.has(job.request_id)) return;
        attempted.add(job.request_id);
        activeRequest = job.request_id;
        if (attempted.size > 64) attempted.delete(attempted.values().next().value);
        let text = "", error, error_code;
        try { text = await execute(job); } catch (failure) { error = failure.message; error_code = failure.code || "page_error"; }
        pageProgress = {request_id: job.request_id, phase: error ? "failed" : "returning", blocks: pageProgress ? pageProgress.blocks : 0};
        pendingResult = {request_id: job.request_id, text, error, error_code};
        const ack = await chrome.runtime.sendMessage({kind: "result", data: pendingResult});
        if (ack && ack.accepted) pendingResult = null;
    } catch (_) { /* app is closed, unpaired, or the tab was refreshed */ }
    finally { working = false; }
}
setInterval(pollOnce, 1200);
for (const event of ["pageshow", "focus", "online"]) window.addEventListener(event, () => { void pollOnce(); });
document.addEventListener("visibilitychange", () => { if (!document.hidden) void pollOnce(); });
void pollOnce();
