local Cooking = require("cooking")

local M = {}

local function Has(text, word)
    return type(text) == "string" and text:find(word, 1, true) ~= nil
end

local function Find(text, entries)
    local best, length, position
    for _, entry in ipairs(entries) do
        for _, alias in ipairs(entry.aliases) do
            local first = text:find(alias, 1, true)
            if first ~= nil and (length == nil or #alias > length) then
                best, length, position = entry, #alias, first
            end
        end
    end
    return best, position
end

local function Any(text, words)
    for _, word in ipairs(words) do if Has(text, word) then return true end end
end

local BOOKS = {
    {recipe = "book_rain", aliases = {"求雨仪式", "雨书", "下雨", "求雨", "雨"}},
    {recipe = "book_horticulture", aliases = {"园艺书", "园艺", "种植"}},
    {recipe = "book_horticulture_upgraded", aliases = {"高级园艺书", "高级园艺"}},
    {recipe = "book_silviculture", aliases = {
        "森林学", "树木书", "长树", "应用造林学", "造林学", "造林"
    }},
    {recipe = "book_research_station", aliases = {"研究书", "研究"}},
    {recipe = "book_birds", aliases = {"鸟书", "鸟"}},
    {recipe = "book_fish", aliases = {"鱼书", "鱼"}},
    {recipe = "book_bees", aliases = {"蜜蜂书", "养蜂"}},
    {recipe = "book_sleep", aliases = {"睡眠书", "睡觉"}},
    {recipe = "book_brimstone", aliases = {"雷书", "雷电"}},
    {recipe = "book_fire", aliases = {"火书", "生火"}},
    {recipe = "book_tentacles", aliases = {"触手书", "触手"}},
    {recipe = "book_web", aliases = {"蜘蛛书", "蛛网"}},
    {recipe = "book_moon", aliases = {"月亮书", "月光"}},
    {recipe = "book_light", aliases = {"光书", "发光"}},
    {recipe = "book_light_upgraded", aliases = {"高级光书", "高级发光"}},
    {recipe = "book_temperature", aliases = {"温度书", "保暖", "降温"}},
}

local DEVICES = {
    {recipe = "portablecookpot_item", aliases = {"便携烹饪锅", "便携锅", "随身锅"}},
    {recipe = "portableblender_item", aliases = {"便携研磨器", "研磨器", "研磨机"}},
    {recipe = "portablespicer_item", aliases = {"便携香料站", "香料站", "调味站"}},
}

local function AddAlias(entries, prefab, alias)
    for _, entry in ipairs(entries) do
        if entry.recipe == prefab then entry.aliases[#entry.aliases + 1] = alias return end
    end
end

AddAlias(DEVICES, "portablecookpot_item", "便携烹饪锅")

local SPICES = {
    {recipe = "spice_chili", spice = "spice_chili", aliases = {"辣椒粉", "辣味粉", "辣粉", "辣味"}},
    {recipe = "spice_garlic", spice = "spice_garlic", aliases = {"蒜粉", "蒜味粉", "大蒜粉", "蒜味"}},
    {recipe = "spice_sugar", spice = "spice_sugar", aliases = {"糖粉", "甜味粉", "甜粉", "甜味"}},
    {recipe = "spice_salt", spice = "spice_salt", aliases = {"盐", "盐粉", "咸味粉", "咸味"}},
}

local function AddRuntimeNames(entries)
    for _, entry in ipairs(entries) do
        local name = STRINGS ~= nil and STRINGS.NAMES ~= nil
            and STRINGS.NAMES[string.upper(entry.recipe)] or nil
        if type(name) == "string" and name ~= "" then entry.aliases[#entry.aliases + 1] = name:lower() end
    end
end

local FOODS = {}
do
    local recipes = Cooking.recipes ~= nil and Cooking.recipes.portablecookpot or {}
    local exclusive = {}
    local ok, warly_foods = pcall(require, "preparedfoods_warly")
    if ok and type(warly_foods) == "table" then
        for prefab in pairs(warly_foods) do exclusive[prefab] = true end
    end
    for prefab in pairs(recipes) do
        if next(exclusive) == nil or exclusive[prefab] then
        local aliases = {prefab}
        local name = STRINGS ~= nil and STRINGS.NAMES ~= nil
            and STRINGS.NAMES[string.upper(prefab)] or nil
        if type(name) == "string" and name ~= "" then aliases[#aliases + 1] = name:lower() end
        FOODS[#FOODS + 1] = {recipe = prefab, aliases = aliases}
        end
    end
end
AddRuntimeNames(BOOKS)
AddRuntimeNames(DEVICES)
AddRuntimeNames(SPICES)

local function BookCommand(text, has_general_command)
    local book, position = Find(text, BOOKS)
    -- Inspect the verb before the title, since titles may contain verbs too
    -- (for example the character for "build" in applied silviculture).
    local prefix = position ~= nil and text:sub(1, position - 1) or text
    if Has(prefix, "读") then
        -- "读书" is intentionally a valid generic request.  The action
        -- module chooses the best available book when no title was supplied.
        return {special = "read", target = book ~= nil and book.recipe or nil}
    end
    if book ~= nil and Any(prefix, {"造", "做", "制作", "制做"}) then
        return {special = "build", recipe = book.recipe}
    end
    -- Bare aliases still support requests like "求雨", but a passing mention
    -- of fish or rain must not steal an ordinary command such as eating.
    if book ~= nil and not has_general_command then
        return {special = "read", target = book.recipe}
    end
end

function M.Parse(friend, text, has_general_command)
    if friend == nil or type(text) ~= "string" then return end
    text = text:lower()
    if friend.prefab == "wendy" and Any(text, {"收回", "回去", "藏"}) then
        return {special = "wendy_recall"}
    end
    if friend.prefab == "wickerbottom" then
        if Any(text, {"书架", "书房"}) and Any(text, {"造", "做", "制作", "制做", "放"}) then
            return {special = "build", recipe = "bookstation"}
        end
        local result = BookCommand(text, has_general_command)
        if result ~= nil then return result end
    elseif friend.prefab == "warly" then
        local device = Find(text, DEVICES)
        if device ~= nil and Any(text, {"造", "做", "制作", "制做"}) then
            return {special = "build", recipe = device.recipe}
        end
        local spice = Find(text, SPICES)
        if spice ~= nil and Any(text, {"造", "做", "制作", "制做"}) then
            return {special = "build", recipe = spice.recipe}
        end
        if Has(text, "调味") then
            local food = Find(text, FOODS)
            if spice ~= nil and food ~= nil then
                return {special = "spice", spice = spice.spice, food = food.recipe}
            end
        end
        local food = Find(text, FOODS)
        if food ~= nil and Any(text, {"造", "做", "制作", "制做"}) then
            return {special = "cook", recipe = food.recipe}
        end
    end
end

return M
