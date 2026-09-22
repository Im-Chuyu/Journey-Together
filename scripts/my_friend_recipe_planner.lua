local Cooking = require("cooking")
local Food = require("my_friend_food_ai")
local Storage = require("my_friend_food_storage")
local M = {}

-- The three prefab aliases used by vanilla cooking.GetIngredientValues.
local ALIASES = {cookedsmallmeat = "smallmeat_cooked",
    cookedmonstermeat = "monstermeat_cooked", cookedmeat = "meat_cooked"}
local RESERVES = {twigs = 20, cutgrass = 20, log = 20}

function M.Size(item)
    return item ~= nil and item:IsValid()
        and (item.components.stackable ~= nil and item.components.stackable:StackSize() or 1) or 0
end

function M.Available(inst, item)
    local inv = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    if inv == nil or inv.islockedinslot or Storage.IsReserved(inst, item)
        or item:HasAnyTag("spoiled", "irreplaceable") then return false end
    local owner = inv.owner
    local c = owner ~= nil and owner.components.container or nil
    return c == nil or not c.readonlycontainer and not c:IsRestricted(inst)
end

local function AcceptsType(types, foodtype)
    if types == nil then return true end
    for _, group in ipairs(types) do
        if type(group) == "table" then
            for _, value in ipairs(group.types) do if value == foodtype then return true end end
        elseif group == foodtype then return true end
    end
    return false
end

function M.RecipeValue(inst, recipe)
    if recipe == nil or recipe.name == "wetgoop" or recipe.name == "beefalofeed"
        or recipe.foodtype == nil then return end
    local h, f, s = recipe.health or 0, recipe.hunger or 0, recipe.sanity or 0
    if h < 0 or f < 0 or s < 0 or h + f + s <= 0 then return end
    local eater = inst.components.eater
    if eater == nil or not AcceptsType(eater.caneat, recipe.foodtype)
        or not AcceptsType(eater.preferseating, recipe.foodtype) then return end
    return h * 3 + f + s * 2
end

-- Evaluate every equally likely top-priority result, without consuming RNG.
-- A mix which can also produce harmful food is not a safe meal plan.
function M.Evaluate(inst, cooker, prefabs)
    local names, tags = {}, {}
    for _, prefab in ipairs(prefabs) do
        local name = ALIASES[prefab] or prefab
        names[name] = (names[name] or 0) + 1
        local data = Cooking.ingredients[name]
        if data == nil then return end
        for tag, value in pairs(data.tags) do tags[tag] = (tags[tag] or 0) + value end
    end
    local priority, value, valid, duration
    for _, recipe in pairs(Cooking.recipes[cooker] or {}) do
        local p = recipe.priority or 0
        if (priority == nil or p >= priority) and recipe.test(cooker, names, tags) then
            local score = M.RecipeValue(inst, recipe)
            if priority == nil or p > priority then
                priority, value, valid, duration = p, score, score ~= nil, recipe.cooktime or 1
            else
                valid = valid and score ~= nil
                if score ~= nil then value = math.min(value or score, score) end
                duration = math.max(duration, recipe.cooktime or 1)
            end
        end
    end
    if valid then return value, duration end
end

function M.EvaluateSpecific(inst, cooker, prefabs, wanted)
    local names, tags = {}, {}
    for _, prefab in ipairs(prefabs) do
        local name = ALIASES[prefab] or prefab
        names[name] = (names[name] or 0) + 1
        local data = Cooking.ingredients[name]
        if data == nil then return end
        for tag, value in pairs(data.tags) do tags[tag] = (tags[tag] or 0) + value end
    end
    local recipe = Cooking.recipes[cooker] ~= nil and Cooking.recipes[cooker][wanted] or nil
    if recipe == nil or not recipe.test(cooker, names, tags) then return end
    for name, other in pairs(Cooking.recipes[cooker]) do
        if name ~= wanted and (other.priority or 0) >= (recipe.priority or 0)
            and other.test(cooker, names, tags) then return end
    end
    local eater = inst.components.eater
    if eater == nil or not AcceptsType(eater.caneat, recipe.foodtype) then return end
    local health = recipe.health or 0
    local hunger = recipe.hunger or 0
    local sanity = recipe.sanity or 0
    return health * 3 + hunger + sanity * 2, recipe.cooktime or 1
end

function M.Pool(inst, fridges, grounds)
    local groups, owncounts, seen = {}, {}, {}
    local own = Storage.ReferenceItems(inst)
    for _, item in ipairs(own) do
        if M.Available(inst, item) then
            owncounts[item.prefab] = (owncounts[item.prefab] or 0) + M.Size(item)
        end
    end
    local function Add(item, external)
        if seen[item] or not M.Available(inst, item) or item:HasTag("preparedfood")
            or not Cooking.IsCookingIngredient(item.prefab) then return end
        seen[item] = true
        local count = M.Size(item)
        if RESERVES[item.prefab] ~= nil then
            if external then return end
            local remaining = math.max(0, (owncounts[item.prefab] or 0) - RESERVES[item.prefab])
            count = math.min(count, remaining)
            owncounts[item.prefab] = (owncounts[item.prefab] or 0) - count
        end
        if count == 0 then return end
        local group = groups[item.prefab]
        if group == nil then
            local value = 0
            if item.components.edible ~= nil and inst.components.eater:CanEat(item)
                and inst.components.eater:PrefersToEat(item) then
                local health, hunger, sanity = Food.GetFoodDeltas(inst, item)
                value = math.max(0, health * 3 + hunger + sanity * 2)
            end
            group = {prefab = item.prefab, count = 0, value = value, sources = {}}
            groups[item.prefab] = group
        end
        group.count = group.count + count
        group.sources[#group.sources + 1] = {item = item, count = count}
    end
    for _, item in ipairs(own) do Add(item, false) end
    for _, fridge in ipairs(fridges or {}) do
        for _, item in ipairs(fridge.components.container:GetAllItems()) do Add(item, true) end
    end
    for _, item in ipairs(grounds or {}) do Add(item, true) end
    local pool = {}
    for _, group in pairs(groups) do pool[#pool + 1] = group end
    table.sort(pool, function(a, b)
        return a.value == b.value and a.prefab < b.prefab or a.value < b.value
    end)
    return pool
end

local function FindAutomatic(inst, cooker, pool)
    local selected, used, best, bestgain = {}, {}, nil, 0
    local checked = 0
    local function Search(first, rawvalue)
        if checked >= 2048 then return end
        if #selected == 4 then
            checked = checked + 1
            local prefabs = {}
            for _, group in ipairs(selected) do prefabs[#prefabs + 1] = group.prefab end
            local value, duration = M.Evaluate(inst, cooker, prefabs)
            local gain = value ~= nil and value - rawvalue or 0
            if gain > bestgain + 1 then
                bestgain = gain
                best = {prefabs = prefabs, duration = duration, gain = gain}
            end
            return
        end
        for i = first, #pool do
            local group = pool[i]
            if (used[i] or 0) < group.count then
                selected[#selected + 1], used[i] = group, (used[i] or 0) + 1
                Search(i, rawvalue + group.value)
                selected[#selected], used[i] = nil, used[i] - 1
            end
            if checked >= 2048 then break end
        end
    end
    Search(1, 0)
    return best
end

-- Explicit orders search all combinations over successive planner ticks.
-- Keep the search independent of entity references, which can vanish on transfer.
local function SpecificSearch(inst, cooker, pool, wanted)
    local selected, used, checked = {}, {}, 0
    local counts = {}
    for _, group in ipairs(pool) do counts[group.prefab] = group.count end
    local function BatchValue(prefabs)
        local needs, portions, cost = {}, math.huge, 0
        for _, name in ipairs(prefabs) do needs[name] = (needs[name] or 0) + 1 end
        for name, count in pairs(needs) do
            portions = math.min(portions, math.floor(counts[name] / count))
            cost = cost + count / counts[name]
        end
        return portions, cost
    end
    local function Evaluate(prefabs)
        checked = checked + 1
        if checked % 2048 == 0 then coroutine.yield() end
        return M.EvaluateSpecific(inst, cooker, prefabs, wanted)
    end
    local function Conserve(prefabs)
        -- Improve fillers without hard-coding recipe requirements: prefer mixes
        -- that can be repeated more often, then lower use of scarce materials.
        local portions, cost = BatchValue(prefabs)
        local improved = true
        while improved do
            improved = false
            for slot = 1, 4 do
                local previous = prefabs[slot]
                for _, group in ipairs(pool) do
                    prefabs[slot] = group.prefab
                    local nextportions, nextcost = BatchValue(prefabs)
                    if (nextportions > portions or nextportions == portions and nextcost < cost - .000001)
                        and Evaluate(prefabs) ~= nil then
                        previous, portions, cost = group.prefab, nextportions, nextcost
                        improved = true
                    end
                end
                prefabs[slot] = previous
            end
        end
    end
    local function Search(first)
        if #selected == 4 then
            local value, duration = Evaluate(selected)
            if value ~= nil then
                local prefabs = {}
                for i, name in ipairs(selected) do prefabs[i] = name end
                Conserve(prefabs)
                return {prefabs = prefabs, duration = duration}
            end
            return
        end
        for i = first, #pool do
            local group = pool[i]
            if (used[i] or 0) < group.count then
                selected[#selected + 1], used[i] = group.prefab, (used[i] or 0) + 1
                local plan = Search(i)
                selected[#selected], used[i] = nil, used[i] - 1
                if plan ~= nil then return plan end
            end
        end
    end
    return Search(1)
end

function M.Find(inst, cooker, pool, wanted)
    if wanted == nil then return FindAutomatic(inst, cooker, pool) end
    if Cooking.GetRecipe(cooker, wanted) == nil then return end
    local ingredients = {}
    for _, group in ipairs(pool) do
        ingredients[#ingredients + 1] = {prefab = group.prefab, count = group.count}
    end
    -- Spend plentiful fillers first; retain scarce ingredients for later pots.
    table.sort(ingredients, function(a, b)
        return a.count == b.count and a.prefab < b.prefab or a.count > b.count
    end)
    local signature = {cooker, wanted}
    for _, group in ipairs(ingredients) do
        signature[#signature + 1] = group.prefab .. "=" .. group.count
    end
    signature = table.concat(signature, ":")
    local searches = inst._my_friend_recipe_search or {}
    inst._my_friend_recipe_search = searches
    local search = searches[signature]
    if search == nil then
        search = {thread = coroutine.create(function()
            return SpecificSearch(inst, cooker, ingredients, wanted)
        end)}
        searches[signature] = search
    end
    if coroutine.status(search.thread) ~= "dead" then
        local ok, plan = coroutine.resume(search.thread)
        if not ok then error(plan) end
        search.plan = plan
    end
    return search.plan, coroutine.status(search.thread) ~= "dead"
end

return M
