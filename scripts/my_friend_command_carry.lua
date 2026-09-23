-- Explicit heavy-object carrying. Kept separate from equipment pickup so a
-- normal "捡装备" command can never select statues or other heavy objects.
local M = {}
local Policy = require("my_friend_policy")
local Riding = require("my_friend_riding")
local Dialogue = require("my_friend_dialogue")

local function IsRiding(inst)
    return inst.components.rider ~= nil and inst.components.rider:IsRiding()
end

local function CanPickUp(inst, entity)
    if entity == nil or not entity:IsValid() or entity.components == nil
        or not entity:HasTag("heavy") then return false end
    local item = entity.components.inventoryitem
    local equip = entity.components.equippable
    local restrictions = inst.components.itemtyperestrictions
    local current = equip ~= nil and inst.components.inventory:GetEquippedItem(equip.equipslot) or nil
    return item ~= nil and equip ~= nil and not equip:IsRestricted(inst)
        and not inst.components.inventory.noheavylifting
        and (current == nil or not current.components.equippable:ShouldPreventUnequipping())
        and item.owner == nil
        and (item.canbepickedup or item.canbepickedupalive and not inst:HasTag("player")
            or item.grabbableoverridetag ~= nil and inst:HasTag(item.grabbableoverridetag))
        and not entity:IsInLimbo()
        and (restrictions == nil or restrictions:IsAllowed(entity))
        and (entity.components.container == nil or not entity.components.container:IsOpenedByOthers(inst))
        and (entity.components.burnable == nil or not entity.components.burnable:IsBurning()
            or entity.components.lighter ~= nil)
        and (entity.components.projectile == nil or not entity.components.projectile:IsThrown())
end

local function Carrying(inst)
    return require("my_friend_equip_slots").GetHeavy(inst.components.inventory)
end

local function FindStatue(inst, command)
    local origin = command.origin or command.player:GetPosition()
    local x, _, z = origin:Get()
    local best, distance
    for _, entity in ipairs(TheSim:FindEntities(x, 0, z, 32, nil,
        {"INLIMBO", "burnt", "fire"})) do
        if CanPickUp(inst, entity)
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
        if IsRiding(inst) then
            -- A previous failed pickup may have left the companion mounted.
            -- Do not issue MOUNT against an already mounted rider; continue
            -- the search from the current position instead.
            command.phase = "find"
        else
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
                and CanPickUp(inst, target) and Carrying(inst) == nil
        end
        action:AddSuccessAction(function()
            -- PICKUP can report success after GiveItem has put a heavy object
            -- into an ordinary inventory slot, especially after the previous
            -- statue was manually removed and the body slot is empty. Force
            -- the real heavy equip, then advance only if it actually worked.
            if Carrying(inst) ~= target and target:IsValid() then
                inst.components.inventory:Equip(target)
            end
            if Carrying(inst) == target then
                command.phase = "mount"
                Dialogue.Reply(inst, "carry_statue_follow")
            else
                command.phase = nil
                inst._my_friend_replan_requested = true
            end
        end)
        return Policy.GuardAction(inst, action, 32)
    end

    if command.phase == "mount" then
        if IsRiding(inst) then
            -- The statue is already secured and the mount action is complete.
            -- Clearing this command hands movement back to the normal riding
            -- behaviour instead of trying to mount the same beefalo again.
            require("my_friend_commands").Clear(inst)
            return
        end
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
