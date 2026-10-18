-- Private game-chat protocol. This module never calls public chat APIs.
local M = {MAX_BYTES = 320, MAX_MESSAGES = 40, QUICK_COUNT = 5, BOT_COUNT = 8}
M.MESSAGE_COUNTS = {bot = 8, player_win = 3, player_loss = 3, cheer = 3}
local loaded, source, names, glyphs = false, nil, {}, {}
function M.EmojiCatalog(refresh)
    if not loaded then loaded = true; if EMOJI_ITEMS == nil then pcall(require, "emoji_items") end end
    if refresh or source ~= EMOJI_ITEMS then
        source, names, glyphs = EMOJI_ITEMS, {}, {}
        for _, item in pairs(source or {}) do
            if type(item) == "table" and type(item.input_name) == "string" and item.input_name ~= ""
                and type(item.data) == "table" and type(item.data.utf8_str) == "string" then
                if glyphs[item.input_name] == nil then names[#names + 1] = item.input_name end
                glyphs[item.input_name] = item.data.utf8_str
            end
        end
        table.sort(names)
    end
    return names
end
local function UTF8(text)
    local i = 1
    while i <= #text do
        local b, count, cp = text:byte(i), 0, 0
        if b < 128 then count, cp = 1, b
        elseif b >= 194 and b <= 223 then count, cp = 2, b - 192
        elseif b >= 224 and b <= 239 then count, cp = 3, b - 224
        elseif b >= 240 and b <= 244 then count, cp = 4, b - 240
        else return false end
        for n = 1, count - 1 do
            local c = text:byte(i + n)
            if c == nil or c < 128 or c > 191 then return false end
            cp = cp * 64 + c - 128
        end
        if count == 3 and cp < 2048 or count == 4 and cp < 65536
            or cp > 1114111 or cp >= 55296 and cp <= 57343 then return false end
        i = i + count
    end
    return true
end
function M.Normalize(kind, value)
    if kind == "text" then
        if type(value) ~= "string" or #value > M.MAX_BYTES or not UTF8(value) then return end
        value = value:gsub("[%c]", " "):match("^%s*(.-)%s*$")
        if value ~= "" then return value end
    elseif kind == "quick" then
        if type(value) == "number" and value % 1 == 0 and value >= 1 and value <= M.QUICK_COUNT then return value end
    elseif kind == "emoji" and type(value) == "string" then
        M.EmojiCatalog()
        if glyphs[value] ~= nil then return value end
    end
end
function M.Valid(entry)
    if type(entry) ~= "table" or type(entry.name) ~= "string" or type(entry.seq) ~= "number" then return false end
    local count = M.MESSAGE_COUNTS[entry.kind]
    if count ~= nil then
        return type(entry.value) == "number" and entry.value % 1 == 0 and entry.value >= 1 and entry.value <= count
            and (entry.kind == "bot" or type(entry.target) == "string")
    end
    return M.Normalize(entry.kind, entry.value) ~= nil
end
function M.Glyph(name)
    M.EmojiCatalog()
    return glyphs[name] or ":" .. name .. ":"
end
function M.Display(entry)
    local L = require("my_friend_games_strings")
    if entry.kind == "quick" then return L.Get("quick_" .. tostring(entry.value)) end
    if M.MESSAGE_COUNTS[entry.kind] ~= nil then
        local key = entry.kind .. "_" .. tostring(entry.value)
        return entry.kind == "bot" and L.Get(key) or L.Format(key, entry.target)
    end
    local text = entry.kind == "emoji" and (":" .. entry.value .. ":") or entry.value
    return text:gsub(":([%w_]+):", M.Glyph)
end
return M
