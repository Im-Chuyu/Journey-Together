"use strict";
document.getElementById("autoNew").onchange = async event => {
    await chrome.storage.local.set({buddyAutoNew: event.target.checked});
};
void (async () => {
    const saved = await chrome.storage.local.get(["buddyToken", "buddyDisabled", "buddyAutoNew"]);
    document.getElementById("autoNew").checked = saved.buddyAutoNew !== false;
    if (saved.buddyToken && !saved.buddyDisabled) {
        const input = document.getElementById("token");
        if (!input.value) input.value = saved.buddyToken;
        document.getElementById("status").textContent = "连接码已保存，重新打开网页或助手后会自动重连，无需重复输入。";
    }
})().catch(() => {});
document.getElementById("connect").onclick = async () => {
    const status = document.getElementById("status");
    try {
        const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
        const token = document.getElementById("token").value.trim();
        if (!tab || !BuddySites.identify(tab.url) || token.length < 20) {
            document.getElementById("status").textContent = "请在 DeepSeek 或豆包聊天页填写助手显示的连接码。";
            return;
        }
        await chrome.storage.local.set({buddyToken: token, buddyTab: tab.id, buddyUrl: tab.url.split("#")[0], buddyDisabled: false, buddyProvider: BuddySites.identify(tab.url).id, buddyAutoNew: document.getElementById("autoNew").checked});
        let page, pingTimer;
        try {
            page = await Promise.race([chrome.tabs.sendMessage(tab.id, {kind: "buddy_ping"}),
                new Promise(resolve => { pingTimer = setTimeout(() => resolve(null), 4000); })]);
        } catch (_) { /* an already-open tab has not loaded the content script */ }
        finally { clearTimeout(pingTimer); }
        if (!page || !page.ready) {
            status.textContent = "连接码已保存，但网页脚本尚未加载或未响应。请关闭此弹窗，按 F5 刷新当前聊天页，随后会自动连接。";
            return;
        }
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 8000);
        let response, data;
        try {
            response = await fetch("http://127.0.0.1:18766/v1/model/heartbeat", {
                method: "POST", headers: {"Content-Type": "application/json"},
                body: JSON.stringify({model_token: token}), signal: controller.signal
            });
            data = await response.json();
        } finally { clearTimeout(timeout); }
        if (!response.ok) throw new Error(data.error || "助手拒绝网页连接");
        status.textContent = "网页脚本和本机助手均已连通。保持此聊天页打开，再检查助手的游戏配对状态。";
    } catch (error) {
        status.textContent = "连接失败：" + error.message + "。已保存的连接码会继续自动重试，请启动助手；仅连接码错误时需要重新复制。";
    }
};
document.getElementById("stop").onclick = async () => {
    await chrome.storage.local.set({buddyDisabled: true});
    await chrome.storage.local.remove(["buddyToken", "buddyTab", "buddyUrl"]);
    await chrome.storage.session.remove(["buddyToken", "buddyTab"]);
    document.getElementById("status").textContent = "已断开网页桥接。";
};
