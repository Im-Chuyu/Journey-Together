-- Client side wardrobe helper. Lives in its own module because both modmain
-- and the panel widget need it: strict.lua only lets a main chunk create new
-- globals, so a shared global function would break the moment it is assigned
-- from inside a callback.
local Characters = require("my_friend_characters")

local M = {}

-- Older/mobile profiles lack the Redux wardrobe's character-skin methods.
-- Keep the adapter private to this screen; never patch the global profile.
function M.LoadoutProfile(profile, character, initial)
    if profile ~= nil and type(profile.GetSkinsForCharacter) == "function"
        and type(profile.SetSkinsForCharacter) == "function" then return profile end
    local saved = {}
    local function Copy(skins)
        local result = {}
        for key, value in pairs(skins or {}) do result[key] = value end
        return result
    end
    saved[character] = Copy(initial)
    local adapter = {}
    function adapter:GetSkinsForCharacter(prefab)
        return Copy(saved[prefab] or {base = prefab .. "_none"})
    end
    function adapter:SetSkinsForCharacter(prefab, skins)
        saved[prefab] = Copy(skins)
    end
    return setmetatable(adapter, {__index = function(_, key)
        local value = profile ~= nil and profile[key] or nil
        if type(value) == "function" then
            return function(_, ...) return value(profile, ...) end
        end
        return value
    end})
end

-- Every clothing skin this client owns for one character, grouped by slot.
function M.Scan(character)
    local owned, sets = {}, { body = {}, hand = {}, legs = {}, feet = {} }
    if TheInventory == nil or PREFAB_SKINS == nil or GetSkinData == nil then
        return owned, sets
    end
    for _, skins in pairs(PREFAB_SKINS) do
        for _, skin in ipairs(skins) do
            local data = GetSkinData(skin)
            if data ~= nil and data.base_prefab == character
                and not skin:match("_none$")
                and not (PREFAB_SKINS_SHOULD_NOT_SELECT ~= nil
                    and PREFAB_SKINS_SHOULD_NOT_SELECT[skin])
                and TheInventory:CheckOwnership(skin) then
                table.insert(owned, skin)
                local slot = CLOTHING ~= nil and CLOTHING[skin] ~= nil
                    and CLOTHING[skin].type or skin:match("_(body|hand|legs|feet)$")
                if slot ~= nil and sets[slot] ~= nil then table.insert(sets[slot], skin) end
            end
        end
    end
    table.sort(owned)
    for _, list in pairs(sets) do table.sort(list) end
    return owned, sets
end

-- Tells the server which skins this client owns, so SetSkins can be validated
-- there. The list is per character, so it is resent whenever the wardrobe is
-- opened in case the companion was switched since login.
function M.Report(character)
    local friend = TheWorld ~= nil and TheWorld._my_friend or nil
    character = character or (friend ~= nil and friend:IsValid() and friend.prefab
        or Characters.DEFAULT)
    local owned = M.Scan(character)
    local reported_skins = {}
    for _, skin in ipairs(owned) do reported_skins[skin] = true end
    if TheInventory ~= nil and CLOTHING ~= nil then
        for skin in pairs(CLOTHING) do
            if TheInventory:CheckOwnership(skin) then reported_skins[skin] = true end
        end
    end
    local reported_list = {}
    for skin in pairs(reported_skins) do reported_list[#reported_list + 1] = skin end
    table.sort(reported_list)
    SendModRPCToServer(GetModRPC("MyFriends", "OwnedSkins"),
        table.concat(reported_list, ","))
    -- The seamless player swap is a vanilla character change, so the client
    -- must not be sent to a paid character it does not own. Ownership is
    -- client-only; report the compact character list alongside skin data.
    local owned_characters = {}
    for _, prefab in ipairs(Characters.List()) do
        local owned_character = false
        if type(IsCharacterOwned) == "function" then
            local ok, result = pcall(IsCharacterOwned, prefab)
            owned_character = ok and result == true
        end
        if owned_character then owned_characters[#owned_characters + 1] = prefab end
    end
    SendModRPCToServer(GetModRPC("MyFriends", "OwnedCharacters"),
        table.concat(owned_characters, ","))
    return owned
end

return M
