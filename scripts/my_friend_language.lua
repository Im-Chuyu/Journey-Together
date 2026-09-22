-- Loads reviewed language files from scripts/languages/<code>/.
local M = {}
local function Load(language, filename)
    local code = type(language) == "string" and language:lower() or "zh"
    local ok, value = pcall(require, "languages/" .. code .. "/" .. filename)
    if ok and type(value) == "table" then return value end
    if code ~= "zh" then
        ok, value = pcall(require, "languages/zh/" .. filename)
        if ok and type(value) == "table" then return value end
    end
end
function M.CommandWords(language)
    local source = Load(language, "command_words")
    if type(source) ~= "table" then return end
    local result = {}
    for _, entry in ipairs(source) do
        if type(entry) == "table" and type(entry.id) == "string" then
            local words = entry.keywords or entry[language]
                or entry.zh or entry.en
            if type(words) == "table" then
                result[#result + 1] = {id = entry.id, keywords = words}
            end
        end
    end
    return result
end
function M.DialogueLines(language) return Load(language, "dialogue_lines") end
return M
