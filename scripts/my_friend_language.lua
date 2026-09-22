-- Loads reviewed language files from scripts/languages/<code>/.
local M = {}
local function Load(language, filename, legacy)
    local code = type(language) == "string" and language:lower() or "zh"
    local ok, value = pcall(require, "languages/" .. code .. "/" .. filename)
    if ok and type(value) == "table" then return value end
    if code ~= "zh" then
        ok, value = pcall(require, "languages/zh/" .. filename)
        if ok and type(value) == "table" then return value end
    end
    if legacy ~= nil then
        ok, value = pcall(require, legacy .. "_" .. code)
        if ok and type(value) == "table" then return value end
        if code ~= "zh" then
            ok, value = pcall(require, legacy .. "_zh")
            if ok and type(value) == "table" then return value end
        end
    end
end
function M.CommandWords(language) return Load(language, "command_words", "my_friend_command_words") end
function M.DialogueLines(language) return Load(language, "dialogue_lines", "my_friend_dialogue_lines") end
function M.Pack(language, base) return Load(language, base, base) end
return M
