local M = {}

function M.Kind(item)
    if item == nil then return end
    if item.prefab == "beargerfur_sack" then return "player_takes_sack" end
    local edible = item.components ~= nil and item.components.edible or nil
    if edible == nil then return end
    -- DST gives some building materials an edible component so characters can
    -- consume them in emergencies. They are not food for this reaction: taking
    -- boards, grass, twigs, or reeds should not produce a meal comment.
    if item:HasTag("preparedfood") or M.IsRealFoodType(edible.foodtype) then
        return "player_takes_food"
    end
end

function M.IsRealFoodType(foodtype)
    if foodtype == nil then return false end
    -- These edible components belong to fuel, materials, or creature-only
    -- resources. They must not be treated as a meal when moved by a player.
    return foodtype ~= FOODTYPE.ROUGHAGE and foodtype ~= FOODTYPE.WOOD
        and foodtype ~= FOODTYPE.ELEMENTAL and foodtype ~= FOODTYPE.GEARS
        and foodtype ~= FOODTYPE.NITRE and foodtype ~= FOODTYPE.LUNAR_SHARDS
        and foodtype ~= FOODTYPE.CORPSE and foodtype ~= FOODTYPE.MIASMA
end

function M.Say(friend, player, kind)
    if kind == nil or friend == nil or not friend:IsValid() or not friend:HasTag("my_friend")
        or not require("my_friend_policy").IsLocalPlayer(player) then return end
    require("my_friend_dialogue").Say(friend, kind, player)
end

local function FriendOwner(entity)
    local invitem = entity ~= nil and entity.components.inventoryitem or nil
    local owner = invitem ~= nil and invitem:GetGrandOwner() or entity
    return owner ~= nil and owner.HasTag ~= nil and owner:HasTag("my_friend") and owner or nil
end

local function Count(item)
    return item ~= nil and item:IsValid()
        and (item.components.stackable ~= nil and item.components.stackable:StackSize() or 1) or 0
end

-- Observe successful player container operations, including splits and swaps.
-- Internal AI transfers never call these UI methods with a real player opener.
function M.WrapContainer(container)
    local methods = {
        TakeActiveItemFromHalfOfSlot = {opener = 2},
        TakeActiveItemFromAllOfSlot = {opener = 2},
        TakeActiveItemFromCountOfSlot = {opener = 3},
        SwapActiveItemWithSlot = {opener = 2},
        SwapOneOfActiveItemWithSlot = {opener = 2},
        MoveItemFromAllOfSlot = {opener = 3, destination = 2},
        MoveItemFromHalfOfSlot = {opener = 3, destination = 2},
        MoveItemFromCountOfSlot = {opener = 4, destination = 2},
    }
    for name, spec in pairs(methods) do
        local original = container[name]
        if original ~= nil then
            container[name] = function(self, ...)
                local args = {...}
                local friend = FriendOwner(self.inst)
                local item = friend ~= nil and self:GetItemInSlot(args[1]) or nil
                local kind, before = M.Kind(item), Count(item)
                local result = original(self, ...)
                if friend ~= nil and kind ~= nil
                    and (spec.destination == nil or FriendOwner(args[spec.destination]) ~= friend)
                    and (self:GetItemInSlot(args[1]) ~= item or Count(item) < before) then
                    M.Say(friend, args[spec.opener], kind)
                end
                return result
            end
        end
    end
end

return M
