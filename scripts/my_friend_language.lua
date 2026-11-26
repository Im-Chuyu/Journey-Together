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
                    character = entry.character, label = entry.label, portal_keywords = entry.portal_keywords}
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
                    label = entry.label or entry[code .. "_label"],
                    book_aliases = entry.book_aliases}
            end
        end
    end
    return result
end
-- Both ends need the same IDs before the game's character list is complete.
-- Empty keyword lists can still describe a wheel button.
function M.CommandCatalogue(language)
    local entries = M.CommandWords(language) or {}
    local seen = {}
    local function AddCharacter(character)
        if type(character) ~= "string" or seen[character] then return end
        seen[character] = true
        for _, entry in ipairs(M.CharacterCommandWords(language, character)) do
            entry.character = character
            entries[#entries + 1] = entry
        end
    end
    for _, character in ipairs(require("my_friend_characters").List()) do AddCharacter(character) end
    for _, character in ipairs({"wendy", "wickerbottom", "warly", "wanda", "wathgrithr", "wortox"}) do
        AddCharacter(character)
    end
    return entries
end

return M
