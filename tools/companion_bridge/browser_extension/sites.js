"use strict";
// Site-specific visible-page capabilities; no cookies or private API adapters.
globalThis.BuddySites = {
    patterns: ["https://chat.deepseek.com/*", "https://www.doubao.com/*", "https://doubao.com/*"],
    identify(url) {
        if (/^https:\/\/chat\.deepseek\.com\/(?:a\/chat(?:\/s\/[\w-]+)?)?\/?(?:[?#]|$)/.test(url || "")) return {id: "deepseek", name: "DeepSeek", home: "https://chat.deepseek.com/"};
        if (/^https:\/\/(?:www\.)?doubao\.com\/(?:chat(?:\/\d*)?)?(?:[?#]|$)/.test(url || "")) return {id: "doubao", name: "豆包", home: "https://www.doubao.com/chat/"};
        return null;
    },
    limit(text) {
        return /(?:达到|已达|超出|超过)[^。\n]{0,8}(?:对话|会话|聊天)[^。\n]{0,15}(?:上限|限制|最大长度)|(?:当前|本次|这个|该)?(?:对话|会话|聊天)[^。\n]{0,35}(?:达到|已达|超出|超过)[^。\n]{0,20}(?:上限|限制|最大长度)|(?:对话|会话|聊天)(?:长度)?(?:过长|太长|已满)|(?:上下文|context)[^。\n]{0,30}(?:已满|超长|上限|limit|too long)|(?:conversation|chat)[^。\n]{0,35}(?:limit|too long|maximum length)/i.test(text);
    },
};
