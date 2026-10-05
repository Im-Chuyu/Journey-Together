local M = {}
local Policy = require("my_friend_policy")
local Dialogue = require("my_friend_dialogue")

M.HEAL_AGE = 73
M.OPTIONAL_HEAL_AGE = 65
M.HEAL_ROLL_INTERVAL = 10
M.HEAL_CHANCE = .1
M.FUEL_RANGE = 20
M.DREADSTONE_RELEASE_PERCENT = 1
M.REFUEL_CHECK_INTERVAL = 2

function M.Configure(inst)
    -- SpawnPrefab skips the character's load/new-spawn initialization. Reuse
    -- Wanda's own age transitions, listeners and damage modifiers.
    if inst.prefab == "wanda" and inst.age_state == nil and inst._OnLoad ~= nil then
        inst:_OnLoad()
    end
end

local function Carried(inst, item)
    local ii = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    return ii ~= nil and not ii.islockedinslot and ii:GetGrandOwner() == inst
end

local function DurabilityPercent(item)
    local armor = item ~= nil and item:IsValid() and item.components ~= nil
        and item.components.armor or nil
    if armor == nil or armor.maxcondition == nil or armor.maxcondition <= 0 then return 1 end
    return math.max(0, math.min(1, (armor.condition or 0) / armor.maxcondition))
end

local function FindDreadstone(inst, items, prefab)
    for _, item in ipairs(items) do
        if item ~= nil and item:IsValid() and item.prefab == prefab
            and item.components ~= nil and item.components.armor ~= nil
            and Carried(inst, item) and DurabilityPercent(item) < M.DREADSTONE_RELEASE_PERCENT then
            return item
        end
    end
end

local function ClearDreadstonePending(inst, item)
    if inst._my_friend_wanda_dreadstone_pending == item then
        inst._my_friend_wanda_dreadstone_pending = nil
        inst._my_friend_wanda_dreadstone_pending_until = nil
    end
end

local function QueueDreadstoneEquip(inst, item)
    local inventory = inst.components.inventory
    if inventory == nil or item == nil or not item:IsValid() then return end
    local deadline = GetTime() + 3
    inst._my_friend_wanda_dreadstone_pending = item
    inst._my_friend_wanda_dreadstone_pending_until = deadline
    local action = BufferedAction(inst, nil, ACTIONS.EQUIP, item)
    action.validfn = function()
        return GetTime() < deadline and inst._my_friend_wanda_dreadstone_pending == item
            and item:IsValid() and Carried(inst, item)
    end
    action:AddSuccessAction(function()
        ClearDreadstonePending(inst, item)
    end)
    action:AddFailAction(function() ClearDreadstonePending(inst, item) end)
    return action
end

function M.GetDreadstoneAction(inst)
    if inst.prefab ~= "wanda" or Policy.IsBusy(inst)
        or inst.components.inventory == nil then return end
    local inventory = inst.components.inventory
    local items = inventory:ReferenceAllItems()
    local head = inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
    local body = inventory:GetEquippedItem(EQUIPSLOTS.BODY)
    local damaged_head = FindDreadstone(inst, items, "dreadstonehat")
    local damaged_body = FindDreadstone(inst, items, "armordreadstone")

    if damaged_head ~= nil and head ~= damaged_head then
        return QueueDreadstoneEquip(inst, damaged_head)
    end
    if damaged_body ~= nil and body == nil then
        return QueueDreadstoneEquip(inst, damaged_body)
    end

end

function M.GetAge(inst)
    if inst.prefab ~= "wanda" or inst.components.oldager == nil
        or inst.components.health == nil then return end
    return TUNING.WANDA_MAX_YEARS_OLD - inst.components.health.currenthealth
        + inst.components.oldager:GetCurrentYearPercent()
end

function M.NeedsHeal(inst)
    local age = M.GetAge(inst)
    if age == nil or inst.components.health:IsDead() or inst:HasTag("playerghost")
        or age < M.OPTIONAL_HEAL_AGE then
        inst._my_friend_optional_watch = nil
        return false
    end
    if age >= M.HEAL_AGE then return true end
    -- Score/validity checks may run several times for the same action. Roll
    -- once per interval and retain that decision until the watch is used.
    if GetTime() >= (inst._my_friend_watch_roll_after or 0) then
        inst._my_friend_watch_roll_after = GetTime() + M.HEAL_ROLL_INTERVAL
        inst._my_friend_optional_watch = inst._my_friend_optional_watch
            or math.random() < M.HEAL_CHANCE
    end
    return inst._my_friend_optional_watch == true
end

function M.GetHealScore(inst)
    if not M.NeedsHeal(inst) then return 0 end
    return M.GetAge(inst) >= M.HEAL_AGE and 145 or 90
end

function M.GetHealAction(inst)
    if not M.NeedsHeal(inst) or Policy.IsBusy(inst)
        or GetTime() < (inst._my_friend_watch_retry or 0) then return end
    inst._my_friend_watch_retry = GetTime() + 2
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if item.prefab == "pocketwatch_heal" and Carried(inst, item)
            and item.components.pocketwatch ~= nil and item.components.pocketwatch:CanCast(inst) then
            local action = BufferedAction(inst, nil, ACTIONS.CAST_POCKETWATCH, item)
            action.validfn = function()
                return M.NeedsHeal(inst) and Carried(inst, item)
                    and item.components.pocketwatch:CanCast(inst)
            end
            action:AddSuccessAction(function()
                inst._my_friend_optional_watch = nil
                inst._my_friend_watch_roll_after = GetTime() + M.HEAL_ROLL_INTERVAL
                Dialogue.RandomReply(inst, "watch_heal")
            end)
            return action
        end
    end
end

function M.FindReviveWatch(inst, ghost)
    if inst.prefab ~= "wanda" then return end
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if item.prefab == "pocketwatch_revive" and Carried(inst, item)
            and item.components.pocketwatch ~= nil
            and (ghost == nil and item.components.pocketwatch.inactive
                or ghost ~= nil and item.components.pocketwatch:CanCast(inst, ghost)) then return item end
    end
end

function M.GetReviveAction(inst, ghost)
    local watch = M.FindReviveWatch(inst, ghost)
    if watch == nil then return end
    local action = BufferedAction(inst, ghost, ACTIONS.CAST_POCKETWATCH, watch)
    action.arrivedist = 2
    action.validfn = function()
        return ghost:IsValid() and Carried(inst, watch)
            and watch.components.pocketwatch:CanCast(inst, ghost)
    end
    action:AddSuccessAction(function() Dialogue.Say(inst, "revive_player", ghost) end)
    return action
end

local function NeedsFuel(inst, item)
    return item ~= nil and item.prefab == "pocketwatch_weapon" and Carried(inst, item)
        and item.components.fueled ~= nil and item.components.fueled:GetPercent() < .1
end

local function RefuelActive(inst, item)
    return item ~= nil and item:IsValid() and item.prefab == "pocketwatch_weapon"
        and Carried(inst, item) and item.components.fueled ~= nil
        and item.components.fueled:GetPercent() <= .9
end

function M.GetRefuelAction(inst)
    if inst.prefab ~= "wanda" or Policy.IsBusy(inst)
        or GetTime() < (inst._my_friend_wanda_refuel_after or 0) then return end
    local now = GetTime()
    local watch = inst._my_friend_wanda_refuel_watch
    if not RefuelActive(inst, watch) then
        if now < (inst._my_friend_wanda_refuel_check_after or 0) then return end
        inst._my_friend_wanda_refuel_check_after = now + M.REFUEL_CHECK_INTERVAL
        watch = nil
        for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
            if NeedsFuel(inst, item) then watch = item break end
        end
        if watch == nil then return end
        inst._my_friend_wanda_refuel_watch = watch
    end
    if not RefuelActive(inst, watch) then
        inst._my_friend_wanda_refuel_watch = nil
        inst._my_friend_wanda_refuel_fuel = nil
        return
    end
    local fuel = inst._my_friend_wanda_refuel_fuel
    if fuel == nil or not Carried(inst, fuel)
        or not watch.components.fueled:CanAcceptFuelItem(fuel) then
        if now < (inst._my_friend_wanda_refuel_fuel_check_after or 0) then return end
        inst._my_friend_wanda_refuel_fuel_check_after = now + 2
        fuel = nil
        for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
            if item.prefab == "nightmarefuel" and Carried(inst, item) then
                fuel = item
                break
            end
        end
        inst._my_friend_wanda_refuel_fuel = fuel
    end
    if watch == nil or fuel == nil or not watch.components.fueled:CanAcceptFuelItem(fuel) then return end
    inst._my_friend_wanda_refuel_after = now + .35
    local action = BufferedAction(inst, watch, ACTIONS.ADDFUEL, fuel)
    action.validfn = function()
        return RefuelActive(inst, watch) and Carried(inst, fuel)
            and watch.components.fueled:CanAcceptFuelItem(fuel)
    end
    action:AddSuccessAction(function()
        if RefuelActive(inst, watch) then
            inst._my_friend_wanda_refuel_after = GetTime() + .15
            if not Carried(inst, fuel) then
                inst._my_friend_wanda_refuel_fuel = nil
                inst._my_friend_wanda_refuel_fuel_check_after = 0
            end
        else
            inst._my_friend_wanda_refuel_watch = nil
            inst._my_friend_wanda_refuel_fuel = nil
            Dialogue.Say(inst, "activity_wanda_refuel")
        end
    end)
    return action
end

local function LooseFuel(inst, item)
    local ii = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    return item ~= nil and item.prefab == "nightmarefuel" and ii ~= nil
        and ii.owner == nil and ii.canbepickedup and not item:IsInLimbo()
        and not item:HasAnyTag("fire", "NOCLICK")
        and not Policy.IsBaseCacheItem(inst, item) and Policy.InRange(inst, item)
        and inst.components.inventory:CanAcceptCount(item, 1) > 0
end

function M.GetFuelPickupAction(inst)
    if inst.prefab ~= "wanda" or Policy.IsBusy(inst) or inst._my_friend_command ~= nil
        or inst._my_friend_work_target ~= nil or inst._my_friend_under_threat
        or GetTime() < (inst._my_friend_wanda_fuel_scan_after or 0) then return end
    inst._my_friend_wanda_fuel_scan_after = GetTime() + 8
    local x, y, z = inst.Transform:GetWorldPosition()
    local best, nearest
    local Navigation = require("my_friend_navigation")
    for _, item in ipairs(TheSim:FindEntities(x, y, z, M.FUEL_RANGE,
        {"_inventoryitem"}, {"INLIMBO", "fire", "NOCLICK"})) do
        if LooseFuel(inst, item) and not Navigation.IsBlocked(inst, item:GetPosition()) then
            local distance = inst:GetDistanceSqToInst(item)
            if nearest == nil or distance < nearest then best, nearest = item, distance end
        end
    end
    if best == nil then return end
    local action = BufferedAction(inst, best, ACTIONS.PICKUP)
    action._my_friend_dialogue_kind = "activity_wanda_fuel"
    action.validfn = function()
        return inst._my_friend_command == nil and not inst._my_friend_under_threat
            and LooseFuel(inst, best) and inst:GetDistanceSqToInst(best) <= M.FUEL_RANGE^2
    end
    return action
end

return M
