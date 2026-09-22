local M = {}

local function IsOwnSack(inst, item)
    return item ~= nil and item:IsValid() and item.prefab == "beargerfur_sack"
        and item.components.container ~= nil and item.components.inventoryitem ~= nil
        and item.components.inventoryitem:GetGrandOwner() == inst
end

function M.ReferenceItems(inst)
    local inventory = inst.components.inventory
    local items = inventory ~= nil and inventory:ReferenceAllItems() or {}
    for index = #items, 1, -1 do
        if IsOwnSack(inst, items[index]) then
            for _, food in ipairs(items[index].components.container:GetAllItems()) do
                items[#items + 1] = food
            end
        end
    end
    return items
end

function M.IsReserved(inst, item, excluded)
    if item == excluded then return true end
    if require("my_friend_pets").IsIngredient(inst, item) then return true end
    for _, record in ipairs(inst._my_friend_food_returns or {}) do
        if record.item == item and record.count > 0 then return true end
    end
    return false
end

-- Inventory maintenance, like merging stacks: move only one stack per tick.
function M.StoreOnePrepared(inst, excluded)
    if inst._my_friend_under_threat or inst._my_friend_container_action
        or inst._my_friend_storage_action or inst._my_friend_chest_transfer
        or inst._my_friend_backpack_action or inst._my_friend_backpack_target ~= nil
        or inst:HasTag("playerghost") or inst.components.health:IsDead()
        or require("my_friend_policy").IsBusy(inst) then return false end
    local inventory = inst.components.inventory
    if inventory == nil then return false end
    local items = inventory:ReferenceAllItems()
    for _, sack in ipairs(items) do
        if IsOwnSack(inst, sack) then
            local container = sack.components.container
            if not container.readonlycontainer and not container:IsRestricted(inst) then
                for _, item in ipairs(items) do
                    local invitem = item.components.inventoryitem
                    if item:HasTag("preparedfood") and invitem ~= nil
                        and not invitem.islockedinslot and invitem:GetGrandOwner() == inst
                        and invitem.owner ~= sack and not M.IsReserved(inst, item, excluded) then
                        local stack = item.components.stackable
                        local size = stack ~= nil and stack:StackSize() or 1
                        local count = container:CanAcceptCount(item, size)
                        if count > 0 then
                            local moved = count < size and stack:Get(count)
                                or invitem:RemoveFromOwner(true)
                            if moved ~= nil then
                                moved.prevcontainer, moved.prevslot = nil, nil
                                if container:GiveItem(moved, nil, inst:GetPosition(), false) then
                                    return true
                                elseif moved:IsValid() then
                                    require("my_friend_inventory").GiveCarried(inst, moved, inst:GetPosition())
                                end
                            end
                            return false
                        end
                    end
                end
            end
        end
    end
    return false
end

return M
