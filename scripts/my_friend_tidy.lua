local Policy = require("my_friend_policy")
local Inventory = require("my_friend_inventory")
local Reserves = require("my_friend_resource_reserves")
local EquipmentReserves = require("my_friend_equipment_reserves")
local M = {}
local EquipSlots = require("my_friend_equip_slots")

local function Count(item)
    return item.components.stackable ~= nil and item.components.stackable:StackSize() or 1
end

local function Totals(inst)
    local counts = {}
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        counts[item.prefab] = (counts[item.prefab] or 0) + Count(item)
    end
    return counts
end

function M.IsSeed(item)
    return item.prefab == "seeds" or item.prefab:match("_seeds$") ~= nil
end

local function Chests(player, inst)
    local p = player:GetPosition()
    local result = {}
    for _, entity in ipairs(TheSim:FindEntities(p.x, 0, p.z, 32, {"_container"}, {"INLIMBO", "burnt"})) do
        local c = entity.components.container
        if c ~= nil and c.type == "chest" and not entity:HasTag("backpack")
            and not entity:HasTag("fridge") and not entity:HasTag("saltbox")
            and not c.readonlycontainer and not c:IsRestricted(inst)
            and not c:IsOpenedByOthers(inst) then result[#result + 1] = entity end
    end
    return result
end

function M.IsUnderPressure(inst)
    local inventory = inst.components.inventory
    if inventory == nil then return false end
    local free = inventory:GetNumSlots() - inventory:NumItems()
    local overflow = inventory:GetOverflowContainer()
    if overflow ~= nil then free = free + overflow:GetNumSlots() - overflow:NumItems() end
    return free <= 2
end

function M.Score(inst, context)
    if context.leader == nil or context.threat or context.dark or context.thermal
        or inst._my_friend_command ~= nil then return 0 end
    return context.full and 103 or 58
end

local function Relaxed(inst, executing, pressure)
    local hunger = inst.components.hunger
    return not inst._my_friend_under_threat
        and inst._my_friend_command == nil
        and (pressure or inst._my_friend_work_target == nil)
        and (inst._my_friend_storage_action == nil or inst._my_friend_storage_action == executing)
        and (executing ~= nil or not Policy.IsBusy(inst))
        and (hunger == nil or hunger:GetPercent() >= (pressure and .4 or .5))
end

local function IsEquipped(inst, item)
    return EquipSlots.IsEquipped(inst.components.inventory, item)
end

local function IsMaterial(item)
    return item.prefab == "cutgrass" or item.prefab == "twigs" or item.prefab == "log"
        or item.prefab == "rocks" or item.prefab == "flint" or item.prefab == "goldnugget"
        or item.prefab == "nitre" or item.prefab == "charcoal" or item.prefab == "cutreeds"
        or item.prefab == "boards" or item.prefab == "cutstone" or item.prefab == "livinglog"
end

local function IsTidyItem(inst, item, pressure)
    if item == nil or not item:IsValid() or IsEquipped(inst, item)
        or item:HasAnyTag("irreplaceable", "heavy", "backpack", "heatrock") then return false end
    if item.components.edible ~= nil and not IsMaterial(item) then return false end
    return item.components.equippable ~= nil or item.components.tool ~= nil
        or item.components.armor ~= nil or item.components.weapon ~= nil
        or item.components.sewing ~= nil or item.components.forgerepair ~= nil
        or IsMaterial(item)
        or pressure and item.components.stackable ~= nil
            and item.components.healer == nil and item.components.deployable == nil
            and item.components.container == nil and item.components.book == nil
end

local function CanStore(inst, chest)
    local c = chest ~= nil and chest:IsValid() and chest.components.container or nil
    return c ~= nil and Inventory.StorageReady(inst, chest) and c.canbeopened and not c.readonlycontainer
        and not c:IsRestricted(inst) and not c:IsOpenedByOthers(inst)
        and not chest:HasAnyTag("INLIMBO", "burnt", "fire")
end

local function StorePlan(inst, chest, keep, eligible)
    if not CanStore(inst, chest) then return {} end
    local plan, remaining = {}, Totals(inst)
    local equipment = EquipmentReserves.GetKeep(inst)
    for prefab, count in pairs(remaining) do remaining[prefab] = math.max(0, count - (keep[prefab] or 0)) end
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        local ii = item.components.inventoryitem
        if item:IsValid() and ii ~= nil and not ii.islockedinslot and ii:GetGrandOwner() == inst
            and not IsEquipped(inst, item) and (eligible == nil or eligible(inst, item)) then
            local count = math.min(Count(item), remaining[item.prefab] or 0,
                math.max(0, Count(item) - (equipment[item] or 0)),
                chest.components.container:CanAcceptCount(item, Count(item)))
            if count > 0 then
                plan[#plan + 1] = {item = item, count = count}
                remaining[item.prefab] = remaining[item.prefab] - count
            end
        end
    end
    return plan
end

local function StoreAction(inst, chest, plan, keep, eligible, allowed, radius)
    if #plan == 0 then return end
    local action = BufferedAction(inst, chest, ACTIONS.MY_FRIEND_STORE, plan[1].item)
    action.arrivedist = Inventory.ContainerReach(inst, chest)
    action._my_friend_store_plan = plan
    action.validfn = function()
        if not allowed(action) then return false end
        -- Inventory may change while walking. Recheck the total reserve across
        -- every stack before the existing store action opens the chest once.
        action._my_friend_store_plan = StorePlan(inst, chest, keep, eligible)
        return #action._my_friend_store_plan > 0
    end
    action:AddFailAction(function()
        if inst._my_friend_storage_action == action then inst._my_friend_storage_action = nil end
        if not action._my_friend_cancelled then Inventory.StorageResult(inst, chest, false) end
    end)
    return Policy.GuardAction(inst, action, radius)
end

-- Store a caller-selected set of carried items in one container interaction.
-- The action is deliberately shared with normal tidy behavior so the chest is
-- opened once and the complete plan is transferred before it is closed.
function M.StoreItemsInto(inst, chest, eligible, radius)
    if not CanStore(inst, chest) then return end
    local plan = StorePlan(inst, chest, {}, eligible)
    if #plan == 0 then return end
    return StoreAction(inst, chest, plan, {}, eligible,
        function(action) return CanStore(inst, chest) end, radius or 32)
end

-- Prefer chests holding the same materials, then deposit all eligible surplus
-- for that chest in one interaction. Counts are shared across split stacks.
function M.GetNearbyRelaxedAction(inst)
    local pressure = M.IsUnderPressure(inst)
    if not Relaxed(inst, nil, pressure) then return end
    local range = pressure and Policy.ACTIVITY_RANGE or 12
    local radius = pressure and Policy.ACTIVITY_RANGE or 14
    local function Eligible(actor, item) return IsTidyItem(actor, item, pressure) end
    local x, y, z = inst.Transform:GetWorldPosition()
    local chests = TheSim:FindEntities(x, y, z, range, {"_container"},
        {"INLIMBO", "burnt", "fridge", "saltbox", "playerghost"})
    local best, bestplan, bestscore
    local keep = Reserves.FollowingKeep()
    for _, chest in ipairs(chests) do
        local c = chest.components.container
        if c ~= nil and c.type == "chest" and not chest:HasTag("backpack")
            and Policy.InRange(inst, chest, radius) and CanStore(inst, chest) then
            local stored = {}
            for _, item in pairs(c.slots) do stored[item.prefab] = true end
            local plan = StorePlan(inst, chest, keep, Eligible)
            for _, entry in ipairs(plan) do
                local matching = stored[entry.item.prefab] and 1000000 or 0
                local score = matching - inst:GetDistanceSqToInst(chest)
                if bestscore == nil or score > bestscore then
                    best, bestplan, bestscore = chest, plan, score
                end
            end
        end
    end
    if best == nil then return end
    return StoreAction(inst, best, bestplan, keep, Eligible,
        function(action) return Relaxed(inst, action, pressure) end, radius)
end

function M.HandOver(inst, command, item, count)
    local action = BufferedAction(inst, command.player, ACTIONS.MY_FRIEND_HANDOVER, item)
    action.arrivedist = 2
    action._my_friend_give_count = count
    return Policy.GuardAction(inst, action, 32)
end

function M.WorkDelivery(inst, command)
    if command.id ~= "grass" and command.id ~= "harvest" then return end
    local totals = Totals(inst)
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        local count
        if command.id == "grass" and (item.prefab == "cutgrass" or item.prefab == "twigs") then
            count = math.max(0, (totals[item.prefab] or 0) - 20)
        elseif command.id == "harvest" and (M.IsSeed(item)
            or (command.harvest_products or {})[item.prefab]) then
            count = Count(item)
        end
        if count ~= nil and count > 0 then
            return M.HandOver(inst, command, item, math.min(count, Count(item)))
        end
    end
end

function M.GetAction(inst, command)
    local inv, player = inst.components.inventory, command.player
    command.initial_items = command.initial_items or Totals(inst)
    command.delivered = command.delivered or {}
    command.failed = command.failed or {}
    local chests = command.id == "tidy" and Chests(player, inst) or {}
    local totals = Totals(inst)
    local equipment = EquipmentReserves.GetKeep(inst)
    local cargo, count
    for _, item in ipairs(inv:ReferenceAllItems()) do
        local surplus = (totals[item.prefab] or 0) - (command.initial_items[item.prefab] or 0)
        surplus = math.min(surplus, math.max(0, Count(item) - (equipment[item] or 0)))
        if surplus > 0 and (command.id == "tidy" or command.id == "seeds" and M.IsSeed(item)) then
            cargo, count = item, math.min(Count(item), surplus)
            break
        end
    end
    if cargo ~= nil then
        if #chests > 0 then
            local best, score
            for _, chest in ipairs(chests) do
                local c = chest.components.container
                if CanStore(inst, chest) and c:CanTakeItemInSlot(cargo) and c:CanAcceptCount(cargo) > 0
                    and GetTime() >= (command.failed[chest.GUID] or 0) then
                    local matching = false
                    for _, stored in pairs(c.slots) do
                        if stored.prefab == cargo.prefab then matching = true break end
                    end
                    local value = (matching and 1000000 or 0) - inst:GetDistanceSqToInst(chest)
                    if score == nil or value > score then best, score = chest, value end
                end
            end
            if best == nil then require("my_friend_commands").Clear(inst) return end
            local plan = StorePlan(inst, best, command.initial_items)
            local action = StoreAction(inst, best, plan, command.initial_items, nil,
                function() return inst._my_friend_command == command end, 32)
            if action == nil then return end
            action:AddFailAction(function()
                if not action._my_friend_cancelled then command.failed[best.GUID] = GetTime() + 20 end
                if inst._my_friend_storage_action == action then inst._my_friend_storage_action = nil end
            end)
            return action
        end
        return M.HandOver(inst, command, cargo, count)
    end
    local p, best, nearest = player:GetPosition()
    for _, item in ipairs(TheSim:FindEntities(p.x, 0, p.z, 32, {"_inventoryitem"},
        {"INLIMBO", "fire", "NOCLICK"})) do
        local ii = item.components.inventoryitem
        if ii ~= nil and ii.owner == nil and ii.canbepickedup
            and not command.delivered[item.GUID] and not item:HasTag("irreplaceable")
            and GetTime() >= (command.failed[item.GUID] or 0)
            and (command.id ~= "seeds" or M.IsSeed(item))
            and (command.id ~= "equipment"
                or item.components.equippable ~= nil and not item:HasTag("backpack"))
            and (inv:CanAcceptCount(item, 1) > 0
                or item.components.equippable ~= nil
                    and inv:GetEquippedItem(item.components.equippable.equipslot) == nil
                    and require("my_friend_equipment").Allowed(inst, item.components.equippable.equipslot))
            and not (item:HasTag("backpack") and GetTime()
                < (inst._my_friend_backpack_recover_after or 0))
            and not require("my_friend_navigation").IsBlocked(inst, item:GetPosition()) then
            local d = inst:GetDistanceSqToInst(item)
            if nearest == nil or d < nearest then best, nearest = item, d end
        end
    end
    if best == nil then
        local retrying = false
        for _, untiltime in pairs(command.failed) do
            if GetTime() < untiltime then retrying = true break end
        end
        if command.id ~= "seeds" and not retrying then require("my_friend_commands").Clear(inst) end
        return
    end
    local action = BufferedAction(inst, best, ACTIONS.PICKUP)
    action:AddFailAction(function()
        if not action._my_friend_cancelled then command.failed[best.GUID] = GetTime() + 15 end
    end)
    action.validfn = function()
        return best:IsValid() and best.components.inventoryitem.owner == nil
            and (command.id ~= "seeds" or M.IsSeed(best))
            and (command.id ~= "equipment"
                or best.components.equippable ~= nil and not best:HasTag("backpack"))
            and (best.components.equippable == nil
                or inst.components.inventory:GetEquippedItem(best.components.equippable.equipslot) ~= nil
                or require("my_friend_equipment").Allowed(inst, best.components.equippable.equipslot))
            and not (best:HasTag("backpack") and GetTime()
                < (inst._my_friend_backpack_recover_after or 0))
    end
    return Policy.GuardAction(inst, action, 32)
end

return M
