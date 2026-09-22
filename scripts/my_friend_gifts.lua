local M = {}
local Policy = require("my_friend_policy")

local function IsOwned(friend, item)
    local invitem = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    return invitem ~= nil and invitem:GetGrandOwner() == friend
end

local function CountStored(friend, prefab)
    local total, representative = 0, nil
    for _, item in ipairs(require("my_friend_food_storage").ReferenceItems(friend)) do
        if item.prefab == prefab and IsOwned(friend, item) then
            local stack = item.components.stackable
            total = total + (stack ~= nil and stack:StackSize() or 1)
            representative = item
        end
    end
    return total, representative
end

-- Shared by explicit panel transfers and native player trades, never pickups.
function M.Record(friend, player, item, count)
    local affinity = friend.components.my_friend_affinity
    if affinity == nil or not Policy.IsLocalPlayer(player)
        or friend:HasTag("playerghost") or not IsOwned(friend, item)
        or (count or 0) <= 0 then return false end
    friend._my_friend_food_supply_cache = nil
    if item.prefab ~= "beargerfur_sack" and item.components.equippable ~= nil then
        local recorded = affinity:RecordEquipmentGift(player, item)
        require("my_friend_dialogue").Gift(friend, player, item)
        return recorded
    end
    return affinity:RecordInventoryGift(player, item, count)
end

function M.Configure(friend)
    local trader = friend.components.trader
    if trader == nil or trader._my_friend_gifts_wrapped then return end
    trader._my_friend_gifts_wrapped = true
    local accept = trader.AcceptGift
    trader.AcceptGift = function(self, giver, item, count, ...)
        if not self.inst:HasTag("my_friend") or self.inst:HasTag("playerghost")
            or not Policy.IsLocalPlayer(giver) or not IsOwned(giver, item) then
            return accept(self, giver, item, count, ...)
        end
        local prefab = item.prefab
        local stack = item.components.stackable
        local offered = math.min(count or 1, stack ~= nil and stack:StackSize() or 1)
        local before = CountStored(self.inst, prefab)
        local accepted, reason = accept(self, giver, item, count, ...)
        if accepted then
            -- GiveItem may merge and remove the offered entity. Inspect the
            -- recipient after the native transfer and retain its real callbacks.
            local after, received = CountStored(self.inst, prefab)
            local given = math.min(offered, after - before)
            if received ~= nil and given > 0 then M.Record(self.inst, giver, received, given) end
        end
        return accepted, reason
    end
end

return M
