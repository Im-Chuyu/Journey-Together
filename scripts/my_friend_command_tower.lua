local Policy = require("my_friend_policy")
local M = {}
M.RANGE = 24

local function IsTower(target)
    return target ~= nil and target:IsValid() and target.prefab == "townportal"
        and not target:HasAnyTag("INLIMBO", "burnt", "fire")
        and target.components.channelable ~= nil
end

local function IsActiveTower(target)
    local teleporter = target ~= nil and target.components ~= nil
        and target.components.teleporter or nil
    return IsTower(target) and teleporter ~= nil and teleporter:IsActive()
end

function M.IsChanneling(inst)
    local command = inst._my_friend_command
    return command ~= nil and command.id == "touch_tower" and IsTower(command.target)
        and command.target.components.channelable:IsChanneling(inst)
end

function M.Cancel(inst, command)
    local target = command ~= nil and command.target or nil
    if IsTower(target) and target.components.channelable.channeler == inst then
        target.components.channelable:StopChanneling(true)
    end
end

function M.GetAction(inst, command)
    command = command or require("my_friend_commands").Get(inst)
    if command == nil or command.id ~= "touch_tower" or Policy.IsBusy(inst) then return end
    if M.IsChanneling(inst) then return end
    if command.channel_started then
        require("my_friend_commands").Clear(inst)
        return
    end
    local target = command.target
    if not IsTower(target) then
        local base = require("my_friend_base_ai").GetBasePoint(inst)
        local atbase = base ~= nil and inst:GetDistanceSqToPoint(base) <= 40 ^ 2
        local origin = atbase and base or command.origin or inst:GetPosition()
        local best
        for _, entity in ipairs(TheSim:FindEntities(origin.x, 0, origin.z,
            atbase and 40 or M.RANGE, nil, {"INLIMBO", "burnt", "fire"})) do
            if IsTower(entity) and (IsActiveTower(entity)
                or entity.components.channelable:GetEnabled()
                    and not entity.components.channelable:IsChanneling()) then
                local distance = inst:GetDistanceSqToInst(entity)
                if best == nil or distance < best then target, best = entity, distance end
            end
        end
        command.target = target
    end
    if not IsTower(target) or not (IsActiveTower(target)
        or target.components.channelable:GetEnabled()
            and not target.components.channelable:IsChanneling()) then
        require("my_friend_commands").Clear(inst)
        require("my_friend_dialogue").RandomReply(inst, "tower_missing")
        return
    end
    if inst.components.rider ~= nil and inst.components.rider:IsRiding() then
        require("my_friend_riding").StopRide(inst)
        return BufferedAction(inst, nil, ACTIONS.DISMOUNT)
    end
    -- A linked/activated town portal disables channelable after pairing. Use
    -- the vanilla teleport action for it; only an unlinked tower can be
    -- activated through STARTCHANNELING.
    local active = IsActiveTower(target)
    local action = BufferedAction(inst, target,
        active and ACTIONS.TELEPORT or ACTIONS.STARTCHANNELING)
    action._my_friend_tower_command = command
    action.validfn = function()
        return inst._my_friend_command == command and IsTower(target)
            and (IsActiveTower(target)
                or target.components.channelable:GetEnabled()
                    and not target.components.channelable:IsChanneling())
    end
    action:AddSuccessAction(function()
        if active then
            require("my_friend_commands").Clear(inst)
        else
            command.channel_started = true
            require("my_friend_dialogue").RandomReply(inst, "tower_channel")
        end
    end)
    action:AddFailAction(function()
        if not action._my_friend_cancelled then require("my_friend_commands").Clear(inst) end
    end)
    return Policy.GuardAction(inst, action, 32)
end

return M
