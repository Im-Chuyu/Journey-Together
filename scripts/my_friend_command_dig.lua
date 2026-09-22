local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")
local Work = require("my_friend_command_work")
local M = {}
M.RANGE = 24
local PRODUCTS = {dig_grass = "dug_grass", dig_sapling = "dug_sapling", dig_stump = "log"}

function M.IsCommand(id)
    return PRODUCTS[id] ~= nil
end

function M.IsTarget(inst, command, target)
    if target == nil or not target:IsValid() or target:HasAnyTag("INLIMBO", "fire")
        or target:GetDistanceSqToInst(command.player) > M.RANGE^2
        or target:GetCurrentPlatform() ~= inst:GetCurrentPlatform() then return false end
    local workable = target.components.workable
    if workable == nil or not workable:CanBeWorked() or workable:GetWorkAction() ~= ACTIONS.DIG then return false end
    return command.id == "dig_grass" and target.prefab == "grass"
        or command.id == "dig_sapling" and target.prefab == "sapling"
        or command.id == "dig_stump" and target:HasTag("stump")
end

local function Finish(inst, command, reply)
    if inst._my_friend_command ~= command then return end
    Work.Finish(inst, command)
    require("my_friend_dialogue").Reply(inst, reply)
end

function M.Action(inst, command, gather, has_room)
    local Base = require("my_friend_base_ai")
    command.waiting = nil
    -- Finish the previous plant's native drop animation and loot before digging
    -- another one, so a new job cannot overwrite the existing cleanup record.
    if inst._my_friend_work_cleanup ~= nil then
        local action = Base.GetCleanupAction(inst)
        command.waiting = inst._my_friend_work_cleanup ~= nil or nil
        if action ~= nil or command.waiting then return action end
    end
    local inv = inst.components.inventory
    local product = PRODUCTS[command.id]
    if not has_room(inst, product) then
        Finish(inst, command, "dig_full")
        return
    end
    command.dig_failed = command.dig_failed or {}
    local x, y, z = command.player.Transform:GetWorldPosition()
    local best, distance
    for _, target in ipairs(TheSim:FindEntities(x, y, z, M.RANGE,
        {"DIG_workable"}, {"INLIMBO", "FX", "DECOR", "fire"})) do
        if M.IsTarget(inst, command, target) and not command.dig_failed[target.GUID]
            and not Navigation.IsBlocked(inst, target:GetPosition())
            and not require("my_friend_behavior_ai").IsTargetUnsafe(inst, target) then
            local d = inst:GetDistanceSqToInst(target)
            if distance == nil or d < distance then best, distance = target, d end
        end
    end
    if best == nil then
        Finish(inst, command, (command.dig_count or 0) > 0 and "dig_done" or "dig_none")
        return
    end
    local tool, preparation = Work.Tool(inst, command, ACTIONS.DIG, "shovel", true)
    if preparation ~= nil then return preparation end
    if tool == nil then Work.Finish(inst, command, true) return end
    if not Base.CanUseHandToolInCurrentLight(inst) then command.waiting = true return end
    if inv:GetEquippedItem(EQUIPSLOTS.HANDS) ~= tool and not inv:Equip(tool) then
        Work.Finish(inst, command, true)
        return
    end
    local point = best:GetPosition()
    local action = gather(inst, best, ACTIONS.DIG, tool)
    local valid = action.validfn
    action.validfn = function(act)
        return M.IsTarget(inst, command, best) and (valid == nil or valid(act))
    end
    action:AddFailAction(function()
        if not action._my_friend_cancelled then command.dig_failed[best.GUID] = true end
    end)
    action:AddSuccessAction(function()
        command.dig_count = (command.dig_count or 0) + 1
        if command.id == "dig_stump" then
            inst._my_friend_work_cleanup = {x = point.x, z = point.z, action = ACTIONS.DIG,
                primary = "log", prefabs = {log = true, charcoal = true}, started = GetTime(),
                deadline = GetTime() + Base.MINE_LOOT_TIMEOUT}
        end
    end)
    return Policy.GuardAction(inst, action, M.RANGE)
end

return M
