local Policy = require("my_friend_policy")
local Home = require("my_friend_home")
local M = {}
M.RANGE = 24

local function IsTower(target)
    return target ~= nil and target:IsValid() and target.prefab == "townportal"
        and not target:HasAnyTag("INLIMBO", "burnt", "fire")
        and target.components.channelable ~= nil
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
    if command == nil or Policy.IsBusy(inst) or Policy.GetLeader(inst) ~= nil then return end
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
            atbase and 40 or M.RANGE, {"channelable"}, {"INLIMBO", "burnt", "fire"})) do
            if IsTower(entity) and entity.components.channelable:GetEnabled()
                and not entity.components.channelable:IsChanneling()
                and Home.IsPointInRange(inst, entity:GetPosition()) then
                local distance = inst:GetDistanceSqToInst(entity)
                if best == nil or distance < best then target, best = entity, distance end
            end
        end
        command.target = target
    end
    if not IsTower(target) or not target.components.channelable:GetEnabled()
        or target.components.channelable:IsChanneling() then
        require("my_friend_commands").Clear(inst)
        require("my_friend_dialogue").Reply(inst, "special_cannot_make")
        return
    end
    local action = BufferedAction(inst, target, ACTIONS.STARTCHANNELING)
    action.validfn = function()
        return inst._my_friend_command == command and IsTower(target)
            and target.components.channelable:GetEnabled()
            and not target.components.channelable:IsChanneling()
    end
    action:AddSuccessAction(function() command.channel_started = true end)
    action:AddFailAction(function()
        if not action._my_friend_cancelled then require("my_friend_commands").Clear(inst) end
    end)
    return Policy.GuardAction(inst, action, 32)
end

return M
