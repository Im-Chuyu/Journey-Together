package.path = "scripts/?.lua;" .. package.path
local Protocol = require("my_friend_games_chat")
local language = require("my_friend_strings")
local reference = require("languages/zh/games")
for _, id in ipairs(require("my_friend_games_catalog").ORDER) do
    local def=require("my_friend_games_catalog").Get(id)
    assert(reference[def.name]~=nil and reference[def.rules_text]~=nil,"missing registered game text: "..id)
end
local count = 0
for _ in pairs(reference) do count = count + 1 end
for _, path in ipairs({"scripts/screens/my_friend_games_screen.lua", "scripts/widgets/my_friend_games_chat.lua",
    "scripts/widgets/my_friend_games_notice.lua", "scripts/my_friend_games_companion.lua"}) do
    local handle = assert(io.open(path, "r")); local source = handle:read("*a"); handle:close()
    for key in source:gmatch('L%.Get%("([%w_]+)"%)') do assert(reference[key] ~= nil, path .. " references missing UI key " .. key) end
    for key in source:gmatch('L%.Format%("([%w_]+)"') do assert(reference[key] ~= nil, path .. " references missing format key " .. key) end
end
local function signature(value)
    local args = {}; for item in value:gmatch("%%[sd]") do args[#args + 1] = item end
    return table.concat(args, ",")
end
for _, locale in ipairs({"zh", "zh_tw", "en", "ru"}) do
    local strings = require("languages/" .. locale .. "/games")
    for _, key in ipairs({"games", "affinity", "game_sit_task"}) do assert(strings[key] ~= nil, locale .. " missing " .. key) end
    language.language = locale; package.loaded.my_friend_games_strings = nil
    local L = require("my_friend_games_strings")
    for key, value in pairs(reference) do
        assert(type(strings[key]) == "string" and strings[key] ~= "", locale .. " missing " .. key)
        assert(signature(value) == signature(strings[key]), locale .. " wrong placeholders: " .. key)
        assert(L.Get(key) == strings[key], "declared languages must resolve their own strings without fallback")
    end
    for key in pairs(strings) do assert(reference[key] ~= nil, locale .. " has an unmatched key: " .. key) end
    for kind, amount in pairs(Protocol.MESSAGE_COUNTS) do for i = 1, amount do
        local key = kind .. "_" .. i
        assert(strings[key] ~= nil, locale .. " missing generated dialogue key " .. key)
        local entry = {seq = 1, name = "Companion", kind = kind, value = i, target = "Player"}
        assert(Protocol.Valid(entry))
        local text = Protocol.Display(entry)
        assert(type(text) == "string" and text ~= key)
        if kind ~= "bot" then assert(text:find("Player", 1, true) ~= nil) end
    end end
    for i = 1, Protocol.QUICK_COUNT do assert(strings["quick_" .. i] ~= nil) end
end
language.language = "zh"; package.loaded.my_friend_games_strings = nil

-- The native item key is not always emoji_<input_name>; catalog every input.
EMOJI_ITEMS = {unrelated_asset_key = {input_name = "new_icon", data = {utf8_str = "<new>"}},
    emoji_pig = {input_name = "pig", data = {utf8_str = "<pig>"}}}
assert(#Protocol.EmojiCatalog(true) == 2 and Protocol.Normalize("emoji", "new_icon") == "new_icon")
assert(Protocol.Glyph("new_icon") == "<new>" and Protocol.Normalize("emoji", "unknown") == nil)
assert(Protocol.Display({kind = "text", value = ":new_icon: :pig:"}) == "<new> <pig>")
if arg[1] ~= nil then
    dofile(arg[1])
    local catalog, expected, actual = Protocol.EmojiCatalog(true), {}, {}
    for _, item in pairs(EMOJI_ITEMS) do if item.input_name ~= nil and item.data ~= nil and item.data.utf8_str ~= nil then
        expected[item.input_name] = item.data.utf8_str
    end end
    for _, name in ipairs(catalog) do actual[name] = true end
    local total = 0
    for name, glyph in pairs(expected) do
        total = total + 1
        assert(actual[name] and Protocol.Normalize("emoji", name) == name and Protocol.Glyph(name) == glyph, name)
    end
    assert(total == #catalog and total > 8, "all native emoji must be supported")
    print("PASS: entire native emoji catalog: " .. total .. " entries")
end
print("PASS: all " .. count .. " game UI/dialogue keys in zh/zh_tw/en/ru, placeholders, generated pools and registered emoji names")
