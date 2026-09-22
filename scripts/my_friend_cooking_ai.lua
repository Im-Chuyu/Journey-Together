local FoodAI = require("my_friend_food_ai")
local SurvivalAI = require("my_friend_survival_ai")
local Policy = require("my_friend_policy")
local M = {}

function M.GetCampfireAction(inst)
    if Policy.IsBusy(inst) or GetTime() < (inst._my_friend_campfire_after or 0) then return end
    local recipe = GetValidRecipe("campfire")
    local builder = inst.components.builder
    if recipe == nil or builder == nil or not builder:KnowsRecipe(recipe)
        or not builder:HasIngredients(recipe) then return end
    local point = SurvivalAI.FindSafeFirePoint(inst, recipe)
    if point == nil then return end
    local action = BufferedAction(inst, nil, ACTIONS.MY_FRIEND_BUILD or ACTIONS.BUILD,
        nil, point, recipe.name, recipe.build_distance)
    -- BUILD also makes portable items, so its general mount permission cannot
    -- decide whether this outdoor cooking setup needs the rider on foot.
    action._my_friend_requires_dismount = true
    action.validfn = function()
        return (inst.components.rider == nil or not inst.components.rider:IsRiding())
            and SurvivalAI.IsFireSafePoint(inst, point, recipe)
            and builder:HasIngredients(recipe)
    end
    action:AddSuccessAction(function()
        inst._my_friend_cook_until = GetTime() + 45
        inst._my_friend_campfire_after = GetTime() + 60
    end)
    return Policy.GuardAction(inst, action)
end

local function NeedsCooking(inst, item)
    if item.components.cookable == nil then return false end
    local health, _, sanity = FoodAI.GetFoodDeltas(inst, item)
    local perish = item.components.perishable
    return health < 0 or sanity < 0
        or perish ~= nil and perish:GetPercent() < .5
end

function M.Remember(inst, source)
    if source.prefab ~= "firepit" then return end
    local point = source:GetPosition()
    local memory = inst._my_friend_fire_memory or {}
    inst._my_friend_fire_memory = memory
    for _, old in ipairs(memory) do
        if (old.x - point.x)^2 + (old.z - point.z)^2 < 1 then return end
    end
    memory[#memory + 1] = { x = point.x, z = point.z }
    if #memory > 32 then table.remove(memory, 1) end
end

function M.GetAction(inst)
    if Policy.IsBusy(inst) or inst._my_friend_container_action
        or inst._my_friend_storage_action then return end
    local inventory = inst.components.inventory
    local food = inventory:FindItem(function(item)
        return item.components.edible ~= nil and inst.components.eater:CanEat(item)
            and not require("my_friend_pets").IsIngredient(inst, item)
            and NeedsCooking(inst, item)
    end)
    local x, y, z, range = Policy.SearchOrigin(inst, 30)
    local best, bestscore
    for _, source in ipairs(TheSim:FindEntities(x, y, z, range, nil,
        {"INLIMBO", "burnt"})) do
        if source.prefab == "firepit" then M.Remember(inst, source) end
        if (source.prefab == "firepit" or source.prefab == "campfire")
            and source.components.cooker ~= nil
            and GetTime() >= ((inst._my_friend_cooking_blocked or {})[source.GUID] or 0) then
            local score = Policy.DistanceSq(inst, source)
            if bestscore == nil or score < bestscore then best, bestscore = source, score end
        end
    end
    if food == nil then
        inst._my_friend_cook_until = nil
        return
    end
    if best ~= nil then
        if best.components.cooker:CanCook(food, inst) then
            local action = BufferedAction(inst, best, ACTIONS.COOK, food)
            action:AddSuccessAction(function()
                inst._my_friend_food_supply_cache = nil
                inst._my_friend_cook_until = GetTime() + 15
            end)
            action:AddFailAction(function()
                if not action._my_friend_cancelled then
                    inst._my_friend_cook_until = nil
                    inst._my_friend_cooking_blocked = inst._my_friend_cooking_blocked or {}
                    inst._my_friend_cooking_blocked[best.GUID] = GetTime() + 20
                end
            end)
            return Policy.GuardAction(inst, action)
        end
        local fueled = best.components.fueled
        if fueled ~= nil and fueled:IsEmpty() then
            local fuel = inventory:FindItem(function(item)
                return (item.prefab == "log" or item.prefab == "cutgrass" or item.prefab == "twigs")
                    and fueled:CanAcceptFuelItem(item)
            end)
            if fuel ~= nil then
                local action = BufferedAction(inst, best, ACTIONS.ADDFUEL, fuel)
                action:AddSuccessAction(function()
                    inst._my_friend_cook_until = GetTime() + 30
                end)
                action:AddFailAction(function()
                    if not action._my_friend_cancelled then
                        inst._my_friend_cooking_blocked = {[best.GUID] = GetTime() + 20}
                    end
                end)
                return Policy.GuardAction(inst, action)
            end
        end
        return
    end
    if Policy.GetLeader(inst) == nil then
        local nearest, distance
        for _, point in ipairs(inst._my_friend_fire_memory or {}) do
            local d = (point.x - x)^2 + (point.z - z)^2
            if distance == nil or d < distance then nearest, distance = point, d end
        end
        if nearest ~= nil then
            -- Revalidate memories in sight so removed fire pits do not trap the planner.
            if distance <= range^2 then
                for index, point in ipairs(inst._my_friend_fire_memory) do
                    if point == nearest then table.remove(inst._my_friend_fire_memory, index) break end
                end
            else
                return BufferedAction(inst, nil, ACTIONS.WALKTO, nil,
                    Vector3(nearest.x, 0, nearest.z))
            end
        end
    end
    return M.GetCampfireAction(inst)
end

function M.OnSave(inst, data)
    data.my_friend_fire_memory = inst._my_friend_fire_memory
end

function M.OnLoad(inst, data)
    inst._my_friend_fire_memory = {}
    for _, point in ipairs(data ~= nil and data.my_friend_fire_memory or {}) do
        if type(point.x) == "number" and type(point.z) == "number"
            and point.x == point.x and point.z == point.z
            and #inst._my_friend_fire_memory < 32 then
            table.insert(inst._my_friend_fire_memory, { x = point.x, z = point.z })
        end
    end
end

return M
