local M = {}
local Policy = require("my_friend_policy")
local Dialogue = require("my_friend_dialogue")

local function Carried(inst, item)
    return item ~= nil and item:IsValid() and item.components.inventoryitem ~= nil
        and not item.components.inventoryitem.islockedinslot
        and item.components.inventoryitem:GetGrandOwner() == inst
end

function M.GetHealAction(inst)
    return require("my_friend_wanda").GetHealAction(inst)
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

function M.InstallSoulHealing()
    require("my_friend_wortox").InstallSoulHealing()
end

return M
