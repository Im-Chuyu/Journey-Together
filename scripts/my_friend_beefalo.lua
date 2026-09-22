local Policy = require("my_friend_policy")
local FoodStorage = require("my_friend_food_storage")
local Cooking = require("my_friend_beefalo_cooking")

local M = {Riding = require("my_friend_riding")}
M.FEED_HUNGER = 270
M.OBEDIENCE = .6
M.MATERIAL_RESERVE = 20
local TRAINING_FOOD = {"beefalofeed", "twigs", "cutgrass"}
local TAMED_FOOD = {"twigs", "cutgrass", "beefalofeed"}

local function Count(item)
    return item ~= nil and item:IsValid()
        and (item.components.stackable ~= nil and item.components.stackable:StackSize() or 1) or 0
end

function M.IsRelaxed(inst, context)
    if context ~= nil and (context.ghost or context.threat or context.hurt or context.hurt_evade
        or context.dark or context.thermal or context.leaderdead or context.constructing
        or context.hunger ~= nil and context.hunger < .5) then return false end
    local c = inst.components
    return not inst:HasTag("playerghost") and not c.health:IsDead()
        and not inst._my_friend_under_threat and inst._my_friend_command == nil
        and GetTime() >= (inst._my_friend_hurt_evade_until or 0)
        and not Policy.IsBusy(inst) and not Policy.IsFollowGatheringPaused(inst)
        and not Policy.IsLeaderDead(inst)
        and not inst._my_friend_container_action and not inst._my_friend_storage_action
        and not inst._my_friend_backpack_action and inst._my_friend_backpack_target == nil
        and inst._my_friend_pending_recipe == nil and inst._my_friend_work_target == nil
        and (c.combat == nil or c.combat.target == nil)
        and (c.rider == nil or not c.rider:IsRiding())
        and (c.hunger == nil or c.hunger:GetPercent() >= .5)
        and not require("my_friend_light_ai").IsDark(inst)
end

function M.NeedsFeed(beefalo)
    if beefalo == nil or not beefalo:IsValid() then return false end
    local c = beefalo.components
    if c.domesticatable == nil or c.hunger == nil or c.hunger.current >= M.FEED_HUNGER
        or c.health ~= nil and c.health:IsDead()
        or c.combat ~= nil and c.combat:HasTarget()
        or c.rideable ~= nil and c.rideable:IsBeingRidden()
        or c.freezable ~= nil and c.freezable:IsFrozen() then return false end
    if c.domesticatable:IsDomesticated() then return c.domesticatable:GetObedience() < M.OBEDIENCE - 1e-6 end
    return c.domesticatable:GetDomestication() < 1
end

local function Available(inst, item)
    local invitem = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    if invitem == nil or invitem.islockedinslot or invitem:GetGrandOwner() ~= inst
        or FoodStorage.IsReserved(inst, item) then return false end
    local owner = invitem.owner
    local container = owner ~= nil and owner.components.container or nil
    return container == nil or not container.readonlycontainer and not container:IsRestricted(inst)
end

function M.FindFeed(inst, beefalo)
    local items, totals = FoodStorage.ReferenceItems(inst), {}
    for _, item in ipairs(items) do
        if Available(inst, item) then totals[item.prefab] = (totals[item.prefab] or 0) + Count(item) end
    end
    local order = beefalo.components.domesticatable:IsDomesticated() and TAMED_FOOD or TRAINING_FOOD
    for _, prefab in ipairs(order) do
        if (totals[prefab] or 0) > (prefab == "beefalofeed" and 0 or M.MATERIAL_RESERVE) then
            for _, item in ipairs(items) do
                if item.prefab == prefab and Available(inst, item)
                    and not item:HasAnyTag("spoiled", "badfood", "unsafefood")
                    and beefalo.components.eater ~= nil and beefalo.components.eater:CanEat(item) then
                    local trader = beefalo.components.trader
                    if trader == nil or trader:AbleToAccept(item, inst, 1)
                        and trader:WantsToAccept(item, inst, 1) then return item end
                end
            end
        end
    end
end

local function InReach(inst, beefalo)
    return Policy.InRange(inst, beefalo) and inst:GetDistanceSqToInst(beefalo) <= 20^2
        and inst:GetCurrentPlatform() == beefalo:GetCurrentPlatform()
end

function M.Score(inst, context)
    if not M.IsRelaxed(inst, context) or GetTime() < (inst._my_friend_beefalo_retry or 0)
        or M.Riding.GetBoundBeefalo(inst) == nil then return 0 end
    local beefalo = M.Riding.GetBoundBeefalo(inst)
    if M.NeedsFeed(beefalo) and M.FindFeed(inst, beefalo) ~= nil then return 67 end
    return Cooking.HasWork(inst) and 67 or 0
end

function M.GetAction(inst)
    if M.Score(inst) == 0 then return end
    local beefalo = M.Riding.GetBoundBeefalo(inst)
    local action = Cooking.GetAction(inst, false)
    if action ~= nil then return action end
    action = Cooking.GetAction(inst, true)
    if action ~= nil then return action end
    if M.NeedsFeed(beefalo) then
        local food = M.FindFeed(inst, beefalo)
        if food ~= nil then
            action = BufferedAction(inst, beefalo, ACTIONS.FEED, food)
            action._my_friend_dialogue_kind = "beefalo_feed"
            action.validfn = function()
                return inst._my_friend_command == nil and not inst._my_friend_under_threat
                    and M.Riding.GetBoundBeefalo(inst) == beefalo
                    and M.NeedsFeed(beefalo) and M.FindFeed(inst, beefalo) == food
            end
            action:AddFailAction(function()
                if not action._my_friend_cancelled then inst._my_friend_beefalo_retry = GetTime() + 10 end
            end)
            return Policy.GuardAction(inst, action)
        end
    end
end

return M
