local Inventory = require("my_friend_inventory")
local Navigation = require("my_friend_navigation")
local Policy = require("my_friend_policy")
local M = {}

function M.Cancel(inst, action)
    action = action or inst._my_friend_storage_action
    local job = inst._my_friend_chest_transfer
    local containers = {}
    if action ~= nil and action.target ~= nil then containers[action.target] = true end
    if job ~= nil then
        if job.source ~= nil then containers[job.source] = true end
        if job.destination ~= nil then containers[job.destination] = true end
    end
    for target in pairs(containers) do
        local container = target:IsValid() and target.components.container or nil
        if container ~= nil and container:IsOpenedBy(inst) then
            container:Close(inst)
            inst:PushEvent("closecontainer", {container = target})
        end
    end
    -- Withdrawn cargo remains in inventory and returns to normal reservation
    -- and tidying rules once its abandoned transfer is released.
    inst._my_friend_storage_action, inst._my_friend_chest_transfer = nil, nil
    inst._my_friend_next_chest_transfer = GetTime() + 10
end

local function Available(inst, chest)
    if chest == nil or not Inventory.StorageReady(inst, chest) or chest:IsInLimbo() then return false end
    local c = chest.components.container
    return c ~= nil and not c.readonlycontainer and not c:IsRestricted(inst)
        and not c:IsOpenedByOthers(inst) and not chest:HasTag("burnt")
        and not Navigation.IsBlocked(inst, chest:GetPosition())
        and GetTime() >= ((inst._my_friend_base_blocked or {})[chest.GUID] or 0)
end

local function Sorted(chests)
    local result = {}
    for _, chest in ipairs(chests) do result[#result + 1] = chest end
    table.sort(result, function(a, b)
        local ap, bp = a:GetPosition(), b:GetPosition()
        if ap.x ~= bp.x then return ap.x < bp.x end
        if ap.z ~= bp.z then return ap.z < bp.z end
        return a.GUID < b.GUID
    end)
    return result
end

local function MergeRoom(container, item)
    local room = 0
    for _, stored in pairs(container.slots) do
        if Inventory.CanMerge(stored, item) then
            room = room + stored.components.stackable:RoomLeft()
        end
    end
    return room
end

function M.PreferredChest(inst, chests, item)
    local best, bestscore
    for _, chest in ipairs(Sorted(chests)) do
        if Available(inst, chest) then
            local c = chest.components.container
            if c:CanAcceptCount(item, 1) > 0 then
                local same = false
                for _, stored in pairs(c.slots) do
                    if stored.prefab == item.prefab then same = true break end
                end
                local score = MergeRoom(c, item) > 0 and 2 or same and 1 or 0
                if bestscore == nil or score > bestscore then best, bestscore = chest, score end
            end
        end
    end
    return best
end

function M.IsCargo(inst, item)
    local transfer = inst._my_friend_chest_transfer
    return transfer ~= nil and transfer.stage == "deliver" and transfer.item == item
end

local function EmptySlot(inst, item)
    local inventory = inst.components.inventory
    for slot = 1, inventory.maxslots do
        if inventory:GetItemInSlot(slot) == nil and inventory:CanTakeItemInSlot(item, slot) then
            return inventory, slot
        end
    end
    local overflow = inventory:GetOverflowContainer()
    if overflow ~= nil then
        for slot = 1, overflow:GetNumSlots() do
            if overflow:GetItemInSlot(slot) == nil and overflow:CanTakeItemInSlot(item, slot) then
                return overflow, slot
            end
        end
    end
end

local function IsCarried(inst, item)
    return item ~= nil and item:IsValid() and item.components.inventoryitem ~= nil
        and item.components.inventoryitem:GetGrandOwner() == inst
end

local function FindTransfer(inst, chests)
    local ordered = Sorted(chests)
    -- Always consolidate towards an earlier chest, preventing transfer loops.
    for index, destination in ipairs(ordered) do
        if Available(inst, destination) then
            for other = index + 1, #ordered do
                local source = ordered[other]
                if Available(inst, source) then
                    for slot = 1, source.components.container:GetNumSlots() do
                        local item = source.components.container:GetItemInSlot(slot)
                        if item ~= nil and item.components.stackable ~= nil
                            and not item.components.inventoryitem.islockedinslot then
                            local room = MergeRoom(destination.components.container, item)
                            if room > 0 and EmptySlot(inst, item) ~= nil
                                and destination.components.container:CanAcceptCount(item, 1) > 0 then
                                return {source = source, destination = destination, item = item,
                                    count = math.min(room, item.components.stackable:StackSize()),
                                    stage = "withdraw"}
                            end
                        end
                    end
                end
            end
        end
    end
end

function M.Withdraw(inst, action)
    local job = action._my_friend_transfer
    if job ~= inst._my_friend_chest_transfer or job.stage ~= "withdraw"
        or action.target ~= job.source or not Available(inst, job.destination) then return false end
    local item = job.item
    if not item:IsValid() or item.components.inventoryitem.owner ~= job.source then return false end
    local storage, slot = EmptySlot(inst, item)
    if storage == nil then return false end
    local count = math.min(job.count, item.components.stackable:StackSize(),
        MergeRoom(job.destination.components.container, item),
        job.destination.components.container:CanAcceptCount(item, job.count))
    if count <= 0 then return false end
    local moved = count < item.components.stackable:StackSize()
        and item.components.stackable:Get(count) or job.source.components.container:RemoveItem(item, true)
    if moved == nil then return false end
    moved.prevcontainer, moved.prevslot = nil, nil
    storage:GiveItem(moved, slot, job.source:GetPosition())
    if IsCarried(inst, moved) then
        job.item, job.count, job.stage = moved, count, "deliver"
        return true
    end
    if moved:IsValid() then job.source.components.container:GiveItem(moved, nil, job.source:GetPosition()) end
    return false
end

function M.Deposit(inst, action)
    local job = action._my_friend_transfer
    if job ~= inst._my_friend_chest_transfer or job.stage ~= "deliver"
        or not IsCarried(inst, job.item) then return false end
    local item, c = job.item, action.target.components.container
    local count = math.min(job.count, item.components.stackable:StackSize(), c:CanAcceptCount(item, job.count))
    if count <= 0 then return false end
    local moved = count < item.components.stackable:StackSize()
        and item.components.stackable:Get(count) or item.components.inventoryitem:RemoveFromOwner(true)
    if moved == nil then return false end
    local accepted = c:GiveItem(moved, nil, action.target:GetPosition(), false)
    local returned = not accepted and moved:IsValid()
        and moved.components.stackable:StackSize() or 0
    if not accepted and moved:IsValid() then
        Inventory.GiveCarried(inst, moved, inst:GetPosition())
    end
    job.count = math.max(0, job.count - (count - returned))
    if not IsCarried(inst, item) and IsCarried(inst, moved) then job.item = moved end
    if job.count == 0 or not IsCarried(inst, job.item) then
        inst._my_friend_chest_transfer = nil
    end
    return accepted == true
end

function M.GetAction(inst, chests, makeaction)
    if Policy.GetLeader(inst) ~= nil or inst._my_friend_storage_action then return end
    local job = inst._my_friend_chest_transfer
    if job ~= nil and (job.item == nil or not job.item:IsValid()
        or job.stage == "deliver" and not IsCarried(inst, job.item)) then
        inst._my_friend_chest_transfer = nil
        job = nil
    end
    if job == nil then
        if GetTime() < (inst._my_friend_next_chest_transfer or 0) then return end
        inst._my_friend_next_chest_transfer = GetTime() + 3
        job = FindTransfer(inst, chests)
        inst._my_friend_chest_transfer = job
    end
    if job == nil then return end
    local target = job.stage == "withdraw" and job.source or job.destination
    if job.stage == "deliver" and (not Available(inst, target)
        or target.components.container:CanAcceptCount(job.item, 1) <= 0) then
        target = M.PreferredChest(inst, chests, job.item)
        job.destination = target
    end
    if not Available(inst, target) then
        if job.stage == "withdraw" then inst._my_friend_chest_transfer = nil end
        return
    end
    local action = makeaction(inst, target,
        job.stage == "withdraw" and ACTIONS.MY_FRIEND_WITHDRAW or ACTIONS.MY_FRIEND_STORE,
        job.stage == "deliver" and job.item or nil)
    action._my_friend_transfer = job
    action._my_friend_withdraw_plan = {{item = job.item, count = job.count}}
    inst._my_friend_storage_action = action
    local previous = action.validfn
    action.validfn = function(act)
        return inst._my_friend_chest_transfer == job and Available(inst, target)
            and job.item:IsValid() and (previous == nil or previous(act))
    end
    action:AddFailAction(function()
        if inst._my_friend_storage_action == action then inst._my_friend_storage_action = nil end
        if job.stage == "withdraw" and inst._my_friend_chest_transfer == job then
            inst._my_friend_chest_transfer = nil
        end
        inst._my_friend_next_chest_transfer = GetTime() + 10
    end)
    return action
end

return M
