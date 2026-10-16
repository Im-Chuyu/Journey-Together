local Forestry = require("my_friend_forestry")
local Navigation = require("my_friend_navigation")
local Policy = require("my_friend_policy")
local M = {RANGE = 10}
local SEEDS = {pinecone = true, acorn = true, twiggy_nut = true}

local function Seed(inst, item)
    local components = item ~= nil and item:IsValid() and item.components or nil
    local inventoryitem = components ~= nil and components.inventoryitem or nil
    return components ~= nil and SEEDS[item.prefab] == true and components.deployable ~= nil
        and inventoryitem ~= nil and not inventoryitem.islockedinslot
        and inventoryitem:GetGrandOwner() == inst
end

local function Finish(inst, command, reply)
    if inst._my_friend_command ~= command then return end
    require("my_friend_commands").Clear(inst)
    require("my_friend_dialogue").Reply(inst, reply)
end

function M.GetAction(inst, command)
    if command == nil or command.id ~= "plant_trees"
        or require("my_friend_commands").Get(inst) ~= command or Policy.IsBusy(inst)
        or inst:HasTag("playerghost") or inst.components.health:IsDead() then return end
    local plot = command.plant_plot
    if plot ~= nil and (command.planted_count or 0) >= #plot.points then
        Finish(inst, command, "plant_trees_done")
        return
    end
    local inventory = inst.components.inventory
    if inventory == nil then return end
    local item = inventory:GetActiveItem()
    if not Seed(inst, item) then
        item = nil
        for _, candidate in ipairs(inventory:ReferenceAllItems()) do
            if Seed(inst, candidate) then item = candidate break end
        end
    end
    if item == nil then
        Finish(inst, command, (command.planted_count or 0) > 0 and "plant_trees_done" or "plant_trees_no_seeds")
        return
    end
    if plot == nil then
        plot = {x = command.origin.x, z = command.origin.z, blocked = {}, half_size = M.RANGE}
        plot.points = Forestry.Points(plot)
        command.plant_plot = plot
    end
    local function Passable(point)
        return math.abs(point.x - command.origin.x) <= M.RANGE
            and math.abs(point.z - command.origin.z) <= M.RANGE
            and Navigation.IsLand(point) and not Navigation.IsBlocked(inst, point)
            and not require("my_friend_behavior_ai").IsHazardousPath(inst, point, point)
    end
    local point, index = Forestry.SelectPlantPoint(inst, item, plot, Forestry.Trees(inst, plot), Passable)
    if point == nil then Finish(inst, command, "plant_trees_no_space") return end
    local action = BufferedAction(inst, nil, ACTIONS.DEPLOY, item, point)
    action._my_friend_command_origin = command.origin
    action.validfn = function()
        return inst:IsValid() and not inst:HasTag("playerghost") and not inst.components.health:IsDead()
            and require("my_friend_commands").Get(inst) == command and Seed(inst, item)
            and Passable(point) and item.components.deployable:CanDeploy(point, nil, inst, 0)
    end
    action:AddSuccessAction(function()
        if inst:IsValid() and inst._my_friend_command == command then
            plot.blocked[index] = math.huge
            command.planted_count = (command.planted_count or 0) + 1
        end
    end)
    action:AddFailAction(function()
        if inst:IsValid() and inst._my_friend_command == command and not action._my_friend_cancelled then
            plot.blocked[index] = math.huge
        end
    end)
    require("my_friend_base_ai").SetTask(inst, "正在当前位置附近种树")
    return Policy.GuardAction(inst, action)
end

return M
