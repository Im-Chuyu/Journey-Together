local M = {}

local function PruneInvalidStorage(storage, seen)
    if storage == nil then return end
    seen = seen or {}
    if seen[storage] then return end
    seen[storage] = true
    local slots = storage.itemslots or storage.slots
    if slots ~= nil then
        for slot, item in pairs(slots) do
            if item == nil or not item:IsValid()
                or item.components == nil or item.components.inventoryitem == nil then
                slots[slot] = nil
            elseif item.components.container ~= nil then
                PruneInvalidStorage(item.components.container, seen)
            end
        end
    end
    if storage.activeitem ~= nil
        and (not storage.activeitem:IsValid() or storage.activeitem.components == nil
            or storage.activeitem.components.inventoryitem == nil) then
        storage.activeitem = nil
    end
end

function M.PruneInvalid(inst)
    local inventory = inst ~= nil and inst.components ~= nil and inst.components.inventory or nil
    if inventory == nil then return end
    local seen = {}
    PruneInvalidStorage(inventory, seen)
    PruneInvalidStorage(inventory:GetOverflowContainer(), seen)
    for slot, item in pairs(inventory.equipslots or {}) do
        if item == nil or not item:IsValid()
            or item.components == nil or item.components.inventoryitem == nil then
            inventory.equipslots[slot] = nil
        elseif item.components.container ~= nil then
            PruneInvalidStorage(item.components.container, seen)
        end
    end
end

local function IsCarriedBy(inst, item)
    return item ~= nil and item:IsValid() and item.components ~= nil
        and item.components.inventoryitem ~= nil
        and item.components.inventoryitem:GetGrandOwner() == inst
end

local function TryContainerGive(container, item, slot, position)
    if container == nil or item == nil or not item:IsValid()
        or item.components == nil or item.components.inventoryitem == nil then
        return false
    end
    return container:GiveItem(item, slot, position, false) == true
end

function M.StorageReady(inst, target)
    local retry = inst._my_friend_storage_retry
    return target ~= nil and target:IsValid()
        and (retry == nil or GetTime() >= (retry[target] or 0))
end

function M.StorageResult(inst, target, success)
    if target == nil then return end
    local retry = inst._my_friend_storage_retry
    if not success and retry == nil then
        retry = setmetatable({}, {__mode = "k"})
        inst._my_friend_storage_retry = retry
    end
    if retry ~= nil then retry[target] = not success and GetTime() + 10 or nil end
end

function M.CanStoreCount(inst, target, item, count)
    if not IsCarriedBy(inst, item) or item.components.inventoryitem.islockedinslot then return 0 end
    local c = target ~= nil and target:IsValid() and target.components.container or nil
    if c == nil or not c.canbeopened or c.readonlycontainer or c:IsRestricted(inst)
        or c:IsOpenedByOthers(inst) or not c:CanTakeItemInSlot(item) then return 0 end
    local size = item.components.stackable ~= nil and item.components.stackable:StackSize() or 1
    return math.max(0, math.min(size, count or size, c:CanAcceptCount(item, count or size)))
end

function M.StorePlan(inst, target, plan)
    local moved_any = false
    local keep = require("my_friend_equipment_reserves").GetKeep(inst)
    for _, entry in ipairs(plan) do
        local source = entry.item
        local count = M.CanStoreCount(inst, target, source, entry.count)
        if count > 0 and keep[source] ~= nil then
            local size = source.components.stackable ~= nil and source.components.stackable:StackSize() or 1
            count = math.min(count, math.max(0, size - keep[source]))
        end
        if count > 0 then
            local stack = source.components.stackable
            local moved
            if stack ~= nil and count < stack:StackSize() then
                moved = stack:Get(count)
            else
                moved = source.components.inventoryitem:RemoveFromOwner(true)
            end
            if moved ~= nil and moved:IsValid() and moved.components.inventoryitem ~= nil then
                moved.prevcontainer, moved.prevslot = nil, nil
                local accepted = target.components.container:GiveItem(moved, nil, target:GetPosition(), false)
                local remaining = moved:IsValid() and moved.components.inventoryitem ~= nil
                    and moved.components.inventoryitem.owner == nil
                if not moved:IsValid() or moved.components.inventoryitem ~= nil
                    and (moved.components.inventoryitem.owner == target
                        or accepted and moved.components.inventoryitem:GetGrandOwner() ~= inst) then
                    moved_any = true
                else
                    local left = moved.components.stackable ~= nil and moved.components.stackable:StackSize() or 1
                    moved_any = moved_any or left < count
                end
                if remaining then M.GiveCarried(inst, moved, inst:GetPosition()) end
            end
        end
    end
    return moved_any
end

function M.CanWithdrawFrom(inst, target)
    local c = target ~= nil and target:IsValid() and target.components.container or nil
    if c == nil or not M.StorageReady(inst, target) or not c.canbeopened
        or c.readonlycontainer or c:IsRestricted(inst) then return false end
    local leader = require("my_friend_policy").GetLeader(inst)
    return not c:IsOpenedByOthers(inst) or leader ~= nil and c:IsOpenedBy(leader)
end

function M.ContainerReach(inst, target)
    return math.max(2, inst:GetPhysicsRadius(0) + target:GetPhysicsRadius(0) + .6)
end

function M.CanReachContainer(inst, target)
    if inst == nil or not inst:IsValid() or target == nil or not target:IsValid() then return false end
    local a, b = inst:GetPosition(), target:GetPosition()
    return (a.x - b.x)^2 + (a.z - b.z)^2 <= (M.ContainerReach(inst, target) + .1)^2
end

function M.GiveCarried(inst, item, position)
    -- Container removal remembers its old slot. GiveItem otherwise silently
    -- returns the item to that still-open chest and reports success.
    if item == nil or not item:IsValid() or item.components == nil
        or item.components.inventoryitem == nil then return false end
    item.prevcontainer, item.prevslot = nil, nil
    M.PruneInvalid(inst)
    local accepted = inst.components.inventory:GiveItem(item, nil, position)
    -- GiveItem may merge the transferred stack and destroy the temporary
    -- entity. Treat that as success and never inspect its removed components.
    if not item:IsValid() then return true end
    if not accepted then return false end
    return not item:IsValid() or IsCarriedBy(inst, item)
end

function M.IsUsableTool(inst, item, action)
    if item == nil or not item:IsValid() then return false end
    local c = item.components
    return c.tool ~= nil and c.tool:GetEffectiveness(action) > 0
        and c.equippable ~= nil and not c.equippable:IsRestricted(inst)
        and c.inventoryitem ~= nil and not c.inventoryitem.islockedinslot
        and (c.finiteuses == nil or c.finiteuses:GetUses() > 0)
end

local function Available(item)
    return item ~= nil and item:IsValid() and item.components.stackable ~= nil
        and item.components.inventoryitem ~= nil
        and not item.components.inventoryitem.islockedinslot
end

function M.CanMerge(target, source)
    return target ~= source and Available(target) and Available(source)
        and not target.components.stackable:IsFull()
        and target.components.stackable:CanStackWith(source)
end

function M.AddSlots(slots, storage)
    local count = storage.maxslots or storage:GetNumSlots()
    for index = 1, count do
        local item = storage:GetItemInSlot(index)
        if item ~= nil then slots[#slots + 1] = { storage = storage, slot = index, item = item } end
    end
end

function M.FindPair(slots, excluded)
    for index = 1, #slots - 1 do
        local target = slots[index]
        if target.item ~= excluded then
            for other = index + 1, #slots do
                local source = slots[other]
                if source.item ~= excluded and M.CanMerge(target.item, source.item) then
                    return target, source
                end
            end
        end
    end
end

function M.Merge(slots, position, excluded)
    local target, source = M.FindPair(slots, excluded)
    if target == nil then return false end
    local stack = source.item.components.stackable
    local amount = math.min(stack:StackSize(), target.item.components.stackable:RoomLeft())
    -- Split just the available room, preserving ownership and the source slot.
    local moved
    if amount < stack:StackSize() then
        moved = stack:Get(amount)
    else
        moved = source.storage:RemoveItemBySlot(source.slot, true)
    end
    if moved == nil or not moved:IsValid() or moved.components == nil
        or moved.components.stackable == nil then return false end
    local remainder = target.item.components.stackable:Put(moved, position)
    if remainder ~= nil and remainder:IsValid() then
        TryContainerGive(source.storage, remainder, source.slot, position)
    end
    return true
end

function M.NeedsContainerMerge(container)
    local slots = {}
    M.AddSlots(slots, container)
    return M.FindPair(slots) ~= nil
end

function M.CompactContainer(container)
    local merged = false
    for _ = 1, container:GetNumSlots() do
        local slots = {}
        M.AddSlots(slots, container)
        if not M.Merge(slots, container.inst:GetPosition()) then break end
        merged = true
    end
    return merged
end

return M
