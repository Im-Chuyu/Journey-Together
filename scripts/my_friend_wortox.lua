local M = {}
local Policy = require("my_friend_policy")
local Dialogue = require("my_friend_dialogue")

M.HEAL_START = .5
M.HEAL_STOP = .8
M.HEAL_RANGE = 20

local function NeedsHealing(player, threshold)
    return Policy.IsLocalPlayer(player) and player.entity:IsVisible()
        and not player:HasAnyTag("playerghost", "health_as_oldage")
        and player.components.health ~= nil and not player.components.health:IsDead()
        and player.components.health:GetPercent() < threshold
end

local function CarriedSoul(inst, soul)
    local ii = soul ~= nil and soul:IsValid() and soul.components.inventoryitem or nil
    return soul ~= nil and soul.prefab == "wortox_soul" and ii ~= nil
        and not ii.islockedinslot and ii:GetGrandOwner() == inst
end

local function FindPatient(inst)
    local patient = inst._my_friend_soul_patient
    if NeedsHealing(patient, M.HEAL_STOP)
        and inst:GetDistanceSqToInst(patient) <= M.HEAL_RANGE^2
        and Policy.InRange(inst, patient) then return patient end
    inst._my_friend_soul_patient = nil
    local leader = Policy.GetLeader(inst)
    if NeedsHealing(leader, M.HEAL_START)
        and inst:GetDistanceSqToInst(leader) <= M.HEAL_RANGE^2 then
        inst._my_friend_soul_patient = leader
        return leader
    end
    local lowest = M.HEAL_START
    for _, player in ipairs(AllPlayers) do
        if NeedsHealing(player, lowest) and Policy.InRange(inst, player)
            and inst:GetDistanceSqToInst(player) <= M.HEAL_RANGE^2 then
            patient, lowest = player, player.components.health:GetPercent()
            inst._my_friend_soul_patient = player
        end
    end
    return inst._my_friend_soul_patient
end

function M.GetHealPlayerAction(inst)
    if inst.prefab ~= "wortox" or Policy.IsBusy(inst) or inst._my_friend_under_threat
        or inst._my_friend_command ~= nil or inst._my_friend_storage_action
        or inst._my_friend_container_action or inst._my_friend_backpack_action
        or GetTime() < (inst._my_friend_soul_heal_after or 0) then return end
    local patient = FindPatient(inst)
    if patient == nil then return end
    local soul
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if CarriedSoul(inst, item) then soul = item break end
    end
    if soul == nil then return end
    local point = patient:GetPosition()
    local action
    if inst:GetDistanceSqToInst(patient) > 2^2 then
        action = BufferedAction(inst, patient, ACTIONS.WALKTO)
        action.arrivedist = 2
    else
        action = BufferedAction(inst, nil, ACTIONS.DROP, soul, point)
        action.options.wholestack = false
        action:AddSuccessAction(function()
            -- Wait for vanilla delayed healing before spending the next soul.
            inst._my_friend_soul_heal_after = GetTime() + TUNING.WORTOX_SOUL_HEAL_DELAY + .5
            Dialogue.Say(inst, "activity_wortox_heal", patient)
        end)
    end
    action.validfn = function()
        return inst._my_friend_command == nil and not inst._my_friend_under_threat
            and NeedsHealing(patient, M.HEAL_STOP) and CarriedSoul(inst, soul)
            and Policy.InRange(inst, patient)
            and inst:GetDistanceSqToInst(patient) <= M.HEAL_RANGE^2
            and (action.action ~= ACTIONS.DROP
                or patient:GetDistanceSqToPoint(point) < 2^2)
    end
    action:AddFailAction(function()
        if not action._my_friend_cancelled then inst._my_friend_soul_heal_after = GetTime() + 5 end
    end)
    return action
end

-- Both native functions select real players from AllPlayers. Use a temporary
-- function environment during that call; leave the real registry untouched.
local function WithCompanion(fn, ...)
    local friend = TheWorld._my_friend
    if friend == nil or not friend:IsValid() or not friend:HasTag("my_friend") then return fn(...) end
    local targets = {}
    for _, player in ipairs(AllPlayers) do
        if player == friend then return fn(...) end
        targets[#targets + 1] = player
    end
    targets[#targets + 1] = friend
    local env = getfenv(fn)
    setfenv(fn, setmetatable({AllPlayers = targets}, {__index = env}))
    local ok, result = pcall(fn, ...)
    setfenv(fn, env)
    if not ok then error(result) end
    return result
end

function M.InstallSoulAttraction(soul)
    if not TheWorld.ismastersim or soul._seektask == nil then return end
    local task = soul._seektask
    local seek = task.fn
    task.fn = function(inst, ...)
        local friend = TheWorld._my_friend
        if friend == nil or not friend:IsValid() or friend.prefab ~= "wortox"
            or not friend:HasTag("soulstealer") or friend:HasTag("playerghost")
            or friend.components.health == nil or friend.components.health:IsDead()
            or not friend.entity:IsVisible() then return seek(inst, ...) end
        local range = TUNING.WORTOX_SOULSTEALER_RANGE
        local skills = friend.components.skilltreeupdater
        if skills ~= nil and skills:IsActivated("wortox_thief_1") then
            range = range + TUNING.SKILLS.WORTOX.SOULSTEALER_RANGE_BONUS
        end
        if inst:GetDistanceSqToInst(friend) >= range^2 then return seek(inst, ...) end
        return WithCompanion(seek, inst, ...)
    end
end

function M.InstallSoulHealing()
    local common = require("prefabs/wortox_soul_common")
    local original = common.DoHeal
    common.DoHeal = function(soul, ...)
        local friend = TheWorld._my_friend
        if friend == nil or not friend:IsValid() or friend.components.health == nil
            or friend.components.health:IsDead() or friend:HasTag("playerghost")
            or not friend.entity:IsVisible()
            or soul:GetDistanceSqToInst(friend) >= (TUNING.WORTOX_SOULHEAL_RANGE
                + (soul.soul_heal_range_modifier or 0))^2 then return original(soul, ...) end
        return WithCompanion(original, soul, ...)
    end
end

return M
