local Cooking = require("cooking")
local Food = require("my_friend_food_ai")
local Storage = require("my_friend_food_storage")
local Rules = require("my_friend_food_rules")
local M = {}

-- The three prefab aliases used by vanilla cooking.GetIngredientValues.
local ALIASES = {cookedsmallmeat = "smallmeat_cooked",
    cookedmonstermeat = "monstermeat_cooked", cookedmeat = "meat_cooked"}
local RESERVES = {twigs = 20, cutgrass = 20, log = 20}
local MONSTER_MEAT = {monstermeat = true, monstermeat_cooked = true, monstermeat_dried = true}

local function IsMonsterMeat(prefab)
    return MONSTER_MEAT[ALIASES[prefab] or prefab] == true
end

local function MeatballsPreference(prefabs)
    local monster, othermeat = false, 0
    for _, prefab in ipairs(prefabs) do
        local ingredient = Cooking.ingredients[ALIASES[prefab] or prefab]
        if IsMonsterMeat(prefab) then
            monster = true
        elseif ingredient ~= nil and (ingredient.tags.meat or 0) > 0 then
            othermeat = othermeat + 1
        end
    end
    return (monster and 350 or 0) - 100 * othermeat
end

function M.Size(item)
    return item ~= nil and item:IsValid()
        and (item.components.stackable ~= nil and item.components.stackable:StackSize() or 1) or 0
end

function M.Available(inst, item, explicit)
    local inv = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    if inv == nil or inv.islockedinslot or Storage.IsReserved(inst, item)
        or not Rules.CanUseIngredient(item, explicit)
        or inst.prefab ~= "warly" and (item.prefab == "lightninggoathorn" or item.prefab == "boneshard")
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

function M.RecipeValue(inst, recipe, stats, health_deficit)
    if recipe == nil or recipe.name == "wetgoop" or recipe.name == "beefalofeed"
        or recipe.foodtype == nil then return end
    local h, f, s = recipe.health or 0, recipe.hunger or 0, recipe.sanity or 0
    if h < 0 or f < 0 or s < 0 or h + f + s <= 0 then return end
    if not Food.CanHealWithFood(inst) then h = 0 end
    local eater = inst.components.eater
    if eater == nil or not AcceptsType(eater.caneat, recipe.foodtype)
        or not AcceptsType(eater.preferseating, recipe.foodtype) then return end
    local healing = 0
    if health_deficit ~= nil then
        local memory = inst.components.foodmemory
        local multiplier = memory ~= nil and memory:GetFoodMultiplier(recipe.name) or 1
        healing = math.min(health_deficit, h * (eater.healthabsorption or 1) * multiplier)
    end
    return M.NutritionValue(inst, h, f, s, stats), healing
end

-- Score nutrition and ingredient cost against the same current deficits.
function M.NutritionValue(inst, health, hunger, sanity, stats, explicit)
    stats = stats or (Food.GetStats ~= nil and Food.GetStats(inst) or nil)
    local hw, fw, sw = 3, 1, 2
    if stats ~= nil then
        local needs_health = not explicit and Food.GetMealHealthDeficit(inst, stats) ~= nil
        local lowhealth = stats.healthpercent < .35
        if needs_health then
            hw, fw, sw = 12, 3, 3
        elseif lowhealth then
            hw, fw, sw = 12, 6, 3
        elseif stats.sanitypercent < .60 then
            hw, fw, sw = 2, 3, 12
        elseif stats.hungerpercent < .65 then
            hw, fw, sw = 3, 10, 3
        else
            -- With all three stats healthy, stock the most useful calories.
            hw, fw, sw = 1, 8, 2
        end
        local deficit_mode = needs_health or lowhealth or stats.hungerpercent < .65 or stats.sanitypercent < .60
        if deficit_mode then
            health = math.min(math.max(0, health or 0), math.max(0, stats.healthmax - stats.health))
            hunger = math.min(math.max(0, hunger or 0), math.max(0, stats.hungermax - stats.hunger))
            sanity = math.min(math.max(0, sanity or 0), math.max(0, stats.sanitymax - stats.sanity))
        end
    end
    local value = (health or 0) * hw + (hunger or 0) * fw + (sanity or 0) * sw
    return value > 0 and value or nil
end

-- Evaluate every equally likely top-priority result, without consuming RNG.
-- A mix which can also produce harmful food is not a safe meal plan.
function M.Evaluate(inst, cooker, prefabs, stale_meat, stats, health_deficit)
    if not Rules.AllowsMix(prefabs, stale_meat) then return end
    local names, tags = {}, {}
    for _, prefab in ipairs(prefabs) do
        local name = ALIASES[prefab] or prefab
        names[name] = (names[name] or 0) + 1
        local data = Cooking.ingredients[name]
        if data == nil then return end
        for tag, value in pairs(data.tags) do tags[tag] = (tags[tag] or 0) + value end
    end
    local priority, value, valid, duration, product, healing
    for _, recipe in pairs(Cooking.recipes[cooker] or {}) do
        local p = recipe.priority or 0
        if (priority == nil or p >= priority) and recipe.test(cooker, names, tags) then
            local score, recovery = M.RecipeValue(inst, recipe, stats, health_deficit)
            if priority == nil or p > priority then
                priority, value, valid, duration = p, score, score ~= nil, recipe.cooktime or 1
                product, healing = recipe.name, recovery
            else
                product = nil
                valid = valid and score ~= nil
                if score ~= nil then value = math.min(value or score, score) end
                if recovery ~= nil then healing = math.min(healing or recovery, recovery) end
                duration = math.max(duration, recipe.cooktime or 1)
            end
        end
    end
    if valid then return value, duration, product, healing end
end

function M.EvaluateSpecific(inst, cooker, prefabs, wanted, stale_meat)
    if not Rules.AllowsMix(prefabs, stale_meat) then return end
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
    if not Food.CanHealWithFood(inst) then health = 0 end
    local hunger = recipe.hunger or 0
    local sanity = recipe.sanity or 0
    local value = M.NutritionValue(inst, health, hunger, sanity, nil, true)
    return value, recipe.cooktime or 1
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
            or not Rules.CanUseIngredient(item)
            or not Cooking.IsCookingIngredient(item.prefab) then return end
        seen[item] = true
        local count = M.Size(item)
        if RESERVES[item.prefab] ~= nil then
            if external then return end
            local reserves = require("my_friend_resource_reserves")
            local keep = reserves.IsLateWorld() and (reserves.MinimumKeep()[item.prefab] or 0)
                or RESERVES[item.prefab]
            local remaining = math.max(0, (owncounts[item.prefab] or 0) - keep)
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
                value = M.NutritionValue(inst, health, hunger, sanity) or 0
            end
            group = {prefab = item.prefab, count = 0, value = value, sources = {}}
            groups[item.prefab] = group
        end
        group.count = group.count + count
        if Rules.IsBigMeat(item.prefab) and Rules.IsStale(item) then
            group.stale_count = (group.stale_count or 0) + count
        end
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
        local am, bm = IsMonsterMeat(a.prefab), IsMonsterMeat(b.prefab)
        if am ~= bm then return am end
        return a.value == b.value and a.prefab < b.prefab or a.value < b.value
    end)
    return pool
end

local function StaleInMix(prefabs, pool)
    local counts, stale = {}, 0
    for _, name in ipairs(prefabs) do counts[name] = (counts[name] or 0) + 1 end
    for _, group in ipairs(pool) do
        stale = stale + math.min(counts[group.prefab] or 0, group.stale_count or 0)
    end
    return stale
end

local function FindAutomatic(inst, cooker, pool)
    local stats = Food.GetStats(inst)
    local health_deficit = Food.GetMealHealthDeficit(inst, stats)
    local healing_target = health_deficit ~= nil and math.min(20, health_deficit) or nil
    local needs_only_health = healing_target ~= nil and stats.hungerpercent >= .65 and stats.sanitypercent >= .60
    local selected, used, best, bestscore, best_meatballs, best_meatballs_score = {}, {}, nil, 0, nil, 0
    local best_healing
    local checked = 0
    local function Search(first, rawvalue)
        if checked >= 2048 then return end
        if #selected == 4 then
            checked = checked + 1
            local prefabs = {}
            for _, group in ipairs(selected) do prefabs[#prefabs + 1] = group.prefab end
            local value, duration, product, healing = M.Evaluate(inst, cooker, prefabs,
                StaleInMix(prefabs, pool), stats, health_deficit)
            if value == nil then return end
            local gain = value - rawvalue
            if healing_target ~= nil and healing >= healing_target and (best_healing == nil
                or healing > best_healing.healing or healing == best_healing.healing and gain > best_healing.gain) then
                best_healing = {prefabs = prefabs, duration = duration, gain = gain, product = product, healing = healing}
            end
            local score = gain
            -- Stew is a fallback when its expensive meat has no better use.
            -- Monster meat is safe here only after native recipe resolution.
            if health_deficit ~= nil then
                if needs_only_health then return end
            elseif product == "bonestew" then
                score = gain * .2
            elseif product == "meatballs" then
                score = gain + 200 + MeatballsPreference(prefabs)
                    + (inst.prefab == "wathgrithr" and 10000 or 0)
                if score > best_meatballs_score + 1 then
                    best_meatballs_score = score
                    best_meatballs = {prefabs = prefabs, duration = duration, gain = gain}
                end
            end
            if score > bestscore + 1 then
                bestscore = score
                best = {prefabs = prefabs, duration = duration, gain = gain, product = product}
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
    if best_healing ~= nil then return best_healing end
    if health_deficit == nil and best ~= nil and best.product == "bonestew" and best_meatballs ~= nil then
        return best_meatballs
    end
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
        return wanted == "meatballs" and MeatballsPreference(prefabs) or 0, portions, cost
    end
    local function Evaluate(prefabs)
        checked = checked + 1
        if checked % 2048 == 0 then coroutine.yield() end
        return M.EvaluateSpecific(inst, cooker, prefabs, wanted, StaleInMix(prefabs, pool))
    end
    local function Conserve(prefabs)
        -- Improve fillers without hard-coding recipe requirements: prefer mixes
        -- that can be repeated more often, then lower use of scarce materials.
        local preference, portions, cost = BatchValue(prefabs)
        local improved = true
        while improved do
            improved = false
            for slot = 1, 4 do
                local previous = prefabs[slot]
                for _, group in ipairs(pool) do
                    prefabs[slot] = group.prefab
                    local nextpreference, nextportions, nextcost = BatchValue(prefabs)
                    if (nextpreference > preference or nextpreference == preference
                        and (nextportions > portions or nextportions == portions and nextcost < cost - .000001))
                        and Evaluate(prefabs) ~= nil then
                        previous, preference, portions, cost = group.prefab, nextpreference, nextportions, nextcost
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
        ingredients[#ingredients + 1] = {prefab = group.prefab, count = group.count,
            stale_count = group.stale_count}
    end
    -- Spend plentiful fillers first; retain scarce ingredients for later pots.
    table.sort(ingredients, function(a, b)
        return a.count == b.count and a.prefab < b.prefab or a.count > b.count
    end)
    local signature = {cooker, wanted}
    for _, group in ipairs(ingredients) do
        signature[#signature + 1] = group.prefab .. "=" .. group.count .. "/" .. (group.stale_count or 0)
    end
    signature = table.concat(signature, ":")
    local now = GetTime()
    local searches = inst._my_friend_recipe_search or {}
    inst._my_friend_recipe_search = searches
    local oldest_key, oldest_time
    for key, entry in pairs(searches) do
        if now - (entry.last_used or 0) > 30 then
            searches[key] = nil
        elseif oldest_time == nil or entry.last_used < oldest_time then
            oldest_key, oldest_time = key, entry.last_used
        end
    end
    local search = searches[signature]
    if search == nil then
        local count = 0
        for _ in pairs(searches) do count = count + 1 end
        if count >= 8 and oldest_key ~= nil then searches[oldest_key] = nil end
        search = {thread = coroutine.create(function()
            return SpecificSearch(inst, cooker, ingredients, wanted)
        end)}
        searches[signature] = search
    end
    search.last_used = now
    if coroutine.status(search.thread) ~= "dead" then
        local ok, plan = coroutine.resume(search.thread)
        if not ok then error(plan) end
        search.plan = plan
    end
    return search.plan, coroutine.status(search.thread) ~= "dead"
end

return M
