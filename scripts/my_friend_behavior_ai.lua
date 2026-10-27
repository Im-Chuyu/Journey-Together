local M = {}
local Policy = require("my_friend_policy")
local FoodAI = require("my_friend_food_ai")
local Navigation = require("my_friend_navigation")
local Home = require("my_friend_home")
local Reserves = require("my_friend_resource_reserves")

M.RESOURCE_MIN = 10
M.RESOURCE_MAX = 40
M.COLLECT_RANGE = 12
M.COLLECT_ACTION_TIMEOUT = 5
M.COLLECT_RETRY_DELAY = 20
M.THREAT_RANGE = 24
M.THREAT_SAFE_DISTANCE = 28
M.RECENT_ATTACKER_TIME = 10
M.ASSIST_ATTACK_WINDOW = 16
M.LEADER_RETURN_DISTANCE = 20
M.ASSIST_RANGE = 32
M.HAZARD_RETREAT_TIME = 8
M.HAZARD_RETREAT_RADIUS = 6
M.COMBAT_DODGE_PADDING = .75
M.COMBAT_DODGE_MIN_TIME = .2
M.COMBAT_DODGE_MAX_TIME = .65
M.RESOURCE_THREAT_RANGE = 8

local RESOURCE_PRODUCTS = {
    cutgrass = true,
    twigs = true,
    rocks = true,
    flint = true,
    goldnugget = true,
    nitre = true,
    log = true,
    pinecone = true,
    acorn = true,
    charcoal = true,
    cutreeds = true,
    dug_grass = true,
    dug_sapling = true,
}

local FOOD_PRODUCTS = {
    asparagus = true,
    berries = true,
    berries_juicy = true,
    blue_cap = true,
    cactus_flower = true,
    cactus_meat = true,
    carrot = true,
    cave_banana = true,
    corn = true,
    dragonfruit = true,
    durian = true,
    eggplant = true,
    forgetmelots = true,
    garlic = true,
    green_cap = true,
    kelp = true,
    lightbulb = true,
    moon_cap = true,
    onion = true,
    pepper = true,
    pomegranate = true,
    potato = true,
    pumpkin = true,
    red_cap = true,
    rock_avocado_fruit_ripe = true,
    tomato = true,
    watermelon = true,
    wormlight_lesser = true,
}

function M.IsFoodProduct(prefab)
    return prefab ~= nil and FOOD_PRODUCTS[prefab] == true
end

local COLLECT_CANT_TAGS = {
    "INLIMBO", "catchable", "fire", "heavy", "irreplaceable",
    "mineactive", "outofreach",
}

local THREAT_CANT_TAGS = {
    "INLIMBO", "NOCLICK", "ghost", "invisible", "noattack",
    "notarget", "playerghost",
}

local DistanceSq = Policy.DistanceSq

local function IsAlive(inst)
    return inst ~= nil and inst:IsValid() and inst.components ~= nil
        and inst.components.health ~= nil and not inst.components.health:IsDead()
end

local function CanAct(inst)
    return IsAlive(inst) and not inst:HasTag("playerghost")
        and inst.components.inventory ~= nil
        and not inst._my_friend_backpack_action
        and inst._my_friend_backpack_target == nil
        and not inst._my_friend_container_action
        and (inst.sg == nil or not inst.sg:HasStateTag("busy"))
end

local function CanPickUp(inst, item)
    local inventoryitem = item.components ~= nil and item.components.inventoryitem or nil
    return inventoryitem ~= nil and inventoryitem.owner == nil
        and inventoryitem.canbepickedup and not item:IsInLimbo()
        and (not Policy.IsBaseCacheItem(inst, item)
            or item.components.edible ~= nil and inst.components.hunger:GetPercent() < .4)
        and inst.components.inventory:CanAcceptCount(item, 1) > 0
end

local function HasRoomForPrefab(inventory, prefab)
    if prefab == nil then return false end
    if inventory:FindItem(function(item)
        return item.prefab == prefab and item.components.stackable ~= nil
            and not item.components.stackable:IsFull()
    end) ~= nil then
        return true
    end
    for i = 1, inventory.maxslots do
        if inventory:GetItemInSlot(i) == nil then return true end
    end
    local overflow = inventory:GetOverflowContainer()
    if overflow ~= nil then
        for i = 1, overflow:GetNumSlots() do
            if overflow:GetItemInSlot(i) == nil then return true end
        end
    end
    return false
end

local function IsPickableProduct(item, products)
    local pickable = item.components ~= nil and item.components.pickable or nil
    return pickable ~= nil and pickable.caninteractwith and pickable:CanBePicked()
        and products[pickable.product] == true
end

local function FindClosest(inst, testfn)
    M.PruneExpiredEntries(inst._my_friend_collect_blocked, GetTime())
    local x, y, z, range = Policy.SearchOrigin(inst, M.COLLECT_RANGE)
    local closest, closestdist
    local entities = TheSim:FindEntities(x, y, z, range, nil,
        COLLECT_CANT_TAGS, {"_inventoryitem", "pickable", "readyforharvest"})
    for _, item in ipairs(entities) do
        local key = item.GUID or item
        local blockeduntil = inst._my_friend_collect_blocked ~= nil
            and inst._my_friend_collect_blocked[key] or nil
        if blockeduntil ~= nil and GetTime() >= blockeduntil then
            inst._my_friend_collect_blocked[key] = nil
            blockeduntil = nil
        end
        if item ~= inst and blockeduntil == nil
            and Home.AllowsTarget(inst, item)
            and not Navigation.IsBlocked(inst, item:GetPosition())
            and not M.IsTargetUnsafe(inst, item)
            and testfn(item) then
            local dist = DistanceSq(inst, item)
            if M.IsCloserCandidate(dist, closestdist) then
                closest, closestdist = item, dist
            end
        end
    end
    return closest
end

function M.IsCloserCandidate(distance, bestdistance)
    return bestdistance == nil or distance < bestdistance
end

function M.IsTargetUnsafe(inst, target)
    if require("my_friend_resource_safety").IsBlocked(inst, target) then return true end
    if target == nil or target.Transform == nil then return false end
    local x, y, z = target.Transform:GetWorldPosition()
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, M.RESOURCE_THREAT_RANGE,
        { "_combat" }, THREAT_CANT_TAGS)) do
        if M.IsThreat(inst, entity) then return true end
    end
    return false
end

function M.PruneExpiredEntries(entries, now)
    if entries == nil then return 0 end
    local remaining = 0
    for key, deadline in pairs(entries) do
        if type(deadline) ~= "number" or deadline <= now then
            entries[key] = nil
        else
            remaining = remaining + 1
        end
    end
    return remaining
end

function M.IsBeforeDeadline(now, deadline)
    return deadline == nil or now < deadline
end

function M.IsRetryAllowed(now, blockeduntil)
    return blockeduntil == nil or now >= blockeduntil
end

local function TimedAction(inst, target, actiontype)
    local deadline = GetTime() + math.max(M.COLLECT_ACTION_TIMEOUT,
        math.sqrt(DistanceSq(inst, target)) / 3 + 5)
    local action = BufferedAction(inst, target, actiontype)
    action.validfn = function()
        return M.IsBeforeDeadline(GetTime(), math.max(deadline,
            action._my_friend_travel_until or 0,
            (action._my_friend_travel_finished or 0) + M.COLLECT_ACTION_TIMEOUT))
            and Policy.InRange(inst, target)
    end
    action:AddFailAction(function()
        if action._my_friend_cancelled then return end
        if inst:IsValid() and target ~= nil then
            inst._my_friend_collect_blocked = inst._my_friend_collect_blocked or {}
            inst._my_friend_collect_blocked[target.GUID or target] =
                GetTime() + M.COLLECT_RETRY_DELAY
        end
    end)
    action:AddSuccessAction(function()
        if inst._my_friend_collect_blocked ~= nil and target ~= nil then
            inst._my_friend_collect_blocked[target.GUID or target] = nil
        end
    end)
    return action
end

function M.UpdateResourceNeed(count, gathering)
    if gathering then return count < M.RESOURCE_MAX end
    return count < M.RESOURCE_MIN
end

function M.CountResource(inst, prefab)
    local inventory = inst.components.inventory
    if inventory == nil then return 0 end
    local _, count = inventory:Has(prefab, M.RESOURCE_MAX)
    return count or 0
end

function M.GetResourceAction(inst, late_minimum)
    if not CanAct(inst) then return end
    local late = Reserves.IsLateWorld()
    if late and not late_minimum then return end
    local minimum_keep = late and Reserves.MinimumKeep() or nil
    local state = inst._my_friend_resource_needs or {}
    inst._my_friend_resource_needs = state
    for prefab in pairs(RESOURCE_PRODUCTS) do
        local count = M.CountResource(inst, prefab)
        local minimum = (prefab == "cutgrass" or prefab == "twigs") and 2 or 0
        local target = late and (minimum_keep[prefab] or 0)
            or (count < minimum and minimum or M.RESOURCE_MAX)
        state[prefab] = count < target
    end
    local has_need = false
    for prefab in pairs(RESOURCE_PRODUCTS) do
        if state[prefab] then has_need = true break end
    end
    if not has_need then return end

    local target = FindClosest(inst, function(item)
        if state[item.prefab] and CanPickUp(inst, item) then return true end
        local pickable = item.components ~= nil and item.components.pickable or nil
        return pickable ~= nil and state[pickable.product]
            and IsPickableProduct(item, RESOURCE_PRODUCTS)
            and HasRoomForPrefab(inst.components.inventory, pickable.product)
    end)
    if target == nil then return end
    return TimedAction(inst, target,
        target.components.pickable ~= nil and RESOURCE_PRODUCTS[target.components.pickable.product]
            and ACTIONS.PICK or ACTIONS.PICKUP)
end

function M.GetLateMinimumAction(inst)
    if not Reserves.IsLateWorld() or inst._my_friend_command ~= nil or inst._my_friend_under_threat then return end
    return M.GetResourceAction(inst, true)
end

function M.GetFoodOrResourceAction(inst)
    if not CanAct(inst) or inst.components.eater == nil then return end
    local needs_food = FoodAI.NeedsFoodSupply(inst)
    local following = Policy.GetLeader(inst) ~= nil
    local late = Reserves.IsLateWorld()
    local state = inst._my_friend_resource_needs or {}
    inst._my_friend_resource_needs = state
    for prefab in pairs(RESOURCE_PRODUCTS) do
        local count = M.CountResource(inst, prefab)
        local target = following and (Reserves.FOLLOW_TARGETS[prefab] or 0) or M.RESOURCE_MAX
        state[prefab] = not late and count < target
    end
    local grass = M.CountResource(inst, "cutgrass")
    local twigs = M.CountResource(inst, "twigs")
    local minimum_missing = not late and (grass < 2 or twigs < 2)
    local target = FindClosest(inst, function(item)
        if minimum_missing then
            if (item.prefab == "cutgrass" and grass < 2
                    or item.prefab == "twigs" and twigs < 2)
                and CanPickUp(inst, item) then return true end
            local pickable = item.components ~= nil and item.components.pickable or nil
            return pickable ~= nil and (pickable.product == "cutgrass" and grass < 2
                    or pickable.product == "twigs" and twigs < 2)
                and IsPickableProduct(item, RESOURCE_PRODUCTS)
                and HasRoomForPrefab(inst.components.inventory, pickable.product)
        end
        if needs_food and CanPickUp(inst, item)
            and FoodAI.IsUsableFood(inst, item) then
            return true
        end
        if state[item.prefab] and CanPickUp(inst, item) then return true end
        local pickable = item.components ~= nil and item.components.pickable or nil
        if pickable ~= nil
            and (state[pickable.product] and IsPickableProduct(item, RESOURCE_PRODUCTS)
                or needs_food and IsPickableProduct(item, FOOD_PRODUCTS))
            and HasRoomForPrefab(inst.components.inventory, pickable.product) then
            return true
        end
        local crop = item.components ~= nil and item.components.crop or nil
        return needs_food and crop ~= nil and crop:IsReadyForHarvest()
            and HasRoomForPrefab(inst.components.inventory, crop.product_prefab)
    end)
    if target == nil then return end
    if target.components.crop ~= nil then
        return TimedAction(inst, target, ACTIONS.HARVEST)
    elseif target.components.pickable ~= nil then
        return TimedAction(inst, target, ACTIONS.PICK)
    end
    return TimedAction(inst, target, ACTIONS.PICKUP)
end

function M.GetFoodAction(inst, commanded)
    if not CanAct(inst) or inst.components.eater == nil then return end
    if not commanded and not FoodAI.NeedsFoodSupply(inst) then return end
    local inventory = inst.components.inventory
    local overflow = inventory:GetOverflowContainer()
    local free = inventory:GetNumSlots() - inventory:NumItems()
        + (overflow ~= nil and overflow:GetNumSlots() - overflow:NumItems() or 0)
    local building = Policy.GetLeader(inst) == nil
        and (inst._my_friend_base == nil or not inst._my_friend_base.complete)
    local function HasFoodRoom(prefab)
        if building and free <= 2 and inst.components.hunger:GetPercent() >= .4 then
            return inventory:FindItem(function(item)
                return item.prefab == prefab and item.components.stackable ~= nil
                    and not item.components.stackable:IsFull()
            end) ~= nil
        end
        return HasRoomForPrefab(inventory, prefab)
    end
    local target = FindClosest(inst, function(item)
        if CanPickUp(inst, item) and FoodAI.IsUsableFood(inst, item)
            and HasFoodRoom(item.prefab) then
            return true
        end
        local pickable = item.components ~= nil and item.components.pickable or nil
        if IsPickableProduct(item, FOOD_PRODUCTS)
            and HasFoodRoom(pickable.product) then
            return true
        end
        local crop = item.components ~= nil and item.components.crop or nil
        return crop ~= nil and crop:IsReadyForHarvest()
            and HasFoodRoom(crop.product_prefab)
    end)
    if target == nil then return end
    if target.components.crop ~= nil then
        return TimedAction(inst, target, ACTIONS.HARVEST)
    elseif target.components.pickable ~= nil then
        return TimedAction(inst, target, ACTIONS.PICK)
    end
    return TimedAction(inst, target, ACTIONS.PICKUP)
end

function M.IsThreat(inst, entity)
    local combat = entity ~= nil and entity.components ~= nil and entity.components.combat or nil
    if entity == inst or not IsAlive(entity) or combat == nil
        or entity:HasAnyTag("structure", "wall") then return false end
    -- A player attack is handled by the short hurt-retreat window. Treating
    -- the player as a normal threat afterwards makes RunAway select its large
    -- safety radius and fights the follow behaviour indefinitely.
    if entity:HasTag("player") and not entity:HasTag("my_friend") then return false end
    if combat.target == inst then return true end
    local owncombat = inst.components ~= nil and inst.components.combat or nil
    return owncombat ~= nil and owncombat.lastattacker == entity
        and GetTime() - (owncombat.lastwasattackedtime or 0) <= M.RECENT_ATTACKER_TIME
end

function M.IsPriorityEngaged(inst, target)
    local rules = require("my_friend_combat_rules")
    local active = rules.IsActiveDefenceWorld()
    if rules.IsFollowTargetPaused(inst, target) or rules.IsBeyondFollowCombatRange(inst)
        or not IsAlive(target) or target == inst
        or target:HasAnyTag("player", "my_friend", "structure", "wall")
        or not (active or rules.IsPriorityEnemy(target)) then return false end
    if M.IsThreat(inst, target) then return DistanceSq(inst, target) <= M.ASSIST_RANGE^2 end
    local combat = target.components ~= nil and target.components.combat or nil
    local victim = combat ~= nil and combat.target or nil
    local leader = Policy.GetLeader(inst)
    return leader ~= nil and victim == leader
        and Policy.IsLocalPlayer(leader) and not leader:HasTag("playerghost")
        and (active or Policy.InRange(inst, target, M.ASSIST_RANGE))
        and DistanceSq(inst, target) <= M.ASSIST_RANGE^2
end

function M.FindAssistTarget(inst)
    local rules = require("my_friend_combat_rules")
    rules.IsFollowTargetPaused(inst)
    if rules.IsBeyondFollowCombatRange(inst) then inst._my_friend_assist_scan = nil return end
    local leader = Policy.GetLeader(inst)
    if leader == nil or leader:HasTag("playerghost")
        or not Policy.InRange(inst, inst, M.ASSIST_RANGE) then
        inst._my_friend_assist_scan = nil
        return
    end
    local now = GetTime()
    local buffered = leader.GetBufferedAction ~= nil and leader:GetBufferedAction() or nil
    local action_target = buffered ~= nil and buffered.action == ACTIONS.ATTACK
        and buffered.target or nil
    local cached = inst._my_friend_assist_scan
    if cached ~= nil and cached.leader == leader and now < cached.untiltime then
        local recent = M.GetLeaderAttackCount(inst, cached.target) > 0
            or action_target == cached.target
        return recent and IsAlive(cached.target) and not rules.IsFollowTargetPaused(inst, cached.target)
            and cached.target or nil
    end
    local function ValidTarget(entity)
        return entity ~= nil and entity ~= inst and entity ~= leader and IsAlive(entity)
            and not rules.IsFollowTargetPaused(inst, entity)
            and not entity:HasAnyTag("player", "my_friend", "structure", "wall")
            and entity.components ~= nil and entity.components.combat ~= nil
            and Policy.InRange(inst, entity, M.ASSIST_RANGE)
            and DistanceSq(inst, entity) <= M.ASSIST_RANGE * M.ASSIST_RANGE
    end
    -- The buffered attack exists before the player's combat target is synced.
    -- Read it so the companion does not miss the first attack tick.
    if ValidTarget(action_target) then
        inst._my_friend_assist_scan = {
            leader = leader, target = action_target, untiltime = now + .25,
        }
        return action_target
    end
    local candidate = inst._my_friend_assist_candidate
    if candidate ~= nil and now < (inst._my_friend_assist_until or 0)
        and ValidTarget(candidate) and M.GetLeaderAttackCount(inst, candidate) > 0 then
        inst._my_friend_assist_scan = {
            leader = leader, target = candidate, untiltime = now + .25,
        }
        return candidate
    end
    inst._my_friend_assist_candidate = nil
    inst._my_friend_assist_until = nil
    inst._my_friend_assist_scan = {
        leader = leader, target = nil, untiltime = now + .25,
    }
    return nil
end

function M.StartHurtRetreat(inst, source, fire_distance, source_position)
    if source == nil or not source:IsValid() or not IsAlive(inst)
        or inst:HasTag("playerghost") then return end
    if fire_distance == nil and (require("my_friend_combat_rules").IsBeyondFollowCombatRange(inst)
        or require("my_friend_combat_rules").IsFollowTargetPaused(inst, source)
        or require("my_friend_combat_rules").IsPriorityEnemy(source)
        or M.IsPriorityEngaged(inst, source)) then return end
    local now = GetTime()
    source_position = source_position or source:GetPosition()
    -- Ordinary hits cannot replace an environmental escape. While still in a
    -- hazard, keep moving rather than letting the short hurt timer run out.
    if now < (inst._my_friend_hurt_evade_until or 0) then
        if fire_distance == nil then return end
        local previous = inst._my_friend_hurt_source
        local destination = inst._my_friend_hurt_destination
        if inst._my_friend_hurt_fire_distance ~= nil
            and (destination ~= nil and not M.IsHazardousPath(inst, destination, destination)
                or fire_distance == inst._my_friend_hurt_fire_distance and previous ~= nil
                    and (previous.x - source_position.x)^2 + (previous.z - source_position.z)^2 < .25^2) then
            inst._my_friend_hurt_until = now + 3
            inst._my_friend_hurt_evade_until = now + 3.5
            return
        end
    end
    inst._my_friend_hurt_position = inst:GetPosition()
    inst._my_friend_hurt_attacker = source
    inst._my_friend_hurt_source = source_position
    inst._my_friend_hurt_destination = nil
    inst._my_friend_hurt_failed_destination = nil
    inst._my_friend_hurt_fire_distance = fire_distance
    inst._my_friend_hurt_until = now + 3
    inst._my_friend_hurt_evade_until = now + 3.5
    inst._my_friend_assist_target = nil
    inst._my_friend_assist_candidate = nil
    inst._my_friend_assist_until = nil
    inst._my_friend_assist_scan = nil
    inst._my_friend_threat_scan = nil
    inst.components.combat:SetTarget(nil)
    require("my_friend_container_ai").Cancel(inst)
    -- Let the utility selector cancel its old node after the hit animation.
    inst._my_friend_replan_requested = true
end

local function ClearHazard(inst)
    inst._my_friend_hazard_position, inst._my_friend_hazard_until = nil, nil
    inst._my_friend_hazard_source, inst._my_friend_hazard_radius = nil, nil
    inst._my_friend_hazard_cause = nil
end

local function GetContactHazard(inst)
    local point = inst._my_friend_hazard_position
    if point == nil then return end
    local source = inst._my_friend_hazard_source
    if source ~= nil then
        if source:IsValid() then
            local aura = source.components.aura
            if aura ~= nil and aura.active then
                for _, tag in ipairs(aura.auraexcludetags or {}) do
                    if inst:HasTag(tag) then ClearHazard(inst) return end
                end
                return source:GetPosition(), aura.radius
            elseif aura == nil then
                local radius = require("my_friend_survival_ai").GetTemperatureDangerRadius(inst, source,
                    inst._my_friend_hazard_cause == "cold" or inst._my_friend_hazard_cause == "freezing")
                if radius > 0 then return source:GetPosition(), radius end
            end
        end
        ClearHazard(inst)
        return
    end
    if GetTime() >= (inst._my_friend_hazard_until or 0) then ClearHazard(inst) return end
    return point, inst._my_friend_hazard_radius
end

local function GetFireHazard(inst)
    local source = inst._my_friend_fire_source
    if source == nil then return end
    local health = inst.components.health
    if health ~= nil and health.GetFireDamageScale ~= nil and health:GetFireDamageScale() <= 0 then
        inst._my_friend_fire_source = nil
        return
    end
    local radius = require("my_friend_survival_ai").GetFireDangerRadius(source)
    if radius <= 0 then inst._my_friend_fire_source = nil return end
    return source:GetPosition(), radius
end

local function IntersectsHazard(from, point, centre, radius)
    if centre == nil then return false end
    local dx, dz = point.x - from.x, point.z - from.z
    local length = dx * dx + dz * dz
    local t = length > 0 and math.max(0, math.min(1,
        ((centre.x - from.x) * dx + (centre.z - from.z) * dz) / length)) or 0
    return (from.x + dx * t - centre.x)^2 + (from.z + dz * t - centre.z)^2 <= radius^2
end

function M.IsHazardousPath(inst, from, point)
    local centre, radius = GetContactHazard(inst)
    if IntersectsHazard(from, point, centre, radius) then return true end
    centre, radius = GetFireHazard(inst)
    return IntersectsHazard(from, point, centre, radius)
end

function M.IsHazardRetreatActive(inst)
    if inst._my_friend_hazard_position == nil and inst._my_friend_fire_source == nil then return false end
    local point = inst:GetPosition()
    return M.IsHazardousPath(inst, point, point)
end

local function RememberHazard(inst, source, cause, centre, distance)
    local current = inst:GetPosition()
    local aura = source ~= nil and source.components.aura or nil
    local override = source ~= nil and source.components.temperatureoverrider or nil
    local point = inst._my_friend_hazard_position
    local radius = inst._my_friend_hazard_radius or M.HAZARD_RETREAT_RADIUS
    -- Unknown damage areas are remembered at the first contact, not recentered
    -- on every tick while the companion is already running away.
    if centre ~= nil then
        point, radius = centre, distance
    elseif aura ~= nil then
        point, radius = source:GetPosition(), aura.radius
    elseif override ~= nil then
        point = source:GetPosition()
        radius = require("my_friend_survival_ai").GetTemperatureDangerRadius(inst, source,
            cause == "cold" or cause == "freezing")
    elseif point == nil or inst._my_friend_hazard_source ~= nil
        or inst._my_friend_hazard_cause ~= cause
        or (current.x - point.x)^2 + (current.z - point.z)^2 > radius^2 then
        point, radius = current, M.HAZARD_RETREAT_RADIUS
    end
    inst._my_friend_hazard_position = Vector3(point.x, 0, point.z)
    inst._my_friend_hazard_radius = radius
    inst._my_friend_hazard_source = centre == nil and (aura ~= nil or override ~= nil) and source or nil
    inst._my_friend_hazard_cause = cause
    inst._my_friend_hazard_until = GetTime() + M.HAZARD_RETREAT_TIME
    M.StartHurtRetreat(inst, source or inst, radius + 1, point)
end

function M.OnFireDamage(inst)
    if not IsAlive(inst) or inst:HasTag("playerghost") then return end
    local health = inst.components.health
    if health.GetFireDamageScale ~= nil and health:GetFireDamageScale() <= 0 then return end
    local now = GetTime()
    if now < (inst._my_friend_fire_check_after or 0) then return end
    inst._my_friend_fire_check_after = now + 1
    local source, distance = require("my_friend_survival_ai").FindDamagingHeatSource(inst, true)
    if source ~= nil then
        inst._my_friend_fire_source = source
        M.StartHurtRetreat(inst, source, distance + 1)
    elseif health.takingfiredamage then
        RememberHazard(inst, nil, "fire")
    end
end

function M.OnHeatDamage(inst)
    if not IsAlive(inst) or inst:HasTag("playerghost") then return end
    local now = GetTime()
    if now < (inst._my_friend_heat_check_after or 0) then return end
    inst._my_friend_heat_check_after = now + 1
    local override = require("my_friend_survival_ai").FindDamagingTemperatureSource(inst, false)
    if override ~= nil then
        RememberHazard(inst, override, "hot")
        return
    end
    local source = require("my_friend_survival_ai").FindDamagingHeatSource(inst)
    if source ~= nil then
        local radius = math.max(M.HAZARD_RETREAT_RADIUS, math.sqrt(DistanceSq(inst, source)) + 2)
        RememberHazard(inst, source, "hot", source:GetPosition(), radius)
    end
end

function M.OnColdDamage(inst)
    if not IsAlive(inst) or inst:HasTag("playerghost") then return end
    local now = GetTime()
    if now < (inst._my_friend_cold_check_after or 0) then return end
    inst._my_friend_cold_check_after = now + 1
    local source = require("my_friend_survival_ai").FindDamagingTemperatureSource(inst, true)
    if source ~= nil then
        RememberHazard(inst, source, "cold")
        return
    end
    -- Summoned cold lights (for example `staffcoldlight`) use the regular
    -- heater component rather than temperatureoverrider. Remember their
    -- bounded area when an actual cold damage event is received.
    source = require("my_friend_survival_ai").FindDamagingHeatSource(inst, false, true)
    if source ~= nil then
        local radius = math.max(M.HAZARD_RETREAT_RADIUS,
            math.sqrt(DistanceSq(inst, source)) + 2)
        RememberHazard(inst, source, "cold", source:GetPosition(), radius)
    end
end

function M.OnEnvironmentalDamage(inst, data)
    if not IsAlive(inst) or inst:HasTag("playerghost") or data == nil
        or (data.amount or 0) >= 0 then return end
    if data.cause == "cold" or data.cause == "freezing" then
        M.OnColdDamage(inst)
        return
    end
    if data.cause == "fire" or data.cause == "hot"
        or data.cause == "hunger" or data.cause == "starvation"
        or data.cause == "oldage" or data.cause == "health_as_oldage"
        or data.cause == "sanity" or data.cause == "sanityloss"
        or data.cause == "acidrain" or data.cause == "statue_attune" then return end
    local source = data.afflicter
    if source ~= nil and source.IsValid ~= nil and source:IsValid() then
        local components = source.components or {}
        local parent = source.entity ~= nil and source.entity:GetParent() or nil
        -- Aura attacks (e.g. spore clouds) are area damage even though they use
        -- combat:GetAttacked. Ordinary creatures, food/items and attached
        -- debuffs must not be mistaken for a patch of dangerous ground.
        if source == inst or parent == inst or components.inventoryitem ~= nil then return end
        if components.aura ~= nil then
            if not components.aura.active then return end
        elseif components.health ~= nil or components.projectile ~= nil
            or components.complexprojectile ~= nil then return end
    else
        source = nil
    end
    RememberHazard(inst, source, data.cause)
end

function M.UpdateFollowCombatReturn(inst)
    if inst._my_friend_hurt_fire_distance == nil
        and require("my_friend_combat_rules").IsBeyondFollowCombatRange(inst) then
        inst._my_friend_hurt_until, inst._my_friend_hurt_evade_until = nil, nil
    end
end

function M.UpdateHazardRetreat(inst)
    local point, radius = GetContactHazard(inst)
    if point == nil then return end
    local x, _, z = inst.Transform:GetWorldPosition()
    if (x - point.x)^2 + (z - point.z)^2 <= radius^2 then
        M.StartHurtRetreat(inst, inst._my_friend_hazard_source or inst, radius + 1, point)
    end
end

function M.UpdateFireRetreat(inst)
    -- Only revisit the remembered fire after contact; no periodic world scan.
    local point, distance = GetFireHazard(inst)
    if point ~= nil and DistanceSq(inst, inst._my_friend_fire_source) <= distance * distance then
        M.StartHurtRetreat(inst, inst._my_friend_fire_source, distance + 1, point)
    end
end

function M.ObservePlayerAttack(inst)
    local now = GetTime()
    if now < (inst._my_friend_attack_observe_next or 0) then return end
    inst._my_friend_attack_observe_next = now + .3
    if inst:HasTag("playerghost") or inst.components.health:IsDead() then
        inst._my_friend_attack_intents = nil
        return
    end
    local attacking = {}
    for _, player in ipairs(AllPlayers or {}) do
        if Policy.IsLocalPlayer(player) and not player:HasTag("playerghost") then
            local combat = player.components.combat
            local action = player:GetBufferedAction()
            if combat ~= nil and combat.target == inst
                or action ~= nil and action.action == ACTIONS.ATTACK and action.target == inst then
                attacking[player] = true
                if not (inst._my_friend_attack_intents or {})[player] then
                    M.StartHurtRetreat(inst, player)
                    require("my_friend_dialogue").Say(inst, "player_attack", player)
                end
            end
        end
    end
    inst._my_friend_attack_intents = attacking
end

function M.GetHurtRetreatAction(inst)
    if GetTime() >= (inst._my_friend_hurt_until or 0) or Policy.IsBusy(inst) then return end
    local origin = inst._my_friend_hurt_position
    if origin == nil then return end
    local current = inst:GetPosition()
    local leader = Policy.GetLeader(inst)
    local source = inst._my_friend_hurt_source
    local fire_distance = inst._my_friend_hurt_fire_distance
    local heading = source ~= nil
        and math.atan2(current.z - source.z, current.x - source.x) or math.random() * 2 * math.pi
    local failed = inst._my_friend_hurt_failed_destination
    for i = inst._my_friend_hurt_destination ~= nil and 0 or 1, 12 do
        local offset = math.ceil((i - 1) / 2) * (i % 2 == 0 and 1 or -1)
        local angle = heading + offset * 2 * math.pi / 12
        local centre = fire_distance ~= nil and source or origin
        local distance = fire_distance or 3
        local point = i == 0 and inst._my_friend_hurt_destination
            or Vector3(centre.x + math.cos(angle) * distance, 0, centre.z + math.sin(angle) * distance)
        local allowed = fire_distance ~= nil or leader == nil or Policy.IsRoaming(inst)
        if fire_distance == nil and leader ~= nil and not Policy.IsRoaming(inst) then
            local p = leader:GetPosition()
            allowed = (point.x - p.x)^2 + (point.z - p.z)^2 <= 36
        end
        if allowed and TheWorld.Map:IsPassableAtPoint(point.x, 0, point.z)
            and not Navigation.IsNearHole(point)
            and (failed == nil or (point.x - failed.x)^2 + (point.z - failed.z)^2 > .5^2)
            and (fire_distance == nil or not M.IsHazardousPath(inst, point, point))
            and (source == nil or (point.x - source.x)^2 + (point.z - source.z)^2
                > (current.x - source.x)^2 + (current.z - source.z)^2)
            and Navigation.IsClear(current, point, Navigation.Caps(inst)) then
            inst._my_friend_hurt_destination = point
            local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point)
            action._my_friend_fire_retreat = fire_distance ~= nil
            action.arrivedist = .25
            local function Failed()
                if not inst:IsValid() or inst._my_friend_hurt_destination ~= point
                    or action._my_friend_cancelled then return end
                inst._my_friend_hurt_destination = nil
                inst._my_friend_hurt_failed_destination = point
                if fire_distance ~= nil and M.IsHazardRetreatActive(inst) then
                    inst._my_friend_hurt_until = GetTime() + 3
                    inst._my_friend_hurt_evade_until = GetTime() + 3.5
                end
            end
            local function Finish()
                if not inst:IsValid() or inst._my_friend_hurt_destination ~= point then return end
                if fire_distance ~= nil and M.IsHazardRetreatActive(inst) then Failed() return end
                inst._my_friend_hurt_until = 0
                inst._my_friend_hurt_evade_until = math.min(
                    inst._my_friend_hurt_evade_until or 0, GetTime() + .5)
            end
            action:AddSuccessAction(Finish)
            action:AddFailAction(Failed)
            return action
        end
    end
end

function M.RecordPlayerAttack(player, data)
    if not Policy.IsLocalPlayer(player) then return end
    local target = data ~= nil and data.target or nil
    if target == nil or not target:IsValid() or not IsAlive(target)
        or target.components.combat == nil
        or target:HasAnyTag("structure", "wall", "INLIMBO", "player", "my_friend") then return end
    local now = GetTime()
    local records = target._my_friend_player_attacks or {}
    target._my_friend_player_attacks = records
    for owner, record in pairs(records) do
        if now - record.time > M.ASSIST_ATTACK_WINDOW then records[owner] = nil end
    end
    local key = player.userid or player
    local old = records[key]
    records[key] = {count = (old ~= nil and old.count or 0) + 1, time = now}
    local friend = TheWorld ~= nil and TheWorld._my_friend or nil
    if friend ~= nil and friend:IsValid() and M.GetLeaderAttackCount ~= nil
        and Policy.GetLeader(friend) == player then
        friend._my_friend_assist_candidate = target
        friend._my_friend_assist_until = now + M.ASSIST_ATTACK_WINDOW
        friend._my_friend_assist_scan = nil
    end
end

function M.GetLeaderAttackCount(inst, target)
    local leader = Policy.GetLeader(inst)
    if leader == nil or target == nil or not target:IsValid() or not IsAlive(target)
        or target:HasAnyTag("structure", "wall", "INLIMBO", "player", "my_friend") then return 0 end
    local records = target._my_friend_player_attacks
    local record = records ~= nil and records[leader.userid or leader] or nil
    return record ~= nil and GetTime() - record.time <= M.ASSIST_ATTACK_WINDOW
        and record.count or 0
end

function M.FindThreat(inst, range)
    local rules = require("my_friend_combat_rules")
    rules.IsFollowTargetPaused(inst)
    if rules.IsBeyondFollowCombatRange(inst) then inst._my_friend_threat_scan = nil return end
    local now = GetTime()
    local wanted_range = range or M.THREAT_RANGE
    local cached = inst._my_friend_threat_scan
    local leader = Policy.GetLeader(inst)
    if cached ~= nil and cached.leader == leader and cached.range == wanted_range
        and now < cached.untiltime then
        local target = cached.target
        -- Aggro can change between scans. Revalidate the relationship without
        -- repeating the world query or losing the independent escape candidate.
        if target ~= nil and IsAlive(target) and not rules.IsFollowTargetPaused(inst, target)
            and (M.IsThreat(inst, target) or M.GetLeaderAttackCount(inst, target) > 0
                or M.IsPriorityEngaged(inst, target)) then return target end
        return
    end
    local x, y, z = inst.Transform:GetWorldPosition()
    local closest, closestscore, escape_target, escape_score
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, wanted_range,
        {"_combat"}, THREAT_CANT_TAGS)) do
        local ignored_attacker = GetTime() < (inst._my_friend_hurt_until or 0)
            and entity == inst._my_friend_hurt_attacker
            and entity:HasTag("player")
        if not ignored_attacker and not rules.IsFollowTargetPaused(inst, entity) then
            local attacks = M.GetLeaderAttackCount(inst, entity)
            if not entity:HasTag("player")
                and (M.IsThreat(inst, entity) or attacks > 0 or M.IsPriorityEngaged(inst, entity)) then
                local dist = DistanceSq(inst, entity)
                -- Prefer the creature the leader has actually been attacking.
                local score = attacks * 1000000 - dist
                if not require("my_friend_combat_rules").CanAttack(entity) then
                    score = -1000000000 - dist
                end
                if closestscore == nil or score > closestscore then
                    closest, closestscore = entity, score
                end
                -- Assistance candidates are not reasons to flee. Track the
                -- companion's own threats independently, so a higher-ranked
                -- player target cannot hide an actual attacker.
                if M.IsThreat(inst, entity)
                    and (escape_score == nil or score > escape_score) then
                    escape_target, escape_score = entity, score
                end
            end
        end
    end
    inst._my_friend_threat_scan = {
        leader = leader, range = wanted_range, target = closest, escape_target = escape_target,
        untiltime = now + .6,
    }
    return closest
end

function M.FindEscapeThreat(inst, range)
    local candidate = M.FindThreat(inst, range)
    local cached = inst._my_friend_threat_scan
    local target = cached ~= nil and cached.escape_target or nil
    -- Aggro can switch during the scan cache lifetime. Recheck the cached
    -- attacker, and also notice if the combat candidate now targets us.
    local rules = require("my_friend_combat_rules")
    if M.IsThreat(inst, target) and not rules.IsFollowTargetPaused(inst, target) then return target end
    if M.IsThreat(inst, candidate) and not rules.IsFollowTargetPaused(inst, candidate) then return candidate end
    local retreat = inst._my_friend_unequipped_retreat
    if retreat ~= nil then
        local previous = (Ents or {})[retreat.guid]
        local leader = Policy.GetLeader(inst)
        if IsAlive(previous) and (leader ~= nil and leader.GUID or nil) == retreat.leader_guid
            and not rules.IsBeyondFollowCombatRange(inst) and not rules.IsFollowTargetPaused(inst, previous)
            and DistanceSq(inst, previous) < M.THREAT_SAFE_DISTANCE^2
            and M.ShouldRetreatUnequipped(inst, previous) then return previous end
        inst._my_friend_unequipped_retreat = nil
    end
end

function M.RememberUnequippedRetreat(inst, target)
    local combat = inst.components.combat
    if target ~= nil and (combat ~= nil and combat.target == target or inst._my_friend_assist_target == target) then
        local leader = Policy.GetLeader(inst)
        local previous = inst._my_friend_unequipped_retreat
        if previous == nil or previous.guid ~= target.GUID then inst._my_friend_replan_requested = true end
        inst._my_friend_unequipped_retreat = {guid = target.GUID, leader_guid = leader ~= nil and leader.GUID or nil}
    end
end

local function HasWorkingArmor(item)
    local armor = item ~= nil and item:IsValid() and item.components ~= nil and item.components.armor or nil
    return armor ~= nil and (armor.indestructible or armor.condition == nil or armor.condition > 0)
end

local function IsActiveLight(item)
    return item ~= nil and item:IsValid() and (item._my_friend_ai_light
        or item._my_friend_manual_light_until ~= nil
        or item.HasAnyTag ~= nil and item:HasAnyTag("light", "nightvision"))
end

local function WeaponDamage(inst, target, item)
    if not IsAlive(inst) or target ~= nil and not IsAlive(target) then return end
    local weapon = item ~= nil and item:IsValid() and item.components ~= nil and item.components.weapon or nil
    if weapon == nil then return end
    if inst.components.combat ~= nil and inst.components.combat.CalcDamage ~= nil
        and target ~= nil and target.HasTag ~= nil then
        local damage = inst.components.combat:CalcDamage(target, item)
        return type(damage) == "number" and damage or nil
    end
    local damage = weapon:GetDamage(inst, target)
    return type(damage) == "number" and damage or nil
end

local function IsWeaponBroken(item)
    if item == nil or not item:IsValid() or item.components == nil then return true end
    if item:HasTag("broken") then return true end
    local finite = item.components.finiteuses
    if finite ~= nil and finite:GetUses() <= 0 then return true end
    local fueled = item.components.fueled
    return fueled ~= nil and fueled:IsEmpty()
end

function M.IsTorchWeapon(item)
    return item ~= nil and item:IsValid() and (item.prefab == "torch"
        or item:HasTag("torch"))
end

local function UsableCombatWeapon(inst, item)
    local c = item ~= nil and item:IsValid() and item.components or nil
    local eq = c ~= nil and c.equippable or nil
    local ii = c ~= nil and c.inventoryitem or nil
    return eq ~= nil and eq.equipslot == EQUIPSLOTS.HANDS
        and (eq.IsRestricted == nil or not eq:IsRestricted(inst))
        and ii ~= nil and not ii.islockedinslot and ii:GetGrandOwner() == inst
        and not M.IsTorchWeapon(item) and not IsWeaponBroken(item)
end

function M.FindBestCombatWeapon(inst, target, items)
    if not IsAlive(inst) or target ~= nil and not IsAlive(target) then return end
    local inventory = inst.components.inventory
    if inventory == nil then return end
    local best = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if not UsableCombatWeapon(inst, best) then best = nil end
    local bestdamage = WeaponDamage(inst, target, best) or 0
    if inventory.ReferenceAllItems ~= nil then
        if items == nil then
            items = inventory:ReferenceAllItems()
            local active = inventory:GetActiveItem()
            if active ~= nil then items[#items + 1] = active end
        end
        for _, item in ipairs(items) do
            local damage = UsableCombatWeapon(inst, item) and WeaponDamage(inst, target, item) or nil
            if damage ~= nil and damage > bestdamage then
                best, bestdamage = item, damage
            end
        end
    end
    return best, bestdamage
end

local function GetArmorValue(inst, item, slot, attacker, weapon)
    if attacker ~= nil and not IsAlive(attacker) then return end
    if weapon ~= nil and not weapon:IsValid() then weapon = nil end
    if not HasWorkingArmor(item) then return end
    local equippable = item.components.equippable
    local inventoryitem = item.components.inventoryitem
    if equippable == nil or equippable.equipslot ~= slot
        or equippable.IsRestricted ~= nil and equippable:IsRestricted(inst)
        or inventoryitem == nil or inventoryitem.islockedinslot
        or inventoryitem:GetGrandOwner() ~= inst or item:HasTag("broken") then
        return
    end
    local armor = item.components.armor
    local absorption
    if armor.GetAbsorption ~= nil then
        absorption = armor:GetAbsorption(attacker, weapon)
    else
        absorption = armor.absorb_percent or .6
    end
    if type(absorption) ~= "number" or absorption <= 0 then return end
    local condition = armor.indestructible and math.huge
        or math.max(0, armor.condition or 0)
    return absorption, condition
end

function M.ShouldRetreatUnequipped(inst, target)
    local c = inst ~= nil and inst.components or nil
    local health, inventory = c ~= nil and c.health or nil, c ~= nil and c.inventory or nil
    if inst == nil or not inst:HasTag("my_friend") or health == nil or inventory == nil or health.GetPercent == nil
        or health:GetPercent() >= .8 then return false end
    local now = GetTime()
    local version = inst._my_friend_discovery_inventory or 0
    local hand = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    local cached = inst._my_friend_unequipped_combat
    local cachedarmor = cached ~= nil and cached.armor_guid ~= nil and (Ents or {})[cached.armor_guid] or nil
    local cachedweapon = cached ~= nil and cached.weapon_guid ~= nil and (Ents or {})[cached.weapon_guid] or nil
    local enemyweapon = target ~= nil and target.components ~= nil and target.components.combat ~= nil
        and target.components.combat.GetWeapon ~= nil and target.components.combat:GetWeapon() or nil
    if cached ~= nil and cached.target_guid == (target ~= nil and target.GUID or nil) and cached.version == version
        and cached.hand_guid == (hand ~= nil and hand.GUID or nil) and now < cached.until_time
        and (cached.armor_guid == nil or cachedarmor ~= nil
            and GetArmorValue(inst, cachedarmor, cached.armor_slot, target, enemyweapon) ~= nil)
        and (cached.weapon_guid == nil or UsableCombatWeapon(inst, cachedweapon)) then return cached.retreat end
    local items = inventory:ReferenceAllItems()
    local active = inventory:GetActiveItem()
    if active ~= nil then items[#items + 1] = active end
    local weapon, damage = M.FindBestCombatWeapon(inst, target, items)
    local armor
    if (damage or 0) < 25 then
        for _, item in ipairs(items) do
            local eq = item:IsValid() and item.components ~= nil and item.components.equippable or nil
            if eq ~= nil and eq.equipslot ~= EQUIPSLOTS.HANDS
                and GetArmorValue(inst, item, eq.equipslot, target, enemyweapon) ~= nil then armor = item break end
        end
    end
    local retreat = (damage or 0) < 25 and armor == nil
    inst._my_friend_unequipped_combat = {target_guid = target ~= nil and target.GUID or nil, version = version,
        hand_guid = hand ~= nil and hand.GUID or nil, armor_guid = armor ~= nil and armor.GUID or nil,
        armor_slot = armor ~= nil and armor.components.equippable.equipslot or nil,
        weapon_guid = not retreat and armor == nil and weapon ~= nil and weapon.GUID or nil,
        retreat = retreat, until_time = now + .25}
    return retreat
end

function M.GetThermalInsulation(item, need)
    return item ~= nil and item:IsValid()
        and require("my_friend_survival_ai").GetInsulationValue(item, need) ~= nil
end

local function IsBetterArmor(absorption, utility, condition,
        bestabsorption, bestutility, bestcondition)
    return bestabsorption == nil or absorption > bestabsorption
        or absorption == bestabsorption and (utility > bestutility
            or utility == bestutility and condition > bestcondition)
end

function M.FindBestCombatArmor(inst, slot, attacker, weapon, thermal_need, items)
    local inventory = inst.components.inventory
    if inventory == nil then return end
    local equipment = require("my_friend_equipment")
    local best = inventory:GetEquippedItem(slot)
    local bestabsorption, bestcondition =
        GetArmorValue(inst, best, slot, attacker, weapon)
    if bestabsorption == nil then best = nil end
    local bestutility = best ~= nil
        and equipment.GetCombatUtilityScore(inst, best, thermal_need) or 0
    if inventory.ReferenceAllItems ~= nil then
        for _, item in ipairs(items or inventory:ReferenceAllItems()) do
            local absorption, condition =
                GetArmorValue(inst, item, slot, attacker, weapon)
            if absorption ~= nil then
                local utility = equipment.GetCombatUtilityScore(inst, item, thermal_need)
                if IsBetterArmor(absorption, utility, condition,
                    bestabsorption, bestutility, bestcondition) then
                    best, bestabsorption, bestutility, bestcondition =
                        item, absorption, utility, condition
                end
            end
        end
    end
    return best, bestabsorption, bestcondition
end

function M.EquipBestCombatArmor(inst, attacker, weapon)
    local inventory = inst.components.inventory
    if inventory == nil or inventory.Equip == nil then return end
    -- All usable armour competes by protection, then active utility and
    -- durability. Other capabilities never turn a helmet into non-armour.
    local thermal_need = require("my_friend_survival_ai").GetThermalNeed(inst)
    local items = inventory.ReferenceAllItems ~= nil and inventory:ReferenceAllItems() or {}
    local preferred_head = require("my_friend_equipment").PreferredHead(inst, items)
    for _, slot in ipairs(require("my_friend_equip_slots").All()) do
        if not IsAlive(inst) or attacker ~= nil and not IsAlive(attacker) then return end
        if weapon ~= nil and not weapon:IsValid() then weapon = nil end
        if slot ~= EQUIPSLOTS.HANDS then
            local current = inventory:GetEquippedItem(slot)
            local best = M.FindBestCombatArmor(inst, slot, attacker, weapon,
                thermal_need, items)
            -- Daily head preferences are a fallback only when no usable
            -- armour protects this slot against the current attack.
            if best == nil and slot == EQUIPSLOTS.HEAD then
                best = preferred_head
            end
            if best ~= nil and best ~= current then
                if current ~= nil
                    and current.HasTag ~= nil and current:HasTag("backpack") then
                    inventory:DropItem(current, true, false, inst:GetPosition())
                end
                if best:IsValid() then inventory:Equip(best) end
            end
        end
    end
end

-- Defence must also run on the unarmed/weak-hand and recovery paths.
local function EquipCombatDefense(inst, target)
    local combat = target.components ~= nil and target.components.combat or nil
    local weapon = combat ~= nil and combat.GetWeapon ~= nil and combat:GetWeapon() or nil
    M.EquipBestCombatArmor(inst, target, weapon)
    return weapon
end

local function GetArmorStats(inventory, attacker, weapon)
    local absorption, condition, protected = 0, 0, false
    for _, slot in ipairs(require("my_friend_equip_slots").All()) do
        local item = inventory:GetEquippedItem(slot)
        local armor = item ~= nil and item.components ~= nil and item.components.armor or nil
        if HasWorkingArmor(item) then
            local amount
            if armor.GetAbsorption ~= nil then
                amount = armor:GetAbsorption(attacker, weapon)
            else
                amount = armor.absorb_percent or .6
            end
            if type(amount) == "number" and amount > 0 then
                protected = true
                absorption = math.max(absorption, amount)
                condition = condition + (armor.indestructible and 100000
                    or math.max(0, armor.condition or 0))
            end
        end
    end
    return absorption, condition, protected
end

function M.EstimateFight(friendhealth, enemyhealth, outgoing, incoming,
        friendperiod, enemyperiod, absorption, armorcondition)
    if type(friendhealth) ~= "number" or type(enemyhealth) ~= "number"
        or type(outgoing) ~= "number" or outgoing <= 0 or friendhealth <= 0 then
        return false
    end
    local attacks_to_win = math.max(1, math.ceil(enemyhealth / outgoing))
    if type(incoming) ~= "number" or incoming <= 0 then return true end

    local health = friendhealth
    local armor = math.max(0, armorcondition or 0)
    local hits_survived = 0
    while health > 0 and hits_survived < 1000 do
        local absorbed = armor > 0 and incoming * math.max(0, math.min(1, absorption or 0)) or 0
        health = health - (incoming - absorbed)
        armor = math.max(0, armor - absorbed)
        hits_survived = hits_survived + 1
    end
    local win_time = attacks_to_win * math.max(.1, friendperiod or .4)
    local survival_time = hits_survived * math.max(.1, enemyperiod or 2)
    return win_time <= survival_time * 1.2
end

function M.CanCounterAttack(inst, target)
    if not require("my_friend_combat_rules").CanAttack(target, inst)
        or not IsAlive(target) or not IsAlive(inst)
        or inst.components.inventory == nil or inst.components.combat == nil then
        return false
    end
    local inventory = inst.components.inventory
    local hand = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    -- A torch has a weapon component in vanilla, but it is lighting equipment,
    -- never a combat weapon for the companion. Refuse the combat decision while
    -- one is in hand so no attack action can be buffered around it.
    if M.IsTorchWeapon(hand) then
        if inventory:CanAcceptCount(hand, 1) > 0 then
            local removed = inventory:Unequip(EQUIPSLOTS.HANDS)
            if removed ~= nil then inventory:GiveItem(removed, nil, inst:GetPosition()) end
        end
        hand = nil
    end
    if require("my_friend_equipment").FindDroppedCombatItem(inst) ~= nil then
        EquipCombatDefense(inst, target)
        return false
    end
    local leader = Policy.GetLeader(inst)
    local self_defending = M.IsThreat(inst, target)
    local scan = inst._my_friend_assist_scan
    local action = leader ~= nil and leader.GetBufferedAction ~= nil and leader:GetBufferedAction() or nil
    local assisting = leader ~= nil and not leader:HasTag("playerghost")
        and (scan ~= nil and scan.leader == leader and GetTime() < scan.untiltime
                and scan.target == target and action ~= nil
                and action.action == ACTIONS.ATTACK and action.target == target
            or M.GetLeaderAttackCount(inst, target) > 0)
        and Policy.InRange(inst, inst, M.ASSIST_RANGE)
        and Policy.InRange(inst, target, M.ASSIST_RANGE)
        and DistanceSq(inst, target) <= M.ASSIST_RANGE * M.ASSIST_RANGE
    local weaponitem, damage = M.FindBestCombatWeapon(inst, target)
    local priority = M.IsPriorityEngaged(inst, target)
    if weaponitem == nil or not weaponitem:IsValid() or type(damage) ~= "number" or damage <= 25
        or weaponitem ~= hand and IsActiveLight(hand) then
        EquipCombatDefense(inst, target)
        if not IsAlive(target) or not IsAlive(inst) then return false end
        if not assisting and not self_defending and not priority then return false end
        local health = inst.components.health
        return priority or health == nil or health.GetPercent == nil or health:GetPercent() >= .15
    end
    if weaponitem ~= hand and inventory.Equip ~= nil then
        if inventory:Equip(weaponitem) ~= true then return false end
        if not IsAlive(target) then return false end
        weaponitem = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
        damage = WeaponDamage(inst, target, weaponitem) or 0
    end
    if weaponitem == nil or not weaponitem:IsValid() or damage <= 25 then
        EquipCombatDefense(inst, target)
        if not IsAlive(target) or not IsAlive(inst) then return false end
        if not assisting and not self_defending and not priority then return false end
        local health = inst.components.health
        return priority or health == nil or health.GetPercent == nil or health:GetPercent() >= .15
    end
    -- Keep the hand slot stable while this target remains relevant. The
    -- survival loadout must not replace a weapon with an umbrella between
    -- combat ticks during rain.
    inst._my_friend_combat_hand_item = weaponitem
    inst._my_friend_combat_hand_until = _G.GetTime() + 4
    -- Snapshot evaluates combat before it assigns combat.target. Keep the
    -- loadout arbiter from immediately taking the weapon back for insulation.
    inst._my_friend_combat_equipment_target = target

    local enemycombat = target.components ~= nil and target.components.combat or nil
    local enemyhealth = target.components ~= nil and target.components.health or nil
    local health = inst.components.health
    local is_wanda = inst.prefab == "wanda" and inst.components.oldager ~= nil
    local enemyweapon = EquipCombatDefense(inst, target)
    if not IsAlive(target) or not IsAlive(inst) or not weaponitem:IsValid() then return false end
    if enemyweapon ~= nil and not enemyweapon:IsValid() then enemyweapon = nil end
    local absorption, armorcondition, protected = GetArmorStats(
        inventory, target, enemyweapon)
    if not IsAlive(target) or not IsAlive(inst) then return false end
    local leader = Policy.GetLeader(inst)
    local self_defending = M.IsThreat(inst, target)
    local assisting = leader ~= nil
        and (inst._my_friend_assist_scan ~= nil
                and inst._my_friend_assist_scan.target == target
            or M.GetLeaderAttackCount(inst, target) > 0)
        and Policy.InRange(inst, inst, M.ASSIST_RANGE)
        and Policy.InRange(inst, target, M.ASSIST_RANGE)
        and DistanceSq(inst, target) <= M.ASSIST_RANGE * M.ASSIST_RANGE
    -- Assistance is deliberately more decisive than self-defence. Once the
    -- companion has a working weapon and armour, it helps the leader instead
    -- of waiting for the conservative damage/survival estimate to pass.
    if assisting or self_defending or priority then
        return priority or is_wanda or health == nil or health.GetPercent == nil
            or health:GetPercent() >= .15
    end
    if damage <= 25 or not protected then return false end
    -- Wanda's remaining years are not ordinary hit points. Low remaining
    -- years increase her weapon damage; the watch behaviour handles healing.
    if is_wanda then return true end
    if enemycombat == nil or enemyhealth == nil or health == nil then return true end
    if health.GetPercent ~= nil and health:GetPercent() < .15 then return false end

    local incoming = enemycombat.CalcDamage ~= nil
        and enemycombat:CalcDamage(inst, enemyweapon) or enemycombat.defaultdamage
    return M.EstimateFight(health.currenthealth, enemyhealth.currenthealth,
        damage, incoming, inst.components.combat.min_attack_period,
        enemycombat.min_attack_period, absorption, armorcondition)
end

-- Frame-level dodge monitoring needs a cheap combat eligibility check. Keep
-- weapon/armour scoring out of that loop; ownership and disarm still update now.
function M.CanContinueCombat(inst, target)
    if not IsAlive(inst) or not IsAlive(target)
        or not require("my_friend_combat_rules").CanAttack(target, inst)
        or inst.components.inventory == nil or inst.components.combat == nil
        or require("my_friend_equipment").FindDroppedCombatItem(inst) ~= nil then
        if inst ~= nil then inst._my_friend_combat_check = nil end
        return false
    end
    local inventory, now = inst.components.inventory, GetTime()
    local hand = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    local leader = Policy.GetLeader(inst)
    local low_health = inst.components.health.GetPercent ~= nil and inst.components.health:GetPercent() < .15
    local cached = inst._my_friend_combat_check
    if cached ~= nil and cached.target == target and cached.hand == hand
        and cached.leader == leader and cached.low_health == low_health
        and not IsWeaponBroken(hand) and now < cached.until_time then return cached.allowed end
    local allowed = M.CanCounterAttack(inst, target)
    inst._my_friend_combat_check = {target = target, hand = inventory:GetEquippedItem(EQUIPSLOTS.HANDS),
        leader = leader, low_health = low_health, allowed = allowed, until_time = now + .25}
    return allowed
end

function M.ShouldDodgeWindow(distance, attackrange, attacking,
        enemyincooldown, friendincooldown)
    return distance <= attackrange + 1.5
        and (attacking or friendincooldown and not enemyincooldown)
end

function M.GetDodgeTimeLimit(enemy_attack_period)
    return math.max(M.COMBAT_DODGE_MIN_TIME, math.min(M.COMBAT_DODGE_MAX_TIME,
        (enemy_attack_period or 2) * .35))
end

function M.ShouldCommitCounterAttack(friend_in_cooldown, dodge_elapsed,
    enemy_attack_period)
    return not friend_in_cooldown
        and (dodge_elapsed or 0) >= M.GetDodgeTimeLimit(enemy_attack_period)
end

function M.ShouldDodge(inst, target)
    if not IsAlive(inst) or not IsAlive(target) or inst.components.combat == nil then return false end
    local combat = target ~= nil and target.components ~= nil and target.components.combat or nil
    if combat == nil then return false end
    local distance = math.sqrt(DistanceSq(inst, target))
    local attackrange = combat.hitrange or combat.GetAttackRange ~= nil
        and combat:GetAttackRange() or combat.attackrange or 3
    attackrange = attackrange + inst:GetPhysicsRadius(0)
    local attacking = target.sg ~= nil
        and target.sg:HasAnyStateTag("attack", "abouttoattack")
    if attacking and target.GetAngleToPoint ~= nil
        and target.Transform ~= nil and target.Transform.GetRotation ~= nil then
        local facing = target.Transform:GetRotation()
        local toward = target:GetAngleToPoint(inst:GetPosition())
        local delta = math.abs((facing - toward + 180) % 360 - 180)
        -- A directional attack is only urgent when its current facing points
        -- at the companion. Area attacks remain urgent through the state tag.
        if delta > 75 and combat.hitrange == nil then attacking = false end
    end
    return M.ShouldDodgeWindow(distance, attackrange, attacking,
        combat.InCooldown ~= nil and combat:InCooldown() or false,
        inst.components.combat:InCooldown())
end

function M.GetCombatDodgeDistance(inst, target)
    if not IsAlive(inst) or not IsAlive(target) then return 3 end
    local combat = target ~= nil and target.components ~= nil and target.components.combat or nil
    if combat == nil then return 3 end
    local attackrange = combat.GetAttackRange ~= nil and combat:GetAttackRange()
        or combat.attackrange or 2
    local friendradius = inst.GetPhysicsRadius ~= nil and inst:GetPhysicsRadius(0) or 0
    return attackrange + friendradius + M.COMBAT_DODGE_PADDING
end

function M.GetLeaderSafetyPoint(inst)
    if Policy.IsRoaming(inst) then return end
    local follower = inst.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    if leader ~= nil and leader:IsValid()
        and DistanceSq(inst, leader) > M.LEADER_RETURN_DISTANCE * M.LEADER_RETURN_DISTANCE then
        return leader:GetPosition()
    end
end

return M
