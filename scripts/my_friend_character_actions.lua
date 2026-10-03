local M = {}
local Policy = require("my_friend_policy")
local Dialogue = require("my_friend_dialogue")

local function Carried(inst, item)
    return item ~= nil and item:IsValid() and item.components.inventoryitem ~= nil
        and not item.components.inventoryitem.islockedinslot
        and item.components.inventoryitem:GetGrandOwner() == inst
end

function M.GetHealAction(inst)
    if not inst:HasTag("health_as_oldage") or Policy.IsBusy(inst)
        or inst.components.health:GetPercent() >= .9
        or GetTime() < (inst._my_friend_watch_retry or 0) then return end
    inst._my_friend_watch_retry = GetTime() + 2
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if item.prefab == "pocketwatch_heal" and Carried(inst, item)
            and item.components.pocketwatch ~= nil and item.components.pocketwatch:CanCast(inst) then
            local action = BufferedAction(inst, nil, ACTIONS.CAST_POCKETWATCH, item)
            action.validfn = function()
                return Carried(inst, item) and item.components.pocketwatch:CanCast(inst)
                    and inst.components.health:GetPercent() < .9
            end
            action:AddSuccessAction(function() Dialogue.RandomReply(inst, "watch_heal") end)
            return action
        end
    end
end

local function CanSqueeze(inst, item)
    return Carried(inst, item) and item.prefab == "wortox_reviver"
        and item.components.spellcaster ~= nil and item.components.spellcaster:CanCast(inst)
        and item.components.linkeditem ~= nil and item.components.linkeditem:GetOwnerInst() ~= nil
end

function M.GetSqueezeAction(inst)
    local Commands = require("my_friend_commands")
    local command = Commands.Get(inst)
    if command == nil or command.id ~= "squeeze_heart" or Policy.IsBusy(inst) then return end
    local item
    for _, candidate in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if CanSqueeze(inst, candidate) then item = candidate break end
    end
    if item == nil or inst.replica.inventory:IsHeavyLifting() then
        Commands.Clear(inst)
        Dialogue.RandomReply(inst, "heart_unavailable")
        return
    end
    if inst.components.rider ~= nil and inst.components.rider:IsRiding() then
        require("my_friend_riding").StopRide(inst)
        return BufferedAction(inst, nil, ACTIONS.DISMOUNT)
    end
    local action = BufferedAction(inst, nil, ACTIONS.CASTSPELL, item)
    action.validfn = function() return inst._my_friend_command == command and CanSqueeze(inst, item) end
    action:AddSuccessAction(function()
        Commands.Clear(inst)
        Dialogue.RandomReply(inst, "heart_squeezed")
    end)
    action:AddFailAction(function()
        if not action._my_friend_cancelled and inst._my_friend_command == command then
            Commands.Clear(inst)
            Dialogue.RandomReply(inst, "heart_unavailable")
        end
    end)
    return action
end

-- Called only when a soul actually heals. Keep vanilla range, sharing, skill
-- modifiers and Wanda's exclusion; never add NPCs to the real-player registry.
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
        local targets = {}
        for _, player in ipairs(AllPlayers) do
            if player == friend then return original(soul, ...) end
            targets[#targets + 1] = player
        end
        -- Invoke the native function in an isolated environment whose player
        -- list also contains the companion, preserving the full heal formula.
        targets[#targets + 1] = friend
        local env = getfenv(original)
        local wrapped = setmetatable({AllPlayers = targets}, {__index = env})
        setfenv(original, wrapped)
        local ok, result = pcall(original, soul, ...)
        setfenv(original, env)
        if not ok then error(result) end
        return result
    end
end

return M
