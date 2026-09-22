local Inventory = require("my_friend_inventory")
local Policy = require("my_friend_policy")
local M = {}
local RANGE = 20

local function Size(item)
    return item.components.stackable ~= nil and item.components.stackable:StackSize() or 1
end

local function Usable(item)
    return item ~= nil and item:IsValid() and item.components.inventoryitem ~= nil
        and not item.components.inventoryitem.islockedinslot and not item:HasTag("nocrafting")
end

local function Nearby(inst, source)
    if not source:IsValid() then return false end
    local x, y, z, range = Policy.SearchOrigin(inst, RANGE)
    local position = source:GetPosition()
    return not source:HasAnyTag("INLIMBO", "burnt", "fire")
        and (position.x - x)^2 + (position.z - z)^2 <= range^2
        and Policy.InRange(inst, source)
        and inst:GetCurrentPlatform() == source:GetCurrentPlatform()
end

local function IsStorage(source)
    return source:HasTag("chest") or source:HasTag("fridge")
        or source.prefab == "treasurechest" or source.prefab == "icebox"
        or source.prefab == "saltbox" or source.prefab == "dragonflychest"
end

-- Count carried and external materials once, then withdraw only the shortage.
-- Planning and execution use the same source rules, including leader-open chests.
function M.Plan(inst, recipe)
    local remaining = {}
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        remaining[ingredient.type] = (remaining[ingredient.type] or 0)
            + math.max(1, RoundBiasedUp(ingredient.amount * (inst.components.builder.ingredientmod or 1)))
    end
    local items = inst.components.inventory:ReferenceAllItems()
    local active = inst.components.inventory:GetActiveItem()
    if active ~= nil then items[#items + 1] = active end
    local seen = {}
    for _, item in ipairs(items) do
        if not seen[item] and Usable(item) and remaining[item.prefab] ~= nil then
            remaining[item.prefab] = math.max(0, remaining[item.prefab] - Size(item))
        end
        seen[item] = true
    end
    local x, y, z, range = Policy.SearchOrigin(inst, RANGE)
    local sources = TheSim:FindEntities(x, y, z, range, nil, {"INLIMBO", "burnt", "fire"})
    table.sort(sources, function(a, b) return inst:GetDistanceSqToInst(a) < inst:GetDistanceSqToInst(b) end)
    local plan = {}
    local function Add(item, source)
        if not seen[item] and Usable(item) and (remaining[item.prefab] or 0) > 0 then
            local count = math.min(remaining[item.prefab], Size(item))
            plan[#plan + 1] = {item = item, source = source, count = count}
            remaining[item.prefab] = remaining[item.prefab] - count
        end
        seen[item] = true
    end
    for _, source in ipairs(sources) do
        if Nearby(inst, source) then
            if IsStorage(source)
                and Inventory.CanWithdrawFrom(inst, source) then
                for _, item in ipairs(source.components.container:GetAllItems()) do Add(item, source) end
            elseif Usable(source) and source.components.inventoryitem.owner == nil
                and source.components.inventoryitem.canbepickedup then
                Add(source)
            end
        end
    end
    for _, count in pairs(remaining) do if count > 0 then return end end
    return plan
end

function M.GetAction(inst, plan)
    local entry = plan ~= nil and plan[1] or nil
    if entry == nil then return end
    local item, source = entry.item, entry.source
    local count = math.min(entry.count, inst.components.inventory:CanAcceptCount(item, entry.count))
    if count < 1 then return end
    local action = BufferedAction(inst, source or item,
        source ~= nil and ACTIONS.MY_FRIEND_WITHDRAW or ACTIONS.PICKUP,
        source ~= nil and item or nil)
    action._my_friend_withdraw_count = count
    action.validfn = function()
        return Usable(item) and Nearby(inst, source or item)
            and item.components.inventoryitem.owner == source
            and (source == nil or Inventory.CanWithdrawFrom(inst, source))
    end
    return Policy.GuardAction(inst, action)
end

return M
