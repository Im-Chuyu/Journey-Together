local M = {}

local PROTECTED = {glommerfuel = true, mandrake = true,
    royaljelly = true, royal_jelly = true}
local BIG_MEAT = {meat = true, cookedmeat = true, meat_cooked = true}

function M.IsProtected(food)
    local name = type(food) == "string" and food or food ~= nil and food.prefab or nil
    return PROTECTED[name] == true
end

function M.CanCook(inst)
    local health = inst ~= nil and inst.components ~= nil and inst.components.health or nil
    return health ~= nil and not health:IsDead() and not inst:HasTag("playerghost")
end

-- Roasting and crock-pot recipe selection have different purposes. Do not
-- apply roasting's health/freshness filter to an entire pot or to base mode.
function M.NeedsRoasting(inst, item, health)
    if item == nil or item.components == nil or item.components.cookable == nil
        or item.components.edible == nil or M.IsProtected(item) then return false end
    if health == nil then health = require("my_friend_food_ai").GetFoodDeltas(inst, item) end
    local perish = item.components.perishable
    return health < 0 or perish ~= nil and perish:GetPercent() < (TUNING.PERISH_STALE or .2)
end

function M.IsStale(item)
    local perish = item ~= nil and item.components ~= nil and item.components.perishable or nil
    return perish ~= nil and perish:GetPercent() < .5
end

function M.IsBigMeat(name) return BIG_MEAT[name] == true end

function M.CanUseIngredient(item)
    return item ~= nil and not M.IsProtected(item)
        and (item.prefab ~= "meat_dried" or M.IsStale(item))
end

function M.AllowsMix(prefabs, stale_meat)
    local count = 0
    for _, name in ipairs(prefabs) do
        if M.IsProtected(name) then return false end
        if BIG_MEAT[name] then count = count + 1 end
    end
    return count - (stale_meat or 0) < 3
end

function M.CountStaleMeat(items)
    local count = 0
    for _, item in pairs(items or {}) do
        if BIG_MEAT[item.prefab] and M.IsStale(item) then
            local stack = item.components.stackable
            count = count + (stack ~= nil and stack:StackSize() or 1)
        end
    end
    return count
end

function M.CookAction(act, original)
    local inst = act.doer
    if inst ~= nil and inst:HasTag("my_friend") then
        if not M.CanCook(inst) then return false end
        if act.invobject ~= nil and M.IsProtected(act.invobject) then return false end
        if act.invobject ~= nil and not M.NeedsRoasting(inst, act.invobject) then return false end
        local target = act.target
        local c = target ~= nil and target.components ~= nil and target.components.container or nil
        if c ~= nil and target.components.stewer ~= nil then
            local items, prefabs = c:GetAllItems(), {}
            for _, item in pairs(items) do
                if not M.CanUseIngredient(item) then return false end
                local stack = item.components.stackable
                for _ = 1, stack ~= nil and stack:StackSize() or 1 do
                    prefabs[#prefabs + 1] = item.prefab
                end
            end
            if not M.AllowsMix(prefabs, M.CountStaleMeat(items)) then return false end
        end
    end
    return original(act)
end

return M
