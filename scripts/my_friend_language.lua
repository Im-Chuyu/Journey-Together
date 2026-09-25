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
                result[#result + 1] = {id = entry.id, keywords = words,
                    character = entry.character, label = entry.label}
            end
        end
    end
    return result
end
function M.DialogueLines(language, character)
    if type(character) == "string" and character ~= "" then
        local code = type(language) == "string" and language:lower() or "zh"
        local ok, value = pcall(require,
            "languages/" .. code .. "/characters/" .. character)
        if ok and type(value) == "table" then return value end
        if character ~= "wendy" then
            ok, value = pcall(require, "languages/" .. code .. "/characters/wendy")
            if ok and type(value) == "table" then return value end
        end
    end
    return Load(language, "dialogue_lines")
end
function M.CharacterCommandWords(language, character)
    if type(character) ~= "string" or character == "" then return {} end
    local code = type(language) == "string" and language:lower() or "zh"
    local ok, source = pcall(require,
        "languages/" .. code .. "/characters/" .. character .. "_command_words")
    if (not ok or type(source) ~= "table") and code ~= "zh" then
        ok, source = pcall(require,
            "languages/zh/characters/" .. character .. "_command_words")
    end
    if not ok or type(source) ~= "table" then return {} end
    local result = {}
    for _, entry in ipairs(source) do
        if type(entry) == "table" and type(entry.id) == "string" then
            local words = entry.keywords or entry[code] or entry.zh or entry.en
            if type(words) == "table" then
                result[#result + 1] = {id = entry.id, keywords = words,
                    label = entry.label or entry[code .. "_label"]}
            end
        end
    end
    return result
end
return M
