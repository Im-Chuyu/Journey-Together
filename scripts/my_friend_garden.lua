local M = {}

function M.IsFertilizer(item)
    return item ~= nil and item:IsValid() and item.components.fertilizer ~= nil
        and item.components.inventoryitem ~= nil
        and not item.components.inventoryitem.islockedinslot
        and (item.components.finiteuses == nil or item.components.finiteuses:GetUses() > 0)
end

function M.Uses(item)
    if not M.IsFertilizer(item) then return 0 end
    local uses = item.components.finiteuses
    local stack = item.components.stackable
    return uses ~= nil and uses:GetUses() or stack ~= nil and stack:StackSize() or 1
end

function M.Plants(inst, base, range, in_garden)
    local result, barren = {}, 0
    for _, plant in ipairs(TheSim:FindEntities(base.x, 0, base.z, range, nil,
        {"INLIMBO", "burnt"})) do
        local pickable = plant.components.pickable
        if (plant.prefab == "grass" or plant.prefab == "sapling")
            and pickable ~= nil and pickable.transplanted
            and in_garden(base, plant:GetPosition()) then
            result[#result + 1] = plant
            if plant.prefab == "grass" and pickable:CanBeFertilized() then barren = barren + 1 end
        end
    end
    table.sort(result, function(a, b) return inst:GetDistanceSqToInst(a) < inst:GetDistanceSqToInst(b) end)
    return result, barren
end

function M.Supply(inst, chests)
    local amount = 0
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do amount = amount + M.Uses(item) end
    for _, chest in ipairs(chests or {}) do
        for _, item in pairs(chest.components.container.slots) do amount = amount + M.Uses(item) end
    end
    return amount
end

function M.Carried(inst)
    local best, score
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if M.IsFertilizer(item) then
            local priority = item.prefab == "spoiled_food" and 0
                or item.prefab == "poop" and 1 or item.prefab == "guano" and 2 or 3
            if score == nil or priority < score then best, score = item, priority end
        end
    end
    return best
end

function M.ProtectFertilizer(inst, reserves, wanted)
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if wanted <= 0 then break end
        if M.IsFertilizer(item) then
            local amount = item.components.finiteuses ~= nil and 1
                or math.min(wanted, M.Uses(item))
            reserves[item.prefab] = (reserves[item.prefab] or 0) + amount
            wanted = wanted - M.Uses(item)
        end
    end
end

function M.FindLoose(inst, radius, allowed)
    local position = inst:GetPosition()
    local entities = radius ~= nil
        and TheSim:FindEntities(position.x, 0, position.z, radius, {"fertilizer"}, {"INLIMBO", "fire"})
        or Ents
    local best, distance
    -- Only real dropped fertilizer is a destination. Savanna turf without
    -- cattle or manure never creates an imaginary fertilizer resource.
    for _, item in pairs(entities or {}) do
        if M.IsFertilizer(item) and item.components.inventoryitem.owner == nil
            and item.components.inventoryitem.canbepickedup and not item:IsInLimbo()
            and inst.components.inventory:CanAcceptCount(item, 1) > 0
            and allowed(item) then
            local d = inst:GetDistanceSqToInst(item)
            if distance == nil or d < distance then best, distance = item, d end
        end
    end
    return best
end

return M
