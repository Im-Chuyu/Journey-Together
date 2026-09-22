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
M.LEADER_RETURN_DISTANCE = 20
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

local function DistanceSq(a, b)
    local ax, _, az = a.Transform:GetWorldPosition()
    local bx, _, bz = b.Transform:GetWorldPosition()
    local dx, dz = bx - ax, bz - az
    return dx * dx + dz * dz
end

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

function M.GetResourceAction(inst)
    if not CanAct(inst) then return end
    local state = inst._my_friend_resource_needs or {}
    inst._my_friend_resource_needs = state
    for prefab in pairs(RESOURCE_PRODUCTS) do
        local count = M.CountResource(inst, prefab)
        local minimum = (prefab == "cutgrass" or prefab == "twigs") and 2 or 0
        local target = count < minimum and minimum or M.RESOURCE_MAX
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

function M.GetFoodOrResourceAction(inst)
    if not CanAct(inst) or inst.components.eater == nil then return end
    local needs_food = FoodAI.NeedsFoodSupply(inst)
    local following = Policy.GetLeader(inst) ~= nil
    local state = inst._my_friend_resource_needs or {}
    inst._my_friend_resource_needs = state
    for prefab in pairs(RESOURCE_PRODUCTS) do
        local count = M.CountResource(inst, prefab)
        local target = following and (Reserves.FOLLOW_TARGETS[prefab] or 0) or M.RESOURCE_MAX
        state[prefab] = count < target
    end
    local grass = M.CountResource(inst, "cutgrass")
    local twigs = M.CountResource(inst, "twigs")
    local minimum_missing = grass < 2 or twigs < 2
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
        if needs_food and CanPickUp(inst, item) and item.components.edible ~= nil
            and inst.components.eater:CanEat(item) then
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
        if CanPickUp(inst, item) and item.components.edible ~= nil
            and inst.components.eater:CanEat(item) and HasFoodRoom(item.prefab) then
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

function M.FindAssistTarget(inst)
    local leader = Policy.GetLeader(inst)
    if leader == nil or not Policy.InRange(inst, inst, 32) then return end
    local x, y, z = leader.Transform:GetWorldPosition()
    local function ValidTarget(entity)
        return entity ~= nil and entity ~= inst and entity ~= leader and IsAlive(entity)
            and not entity:HasAnyTag("player", "my_friend", "structure", "wall")
            and entity.components ~= nil and entity.components.combat ~= nil
            and Policy.InRange(inst, entity, 32)
    end
    local leader_target = leader.components ~= nil and leader.components.combat ~= nil
        and leader.components.combat.target or nil
    if ValidTarget(leader_target) then return leader_target end

    local best, distance
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, 32, {"_combat"}, THREAT_CANT_TAGS)) do
        if ValidTarget(entity) and (entity.components.combat.target == leader
            or entity.components.combat.target == inst
            or M.GetLeaderAttackCount(inst, entity) > 0) then
            if entity == inst._my_friend_assist_target then return entity end
            local d = inst:GetDistanceSqToInst(entity)
            if distance == nil or d < distance then best, distance = entity, d end
        end
    end
    return best
end

function M.StartHurtRetreat(inst, source)
    if source == nil or not source:IsValid() or not IsAlive(inst)
        or inst:HasTag("playerghost") then return end
    -- Repeated damage within one retreat must not move its origin or extend it.
    if GetTime() < (inst._my_friend_hurt_evade_until or 0) then return end
    inst._my_friend_hurt_position = inst:GetPosition()
    inst._my_friend_hurt_attacker = source
    inst._my_friend_hurt_source = source:GetPosition()
    inst._my_friend_hurt_destination = nil
    inst._my_friend_hurt_until = GetTime() + 3
    inst._my_friend_hurt_evade_until = GetTime() + 3.5
    inst._my_friend_assist_target = nil
    inst.components.combat:SetTarget(nil)
    require("my_friend_container_ai").Cancel(inst)
    -- Let the utility selector cancel its old node after the hit animation.
    inst._my_friend_replan_requested = true
end

function M.ObservePlayerAttack(inst)
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
    local heading = source ~= nil
        and math.atan2(current.z - source.z, current.x - source.x) or math.random() * 2 * math.pi
    for i = 1, 12 do
        local offset = math.ceil((i - 1) / 2) * (i % 2 == 0 and 1 or -1)
        local angle = heading + offset * 2 * math.pi / 12
        local point = inst._my_friend_hurt_destination
            or Vector3(origin.x + math.cos(angle) * 3, 0, origin.z + math.sin(angle) * 3)
        local allowed = leader == nil or Policy.IsRoaming(inst)
        if leader ~= nil and not Policy.IsRoaming(inst) then
            local p = leader:GetPosition()
            allowed = (point.x - p.x)^2 + (point.z - p.z)^2 <= 36
        end
        if allowed and TheWorld.Map:IsPassableAtPoint(point.x, 0, point.z)
            and not Navigation.IsNearHole(point)
            and (source == nil or (point.x - source.x)^2 + (point.z - source.z)^2
                > (current.x - source.x)^2 + (current.z - source.z)^2)
            and Navigation.IsClear(current, point, Navigation.Caps(inst)) then
            inst._my_friend_hurt_destination = point
            local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point)
            action.arrivedist = .25
            local function Finish()
                inst._my_friend_hurt_until = 0
                inst._my_friend_hurt_evade_until = math.min(
                    inst._my_friend_hurt_evade_until or 0, GetTime() + .5)
            end
            action:AddSuccessAction(Finish)
            action:AddFailAction(Finish)
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
        if now - record.time > 120 then records[owner] = nil end
    end
    local key = player.userid or player
    local old = records[key]
    records[key] = {count = (old ~= nil and old.count or 0) + 1, time = now}
end

function M.GetLeaderAttackCount(inst, target)
    local leader = Policy.GetLeader(inst)
    if leader == nil or target == nil or not target:IsValid() or not IsAlive(target)
        or target:HasAnyTag("structure", "wall", "INLIMBO", "player", "my_friend") then return 0 end
    local records = target._my_friend_player_attacks
    local record = records ~= nil and records[leader.userid or leader] or nil
    return record ~= nil and GetTime() - record.time <= 120 and record.count or 0
end

function M.FindThreat(inst, range)
    local x, y, z = inst.Transform:GetWorldPosition()
    local closest, closestscore
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, range or M.THREAT_RANGE,
        {"_combat"}, THREAT_CANT_TAGS)) do
        local ignored_attacker = GetTime() < (inst._my_friend_hurt_until or 0)
            and entity == inst._my_friend_hurt_attacker
            and entity:HasTag("player")
        if not ignored_attacker then
            local attacks = M.GetLeaderAttackCount(inst, entity)
            if not entity:HasTag("player")
                and (M.IsThreat(inst, entity) or attacks > 0) then
                local dist = DistanceSq(inst, entity)
                -- Prefer the creature the leader has actually been attacking.
                local score = attacks * 1000000 - dist
                if closestscore == nil or score > closestscore then
                    closest, closestscore = entity, score
                end
            end
        end
    end
    return closest
end

local function HasWorkingArmor(item)
    local armor = item ~= nil and item.components ~= nil and item.components.armor or nil
    return armor ~= nil and (armor.indestructible or armor.condition == nil or armor.condition > 0)
end

local function IsActiveLight(item)
    return item ~= nil and (item._my_friend_ai_light
        or item._my_friend_manual_light_until ~= nil
        or item.HasAnyTag ~= nil and item:HasAnyTag("light", "nightvision"))
end

local function WeaponDamage(inst, target, item)
    local weapon = item ~= nil and item.components ~= nil and item.components.weapon or nil
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
    if item == nil or item.components == nil then return true end
    if item:HasTag("broken") then return true end
    local finite = item.components.finiteuses
    if finite ~= nil and finite:GetUses() <= 0 then return true end
    local fueled = item.components.fueled
    return fueled ~= nil and fueled:IsEmpty()
end

function M.FindBestCombatWeapon(inst, target)
    local inventory = inst.components.inventory
    if inventory == nil then return end
    local best = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if IsWeaponBroken(best) then best = nil end
    local bestdamage = WeaponDamage(inst, target, best) or 0
    if inventory.ReferenceAllItems ~= nil then
        for _, item in ipairs(inventory:ReferenceAllItems()) do
            local equippable = item.components ~= nil and item.components.equippable or nil
            local damage = not IsWeaponBroken(item)
                and WeaponDamage(inst, target, item) or nil
            if damage ~= nil and damage > bestdamage
                and equippable ~= nil and equippable.equipslot == EQUIPSLOTS.HANDS
                and (equippable.IsRestricted == nil or not equippable:IsRestricted(inst)) then
                best, bestdamage = item, damage
            end
        end
    end
    return best, bestdamage
end

local function GetArmorValue(inst, item, slot, attacker, weapon)
    if not HasWorkingArmor(item) then return end
    local equippable = item.components.equippable
    if equippable == nil or equippable.equipslot ~= slot
        or equippable.IsRestricted ~= nil and equippable:IsRestricted(inst) then
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

function M.GetThermalInsulation(item, need)
    return require("my_friend_survival_ai").GetInsulationValue(item, need) ~= nil
end

local function IsBetterArmor(absorption, condition, bestabsorption, bestcondition)
    return bestabsorption == nil or absorption > bestabsorption
        or absorption == bestabsorption and condition > bestcondition
end

function M.FindBestCombatArmor(inst, slot, attacker, weapon, thermal_need)
    local inventory = inst.components.inventory
    if inventory == nil then return end
    local best = inventory:GetEquippedItem(slot)
    if thermal_need ~= nil and not M.GetThermalInsulation(best, thermal_need) then
        best = nil
    end
    local bestabsorption, bestcondition =
        GetArmorValue(inst, best, slot, attacker, weapon)
    if inventory.ReferenceAllItems ~= nil then
        for _, item in ipairs(inventory:ReferenceAllItems()) do
            if thermal_need == nil or M.GetThermalInsulation(item, thermal_need) then
                local absorption, condition =
                    GetArmorValue(inst, item, slot, attacker, weapon)
                if absorption ~= nil and IsBetterArmor(absorption, condition,
                    bestabsorption, bestcondition) then
                    best, bestabsorption, bestcondition = item, absorption, condition
                end
            end
        end
    end
    return best, bestabsorption, bestcondition
end

function M.EquipBestCombatArmor(inst, attacker, weapon)
    local inventory = inst.components.inventory
    if inventory == nil or inventory.Equip == nil then return end
    -- Ordinary warmth/cooling equipment is allowed to give way to combat
    -- gear. Preserve it only when the body is actually taking temperature
    -- damage, rather than merely being above the equipment threshold.
    local thermal_need = require("my_friend_survival_ai").GetThermalNeed(inst)
    for _, slot in ipairs(require("my_friend_equip_slots").All()) do
        if slot ~= EQUIPSLOTS.HANDS then
            local current = inventory:GetEquippedItem(slot)
            -- When temperature protection is active, prefer armour that also
            -- insulates. If no such armour exists, retain a currently worn
            -- insulating item instead of stripping it for ordinary armour.
            local best = M.FindBestCombatArmor(inst, slot, attacker, weapon,
                thermal_need)
            if best == nil and (current == nil
                or not M.GetThermalInsulation(current, thermal_need)) then
                best = M.FindBestCombatArmor(inst, slot, attacker, weapon)
            end
            local currentproof = current ~= nil and current.components ~= nil
                and current.components.waterproofer ~= nil
                and current.components.waterproofer:GetEffectiveness() >= 1
            local bestproof = best ~= nil and best.components ~= nil
                and best.components.waterproofer ~= nil
                and best.components.waterproofer:GetEffectiveness() >= 1
            -- Full rain protection is already complete. Do not trade it for
            -- ordinary armour during every combat re-evaluation.
            if currentproof and not bestproof then best = current end
            if thermal_need ~= nil and current ~= nil
                and M.GetThermalInsulation(current, thermal_need)
                and (best == nil or not M.GetThermalInsulation(best, thermal_need)) then
                best = current
            end
            if best ~= nil and best ~= current then
                if current ~= nil
                    and current.HasTag ~= nil and current:HasTag("backpack") then
                    inventory:DropItem(current, true, false, inst:GetPosition())
                end
                inventory:Equip(best)
            end
        end
    end
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
            if amount ~= nil and amount > 0 then
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
    if target == nil or inst.components.inventory == nil or inst.components.combat == nil then
        return false
    end
    local inventory = inst.components.inventory
    local hand = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    local weaponitem, damage = M.FindBestCombatWeapon(inst, target)
    if weaponitem == nil or damage <= 25
        or weaponitem ~= hand and IsActiveLight(hand) then return false end
    if weaponitem ~= hand and inventory.Equip ~= nil then
        if inventory:Equip(weaponitem) ~= true then return false end
        weaponitem = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
        damage = WeaponDamage(inst, target, weaponitem) or 0
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
    local enemyweapon = enemycombat ~= nil and enemycombat.GetWeapon ~= nil
        and enemycombat:GetWeapon() or nil
    M.EquipBestCombatArmor(inst, target, enemyweapon)
    local absorption, armorcondition, protected = GetArmorStats(
        inventory, target, enemyweapon)
    local leader = Policy.GetLeader(inst)
    local leader_target = leader ~= nil and leader.components ~= nil
        and leader.components.combat ~= nil and leader.components.combat.target or nil
    local assisting = leader ~= nil and enemycombat ~= nil
        and (enemycombat.target == leader or leader_target == target
            or target == inst._my_friend_assist_target)
        and Policy.InRange(inst, inst, 32) and Policy.InRange(inst, target, 32)
    -- Assistance is deliberately more decisive than self-defence. Once the
    -- companion has a working weapon and armour, it helps the leader instead
    -- of waiting for the conservative damage/survival estimate to pass.
    if assisting then
        return health == nil or health.GetPercent == nil
            or health:GetPercent() >= .15
    end
    if damage <= 25 or not protected then return false end
    if enemycombat == nil or enemyhealth == nil or health == nil then return true end
    if health.GetPercent ~= nil and health:GetPercent() < .15 then return false end

    local incoming = enemycombat.CalcDamage ~= nil
        and enemycombat:CalcDamage(inst, enemyweapon) or enemycombat.defaultdamage
    return M.EstimateFight(health.currenthealth, enemyhealth.currenthealth,
        damage, incoming, inst.components.combat.min_attack_period,
        enemycombat.min_attack_period, absorption, armorcondition)
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
