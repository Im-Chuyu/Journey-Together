local M = {}
local function FindShovel(inst)
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if require("my_friend_inventory").IsUsableTool(inst, item, ACTIONS.DIG) then return item end
    end
end

local function Count(inst, prefab)
    local total = 0
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if item.prefab == prefab then
            total = total + (item.components.stackable ~= nil and item.components.stackable:StackSize() or 1)
        end
    end
    return total
end

function M.Record(inst, tree, point, deferred)
    local command = inst._my_friend_command
    if command == nil or command.id ~= "chop" then return end
    command.chop_cleanup = {tree = tree, point = point, ready = GetTime() + 1,
        expires = GetTime() + 60, failed = {},
        dug = deferred ~= false}
    inst._my_friend_work_cleanup = nil
end

function M.Action(inst, command)
    local inv = inst.components.inventory
    command.chop_cargo = command.chop_cargo or {}
    local overflow = inv:GetOverflowContainer()
    local free = inv:GetNumSlots() - inv:NumItems()
        + (overflow ~= nil and overflow:GetNumSlots() - overflow:NumItems() or 0)
    if free <= 2 or command.chop_delivering then
        command.chop_delivering = true
        for _, item in ipairs(inv:ReferenceAllItems()) do
            local count = math.min(command.chop_cargo[item.prefab] or 0,
                item.components.stackable ~= nil and item.components.stackable:StackSize() or 1)
            if count > 0 then
                local prefab = item.prefab
                local action = require("my_friend_tidy").HandOver(inst, command, item, count)
                action._my_friend_chop_delivery = true
                action:AddSuccessAction(function()
                    command.chop_cargo[prefab] = math.max(0, (command.chop_cargo[prefab] or 0) - count)
                    if command.chop_cleanup ~= nil then
                        command.chop_cleanup.expires = GetTime() + 60
                    end
                end)
                action:AddFailAction(function()
                    if not action._my_friend_cancelled and inst._my_friend_command == command then
                        require("my_friend_commands").Clear(inst)
                    end
                end)
                return action, true
            end
        end
        command.chop_delivering = nil
        if free <= 0 then require("my_friend_commands").Clear(inst) return nil, true end
    end
    local cleanup = command.chop_cleanup
    if cleanup == nil then return end
    if GetTime() < cleanup.ready then
        local wait = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, inst:GetPosition())
        wait._my_friend_command_origin = command.origin
        return wait, true
    end
    if GetTime() >= cleanup.expires then command.chop_cleanup = nil return end
    local tree = cleanup.tree
    if tree ~= nil and tree:IsValid() and tree:HasTag("stump") and not cleanup.dug then
        local workable = tree.components.workable
        local tool = FindShovel(inst)
        if tool ~= nil and workable ~= nil and workable:CanBeWorked()
            and workable:GetWorkAction() == ACTIONS.DIG then
            if not require("my_friend_base_ai").CanUseHandToolInCurrentLight(inst) then return nil, true end
            local action = BufferedAction(inst, tree, ACTIONS.DIG, tool)
            action:AddSuccessAction(function() cleanup.dug = true cleanup.ready = GetTime() + .5 end)
            action:AddFailAction(function() if not action._my_friend_cancelled then cleanup.dug = true end end)
            return action, true
        end
        cleanup.dug = true
    end
    local p, best, distance = cleanup.point
    for _, item in ipairs(TheSim:FindEntities(p.x, 0, p.z, 5, {"_inventoryitem"}, {"INLIMBO", "fire"})) do
        local ii = item.components.inventoryitem
        if ii ~= nil and ii.owner == nil and ii.canbepickedup and not item:HasTag("irreplaceable")
            and item.components.equippable == nil and not cleanup.failed[item.GUID]
            and not (command.delivered or {})[item.GUID] and inv:CanAcceptCount(item, 1) > 0 then
            local d = inst:GetDistanceSqToInst(item)
            if distance == nil or d < distance then best, distance = item, d end
        end
    end
    if best ~= nil then
        local prefab, before = best.prefab, Count(inst, best.prefab)
        local action = BufferedAction(inst, best, ACTIONS.PICKUP)
        action._my_friend_chop_loot = cleanup.point
        action:AddSuccessAction(function()
            command.chop_cargo[prefab] = (command.chop_cargo[prefab] or 0)
                + math.max(0, Count(inst, prefab) - before)
        end)
        action:AddFailAction(function() if not action._my_friend_cancelled then cleanup.failed[best.GUID] = true end end)
        return action, true
    end
    command.chop_cleanup = nil
end

return M
