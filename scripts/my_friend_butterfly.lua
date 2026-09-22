local Policy = require("my_friend_policy")
local Behaviour = require("my_friend_behavior_ai")
local Navigation = require("my_friend_navigation")
local Food = require("my_friend_food_ai")
local M = {RANGE = 20, ATTACK_DISTANCE = .6, CHASE_TIME = 15, LOW_HEALTH = .35}
local LOOT = {butterflywings = true, butter = true}

local function Current(inst, state)
    return state.automatic and inst._my_friend_butterfly_hunt == state and Policy.GetLeader(inst) == nil
        or not state.automatic and inst._my_friend_command == state
            and Policy.GetLeader(inst) == state.player
end

local function InRange(inst, state, target)
    local origin = state.automatic and state.origin or state.player:GetPosition()
    local p = target:GetPosition()
    return (origin.x - p.x)^2 + (origin.z - p.z)^2 <= M.RANGE^2
        and Policy.InRange(inst, target)
end

local function Valid(inst, state, target)
    local health = target ~= nil and target:IsValid() and target.components.health or nil
    return target ~= nil and target.prefab == "butterfly" and health ~= nil and not health:IsDead()
        and not target:HasAnyTag("INLIMBO", "NOCLICK", "notarget", "player")
        and target.components.combat ~= nil
        and (target.components.inventoryitem == nil or target.components.inventoryitem.owner == nil)
        and InRange(inst, state, target)
        and inst.components.combat:CanTarget(target)
end

local function FindTarget(inst, state)
    local p = state.automatic and state.origin or state.player:GetPosition()
    local best, distance
    for _, target in ipairs(TheSim:FindEntities(p.x, 0, p.z, M.RANGE,
        {"butterfly"}, {"INLIMBO", "NOCLICK", "notarget"})) do
        if Valid(inst, state, target) and GetTime() >= ((state.butterfly_failed or {})[target] or 0)
            and not Navigation.IsBlocked(inst, target:GetPosition()) then
            local d = inst:GetDistanceSqToInst(target)
            if distance == nil or d < distance then best, distance = target, d end
        end
    end
    return best
end

-- Native locomotor accepts the full weapon range even with a smaller arrivedist.
-- Restrict only our queued butterfly attack, retaining validity and cooldown.
local function ConfigureApproach(inst)
    local combat = inst.components.combat
    if combat._my_friend_butterfly_approach or combat.LocomotorCanAttack == nil then return end
    combat._my_friend_butterfly_approach = true
    local original = combat.LocomotorCanAttack
    combat.LocomotorCanAttack = function(self, reached, target)
        local ready, invalid, cooldown = original(self, reached, target)
        local action = inst.components.locomotor ~= nil and inst.components.locomotor.bufferedaction
        if action ~= nil and action._my_friend_butterfly_attack and action.target == target
            and target ~= nil and target:IsValid() then
            ready = ready and Policy.DistanceSq(inst, target) <= M.ATTACK_DISTANCE^2
        end
        return ready, invalid, cooldown
    end
end

local function MarkMiss(state, target)
    state.butterfly_failed[target] = GetTime() + 10
    state.butterfly_target, state.butterfly_until = nil, nil
end

local function GetLootAction(inst, state)
    local loot = state.butterfly_loot
    if loot == nil then return end
    if GetTime() >= loot.untiltime then state.butterfly_loot = nil return end
    local best, distance
    for _, item in ipairs(TheSim:FindEntities(loot.point.x, 0, loot.point.z, 4,
        {"_inventoryitem"}, {"INLIMBO", "NOCLICK"})) do
        local component = item.components.inventoryitem
        if item:IsValid() and LOOT[item.prefab] and component ~= nil and component.owner == nil
            and component.canbepickedup and not loot.failed[item] and InRange(inst, state, item)
            and not Navigation.IsBlocked(inst, item:GetPosition())
            and inst.components.inventory:CanAcceptCount(item, 1) > 0 then
            local d = inst:GetDistanceSqToInst(item)
            if distance == nil or d < distance then best, distance = item, d end
        end
    end
    if best == nil then state.butterfly_loot = nil return end
    local action = BufferedAction(inst, best, ACTIONS.PICKUP)
    action._my_friend_dialogue_kind = "butterfly_loot"
    action.validfn = function()
        return Current(inst, state) and InRange(inst, state, best)
            and best.components.inventoryitem.owner == nil
    end
    action:AddSuccessAction(function() inst._my_friend_food_supply_cache = nil end)
    action:AddFailAction(function()
        if not action._my_friend_cancelled then loot.failed[best] = true end
    end)
    return Policy.GuardAction(inst, action, M.RANGE)
end

local function ObserveDeath(state)
    local target = state.butterfly_target
    if target ~= nil and target:IsValid() and target.components.health:IsDead() then
        state.butterfly_loot = {point = target:GetPosition(), untiltime = GetTime() + 8, failed = {}}
        state.butterfly_target, state.butterfly_until = nil, nil
        state.butterfly_killed = true
    end
end

local function GetAction(inst, state)
    if not Current(inst, state) or Policy.IsBusy(inst) then return end
    ObserveDeath(state)
    local loot = GetLootAction(inst, state)
    if loot ~= nil then return loot end
    if state.automatic and state.butterfly_killed then return end
    state.butterfly_failed = state.butterfly_failed or {}
    local target = state.butterfly_target
    if target ~= nil and (not Valid(inst, state, target) or GetTime() >= state.butterfly_until) then
        MarkMiss(state, target)
        target = nil
    end
    if target == nil then
        target = FindTarget(inst, state)
        if target == nil then return end
        state.butterfly_target, state.butterfly_until = target, GetTime() + M.CHASE_TIME
    end
    ConfigureApproach(inst)
    local inventory = inst.components.inventory
    local weapon = Behaviour.FindBestCombatWeapon(inst, target)
    if weapon ~= nil and inventory:GetEquippedItem(EQUIPSLOTS.HANDS) ~= weapon
        and require("my_friend_base_ai").CanUseHandToolInCurrentLight(inst) then inventory:Equip(weapon) end
    local deadline = state.butterfly_until
    inst._my_friend_combat_hand_until = deadline
    local function ReleaseHand()
        if inst._my_friend_combat_hand_until == deadline then inst._my_friend_combat_hand_until = nil end
    end
    local action = BufferedAction(inst, target, ACTIONS.ATTACK)
    action.arrivedist, action._my_friend_butterfly_attack = M.ATTACK_DISTANCE, true
    action._my_friend_dialogue_kind = "butterfly_hunt"
    action.validfn = function()
        return Current(inst, state) and state.butterfly_target == target
            and Valid(inst, state, target) and GetTime() < deadline
    end
    action:AddSuccessAction(function()
        ReleaseHand()
        state.butterfly_started = true
        ObserveDeath(state)
    end)
    action:AddFailAction(function()
        ReleaseHand()
        if not action._my_friend_cancelled and state.butterfly_target == target then MarkMiss(state, target) end
    end)
    return Policy.GuardAction(inst, action, M.RANGE)
end

function M.GetCommandAction(inst, command)
    local action = GetAction(inst, command)
    if action ~= nil or Policy.IsBusy(inst) then return action end
    require("my_friend_commands").Clear(inst)
    require("my_friend_dialogue").Reply(inst,
        command.butterfly_started and "butterfly_done" or "butterfly_none")
end

function M.Cancel(inst)
    inst._my_friend_butterfly_hunt = nil
end

local function HasRoom(inst)
    local inventory = inst.components.inventory
    if not inventory:IsFull() then return true end
    local overflow = inventory:GetOverflowContainer()
    if overflow ~= nil and not overflow:IsFull() then return true end
    return inventory:FindItem(function(item)
        return LOOT[item.prefab] and item.components.stackable ~= nil and not item.components.stackable:IsFull()
    end) ~= nil
end

local function CanUseWings(inst)
    local sample = SpawnPrefab("butterflywings")
    if sample == nil then return false end
    local eater = inst.components.eater
    local useful = eater ~= nil and eater:CanEat(sample) and eater:PrefersToEat(sample)
    if useful then
        local health, hunger = Food.GetFoodDeltas(inst, sample)
        useful = Food.NeedsFoodSupply(inst) and hunger > 0
            or inst.components.health:GetPercent() <= M.LOW_HEALTH and health > 0
    end
    sample:Remove()
    return useful
end

function M.Score(inst, context)
    if context.leader ~= nil or context.ghost or context.threat ~= nil or context.dark
        or context.thermal or context.hurt or context.hurt_evade then M.Cancel(inst) return 0 end
    local state = inst._my_friend_butterfly_hunt
    if state ~= nil then
        if GetTime() < state.untiltime then return 106 end
        M.Cancel(inst)
        inst._my_friend_butterfly_after = GetTime() + 5
    end
    return GetTime() >= (inst._my_friend_butterfly_after or 0)
        and (context.needsfood or inst.components.health:GetPercent() <= M.LOW_HEALTH)
        and FindTarget(inst, {automatic = true, origin = inst:GetPosition()}) ~= nil and 103 or 0
end

function M.GetSurvivalAction(inst)
    if Policy.GetLeader(inst) ~= nil or inst:HasTag("playerghost") or Policy.IsBusy(inst)
        or inst.components.health:IsDead() then return end
    local state = inst._my_friend_butterfly_hunt
    if state == nil then
        if GetTime() < (inst._my_friend_butterfly_after or 0) or not HasRoom(inst) then return end
        -- Eat an available meal first; chasing is for a shortage of useful food.
        local eat = Food.GetEatAction(inst)
        if eat ~= nil then return eat end
        if not Food.NeedsFoodSupply(inst) and inst.components.health:GetPercent() > M.LOW_HEALTH then return end
        if not CanUseWings(inst) then
            inst._my_friend_butterfly_after = GetTime() + 5
            return
        end
        state = {automatic = true, origin = inst:GetPosition(), untiltime = GetTime() + 30}
        inst._my_friend_butterfly_hunt = state
    end
    local action = GetAction(inst, state)
    if action == nil then
        M.Cancel(inst)
        inst._my_friend_butterfly_after = GetTime() + 5
    end
    return action
end

return M
