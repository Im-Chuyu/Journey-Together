-- Replies are contextual conversation, never command ids or wheel entries.
local Language = require("my_friend_strings")
local Files = require("my_friend_language")
local M = {}
local function Normalize(text)
    if type(text) ~= "string" then return end
    return text:lower():gsub("[,%.!?:;]", "")
        :gsub("。", ""):gsub("！", ""):gsub("？", ""):gsub("，", ""):gsub("：", "")
        :gsub("%s+", " "):match("^%s*(.-)%s*$")
end
function M.Match(kind, text)
    local answer = Normalize(text)
    if answer == nil or answer == "" then return end
    local data = Files.DialogueLines(Language.language)
    local group = data ~= nil and data.chat_replies ~= nil and data.chat_replies[kind] or nil
    if type(group) ~= "table" then return end
    -- Whole answers avoid treating "not okay" or "不太好" as agreement.
    for _, outcome in ipairs({"no", "yes"}) do
        for _, word in ipairs(group[outcome] or {}) do
            if answer == Normalize(word) then return outcome end
        end
    end
end
return M
