local M = {}

local HEALTH_THRESHOLD = .80
local HUNGER_THRESHOLD = .65
local SANITY_THRESHOLD = .60
local EXPIRING_DAYS = .35
local PERISH_BONUS_DAYS = .75
local FOOD_SUPPLY_HUNGER_THRESHOLD = .85
local FOOD_SUPPLY_MIN_COUNT = 4
local EMERGENCY_THRESHOLD = .15

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function GetMaximum(component, fallback)
    return component.GetMaxWithPenalty ~= nil and component:GetMaxWithPenalty()
        or component.max or component.maxhealth or fallback
end

local function GetStats(inst)
    local health = inst.components.health
    local hunger = inst.components.hunger
    local sanity = inst.components.sanity
    if health == nil or hunger == nil or sanity == nil then return end
    local hpmax = math.max(1, GetMaximum(health, health.currenthealth))
    local hungermax = math.max(1, GetMaximum(hunger, hunger.current))
    local sanitymax = math.max(1, GetMaximum(sanity, sanity.current))
    return {
        health = health.currenthealth,
        healthmax = hpmax,
        healthpercent = Clamp(health.currenthealth / hpmax, 0, 1),
        hunger = hunger.current,
        hungermax = hungermax,
        hungerpercent = Clamp(hunger.current / hungermax, 0, 1),
        sanity = sanity.current,
        sanitymax = sanitymax,
        sanitypercent = Clamp(sanity.current / sanitymax, 0, 1),
    }
end

function M.IsEmergency(inst, stats)
    stats = stats or GetStats(inst)
    return stats ~= nil and (stats.hungerpercent <= EMERGENCY_THRESHOLD
        or stats.healthpercent <= EMERGENCY_THRESHOLD)
end

local function GetFoodDeltas(inst, food)
    local eater = inst.components.eater
    local edible = food.components.edible
    local memorymult = inst.components.foodmemory ~= nil
        and inst.components.foodmemory:GetFoodMultiplier(food.prefab) or 1
    local stackmult = eater.eatwholestack and edible:GetStackMultiplier() or 1
    local health, hunger, sanity = 0, 0, 0
    if edible.healthvalue >= 0 or eater:DoFoodEffects(food) then
        health = edible:GetHealth(inst) * memorymult * eater.healthabsorption
    end
    hunger = edible:GetHunger(inst) * memorymult * eater.hungerabsorption
    if edible.sanityvalue >= 0 or eater:DoFoodEffects(food) then
        sanity = edible:GetSanity(inst) * memorymult * eater.sanityabsorption
    end
    if eater.custom_stats_mod_fn ~= nil then
        health, hunger, sanity = eater.custom_stats_mod_fn(
            inst, health, hunger, sanity, food, inst)
    end
    return health * stackmult, hunger * stackmult, sanity * stackmult
end

local function IsInBeargerSack(item)
    local inventoryitem = item ~= nil and item.components ~= nil
        and item.components.inventoryitem or nil
    local owner = inventoryitem ~= nil and inventoryitem.owner or nil
    return owner ~= nil and owner.prefab == "beargerfur_sack"
end

local function ScoreDelta(delta, current, maximum, gainweight, harmweight)
    if delta > 0 then
        if gainweight == 0 then return 0 end
        local usable = math.min(delta, math.max(0, maximum - current))
        local wasted = delta - usable
        return usable / maximum * 100 * gainweight
            - wasted / maximum * 25
    elseif delta < 0 then
        return delta / maximum * 100 * harmweight
    end
    return 0
end

local function GetPerishData(food)
    local perishable = food.components.perishable
    if perishable == nil or perishable.perishremainingtime == nil then return nil, 0 end
    local day = TUNING.TOTAL_DAY_TIME
    local days = perishable.perishremainingtime / day
    local bonus = Clamp((PERISH_BONUS_DAYS - days) / PERISH_BONUS_DAYS, 0, 1) * 12
    return days, bonus
end

function M.Evaluate(inst, food, stats)
    if food == nil or not food:IsValid() or food.components == nil
        or food.components.edible == nil or food.components.inventoryitem == nil
        or food.components.inventoryitem.islockedinslot
        or not inst.components.eater:CanEat(food)
        or not inst.components.eater:PrefersToEat(food) then return end

    stats = stats or GetStats(inst)
    if stats == nil then return end
    local health, hunger, sanity = GetFoodDeltas(inst, food)
    if M.IsEmergency(inst, stats) then
        -- Actual eater deltas include spoilage, food memory and character
        -- absorption. In an emergency only a lethal serving is vetoed.
        if health < 0 and stats.health + health <= 0 then return end
        local perishdays = GetPerishData(food)
        local healing = math.min(math.max(0, health), stats.healthmax - stats.health)
        local calories = math.min(math.max(0, hunger), stats.hungermax - stats.hunger)
        local score = healing * (stats.healthpercent <= EMERGENCY_THRESHOLD and 8 or 2)
            + calories * (stats.hungerpercent <= EMERGENCY_THRESHOLD and 5 or 1)
            + math.min(0, health) * 8 + math.min(0, hunger) * 3 + math.min(0, sanity)
        return math.max(1, 100 + score), perishdays, health, hunger, sanity
    end
    if require("my_friend_pets").IsIngredient(inst, food) then return end
    if food.components.cookable ~= nil and (health < 0 or sanity < 0)
        and stats.hungerpercent > .2 and stats.healthpercent > .35 then return end
    if health < 0 and stats.health + health <= 1
        or hunger < 0 and stats.hunger + hunger <= 0
        or health < 0 and stats.healthpercent <= .35 then return end

    local routine_need = stats.healthpercent < HEALTH_THRESHOLD
        or stats.hungerpercent < HUNGER_THRESHOLD
        or stats.sanitypercent < SANITY_THRESHOLD
    local needhealth = stats.healthpercent < HEALTH_THRESHOLD
    local needhunger = stats.hungerpercent < HUNGER_THRESHOLD
    local needsanity = stats.sanitypercent < SANITY_THRESHOLD
    local perishdays, perishbonus = GetPerishData(food)
    local expiring = perishdays ~= nil and perishdays <= EXPIRING_DAYS
    if not routine_need and not expiring then return end

    -- Surplus calories cannot justify a meal intended to heal or restore sanity.
    -- Small benefits remain usable; there is no minimum food-value cutoff.
    if routine_need and not (needhealth and health > 0
        or needhunger and hunger > 0 or needsanity and sanity > 0) then return end

    local healthgain = 2.8 + 8.5 * (1 - stats.healthpercent)^2
    local hungergain = 2.2 + 7.5 * (1 - stats.hungerpercent)^2
    local sanitygain = 1.5 + 5 * (1 - stats.sanitypercent)^2
    local score = ScoreDelta(health, stats.health, stats.healthmax,
            routine_need and not needhealth and 0 or healthgain, 8 + 12 * (1 - stats.healthpercent)^2)
        + ScoreDelta(hunger, stats.hunger, stats.hungermax,
            routine_need and not needhunger and 0 or hungergain, 6 + 9 * (1 - stats.hungerpercent)^2)
        + ScoreDelta(sanity, stats.sanity, stats.sanitymax,
            routine_need and not needsanity and 0 or sanitygain, 4 + 6 * (1 - stats.sanitypercent)^2)
        + (routine_need and 0 or perishbonus)

    local useful = math.min(math.max(0, health), math.max(0, stats.healthmax - stats.health))
        + math.min(math.max(0, hunger), math.max(0, stats.hungermax - stats.hunger))
        + math.min(math.max(0, sanity), math.max(0, stats.sanitymax - stats.sanity))
    if useful <= 0 or score <= 0 then return end
    return score, perishdays, health, hunger, sanity
end

function M.FindBestFood(inst)
    local inventory = inst.components.inventory
    local stats = GetStats(inst)
    if inventory == nil or inst.components.eater == nil or stats == nil then return end
    local best, bestscore, bestperish
    for _, food in ipairs(inventory:ReferenceAllItems()) do
        local score, perish
        if not IsInBeargerSack(food) then score, perish = M.Evaluate(inst, food, stats) end
        if score ~= nil and (bestscore == nil or score > bestscore + .001
            or math.abs(score - bestscore) <= .001
                and (perish or math.huge) < (bestperish or math.huge)) then
            best, bestscore, bestperish = food, score, perish
        end
    end
    return best, bestscore
end

-- Explicit meals ignore fullness, but never knowingly eat a lethal serving.
function M.CommandScore(inst, food, positive_only)
    if food == nil or not food:IsValid() or food.components.edible == nil
        or food.components.inventoryitem == nil or food.components.inventoryitem.islockedinslot
        or not inst.components.eater:CanEat(food)
        or not inst.components.eater:PrefersToEat(food) then return end
    if M.IsEmergency(inst) then
        local score = M.Evaluate(inst, food)
        return score, score ~= nil
    end
    local health, hunger, sanity = GetFoodDeltas(inst, food)
    if health < 0 and inst.components.health.currenthealth + health <= 1 then return end
    if hunger < 0 and inst.components.hunger.current + hunger <= 0 then return end
    local positive = health >= 0 and hunger >= 0 and sanity >= 0
    if positive_only and not positive then return end
    return health * 3 + hunger + sanity * 2, positive
end

function M.FindCommandFood(inst, positive_only)
    local best, score
    for _, food in ipairs(inst.components.inventory:ReferenceAllItems()) do
        local value = not IsInBeargerSack(food)
            and M.CommandScore(inst, food, positive_only) or nil
        if value ~= nil and (score == nil or value > score) then best, score = food, value end
    end
    return best
end

function M.GetEatAction(inst, commanded_food)
    if commanded_food == nil and inst._my_friend_command ~= nil
        and inst._my_friend_command.id == "food" then return end
    if inst.sg == nil or inst.sg:HasStateTag("busy") or inst:HasTag("playerghost")
        or inst.components.health == nil or inst.components.health:IsDead()
        or inst._my_friend_backpack_target ~= nil or inst._my_friend_backpack_action then return end
    if commanded_food == nil then
        local action = require("my_friend_container_ai").GetCarriedFoodAction(inst)
        if action ~= nil then return action end
    end
    if inst._my_friend_container_action then return end
    if commanded_food == nil and GetTime() < (inst._my_friend_eat_after or 0)
        and not M.IsEmergency(inst) and inst.components.hunger:GetPercent() >= .2 then return end
    local food = commanded_food or M.FindBestFood(inst)
    if food == nil then return end
    if commanded_food == nil and not M.IsEmergency(inst)
        and require("my_friend_recipe_cooking").ShouldReserve(inst, food) then return end
    local action = BufferedAction(inst, nil, ACTIONS.EAT, food)
    action:AddSuccessAction(function()
        inst._my_friend_food_supply_cache = nil
        inst._my_friend_eat_after = GetTime() + 2
        inst._my_friend_next_greeting = GetTime() + 5
    end)
    action:AddFailAction(function() inst._my_friend_eat_after = GetTime() + 1 end)
    return action
end

function M.GetFoodSupply(inst)
    local hunger = inst.components.hunger
    local inventory = inst.components.inventory
    local eater = inst.components.eater
    if hunger == nil or inventory == nil or eater == nil then return 0 end
    local cached = inst._my_friend_food_supply_cache
    if cached ~= nil and GetTime() < cached.untiltime then return cached.supply end
    local supply = 0
    for _, item in ipairs(require("my_friend_food_storage").ReferenceItems(inst)) do
        if item.components ~= nil and item.components.edible ~= nil
            and eater:CanEat(item) and eater:PrefersToEat(item) then
            local health, calories = GetFoodDeltas(inst, item)
            if health >= 0 then
                supply = supply + math.max(0, calories)
                    * (not eater.eatwholestack and item.components.stackable ~= nil
                        and item.components.stackable:StackSize() or 1)
            end
        end
    end
    inst._my_friend_food_supply_cache = {supply = supply, untiltime = GetTime() + .75}
    return supply
end

function M.NeedsFoodSupply(inst)
    local follower = inst.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    local days = leader ~= nil and leader:IsValid() and 1 or 2
    if days == 2 and (inst._my_friend_base == nil or not inst._my_friend_base.complete) then
        days = 1
    end
    return M.GetFoodSupply(inst) < M.GetDailyHunger(inst) * days
end

function M.GetDailyHunger(inst)
    local hunger = inst.components.hunger
    local rate = hunger ~= nil and hunger.hungerrate or nil
    return math.max(1, (rate or (75 / TUNING.TOTAL_DAY_TIME))
        * TUNING.TOTAL_DAY_TIME)
end

M.GetFoodDeltas = GetFoodDeltas

function M.NeedsFoodSupplyAtPercent(hungerpercent, foodcount)
    return hungerpercent < FOOD_SUPPLY_HUNGER_THRESHOLD
        and foodcount < FOOD_SUPPLY_MIN_COUNT
end

return M
