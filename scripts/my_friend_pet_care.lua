local Policy = require("my_friend_policy")
local Food = require("my_friend_food_ai")
local FoodStorage = require("my_friend_food_storage")
local M = {}

M.FOOD_VALUE_LIMIT = 20
local FEED_RANGE = 7
local RETRY_DELAY = 15

local function Available(inst)
    local c = inst.components
    local leader = Policy.GetLeader(inst)
    return not inst:HasTag("playerghost") and not c.health:IsDead()
        and c.petleash ~= nil and inst._my_friend_command == nil
        and not inst._my_friend_under_threat
        and GetTime() >= math.max(inst._my_friend_hurt_until or 0, inst._my_friend_hurt_evade_until or 0)
        and not Policy.IsFollowGatheringPaused(inst) and not Policy.IsLeaderDead(inst)
        and (leader == nil or inst:GetDistanceSqToInst(leader) <= FEED_RANGE^2
            and inst:GetCurrentPlatform() == leader:GetCurrentPlatform())
        and (c.combat == nil or c.combat.target == nil)
        and (c.rider == nil or not c.rider:IsRiding())
        and not inst._my_friend_riding_dismounting
        and not c.inventory:IsHeavyLifting()
        and not inst._my_friend_container_action and not inst._my_friend_storage_action
        and not inst._my_friend_chest_transfer and not inst._my_friend_backpack_action
        and inst._my_friend_backpack_target == nil and inst._my_friend_pending_recipe == nil
        and inst._my_friend_work_target == nil
        and c.hunger:GetPercent() >= .65 and c.health:GetPercent() >= .35
        and c.sanity:GetPercent() >= .2
        and inst.sg ~= nil and not inst.sg:HasAnyStateTag("sleeping", "frozen", "jumping", "floating")
        and not require("my_friend_light_ai").IsDark(inst)
        and not require("my_friend_survival_ai").NeedsTemperatureHelp(inst)
end

function M.CanFeed(inst, pet)
    local leash = inst.components.petleash
    if pet == nil or not pet:IsValid() or not pet:HasTag("critter")
        or pet:HasAnyTag("INLIMBO", "fire", "playerghost")
        or leash == nil or not leash:GetPets()[pet] then return false end
    local c = pet.components
    -- Native critters use perishable as hunger, and one serving resets it.
    return c.follower ~= nil and c.follower:GetLeader() == inst
        and c.perishable ~= nil and c.perishable:GetPercent() <= .5
        and c.eater ~= nil and not c.eater.eatwholestack
        and (c.health == nil or not c.health:IsDead())
        and (c.freezable == nil or not c.freezable:IsFrozen())
        and (c.combat == nil or c.combat.target == nil)
        and inst:GetCurrentPlatform() == pet:GetCurrentPlatform()
        and inst:GetDistanceSqToInst(pet) <= FEED_RANGE^2 and Policy.InRange(inst, pet, FEED_RANGE)
end

local function FoodValue(inst, pet, item)
    if item == nil or not item:IsValid() then return end
    local invitem, edible = item.components.inventoryitem, item.components.edible
    if invitem == nil or edible == nil or invitem.islockedinslot
        or invitem:GetGrandOwner() ~= inst or FoodStorage.IsReserved(inst, item) then return end
    local owner = invitem.owner
    local container = owner ~= nil and owner.components.container or nil
    if container ~= nil and (container.readonlycontainer or container:IsRestricted(inst)) then return end
    -- Base values protect good meals from being classified as cheap because
    -- they are stale or the companion has a food-memory penalty.
    local health, hunger, sanity = edible.healthvalue, edible.hungervalue, edible.sanityvalue
    if health >= M.FOOD_VALUE_LIMIT or hunger >= M.FOOD_VALUE_LIMIT or sanity >= M.FOOD_VALUE_LIMIT
        or not pet.components.eater:CanEat(item) or not pet.components.eater:PrefersToEat(item) then return end
    if inst.components.eater:CanEat(item) and inst.components.eater:PrefersToEat(item) then
        local hp, calories, sanitygain = Food.GetFoodDeltas(inst, item)
        if hp > 0 and inst.components.health:GetPercent() < .8
            or calories > 0 and inst.components.hunger:GetPercent() < .65
            or sanitygain > 0 and inst.components.sanity:GetPercent() < .6 then return end
    end
    return math.max(0, health) + math.max(0, hunger) + math.max(0, sanity)
end

function M.Score(inst, context)
    if inst.components.petleash == nil or GetTime() < (inst._my_friend_pet_feed_after or 0)
        or context ~= nil and (context.ghost or context.threat or context.hurt or context.hurt_evade
            or context.dark or context.thermal or context.constructing or context.leaderdead)
        or not Available(inst) or Policy.IsBusy(inst) then return 0 end
    for pet in pairs(inst.components.petleash:GetPets()) do
        if M.CanFeed(inst, pet) then return 14 end
    end
    return 0
end

function M.GetAction(inst)
    if M.Score(inst) == 0 or inst:GetBufferedAction() ~= nil then return end
    local target, food, value
    local items = FoodStorage.ReferenceItems(inst)
    for pet in pairs(inst.components.petleash:GetPets()) do
        if M.CanFeed(inst, pet) then
            for _, item in ipairs(items) do
                local score = FoodValue(inst, pet, item)
                if score ~= nil and (value == nil or score < value) then
                    target, food, value = pet, item, score
                end
            end
        end
    end
    if food == nil then
        inst._my_friend_pet_feed_after = GetTime() + RETRY_DELAY
        return
    end
    local action = BufferedAction(inst, target, ACTIONS.FEED, food)
    action.validfn = function()
        -- Do not test the doer's busy tag here: FEED itself enters a busy SG.
        return Available(inst) and M.CanFeed(inst, target) and FoodValue(inst, target, food) ~= nil
    end
    action:AddSuccessAction(function()
        inst._my_friend_pet_feed_after = GetTime() + RETRY_DELAY
        inst._my_friend_food_supply_cache = nil
        require("my_friend_dialogue").Say(inst, "pet_feed")
    end)
    action:AddFailAction(function()
        inst._my_friend_pet_feed_after = GetTime() + RETRY_DELAY
    end)
    return Policy.GuardAction(inst, action, FEED_RANGE)
end

return M
