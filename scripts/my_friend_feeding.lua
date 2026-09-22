local M = {}

local function IsMealState(inst)
    local state = inst.sg ~= nil and inst.sg.currentstate or nil
    return state ~= nil and (state.name == "eat" or state.name == "quickeat")
end

local function FinishMeal(inst, meal)
    if inst._my_friend_external_meal ~= meal then return end
    if inst._my_friend_meal_watch ~= nil then
        inst._my_friend_meal_watch:Cancel()
        inst._my_friend_meal_watch = nil
    end
    inst._my_friend_external_meal = nil
    inst._my_friend_food_supply_cache = nil
    inst._my_friend_replan_requested = true
    -- Preserve any unexpired greeting pause; do not restart its five seconds.
    if GetTime() >= (inst._my_friend_greeting_pause_until or 0) then
        inst._my_friend_greeting_pause_until = nil
    end
    if inst._my_friend_work_target ~= nil then
        inst._my_friend_work_stall_deadline = GetTime() + 15
    end
    if inst.brain ~= nil then inst.brain:ForceUpdate() end
    inst:DoTaskInTime(6, function()
        if not inst:IsValid() or inst._my_friend_external_meal ~= nil
            or inst.sg == nil or not inst.sg:HasStateTag("idle")
            or inst:HasTag("playerghost") then return end
        local decision = inst._my_friend_decision or {}
        print("[MyFriends] Idle after feeding: task=" .. tostring(decision.task)
            .. ", greeting=" .. tostring(GetTime() < (inst._my_friend_greeting_pause_until or 0))
            .. ", backpack=" .. tostring(inst._my_friend_backpack_action)
            .. ", container=" .. tostring(inst._my_friend_container_action)
            .. ", storage=" .. tostring(inst._my_friend_storage_action))
    end)
end

local function WatchMeal(inst)
    local meal = inst._my_friend_external_meal
    if type(meal) ~= "table" then return end
    if not IsMealState(inst) then
        FinishMeal(inst, meal)
        return
    end
    -- Recover only a finished meal animation, never interrupt the eating
    -- timeline, a queued food effect, death, or another busy action.
    if GetTime() - meal.started > 1 and inst.AnimState:AnimDone()
        and inst.sg.statemem.queued_post_eat_state == nil then
        inst.sg:GoToState("idle")
        FinishMeal(inst, meal)
        return
    end
    if not meal.reported and GetTime() - meal.started > 8 then
        meal.reported = true
        print("[MyFriends] Feeding still waiting: state=" .. inst.sg.currentstate.name
            .. ", busy=" .. tostring(inst.sg:HasStateTag("busy"))
            .. ", animation_done=" .. tostring(inst.AnimState:AnimDone()))
    end
    if inst.brain ~= nil then inst.brain:ForceUpdate() end
end

function M.IsUnsafe(food, target)
    local edible = food ~= nil and food.components.edible or nil
    if food == nil then return false end
    if food:HasAnyTag("badfood", "unsafefood", "spoiled") then return true end
    return edible ~= nil and (edible:GetHealth(target) < 0
        or edible:GetSanity(target) < 0 or edible:GetHunger(target) < 0)
end

function M.Feed(act)
    local target, food, player = act.target, act.invobject, act.doer
    if target == nil or not target:IsValid() or food == nil or not food:IsValid()
        or player == nil or not player:IsValid() or player.userid == nil
        or target.sg == nil or not target.sg:HasStateTag("idle")
        or target.sg:HasAnyStateTag("busy", "attacking", "sleeping")
        or target:HasAnyTag("playerghost", "wereplayer")
        or target.components.eater == nil or food.components.edible == nil
        or food.components.inventoryitem == nil
        or food.components.inventoryitem:GetGrandOwner() ~= player then return false end
    local affinity = target.components.my_friend_affinity
    if affinity == nil or not affinity:CanFeed(player)
        or not require("my_friend_policy").IsLocalPlayer(player)
        or (M.IsUnsafe(food, target) and not affinity:AcceptsUnsafeFood(player))
        or not target.components.eater:CanEat(food) then return false end
    if not target.components.eater:PrefersToEat(food) then
        target:PushEvent("wonteatfood", { food = food })
        return true
    end
    -- Match FEEDPLAYER's ownership and state data so interrupted meals are returned.
    local active = player.components.inventory:GetActiveItem() == food
    food = food.components.inventoryitem:RemoveFromOwner()
    if food == nil then return false end
    local root = target.brain ~= nil and target.brain.bt ~= nil and target.brain.bt.root or nil
    if root ~= nil and root.CancelActive ~= nil then root:CancelActive() end
    target.components.locomotor:Clear()
    target.components.locomotor:Stop()
    target._my_friend_next_greeting = GetTime() + 10
    target._my_friend_external_meal = {started = GetTime()}
    -- Native meals resume player-controlled pocket rummaging. The companion
    -- must resume its planner instead; this does not close or empty the bag.
    target.sg.mem.pocket_rummage_item = nil
    target:AddChild(food)
    food:RemoveFromScene()
    food.components.inventoryitem:HibernateLivingItem()
    food.persists = false
    local state = food:HasTag("quickeat") and "quickeat"
        or food:HasTag("sloweat") and "eat"
        or (food.components.edible.foodtype == FOODTYPE.MEAT
            and not food:HasTag("fooddrink")) and "eat" or "quickeat"
    target.sg:GoToState(state, { feed = food, feeder = player, active = active })
    if target._my_friend_meal_watch ~= nil then target._my_friend_meal_watch:Cancel() end
    target._my_friend_meal_watch = target:DoPeriodicTask(.25, WatchMeal)
    if target.brain ~= nil then target.brain:ForceUpdate() end
    return true
end

function M.OnMealExit(inst)
    if not inst:HasTag("my_friend") then return end
    local meal = inst._my_friend_external_meal
    -- Run after SGwilson has returned any uneaten item and entered its next
    -- state. Do not cancel or replace the native feeding animation.
    inst:DoTaskInTime(0, function()
        if not inst:IsValid() then return end
        if meal ~= nil and not IsMealState(inst) then
            FinishMeal(inst, meal)
        end
        if inst.brain ~= nil then inst.brain:ForceUpdate() end
    end)
end

function M.WrapEater(eater, inst)
    local eat = eater.Eat
    eater.Eat = function(self, food, feeder)
        local affinity = inst.components.my_friend_affinity
        if not inst:HasTag("my_friend") or affinity == nil or feeder == nil
            or feeder == inst or feeder.userid == nil then
            return eat(self, food, feeder)
        end
        local health = inst.components.health
        local hunger = inst.components.hunger
        local sanity = inst.components.sanity
        if health == nil or hunger == nil or sanity == nil then
            return eat(self, food, feeder)
        end
        local hp, hu, sa = health.currenthealth, hunger.current, sanity.current
        affinity:BeginMeal()
        local result = eat(self, food, feeder)
        affinity:EndMeal()
        if result then
            affinity:RecordMeal(feeder, health.currenthealth - hp,
                hunger.current - hu, sanity.current - sa)
            inst._my_friend_next_greeting = GetTime() + 10
            inst._my_friend_eat_after = GetTime() + 2
            require("my_friend_dialogue").Say(inst, "fed", feeder)
        end
        return result
    end
end

function M.WrapHealth(health, inst)
    local do_delta = health.DoDelta
    health.DoDelta = function(self, ...)
        local old = self.currenthealth
        local result = do_delta(self, ...)
        local affinity = inst.components.my_friend_affinity
        if affinity ~= nil and inst:HasTag("my_friend") and not affinity:IsRecordingMeal() then
            affinity:RecordFollowerChange(self.currenthealth - old, 0)
        end
        return result
    end
end

function M.WrapSanity(sanity, inst)
    local do_delta = sanity.DoDelta
    sanity.DoDelta = function(self, ...)
        local old = self.current
        local result = do_delta(self, ...)
        local affinity = inst.components.my_friend_affinity
        if affinity ~= nil and inst:HasTag("my_friend") and not affinity:IsRecordingMeal() then
            affinity:RecordFollowerChange(0, self.current - old)
        end
        return result
    end
end

return M
