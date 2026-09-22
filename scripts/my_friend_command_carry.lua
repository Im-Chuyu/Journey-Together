-- Explicit heavy-object carrying. Kept separate from equipment pickup so a
-- normal "捡装备" command can never select statues or other heavy objects.
local M = {}
local Policy = require("my_friend_policy")
local Riding = require("my_friend_riding")
local Dialogue = require("my_friend_dialogue")

local function IsStatue(entity)
    if entity == nil or entity.components == nil
        or entity.components.inventoryitem == nil then return false end
    local prefab = entity.prefab or ""
    return entity:HasTag("statue") or entity:HasTag("sculpture")
        or prefab:find("statue", 1, true) ~= nil
        or prefab:find("sculpture_", 1, true) ~= nil
end

local function CanPickUp(entity)
    local item = entity.components.inventoryitem
    return item ~= nil and (item.canbepickedup or item.canbepickedupalive)
        and not entity:IsInLimbo()
end

local function Carrying(inst)
    local inventory = inst.components.inventory
    if inventory == nil then return nil end
    local body = inventory:GetEquippedItem(EQUIPSLOTS.BODY)
    return body ~= nil and body:HasTag("heavy") and body or nil
end

local function FindStatue(inst, command)
    local origin = command.origin or command.player:GetPosition()
    local x, _, z = origin:Get()
    local best, distance
    for _, entity in ipairs(TheSim:FindEntities(x, 0, z, 32, nil,
        {"INLIMBO", "burnt", "fire"})) do
        if IsStatue(entity) and CanPickUp(entity)
            and not require("my_friend_navigation").IsBlocked(inst, entity:GetPosition()) then
            local d = inst:GetDistanceSqToInst(entity)
            if distance == nil or d < distance then best, distance = entity, d end
        end
    end
    return best
end

local function FinishWalking(inst)
    Dialogue.Reply(inst, "carry_statue_follow")
    require("my_friend_commands").Clear(inst)
end

function M.GetAction(inst, command)
    local carried = Carrying(inst)
    if carried == nil and command.phase == nil then
        local mount = Riding.GetBeefalo(inst)
        if mount ~= nil then
            command.phase = "mount_before"
            local action = Riding.GetMountAction(inst, mount)
            if action ~= nil then
                action._my_friend_dialogue_kind = "carry_statue_mount"
                action:AddSuccessAction(function()
                    if inst.components.rider ~= nil and inst.components.rider:IsRiding() then
                        command.phase = "find"
                    else
                        command.phase = nil
                    end
                end)
                action:AddFailAction(function()
                    if not action._my_friend_cancelled then command.phase = "find" end
                end)
                return Policy.GuardAction(inst, action, 32)
            end
            command.phase = "find"
        else
            command.phase = "find"
        end
    end
    if carried == nil then
        local target = FindStatue(inst, command)
        if target == nil then
            Dialogue.Reply(inst, "carry_statue_none")
            require("my_friend_commands").Clear(inst)
            return
        end
        local action = BufferedAction(inst, target, ACTIONS.PICKUP)
        action.arrivedist = 2
        action._my_friend_dialogue_kind = "carry_statue"
        action.validfn = function()
            return command == inst._my_friend_command and target:IsValid()
                and CanPickUp(target) and Carrying(inst) == nil
        end
        action:AddSuccessAction(function()
            command.phase = "mount"
            Dialogue.Reply(inst, "carry_statue_follow")
        end)
        return Policy.GuardAction(inst, action, 32)
    end

    if command.phase == "mount" then
        local mount = Riding.GetBeefalo(inst)
        if mount == nil then
            FinishWalking(inst)
            return
        end
        local action = Riding.GetMountAction(inst, mount)
        if action == nil then
            FinishWalking(inst)
            return
        end
        action._my_friend_dialogue_kind = "carry_statue_mount"
        action:AddSuccessAction(function()
            if inst.components.rider ~= nil and inst.components.rider:IsRiding() then
                -- The normal ride node now owns mounted movement and keeps the
                -- heavy body item equipped while the companion follows.
                require("my_friend_commands").Clear(inst)
            end
        end)
        return Policy.GuardAction(inst, action, 32)
    end

    FinishWalking(inst)
end

return M
