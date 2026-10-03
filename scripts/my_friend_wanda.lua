local M = {}
local Policy = require("my_friend_policy")
local Dialogue = require("my_friend_dialogue")

M.HEAL_AGE = 73
M.FUEL_RANGE = 20

local function Carried(inst, item)
    local ii = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    return ii ~= nil and not ii.islockedinslot and ii:GetGrandOwner() == inst
end

function M.GetAge(inst)
    if inst.prefab ~= "wanda" or inst.components.oldager == nil
        or inst.components.health == nil then return end
    return TUNING.WANDA_MAX_YEARS_OLD - inst.components.health.currenthealth
        + inst.components.oldager:GetCurrentYearPercent()
end

function M.NeedsHeal(inst)
    local age = M.GetAge(inst)
    return age ~= nil and age >= M.HEAL_AGE
        and not inst.components.health:IsDead() and not inst:HasTag("playerghost")
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
            action:AddSuccessAction(function() Dialogue.RandomReply(inst, "watch_heal") end)
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

function M.GetRefuelAction(inst)
    if inst.prefab ~= "wanda" or Policy.IsBusy(inst)
        or GetTime() < (inst._my_friend_wanda_refuel_after or 0) then return end
    inst._my_friend_wanda_refuel_after = GetTime() + 3
    local watch, fuel
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if NeedsFuel(inst, item) then watch = watch or item end
        if item.prefab == "nightmarefuel" and Carried(inst, item) then fuel = fuel or item end
    end
    if watch == nil or fuel == nil or not watch.components.fueled:CanAcceptFuelItem(fuel) then return end
    local action = BufferedAction(inst, watch, ACTIONS.ADDFUEL, fuel)
    action.validfn = function()
        return NeedsFuel(inst, watch) and Carried(inst, fuel)
            and watch.components.fueled:CanAcceptFuelItem(fuel)
    end
    action:AddSuccessAction(function() Dialogue.Say(inst, "activity_wanda_refuel") end)
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
