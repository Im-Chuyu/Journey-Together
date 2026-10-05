-- Client side wardrobe helper. Lives in its own module because both modmain
-- and the panel widget need it: strict.lua only lets a main chunk create new
-- globals, so a shared global function would break the moment it is assigned
-- from inside a callback.
local Characters = require("my_friend_characters")

local M = {}

-- Every clothing skin this client owns for one character, grouped by slot.
function M.Scan(character)
    local owned, sets = {}, { body = {}, hand = {}, legs = {}, feet = {} }
    if TheInventory == nil or type(TheInventory.CheckOwnership) ~= "function" then
        return owned, sets
    end
    if type(PREFAB_SKINS) == "table" then
        for prefab, skins in pairs(PREFAB_SKINS) do
            if type(skins) == "table" then
                for _, skin in ipairs(skins) do
                    local data = type(skin) == "string" and type(GetSkinData) == "function"
                        and GetSkinData(skin) or nil
                    local base_prefab = type(data) == "table" and data.base_prefab or nil
                    if type(skin) == "string"
                        and (base_prefab == character
                            or base_prefab == nil and prefab == character)
                        and not skin:match("_none$")
                        and not (PREFAB_SKINS_SHOULD_NOT_SELECT ~= nil
                            and PREFAB_SKINS_SHOULD_NOT_SELECT[skin])
                        and (CLOTHING == nil or CLOTHING[skin] == nil)
                        and TheInventory:CheckOwnership(skin) then
                        table.insert(owned, skin)
                    end
                end
            end
        end
    end
    if type(CLOTHING) == "table" then
        for skin, data in pairs(CLOTHING) do
            if data ~= nil and sets[data.type] ~= nil
                and TheInventory:CheckOwnership(skin) then
                table.insert(sets[data.type], skin)
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
    if TheInventory ~= nil and type(TheInventory.CheckOwnership) == "function"
        and type(CLOTHING) == "table" then
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
