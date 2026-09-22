local Inventory = require("my_friend_inventory")
local Policy = require("my_friend_policy")

local M = {}

M.ITEM_TO_STRUCTURE = {
    portablecookpot_item = "portablecookpot",
    portableblender_item = "portableblender",
    portablespicer_item = "portablespicer",
}

local function CarriedItems(inst)
    local items = inst.components.inventory:ReferenceAllItems()
    local active = inst.components.inventory:GetActiveItem()
    if active ~= nil then items[#items + 1] = active end
    return items
end

function M.IsRecipe(recipe_name)
    return recipe_name ~= nil and recipe_name:sub(-5) == "_item"
        and M.ITEM_TO_STRUCTURE[recipe_name] ~= nil
end

function M.FindItem(inst, recipe_name)
    for _, item in ipairs(CarriedItems(inst)) do
        if item:IsValid() and item.prefab == recipe_name
            and item.components.deployable ~= nil
            and item.components.inventoryitem:GetGrandOwner() == inst then
            return item
        end
    end
end

local function DistanceSq(point, anchor)
    return (point.x - anchor.x)^2 + (point.z - anchor.z)^2
end

local function FindAnchor(inst, structure)
    local x, y, z, range = Policy.SearchOrigin(inst, 24)
    local best, bestdistance
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, range, nil, {"INLIMBO", "burnt", "fire"})) do
        if M.ITEM_TO_STRUCTURE[entity.prefab] == nil
            and (entity.prefab == structure or entity.prefab == "portablecookpot"
                or entity.prefab == "portableblender" or entity.prefab == "portablespicer") then
            local distance = inst:GetDistanceSqToInst(entity)
            if bestdistance == nil or distance < bestdistance then
                best, bestdistance = entity, distance
            end
        end
    end
    return best ~= nil and best:GetPosition() or Vector3(x, 0, z)
end

local function FindPoint(inst, item)
    local structure = M.ITEM_TO_STRUCTURE[item.prefab]
    local anchor = FindAnchor(inst, structure)
    local candidates = {}
    for radius = 1.8, 8, 1.4 do
        for index = 0, 15 do
            local angle = index * PI2 / 16
            candidates[#candidates + 1] = Vector3(
                anchor.x + math.cos(angle) * radius, 0,
                anchor.z + math.sin(angle) * radius)
        end
    end
    table.sort(candidates, function(a, b)
        local ad = DistanceSq(a, anchor)
        local bd = DistanceSq(b, anchor)
        return ad == bd and DistanceSq(a, inst:GetPosition()) < DistanceSq(b, inst:GetPosition()) or ad < bd
    end)
    local deployable = item.components.deployable
    for _, point in ipairs(candidates) do
        if deployable:CanDeploy(point, nil, inst, 0) then return point end
    end
end

function M.GetDeployAction(inst, item)
    if item == nil or not item:IsValid() or not M.IsRecipe(item.prefab)
        or item.components.inventoryitem:GetGrandOwner() ~= inst then return end
    local point = FindPoint(inst, item)
    if point == nil then return end
    local action = BufferedAction(inst, nil, ACTIONS.DEPLOY, item, point)
    action.arrivedist = ACTIONS.DEPLOY.arrivedist or 1.1
    action.validfn = function()
        return item:IsValid() and item.components.inventoryitem:GetGrandOwner() == inst
            and item.components.deployable:CanDeploy(point, nil, inst, action.rotation or 0)
    end
    action:AddSuccessAction(function()
        local command = inst._my_friend_command
        if command ~= nil and command.special == "build"
            and command.recipe == item.prefab then
            require("my_friend_commands").Clear(inst)
        end
    end)
    return Policy.GuardAction(inst, action)
end

return M
