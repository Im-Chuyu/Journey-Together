-- Server-side ownership checks and client-side wardrobe listings.
local M = {}

function M.Owns(player, skin)
    local inventory = TheInventory
    if inventory == nil or player == nil or type(player.userid) ~= "string" or player.userid == "" then return false end
    if inventory.CheckClientOwnership ~= nil and inventory:CheckClientOwnership(player.userid, skin) then return true end
    return player == ThePlayer and inventory.CheckOwnership ~= nil and inventory:CheckOwnership(skin) == true
end

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

return M
