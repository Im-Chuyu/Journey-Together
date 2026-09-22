local Inventory = require("my_friend_inventory")
local Policy = require("my_friend_policy")
local Pot = require("my_friend_cookpot")
local Planner = require("my_friend_recipe_planner")
local Storage = require("my_friend_food_storage")
local M = {}

function M.CanClean(inst, pot)
    local command = inst._my_friend_command
    if command == nil or command.special ~= "cook" or pot == nil
        or pot.prefab ~= "portablecookpot" or not Pot.Accessible(inst, pot, command.cooking_origin)
        or pot._my_friend_beefalo_chef ~= nil then return false end
    local job = pot._my_friend_recipe_job
    if job ~= nil and job.owner ~= Pot.OwnerID(inst) then return false end
    local c, s = pot.components.container, pot.components.stewer
    if s:IsCooking() or s:IsDone() or not c:CanOpen() then return false end
    local items = c:GetAllItems()
    if next(items) == nil then return false end
    for _, item in pairs(items) do
        if not item:IsValid() or item.components.inventoryitem == nil
            or item.components.inventoryitem.islockedinslot then return false end
    end
    return true
end

local function Carried(inst, prefab)
    local first, count = nil, 0
    for _, item in ipairs(Storage.ReferenceItems(inst)) do
        local ii = item.components.inventoryitem
        if item.prefab == prefab and ii ~= nil and not ii.islockedinslot
            and ii:GetGrandOwner() == inst and not Storage.IsReserved(inst, item) then
            first, count = first or item, count + Planner.Size(item)
        end
    end
    return first, count
end

local function CanStore(inst, target, item, origin)
    if not target:IsValid() or (target.prefab ~= "icebox" and target.prefab ~= "saltbox")
        or target:HasAnyTag("INLIMBO", "fire", "burnt")
        or origin:GetDistanceSqToInst(target) > Pot.RANGE^2
        or not Policy.InRange(inst, target)
        or inst:GetCurrentPlatform() ~= target:GetCurrentPlatform() then return false end
    local c = target.components.container
    return c ~= nil and c.canbeopened and not c.readonlycontainer
        and not c:IsRestricted(inst) and not c:IsOpenedByOthers(inst)
        and c:CanTakeItemInSlot(item) and c:CanAcceptCount(item, 1) > 0
end

function M.GetDeliveryAction(inst, guard)
    local cargo = inst._my_friend_recipe_cleanup
    if cargo == nil then return end
    local command = inst._my_friend_command
    local item, total = Carried(inst, cargo.prefab)
    if command ~= cargo.command or item == nil or not cargo.pot:IsValid()
        or not Pot.Accessible(inst, cargo.pot, command.cooking_origin) then
        inst._my_friend_recipe_cleanup = nil
        return
    end
    local x, y, z = cargo.pot.Transform:GetWorldPosition()
    local destination, distance
    for _, target in ipairs(TheSim:FindEntities(x, y, z, Pot.RANGE, nil, {"INLIMBO", "fire", "burnt"})) do
        if CanStore(inst, target, item, cargo.pot) then
            local d = inst:GetDistanceSqToInst(target)
            if distance == nil or d < distance then destination, distance = target, d end
        end
    end
    if destination == nil then
        inst._my_friend_recipe_cleanup = nil
        return
    end
    local action = BufferedAction(inst, destination, ACTIONS.MY_FRIEND_STORE, item)
    action.arrivedist = Inventory.ContainerReach(inst, destination)
    action._my_friend_store_count = math.min(cargo.count, Planner.Size(item),
        destination.components.container:CanAcceptCount(item, cargo.count))
    action:AddSuccessAction(function()
        if inst._my_friend_recipe_cleanup ~= cargo then return end
        local _, remaining = Carried(inst, cargo.prefab)
        local moved = math.max(0, total - remaining)
        cargo.count = cargo.count - moved
        if moved == 0 or cargo.count <= 0 then inst._my_friend_recipe_cleanup = nil end
    end)
    action:AddFailAction(function()
        if inst._my_friend_recipe_cleanup == cargo then inst._my_friend_recipe_cleanup = nil end
    end)
    action = guard(inst, cargo.pot, action, function()
        return inst._my_friend_recipe_cleanup == cargo and item:IsValid()
            and item.components.inventoryitem:GetGrandOwner() == inst
            and CanStore(inst, destination, item, cargo.pot)
    end)
    action._my_friend_dialogue_kind = "recipe_clear"
    return action
end

function M.GetAction(inst, pot, guard)
    if not M.CanClean(inst, pot) then return nil, "paused" end
    local _, item = next(pot.components.container:GetAllItems())
    local count = math.min(Planner.Size(item), inst.components.inventory:CanAcceptCount(item, Planner.Size(item)))
    if count <= 0 then return nil, "full" end
    local command = inst._my_friend_command
    local prefab = item.prefab
    local _, before = Carried(inst, prefab)
    local action = BufferedAction(inst, pot, ACTIONS.MY_FRIEND_WITHDRAW, item)
    action.arrivedist = Inventory.ContainerReach(inst, pot)
    action._my_friend_withdraw_count = count
    action:AddSuccessAction(function()
        if inst._my_friend_command ~= command then return end
        pot._my_friend_recipe_job = nil
        local _, after = Carried(inst, prefab)
        if after > before then
            inst._my_friend_recipe_cleanup = {pot = pot, command = command, prefab = prefab, count = after - before}
        end
    end)
    action = guard(inst, pot, action, function()
        return M.CanClean(inst, pot) and item:IsValid()
            and item.components.inventoryitem.owner == pot and Inventory.CanWithdrawFrom(inst, pot)
    end)
    action._my_friend_dialogue_kind = "recipe_clear"
    return action
end

return M
