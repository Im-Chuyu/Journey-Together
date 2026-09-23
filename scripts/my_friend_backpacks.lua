local M = {}
local Policy = require("my_friend_policy")
local Safety = require("my_friend_recovery_safety")
local EquipSlots = require("my_friend_equip_slots")

local COMMAND_RANGE = 10
local COMMAND_RANGE_SQ = COMMAND_RANGE * COMMAND_RANGE
local COMMAND_TIMEOUT = 20
local RECOVERY_TIMEOUT = 30

local function DistanceSq(a, b)
    local ax, _, az = a.Transform:GetWorldPosition()
    local bx, _, bz = b.Transform:GetWorldPosition()
    local dx, dz = bx - ax, bz - az
    return dx * dx + dz * dz
end

local function IsBackpack(item)
    return item ~= nil and item:IsValid() and item:HasTag("backpack")
        and item.components ~= nil
        and item.components.inventoryitem ~= nil
        and item.components.equippable ~= nil
        and EquipSlots.IsRegistered(item.components.equippable.equipslot)
end

local function CanEquip(friend, item)
    return IsBackpack(item) and not item.components.equippable:IsRestricted(friend)
end

local function IsAvailable(friend, item, range_sq)
    return CanEquip(friend, item) and not item:IsInLimbo()
        and (range_sq == nil or DistanceSq(friend, item) <= range_sq)
        and item.components.inventoryitem.owner == nil
        and item.components.inventoryitem.canbepickedup
end

local function SetOwned(item, owned)
    if not IsBackpack(item) then return end
    item._my_friend_owned_backpack = owned == true
    if owned then
        item:AddTag("my_friend_owned_backpack")
    else
        item:RemoveTag("my_friend_owned_backpack")
        item._my_friend_heavy_left = nil
    end
end

function M.WrapBackpack(inst)
    if not IsBackpack(inst) or inst._my_friend_backpack_save_wrapped then return end
    inst._my_friend_backpack_save_wrapped = true
    local old_save, old_load = inst.OnSave, inst.OnLoad
    inst.OnSave = function(self, data)
        local refs = old_save ~= nil and old_save(self, data) or nil
        if self._my_friend_owned_backpack then data.my_friend_owned_backpack = true end
        if self._my_friend_heavy_left then data.my_friend_heavy_left = true end
        return refs
    end
    inst.OnLoad = function(self, data, ents)
        if old_load ~= nil then old_load(self, data, ents) end
        SetOwned(self, data ~= nil and data.my_friend_owned_backpack == true)
        self._my_friend_heavy_left = self._my_friend_owned_backpack
            and data ~= nil and data.my_friend_heavy_left == true or nil
    end
end

function M.IsOwned(item)
    return IsBackpack(item) and item._my_friend_owned_backpack == true
end

function M.ClearOwned(item)
    SetOwned(item, false)
end

local function AllEntities()
    return Ents or {}
end

function M.MarkOwned(friend, backpack)
    if not CanEquip(friend, backpack) then return false end
    for _, item in pairs(AllEntities()) do
        if item ~= backpack and M.IsOwned(item) then SetOwned(item, false) end
    end
    local previous = friend._my_friend_owned_backpack
    if previous ~= nil and previous ~= backpack and M.IsOwned(previous) then
        SetOwned(previous, false)
    end
    M.WrapBackpack(backpack)
    SetOwned(backpack, true)
    friend._my_friend_owned_backpack = backpack
    return true
end

function M.FindOwned(friend)
    local remembered = friend._my_friend_owned_backpack
    if M.IsOwned(remembered) then return remembered end
    local inventory = friend.components ~= nil and friend.components.inventory or nil
    if inventory ~= nil and inventory.ReferenceAllItems ~= nil then
        for _, item in ipairs(inventory:ReferenceAllItems()) do
            if M.IsOwned(item) then
                friend._my_friend_owned_backpack = item
                return item
            end
        end
    end
    local now = GetTime()
    if (friend._my_friend_backpack_next_owned_scan or 0) > now then return end
    friend._my_friend_backpack_next_owned_scan = now + 2
    for _, item in pairs(AllEntities()) do
        if M.IsOwned(item) then
            friend._my_friend_owned_backpack = item
            return item
        end
    end
end

function M.NeedsCraftedBackpack(friend)
    -- A direct "pick/change backpack" request never silently turns into crafting.
    -- The command is allowed to finish quietly when no usable ground bag exists.
    if friend._my_friend_backpack_no_craft_until ~= nil
        and GetTime() < friend._my_friend_backpack_no_craft_until then
        return false
    end
    if GetTime() < (friend._my_friend_backpack_craft_after or 0) then return false end
    local inventory = friend.components ~= nil and friend.components.inventory or nil
    if inventory == nil then return false end
    local equipped = EquipSlots.GetBackpack(inventory)
    return not IsBackpack(equipped) and M.FindOwned(friend) == nil
end

local function BuildOrder(friend, equipped)
    local x, y, z = friend.Transform:GetWorldPosition()
    local order = {}
    for _, item in ipairs(TheSim:FindEntities(x, y, z, COMMAND_RANGE,
        { "backpack" }, { "INLIMBO" })) do
        if item ~= friend._my_friend_abandoned_backpack
            and IsAvailable(friend, item, COMMAND_RANGE_SQ) then order[#order + 1] = item end
    end
    table.sort(order, function(a, b)
        local ad, bd = DistanceSq(friend, a), DistanceSq(friend, b)
        return ad == bd and a.GUID < b.GUID or ad < bd
    end)
    if equipped ~= nil and equipped ~= friend._my_friend_abandoned_backpack then
        order[#order + 1] = equipped
    end
    friend._my_friend_backpack_order = order
    friend._my_friend_backpack_index = 0
    return order
end

local function FindNext(friend, order)
    local count = #order
    local start = friend._my_friend_backpack_index or 0
    for offset = 1, count do
        local index = (start + offset - 1) % count + 1
        if order[index] ~= friend._my_friend_abandoned_backpack
            and IsAvailable(friend, order[index], COMMAND_RANGE_SQ) then
            return order[index], index
        end
    end
end

function M.Request(friend, another)
    if friend == nil or not friend:IsValid() or friend.components.inventory == nil
        or friend.components.health == nil or friend.components.health:IsDead()
        or friend:HasTag("playerghost") or friend._my_friend_backpack_target ~= nil
        or friend._my_friend_backpack_action then return false end

    local equipped = EquipSlots.GetBackpack(friend.components.inventory)
    local has_backpack = IsBackpack(equipped)
    if another and not has_backpack or not another and has_backpack then return false end
    if another and equipped.components.equippable:ShouldPreventUnequipping() then return false end

    -- Only the bag being taken off is skipped, and only while swapping.
    -- Using FindOwned here meant a bag lying on the ground was marked as
    -- "abandoned" during a plain "pick up a backpack" request, so the one bag
    -- the companion was being sent to fetch became invisible to the search
    -- and the command quietly did nothing.
    local previous = M.FindOwned(friend)
    if previous ~= nil then SetOwned(previous, false) end
    friend._my_friend_abandoned_backpack = another and equipped or nil
    friend._my_friend_owned_backpack = nil
    friend._my_friend_backpack_retry = nil
    friend._my_friend_backpack_recover_after = nil

    local order = friend._my_friend_backpack_order
    if not another or order == nil or #order == 0 then
        order = BuildOrder(friend, another and equipped or nil)
    end
    local target, index = FindNext(friend, order)
    if target == nil then
        order = BuildOrder(friend, another and equipped or nil)
        target, index = FindNext(friend, order)
    end
    if target == nil then
        friend._my_friend_backpack_no_craft_until = GetTime() + COMMAND_TIMEOUT
        friend._my_friend_abandoned_backpack = nil
        return false
    end

    friend._my_friend_backpack_target = target
    if friend._my_friend_equip_after ~= nil then
        friend._my_friend_equip_after[target.components.equippable.equipslot] = nil
    end
    friend._my_friend_backpack_no_craft_until = nil
    friend._my_friend_backpack_pending_index = index
    friend._my_friend_backpack_deadline = GetTime() + COMMAND_TIMEOUT
    friend._my_friend_backpack_commanded = true
    return true
end

local function ClearAction(friend)
    friend._my_friend_backpack_action = nil
    friend._my_friend_backpack_action_since = nil
    friend._my_friend_backpack_target = nil
    friend._my_friend_backpack_pending_index = nil
    friend._my_friend_backpack_commanded = nil
    friend._my_friend_backpack_switch_prepared = nil
    -- Only skip the previous bag while the request that replaced it runs.
    -- Leaving it set made that bag invisible to every later request, so a
    -- second "pick up a backpack" found nothing and did nothing.
    friend._my_friend_abandoned_backpack = nil
end

local function StartOwnedRecovery(friend)
    if require("my_friend_carry_backpack").BlocksRecovery(friend) then return end
    if friend._my_friend_backpack_target ~= nil then return end
    if friend._my_friend_recover_death_drops then return end
    if GetTime() < (friend._my_friend_backpack_recover_after or 0) then return end
    local inventory = friend.components.inventory
    local equipped = EquipSlots.GetBackpack(inventory)
    if IsBackpack(equipped) then
        if M.IsOwned(equipped) then friend._my_friend_owned_backpack = equipped end
        return
    end
    local owned = M.FindOwned(friend)
    if owned == nil then return end
    local slot = owned.components.equippable.equipslot
    if not require("my_friend_equipment").Allowed(friend, slot)
        or slot == EQUIPSLOTS.BODY and friend._my_friend_temperature_body_equipped then return end
    local retry = friend._my_friend_backpack_retry
    if retry ~= nil and retry.target == owned then
        if DistanceSq(friend, owned) > 20^2 then retry.left = true end
        if not retry.left or DistanceSq(friend, owned) > 12^2
            or GetTime() < retry.after then return end
        friend._my_friend_backpack_retry = nil
    end
    if owned.components.inventoryitem.owner == friend then
        if CanEquip(friend, owned) then inventory:Equip(owned) end
    elseif IsAvailable(friend, owned)
        and Safety.IsSafe(friend, owned:GetPosition()) then
        friend._my_friend_backpack_target = owned
        friend._my_friend_backpack_deadline = GetTime() + RECOVERY_TIMEOUT
        friend._my_friend_backpack_commanded = false
    end
end

local function DeferRecovery(friend, target)
    if friend._my_friend_backpack_commanded ~= true and target ~= nil then
        friend._my_friend_backpack_retry = {target = target, after = GetTime() + 30,
            left = DistanceSq(friend, target) > 20^2}
    end
    ClearAction(friend)
end

function M.CancelRecovery(friend)
    local target = friend._my_friend_backpack_target
    DeferRecovery(friend, target ~= nil and target:IsValid() and target or nil)
end

-- _my_friend_backpack_action is raised while GetAction builds the pickup, and
-- only the action's own success/fail callbacks lower it again. An action that
-- is built but never run -- the brain prepares a higher priority action and
-- then discards it when something else wins the same tick -- used to leave the
-- flag raised for good, and every CanAct() test in the mod fails while it is.
-- That is what left a freshly revived companion unable to fetch its bag, break
-- its own skeleton or answer a backpack command ever again.
local function ReleaseStuckAction(friend)
    if not friend._my_friend_backpack_action then
        friend._my_friend_backpack_action_since = nil
        return
    end
    local now = GetTime()
    local locomotor = friend.components.locomotor
    local moving = locomotor ~= nil and locomotor.bufferedaction or nil
    local planning = friend._my_friend_navigation_action
    if friend:GetBufferedAction() ~= nil
        or moving ~= nil and moving.target == friend._my_friend_backpack_target
        or planning ~= nil and planning.target == friend._my_friend_backpack_target
        or friend.sg ~= nil and friend.sg:HasStateTag("busy") then
        friend._my_friend_backpack_action_since = now
        return
    end
    friend._my_friend_backpack_action_since = friend._my_friend_backpack_action_since or now
    if now - friend._my_friend_backpack_action_since > 3 then
        DeferRecovery(friend, friend._my_friend_backpack_target)
    end
end

function M.Priority(friend)
    ReleaseStuckAction(friend)
    local command = friend._my_friend_command
    if command ~= nil and (command.id == "seeds" or command.id == "tidy"
        or command.id == "equipment") then return 0 end
    M.Update(friend)
    local target = friend._my_friend_backpack_target
    if target ~= nil and GetTime() > (friend._my_friend_backpack_deadline or 0) then
        DeferRecovery(friend, target)
        return 0
    end
    return target ~= nil and 112 or 0
end

function M.Update(friend)
    if friend == nil or not friend:IsValid() or friend.components == nil
        or friend.components.inventory == nil or friend.components.health == nil
        or friend.components.health:IsDead() or friend:HasTag("playerghost")
        or friend._my_friend_under_threat or friend._my_friend_backpack_action
        or friend.sg ~= nil and friend.sg:HasStateTag("busy") then return end
    StartOwnedRecovery(friend)
end

function M.GetAction(friend)
    if require("my_friend_carry_backpack").BlocksRecovery(friend) then return end
    M.Update(friend)
    if friend == nil or not friend:IsValid() or friend.components.inventory == nil
        or friend._my_friend_under_threat or friend._my_friend_backpack_action
        or friend.sg ~= nil and friend.sg:HasStateTag("busy") then return end
    local target = friend._my_friend_backpack_target
    if target == nil then return end
    if not IsBackpack(target) then DeferRecovery(friend, target) return end
    local slot = target.components.equippable.equipslot
    if not require("my_friend_equipment").Allowed(friend, slot)
        or GetTime() < (friend._my_friend_backpack_recover_after or 0) then return end
    local commanded = friend._my_friend_backpack_commanded == true
    local range_sq = commanded and COMMAND_RANGE_SQ or nil
    if not IsAvailable(friend, target, range_sq)
        or commanded and not Policy.InRange(friend, target)
        or not Safety.IsSafe(friend, target:GetPosition())
        or GetTime() > (friend._my_friend_backpack_deadline or 0) then
        -- A command that is dropped here used to vanish without a word, which
        -- is indistinguishable from the command never having been heard.
        if commanded then
            require("my_friend_dialogue").Reply(friend, "backpack_unreachable")
        end
        DeferRecovery(friend, target)
        return
    end

    if not friend._my_friend_backpack_switch_prepared then
        local old = friend.components.inventory:GetEquippedItem(slot)
        if old ~= nil and old ~= target then
            if DistanceSq(friend, target) > 2^2 then
                local approach = BufferedAction(friend, target, ACTIONS.WALKTO)
                approach.arrivedist = 1.8
                approach.validfn = function()
                    return IsAvailable(friend, target, range_sq)
                        and require("my_friend_equipment").Allowed(friend, slot)
                        and GetTime() >= (friend._my_friend_backpack_recover_after or 0)
                        and (not commanded or Policy.InRange(friend, target))
                        and GetTime() <= (friend._my_friend_backpack_deadline or 0)
                        and Safety.IsSafe(friend, target:GetPosition())
                end
                approach._my_friend_owned_recovery = not commanded
                approach:AddFailAction(function()
                    if approach._my_friend_cancelled then friend._my_friend_backpack_action = nil
                    else DeferRecovery(friend, target) end
                end)
                return approach
            end
            if old.components.equippable:ShouldPreventUnequipping() then
                ClearAction(friend)
                return
            end
            if friend._my_friend_recover_death_drops
                and old.components.my_friend_death_drop == nil then
                old:AddComponent("my_friend_death_drop")
            end
            if IsBackpack(old) then
                friend.components.inventory:DropItem(old, true, false, friend:GetPosition())
            else
                local removed = friend.components.inventory:Unequip(slot)
                if removed ~= nil then
                    friend.components.inventory:GiveItem(removed, nil, friend:GetPosition())
                end
            end
        end
        friend._my_friend_backpack_switch_prepared = true
    end

    friend._my_friend_backpack_action = true
    friend._my_friend_backpack_action_since = GetTime()
    local pending_index = friend._my_friend_backpack_pending_index
    local action = BufferedAction(friend, target, ACTIONS.PICKUP)
    action._my_friend_owned_recovery = not commanded
    action.validfn = function()
        return IsAvailable(friend, target, range_sq)
            and require("my_friend_equipment").Allowed(friend, slot)
            and GetTime() >= (friend._my_friend_backpack_recover_after or 0)
            and (not commanded or Policy.InRange(friend, target))
            and Safety.IsSafe(friend, target:GetPosition())
            and GetTime() <= (friend._my_friend_backpack_deadline or 0)
    end
    action:AddSuccessAction(function()
        local inventory = friend.components.inventory
        local equipped = inventory:GetEquippedItem(slot)
        -- PICKUP only auto-equips when the item's slot happened to be free, so
        -- a bag that merely landed in the inventory still has to be put on.
        if equipped ~= target and target:IsValid() and CanEquip(friend, target)
            and target.components.inventoryitem:GetGrandOwner() == friend then
            inventory:Equip(target)
            equipped = inventory:GetEquippedItem(slot)
        end
        local held = target:IsValid()
            and target.components.inventoryitem:GetGrandOwner() == friend
        if equipped == target or held then
            -- Carried but not worn still counts as ours: the companion has to
            -- recognise it after dying, which is the whole point of the mark.
            if pending_index ~= nil then friend._my_friend_backpack_index = pending_index end
            M.MarkOwned(friend, target)
        elseif target:IsValid() then
            DeferRecovery(friend, target)
            return
        end
        ClearAction(friend)
        friend._my_friend_backpack_retry = nil
    end)
    action:AddFailAction(function()
        if action._my_friend_cancelled and GetTime() < (friend._my_friend_backpack_deadline or 0) then
            friend._my_friend_backpack_action = nil
        else DeferRecovery(friend, target) end
    end)
    return action
end

function M.GetOwnedRecoveryAction(friend, target)
    if require("my_friend_carry_backpack").BlocksRecovery(friend) then return end
    -- A player request owns the backpack slot until it finishes. Overwriting
    -- its target from the death-drop recovery loop is what made "换个背包" and
    -- "捡个背包" look like they were ignored right after a revive.
    if friend._my_friend_backpack_commanded == true then return end
    if not M.IsOwned(target) or not IsAvailable(friend, target)
        or GetTime() < (friend._my_friend_backpack_recover_after or 0)
        or not Policy.InRange(friend, target)
        or not Safety.IsSafe(friend, target:GetPosition()) then return end
    local previous_target = friend._my_friend_backpack_target
    local previous_deadline = friend._my_friend_backpack_deadline
    friend._my_friend_backpack_target = target
    friend._my_friend_backpack_deadline = GetTime() + RECOVERY_TIMEOUT
    friend._my_friend_backpack_commanded = false
    local action = M.GetAction(friend)
    -- GetAction returns quietly while the companion is threatened, busy, or
    -- still inside an equip cooldown. Keeping the target across those ticks
    -- held CanAct() false, which blocked the skeleton, the hammer hunt and the
    -- chest search -- and the refreshed deadline meant Priority() never timed
    -- the target out either, so the block never lifted.
    if action == nil and friend._my_friend_backpack_target == target then
        friend._my_friend_backpack_target = previous_target
        friend._my_friend_backpack_deadline = previous_deadline
        friend._my_friend_backpack_switch_prepared = nil
    end
    return action
end

return M
