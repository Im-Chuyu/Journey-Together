local M = {}
local Policy = require("my_friend_policy")
local Food = require("my_friend_food_ai")
local FoodStorage = require("my_friend_food_storage")

M.HEAL_COOLDOWN = 30
M.HUNGER_COOLDOWN = 15
M.RETRY_COOLDOWN = 10
M.FAILURE_COOLDOWN = 60

local function Needs(player)
    if player == nil or not player:IsValid() or player:HasAnyTag("playerghost", "wereplayer")
        or player.components.health == nil or player.components.health:IsDead()
        or player.components.hunger == nil or player.components.eater == nil then return false, false end
    return player.components.health:GetPercent() < .5, player.components.hunger:GetPercent() < .5
end

local function CanReceive(player)
    return player.sg ~= nil and player.sg:HasStateTag("idle")
        and not player.sg:HasAnyStateTag("busy", "attacking", "sleeping")
end

local function GetCooldown(inst, player)
    local cooldowns = inst._my_friend_feed_cooldowns
    return cooldowns ~= nil and cooldowns[player.userid or player] or nil
end

function M.OnSave(inst, data)
    local now = GetTime()
    local saved
    for userid, state in pairs(inst._my_friend_feed_cooldowns or {}) do
        if type(userid) == "string" and type(state) == "table" then
            local deadline = type(state.nexttime) == "number" and state.nexttime or 0
            local failure_count = type(state.failures) == "number" and state.failures or 0
            local remaining = math.max(0, deadline - now)
            local failures = math.max(0, math.min(2, math.floor(failure_count)))
            if remaining > 0 or failures > 0 then
                saved = saved or {}
                saved[userid] = {
                    nexttime = math.min(M.FAILURE_COOLDOWN, remaining),
                    failures = failures,
                }
            end
        end
    end
    data.my_friend_feed_cooldowns = saved
end

function M.OnLoad(inst, data)
    inst._my_friend_feed_cooldowns = {}
    for userid, state in pairs(data ~= nil and data.my_friend_feed_cooldowns or {}) do
        if type(userid) == "string" and type(state) == "table"
            and type(state.nexttime) == "number" and state.nexttime == state.nexttime
            and type(state.failures) == "number" and state.failures == state.failures then
            local remaining = math.max(0, math.min(M.FAILURE_COOLDOWN, state.nexttime))
            local failures = math.max(0, math.min(2, math.floor(state.failures)))
            if remaining > 0 or failures > 0 then
                inst._my_friend_feed_cooldowns[userid] = {
                    nexttime = GetTime() + remaining,
                    failures = failures,
                }
            end
        end
    end
end

function M.Score(inst, player)
    local hurt, hungry = Needs(player)
    if not (hurt or hungry) or not CanReceive(player)
        or inst._my_friend_command ~= nil or inst._my_friend_under_threat
        or inst._my_friend_container_action or inst._my_friend_storage_action
        or inst._my_friend_backpack_action or inst._my_friend_backpack_target ~= nil
        or inst.components.combat ~= nil and inst.components.combat.target ~= nil then return 0 end
    local cooldown = GetCooldown(inst, player)
    if cooldown ~= nil and GetTime() < cooldown.nexttime then return 0 end
    return hurt and 70 or 34
end

local function Suitable(inst, player, food)
    if food == nil or not food:IsValid() or food.components.inventoryitem == nil
        or food.components.inventoryitem.islockedinslot
        or food.components.inventoryitem:GetGrandOwner() ~= inst
        or FoodStorage.IsReserved(inst, food)
        or food:HasAnyTag("badfood", "unsafefood", "spoiled") then return end
    local owner = food.components.inventoryitem.owner
    if owner ~= nil and owner.prefab == "beargerfur_sack" then
        local container = owner.components.container
        if container == nil or container.readonlycontainer or container:IsRestricted(inst) then return end
    end
    local score, positive = Food.CommandScore(player, food, true)
    if not positive then return end
    local health, hunger = Food.GetFoodDeltas(player, food)
    local hurt, hungry = Needs(player)
    if hurt and health > 0 or hungry and hunger > 0 then
        -- Rank healing first, then use the existing food score to break ties.
        return score, hurt and math.max(0, health) or 0
    end
end

function M.GetAction(inst)
    local player = Policy.GetLeader(inst)
    if M.Score(inst, player) == 0 or Policy.IsBusy(inst) then return end
    local best, bestscore, besthealth
    for _, food in ipairs(FoodStorage.ReferenceItems(inst)) do
        local score, health = Suitable(inst, player, food)
        if score ~= nil and (best == nil or health > besthealth
            or health == besthealth and score > bestscore) then
            best, bestscore, besthealth = food, score, health
        end
    end
    if best == nil then return end
    local action = BufferedAction(inst, player, ACTIONS.FEEDPLAYER, best)
    action.arrivedist = 2
    local healing = false
    action.validfn = function()
        local score, health = Suitable(inst, player, best)
        healing = health ~= nil and health > 0
        return Policy.GetLeader(inst) == player and M.Score(inst, player) > 0 and score ~= nil
    end
    local finished = false
    local function FinishAttempt(success)
        if finished then return end
        finished = true
        if not success and action._my_friend_cancelled then return end
        inst._my_friend_feed_cooldowns = inst._my_friend_feed_cooldowns or {}
        local key = player.userid or player
        local state = inst._my_friend_feed_cooldowns[key] or {failures = 0}
        inst._my_friend_feed_cooldowns[key] = state
        if success then
            state.failures = 0
            state.nexttime = GetTime() + (healing and M.HEAL_COOLDOWN or M.HUNGER_COOLDOWN)
            inst._my_friend_food_supply_cache = nil
            require("my_friend_dialogue").Say(inst, "feed_player", player)
        else
            state.failures = state.failures + 1
            state.nexttime = GetTime() + (state.failures >= 3 and M.FAILURE_COOLDOWN or M.RETRY_COOLDOWN)
            if state.failures >= 3 then state.failures = 0 end
        end
    end
    -- Vanilla FEEDPLAYER removes one serving from its inventory/container owner
    -- and gives SGwilson responsibility for eating or returning it on interruption.
    action:AddSuccessAction(function() FinishAttempt(true) end)
    action:AddFailAction(function() FinishAttempt(false) end)
    return Policy.GuardAction(inst, action, 7)
end

return M
