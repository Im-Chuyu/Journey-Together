-- Client side wardrobe helper. Lives in its own module because both modmain
-- and the panel widget need it: strict.lua only lets a main chunk create new
-- globals, so a shared global function would break the moment it is assigned
-- from inside a callback.
local Characters = require("my_friend_characters")

local M = {}

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
    SendModRPCToServer(GetModRPC("MyFriends", "OwnedSkins"), table.concat(owned, ","))
    return owned
end

return M
