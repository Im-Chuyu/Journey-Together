local LightAI = require("my_friend_light_ai")
local Navigation = require("my_friend_navigation")
local Home = require("my_friend_home")

local M = {}

M.COLD_START = 5
M.COLD_RECOVER = 15
M.HOT_START_MARGIN = 5
M.HOT_RECOVER_MARGIN = 15
-- Insulation goes on well before the companion is actually in danger, and
-- comes off again only after a wide margin so it never flaps between states.
M.COLD_EQUIPMENT_TEMP = 25
-- Cooling gear is only needed once the body is genuinely hot. Keeping this
-- above the normal warm-weather range also leaves room for combat equipment.
M.HOT_EQUIPMENT_TEMP = 55
M.COLD_EQUIPMENT_EXTREME = 5
M.HOT_EQUIPMENT_EXTREME = 60
M.COLD_EQUIPMENT_RELEASE = 32
-- Worn out gear is taken off and kept rather than destroyed on the body.
M.EQUIPMENT_WEAR_LIMIT = .05
M.THERMAL_SEARCH_RANGE = 20
M.MATERIAL_SEARCH_RANGE = 15
M.FIRE_CLEARANCE = 4
M.FIRE_POINT_SEARCH_RANGE = 14
M.FEATHERFAN_TEMPERATURE = 65
M.COOLING_SEARCH_RANGE = 24
M.TEMPERATURE_SOURCE_RANGE = 64
-- Shade discovery is demand driven.  The next temperature decision may
-- refresh this memory, but there is never a repeating scan task.
M.BASE_SHADE_SCAN_INTERVAL = 4 * 60

local THERMAL_CANT_TAGS = {
    "INLIMBO", "burnt", "playerghost",
}
local HEATER_RANGE = 10 -- Native temperature component's heater search and falloff radius.
local HEATER_TAGS = { "HASHEATER" }
local FIRE_TAGS = { "campfire" }
local SHADE_TAGS = { "shadecanopy", "shadecanopysmall" }

local PICKUP_CANT_TAGS = {
    "INLIMBO", "catchable", "fire", "heavy", "irreplaceable",
    "mineactive", "outofreach",
}

local FIRE_RISK_ONE_OF_TAGS = {
    "canlight", "structure", "tree",
}

local function IsAlive(inst)
    return inst ~= nil and inst:IsValid()
        and (inst.components.health == nil or not inst.components.health:IsDead())
end

local function CanAct(inst)
    return IsAlive(inst) and not inst:HasTag("playerghost")
        and inst.components.inventory ~= nil
        and not inst._my_friend_backpack_action
        and inst._my_friend_backpack_target == nil
        and not inst._my_friend_container_action
        and (inst.sg == nil or not inst.sg:HasStateTag("busy"))
end

function M.UpdateThermalNeed(current, overheat, previous)
    if previous == "cold" then
        return current < M.COLD_RECOVER and "cold" or nil
    elseif previous == "hot" then
        return current > overheat - M.HOT_RECOVER_MARGIN and "hot" or nil
    elseif current <= M.COLD_START then
        return "cold"
    elseif current >= overheat - M.HOT_START_MARGIN then
        return "hot"
    end
end

function M.GetThermalNeed(inst)
    local temperature = inst.components.temperature
    if temperature == nil then return end
    local leader = require("my_friend_policy").GetLeader(inst)
    -- A follower that has recovered from cold must resume following. Keep
    -- the normal hot-temperature branch available, however; this exception
    -- only releases a previously active cold-heating request.
    if leader ~= nil and temperature.current >= M.COLD_START
        and (inst._my_friend_thermal_need == "cold"
            or inst._my_friend_thermal_target_need == "cold") then
        M.StopForFollow(inst)
        inst._my_friend_thermal_need = nil
        inst._my_friend_cooling_target = nil
        inst._my_friend_thermal_target_need = nil
        return nil
    end
    -- Native canopy cooling levels off at overheattemp - 5, not at 55C.
    if M.IsUnderRememberedShade(inst) and (temperature.sheltered_level or 1) > 1
        and temperature.current > M.COLD_RECOVER
        and temperature.current <= temperature.overheattemp - 4.5
        and temperature.rate <= 0 then
        inst._my_friend_thermal_need = nil
        return
    end
    inst._my_friend_thermal_need = M.UpdateThermalNeed(
        temperature.current, temperature.overheattemp,
        inst._my_friend_thermal_need)
    return inst._my_friend_thermal_need
end

function M.StopForFollow(inst)
    local target = inst._my_friend_cooling_target
    local cold_request = inst._my_friend_thermal_target_need == "cold"
        or inst._my_friend_thermal_need == "cold"
    if not cold_request then return end
    local action = inst.GetBufferedAction ~= nil and inst:GetBufferedAction() or nil
    if action ~= nil and (action.target == target or action._my_friend_temperature_action) then
        action._my_friend_cancelled = true
        if inst.ClearBufferedAction ~= nil then inst:ClearBufferedAction() end
    end
    inst._my_friend_cooling_target = nil
    inst._my_friend_thermal_target_need = nil
end

local function SetThermalTarget(inst, target, need)
    inst._my_friend_cooling_target = target
    inst._my_friend_thermal_target_need = need
end

local function MarkTemperatureAction(action)
    if action ~= nil then action._my_friend_temperature_action = true end
    return action
end

function M.NeedsTemperatureHelp(inst)
    return M.GetThermalNeed(inst) ~= nil
        or M.HasUsableFeatherfan(inst)
end

function M.HasUsableFeatherfan(inst)
    local temperature = inst ~= nil and inst.components ~= nil
        and inst.components.temperature or nil
    if temperature == nil or temperature.current <= M.FEATHERFAN_TEMPERATURE then
        return false
    end
    local inventory = inst ~= nil and inst.components ~= nil
        and inst.components.inventory or nil
    if inventory == nil then return false end
    for _, item in ipairs(inventory:ReferenceAllItems()) do
        if item.prefab == "featherfan" and item.components ~= nil
            and item.components.fan ~= nil
            and item.components.finiteuses ~= nil
            and item.components.finiteuses:GetUses() > 0 then
            return true
        end
    end
    return false
end

function M.GetTemperatureEquipmentNeed(current)
    if type(current) ~= "number" then return end
    return current <= M.COLD_EQUIPMENT_TEMP and "cold"
        or current >= M.HOT_EQUIPMENT_TEMP and "hot" or nil
end

-- Cold gear keeps its small hysteresis. Cooling gear uses only the requested
-- 55 degree start threshold, so it is not kept on after the temperature drops.
function M.UpdateEquipmentThermalState(current, previous)
    if type(current) ~= "number" then return end
    if previous == "cold" then
        return current <= M.COLD_EQUIPMENT_RELEASE and "cold" or nil
    elseif previous == "hot" then
        return current >= M.HOT_EQUIPMENT_TEMP and "hot" or nil
    end
    return M.GetTemperatureEquipmentNeed(current)
end

function M.GetEquipmentThermalNeed(inst)
    local temperature = inst ~= nil and inst.components ~= nil
        and inst.components.temperature or nil
    if temperature == nil then
        if inst ~= nil then inst._my_friend_thermal_equipment_state = nil end
        return
    end
    local worldstate = TheWorld ~= nil and TheWorld.state or nil
    local season = worldstate ~= nil and worldstate.iswinter and "winter"
        or worldstate ~= nil and worldstate.issummer and "summer" or "normal"
    if inst._my_friend_thermal_equipment_season ~= season then
        inst._my_friend_thermal_equipment_season = season
        inst._my_friend_thermal_equipment_state = nil
    end
    if season == "winter" then
        -- Winter keeps warm gear by default. Only extreme heat releases it
        -- and asks the normal loadout arbiter for cooling gear instead.
        inst._my_friend_thermal_equipment_state = temperature.current
            >= M.HOT_EQUIPMENT_EXTREME and "hot" or "cold"
    elseif season == "summer" then
        -- Summer keeps cooling gear by default. Only extreme cold releases it
        -- and asks for warm gear instead.
        inst._my_friend_thermal_equipment_state = temperature.current
            <= M.COLD_EQUIPMENT_EXTREME and "cold" or "hot"
    else
        -- Spring, autumn and non-seasonal worlds retain the original 25/55
        -- start thresholds and their existing hysteresis.
        inst._my_friend_thermal_equipment_state = M.UpdateEquipmentThermalState(
            temperature.current, inst._my_friend_thermal_equipment_state)
    end
    return inst._my_friend_thermal_equipment_state
end

-- Smallest remaining fraction across every wear mechanic an item may use.
function M.GetDurabilityPercent(item)
    local components = item ~= nil and item.components or nil
    if components == nil then return end
    local lowest
    for _, name in ipairs({"finiteuses", "fueled", "armor", "perishable"}) do
        local component = components[name]
        if component ~= nil and component.GetPercent ~= nil then
            local value = component:GetPercent()
            if type(value) == "number" and value == value
                and (lowest == nil or value < lowest) then
                lowest = value
            end
        end
    end
    return lowest
end

function M.IsWornOut(item)
    local percent = M.GetDurabilityPercent(item)
    return percent ~= nil and percent < M.EQUIPMENT_WEAR_LIMIT
end

function M.GetInsulationValue(item, need)
    local insulator = item ~= nil and item.components ~= nil
        and item.components.insulator or nil
    local equippable = item ~= nil and item.components ~= nil
        and item.components.equippable or nil
    if insulator == nil or equippable == nil then return end
    local wanted = need == "cold" and SEASONS.WINTER
        or need == "hot" and SEASONS.SUMMER or nil
    local value, insulation_type = insulator:GetInsulation()
    return insulation_type == wanted and type(value) == "number" and value > 0
        and value or nil
end

local function GetRootEntity(entity)
    local root = entity
    for _ = 1, 5 do
        local parent = root.entity ~= nil and root.entity:GetParent() or nil
        if parent == nil then break end
        root = parent
    end
    return root
end

local function GetDamageDistance(source)
    local distance = 0
    local entity = source
    for _ = 1, 6 do
        if entity:HasTag("campfire") then return 0 end
        if entity:HasTag("lava") then distance = math.max(distance, 6) end
        if entity.prefab == "fire" or entity.prefab == "lavalight"
            or entity.prefab == "character_fire" then
            distance = math.max(distance, 4)
        end
        local propagator = entity.components ~= nil and entity.components.propagator or nil
        if propagator ~= nil and propagator.damages then
            distance = math.max(distance, (propagator.damagerange or 3) + 1)
        end
        entity = entity.entity ~= nil and entity.entity:GetParent() or nil
        if entity == nil then break end
    end
    return distance
end

local function IsHostileHeater(inst, source)
    local root = GetRootEntity(source)
    local combat = root.components ~= nil and root.components.combat or nil
    return root ~= inst and combat ~= nil
        and combat.target == inst
end

function M.GetFireDangerRadius(source)
    if source == nil or not source:IsValid() then return 0 end
    local propagator = source.components ~= nil and source.components.propagator or nil
    if propagator ~= nil and not propagator.spreading then return 0 end
    local distance = GetDamageDistance(source)
    if distance > 0 and propagator ~= nil and propagator.damages then
        local multiplier = TheWorld.state.isspring and (TUNING.SPRING_FIRE_RANGE_MOD or 1) or 1
        distance = math.max(distance, (propagator.damagerange or 3) * multiplier + 1)
    end
    return distance
end

local function GetHeater(inst, source)
    if source == inst or not source:IsValid() or source:IsInLimbo() then return end
    local temperature = inst.components.temperature
    if temperature.ignoreheatertags ~= nil and source:HasAnyTag(temperature.ignoreheatertags) then return end
    return source.components.heater
end

function M.GetHotHeaterDangerRadius(inst, source, threshold)
    local heater = GetHeater(inst, source)
    local heat = heater ~= nil and heater:GetHeat(inst) or nil
    if type(heat) ~= "number" or not heater:IsExothermic() then return 0 end
    if inst:GetIsWet() then heat = heat * (TUNING.WET_HEAT_FACTOR_PENALTY or .75) end
    threshold = threshold or inst.components.temperature.overheattemp
    if heat <= threshold then return 0 end
    local radius = math.min(HEATER_RANGE, heater:GetHeatRadiusCutoff() or HEATER_RANGE)
    if heater:ShouldFalloff() then
        radius = math.min(radius, HEATER_RANGE * math.sqrt(1 - threshold / heat))
    end
    return radius
end

function M.FindDamagingHeatSource(inst, fire_only, cold)
    local x, y, z = inst.Transform:GetWorldPosition()
    local best, bestscore
    local temperature = inst.components.temperature
    if not fire_only and not cold then
        -- Overheating ticks also happen while cooling. Only an active heater
        -- that can still raise body temperature here warrants a retreat.
        if temperature == nil or (temperature.rate or 0) <= 0 then return end
        for _, source in ipairs(TheSim:FindEntities(x, y, z, HEATER_RANGE,
            HEATER_TAGS, THERMAL_CANT_TAGS)) do
            local radius = M.GetHotHeaterDangerRadius(inst, source, temperature.current)
            local distance = inst:GetDistanceSqToInst(source)
            if radius > 0 and distance < radius^2 and (bestscore == nil or distance < bestscore) then
                best, bestscore = source, distance
            end
        end
        return best, best ~= nil and M.GetHotHeaterDangerRadius(inst, best) or nil
    end
    for _, source in ipairs(TheSim:FindEntities(x, y, z, 16, nil, THERMAL_CANT_TAGS)) do
        if source ~= inst and source.entity:GetParent() == nil then
            local heater = source.components.heater
            local heat = heater ~= nil and heater:GetHeat(inst) or nil
            local damage = cold and 0
                or fire_only and M.GetFireDangerRadius(source) or GetDamageDistance(source)
            local cutoff = heater ~= nil and (heater:GetHeatRadiusCutoff() or 10) or damage
            local p = source:GetPosition()
            local distance = (p.x - x)^2 + (p.z - z)^2
            local temperature_damage = not fire_only and temperature ~= nil and heat ~= nil
                and heater:IsEndothermic() and heat < temperature.current
            if (damage > 0 or temperature_damage)
                and distance < (fire_only and damage or math.max(cutoff, damage))^2 then
                local score = distance - damage * 2
                if bestscore == nil or score < bestscore then best, bestscore = source, score end
            end
        end
    end
    return best, best ~= nil and M.GetFireDangerRadius(best) or nil
end

function M.GetTemperatureDangerRadius(inst, source, cold)
    local override = source ~= nil and source:IsValid() and source.components.temperatureoverrider or nil
    local temperature = inst.components.temperature
    if override == nil or temperature == nil then return 0 end
    local radius, value = override:GetActiveRadius(), override:GetTemperature()
    if radius > 0 and (cold and value < 0 or not cold and value > temperature.overheattemp) then
        -- The ward's broad ambient cooling can be offset by heaters. Only
        -- its ground ice directly clamps body temperature every frame.
        if cold and source.prefab == "deerclopseyeball_sentryward" then
            radius = math.min(radius, TUNING.DEERCLOPSEYEBALL_SENTRYWARD_GROUND_ICE_RADIUS or 3.5)
        end
        return radius
    end
    return 0
end

function M.FindDamagingTemperatureSource(inst, cold)
    local x, y, z = inst.Transform:GetWorldPosition()
    local closest, bestdistance
    for _, source in ipairs(TheSim:FindEntities(x, y, z, M.TEMPERATURE_SOURCE_RANGE, nil, THERMAL_CANT_TAGS)) do
        local override = source:IsValid() and source.components.temperatureoverrider or nil
        if override ~= nil then
            local point = source:GetPosition()
            local distance = (point.x - x)^2 + (point.z - z)^2
            if distance <= override:GetActiveRadius()^2 and override:GetActiveRadius() > 0
                and (bestdistance == nil or distance < bestdistance) then
                closest, bestdistance = source, distance
            end
        end
    end
    local radius = closest ~= nil and M.GetTemperatureDangerRadius(inst, closest, cold) or 0
    if radius > 0 and bestdistance <= radius^2 then return closest, radius end
end

local function GetSourceData(inst, source, need)
    local heater = GetHeater(inst, source)
    if heater == nil or IsHostileHeater(inst, source) then return end
    local heat = heater:GetHeat(inst)
    local current = inst.components.temperature.current
    if type(heat) ~= "number"
        or need == "cold" and (not heater:IsExothermic() or heat <= current)
        or need == "hot" and (not heater:IsEndothermic() or heat >= current) then
        return
    end
    local damage_distance = GetDamageDistance(source)
    local distance = damage_distance > 0 and damage_distance or 2
    local cutoff = heater:GetHeatRadiusCutoff() or HEATER_RANGE
    if need == "hot" then
        -- Native temperature gives exothermic mode precedence.
        if heater:IsExothermic() then return end
        cutoff = math.min(cutoff, HEATER_RANGE)
        distance = math.min(distance, cutoff * .75)
    end
    if distance >= cutoff then return end
    return heat, distance, damage_distance > 0
end

local function CanApproachCoolingPoint(inst, point)
    return Navigation.InTravelRange(inst, point) and not Navigation.IsBlocked(inst, point)
        and not require("my_friend_behavior_ai").IsHazardousPath(inst, point, point)
end

function M.FindThermalSource(inst, need)
    need = need or M.GetThermalNeed(inst)
    if need == nil then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local best, bestdistance, besthazardous, bestscore
    local range = need == "hot" and M.COOLING_SEARCH_RANGE or M.THERMAL_SEARCH_RANGE
    local sources
    if need == "hot" then
        local cached = inst._my_friend_cooling_scan
        local now = GetTime()
        if cached == nil or now >= cached.untiltime or (x - cached.x)^2 + (z - cached.z)^2 >= 3^2 then
            cached = {x = x, z = z, untiltime = now + 1.5,
                sources = TheSim:FindEntities(x, y, z, range, HEATER_TAGS, THERMAL_CANT_TAGS)}
            inst._my_friend_cooling_scan = cached
        end
        sources = cached.sources
    else
        sources = TheSim:FindEntities(x, y, z, range, HEATER_TAGS, THERMAL_CANT_TAGS)
    end
    for _, source in ipairs(sources) do
        if source ~= inst then
            local heat, distance, hazardous = GetSourceData(inst, source, need)
            if heat ~= nil then
                local distancesq = inst:GetDistanceSqToInst(source)
                if distancesq <= range^2 and (need ~= "hot"
                    or (distancesq > (distance + .5)^2 or inst.components.temperature.rate < 0)
                        and CanApproachCoolingPoint(inst, source:GetPosition())) then
                    local score = distancesq + (hazardous and 12 or 0)
                        - math.min(math.abs(heat - inst.components.temperature.current), 100) * .05
                    if bestscore == nil or score < bestscore then
                        best, bestdistance, besthazardous, bestscore =
                            source, distance, hazardous, score
                    end
                end
            end
        end
    end
    return best, bestdistance, besthazardous
end

local function IsShadeTree(tree)
    return tree ~= nil and tree:IsValid()
        and tree:HasAnyTag("shadecanopy", "shadecanopysmall")
        and not tree:HasAnyTag("INLIMBO", "burnt", "stump", "fire")
        and (tree._hascanopy == nil or tree._hascanopy:value())
end

local function ShadeRadius(tree)
    local range = tree ~= nil and tree:HasTag("shadecanopy")
        and (TUNING.SHADE_CANOPY_RANGE or 28)
        or (TUNING.SHADE_CANOPY_RANGE_SMALL or 22)
    return math.max(3, range - 2)
end

function M.IsUnderRememberedShade(inst, point)
    if TheWorld == nil or TheWorld.state == nil or not TheWorld.state.issummer then
        return false
    end
    local tree = inst._my_friend_shade_tree
    local remembered = inst._my_friend_shade_base
    local base = inst._my_friend_home or inst._my_friend_base
    if remembered ~= nil and base ~= nil
        and (remembered.x ~= base.x or remembered.z ~= base.z) then return false end
    return IsShadeTree(tree) and (point ~= nil and tree:GetDistanceSqToPoint(point)
        or inst:GetDistanceSqToInst(tree)) <= ShadeRadius(tree) ^ 2
end

-- Keep the model's comfort check cache-only.
function M.IsShadeComfortOnly(inst)
    if TheWorld == nil or TheWorld.state == nil or not TheWorld.state.issummer
        or inst == nil or inst.components == nil
        or inst.components.temperature == nil then return false end
    local temperature = inst.components.temperature
    if temperature.current >= temperature.overheattemp
        or inst._my_friend_under_threat then return false end
    if M.GetThermalNeed(inst) ~= "hot" then return false end
    local tree = inst._my_friend_shade_tree
    local base = Home.Get(inst) or require("my_friend_base_ai").GetBasePoint(inst)
    return IsShadeTree(tree) and base ~= nil
        and inst:GetDistanceSqToPoint(base) <= Home.Radius(inst) ^ 2
        and Home.IsPointInRange(inst, inst:GetPosition())
        and inst._my_friend_shade_point ~= nil
        and CanApproachCoolingPoint(inst, inst._my_friend_shade_point)
        and not M.IsUnderRememberedShade(inst)
end

function M.ConfigureShelter(inst)
    local sheltered = inst.components.sheltered
    if sheltered == nil or sheltered._my_friend_shade_hook then return end
    sheltered._my_friend_shade_hook = true
    local update = sheltered.OnUpdate
    sheltered.OnUpdate = function(self, dt)
        if not inst:HasTag("my_friend") then return update(self, dt) end
        local count = inst.canopytrees
        if M.IsUnderRememberedShade(inst) then
            inst.canopytrees = (count or 0) + 1
        end
        update(self, dt)
        inst.canopytrees = count
        -- Native sheltered only sends the event on entry/exit. The level
        -- can still change while moving between two overlapping shelters.
        if inst.components.temperature ~= nil then
            inst.components.temperature.sheltered_level = self.sheltered_level
        end
    end
end

local function FindShadePoint(inst, tree, base)
    local tx, _, tz = tree.Transform:GetWorldPosition()
    local origin = inst:GetPosition()
    local heading = math.atan2(origin.z - tz, origin.x - tx)
    local edge = ShadeRadius(tree)
    local caps = Navigation.Caps(inst)
    local needs_light = LightAI.IsDark(inst)
    for _, radius in ipairs({edge - 1, edge * .65, edge * .35}) do
        for i = 0, 15 do
            local angle = heading + i * PI2 / 16
            local point = Vector3(tx + math.cos(angle) * radius, 0, tz + math.sin(angle) * radius)
            if (point.x - base.x)^2 + (point.z - base.z)^2 <= Home.Radius(inst)^2
                and CanApproachCoolingPoint(inst, point) and Navigation.IsLand(point)
                and Navigation.IsStepClear(inst, point, point, caps)
                and (not needs_light or LightAI.IsPointExternallyLit(inst, point)) then
                return point
            end
        end
    end
end

local function FindBaseShade(inst)
    if not TheWorld.state.issummer then return end
    local base = Home.Get(inst) or require("my_friend_base_ai").GetBasePoint(inst)
    local origin = inst:GetPosition()
    if base == nil or inst:GetDistanceSqToPoint(base) > Home.Radius(inst) ^ 2
        or not Home.IsPointInRange(inst, origin) then return end

    local remembered_base = inst._my_friend_shade_base
    if remembered_base == nil or remembered_base.x ~= base.x
        or remembered_base.z ~= base.z then
        inst._my_friend_shade_base = {x = base.x, z = base.z}
        inst._my_friend_shade_tree = nil
        inst._my_friend_shade_point = nil
        inst._my_friend_shade_scan_after = nil
    end

    local tree = inst._my_friend_shade_tree
    local now = GetTime()
    if now < (inst._my_friend_shade_scan_after or 0) then
        if M.IsUnderRememberedShade(inst) then return tree, origin end
        local point = inst._my_friend_shade_point
        if IsShadeTree(tree) and point ~= nil and CanApproachCoolingPoint(inst, point) then
            if not LightAI.IsDark(inst) or LightAI.IsPointExternallyLit(inst, point) then
                return tree, point
            end
            return
        end
        -- A lost tree or a blocked cached route gets a fresh search.
        if tree == nil then return end
    end

    local candidates = {}
    -- A coastal tree can be outside the base and still shade walkable land.
    for _, entity in ipairs(TheSim:FindEntities(base.x, 0, base.z,
        Home.Radius(inst) + (TUNING.SHADE_CANOPY_RANGE or 28),
        nil, THERMAL_CANT_TAGS, SHADE_TAGS)) do
        if IsShadeTree(entity) then
            local radius = ShadeRadius(entity)
            if entity:GetDistanceSqToPoint(base) < (Home.Radius(inst) + radius)^2 then
                local distance = math.sqrt(inst:GetDistanceSqToInst(entity))
                candidates[#candidates + 1] = {tree = entity,
                    score = math.max(0, distance - radius) + (entity:HasTag("shadecanopy") and 0 or 1)}
            end
        end
    end
    table.sort(candidates, function(a, b) return a.score < b.score end)
    for _, candidate in ipairs(candidates) do
        tree = candidate.tree
        local point = tree:GetDistanceSqToPoint(origin) <= ShadeRadius(tree)^2
            and origin or FindShadePoint(inst, tree, base)
        if point ~= nil then
            inst._my_friend_shade_tree, inst._my_friend_shade_point = tree, point
            inst._my_friend_shade_scan_after = now + M.BASE_SHADE_SCAN_INTERVAL
            return tree, point
        end
    end
    inst._my_friend_shade_tree, inst._my_friend_shade_point = nil, nil
    inst._my_friend_shade_scan_after = now + (#candidates == 0 and M.BASE_SHADE_SCAN_INTERVAL or 20)
end

M.FindBaseShade = FindBaseShade

local function GetShadeAction(inst, tree, point)
    local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point)
    action.validfn = function() return TheWorld.state.issummer and IsShadeTree(tree) end
    return MarkTemperatureAction(action)
end

local function CanCoolInShade(inst, temperature)
    return M.IsUnderRememberedShade(inst)
        and ((temperature.sheltered_level or 1) < 2 or temperature.rate < 0)
end

local function DistanceSq(inst, target)
    local x, _, z = inst.Transform:GetWorldPosition()
    local tx, _, tz = target.Transform:GetWorldPosition()
    local dx, dz = tx - x, tz - z
    return dx * dx + dz * dz
end

local function IsCoolingInPlace(inst, temperature)
    if CanCoolInShade(inst, temperature) then return true end
    local target = inst._my_friend_cooling_target
    if target == nil or not target:IsValid() or inst._my_friend_thermal_target_need ~= "hot" then
        return false
    end
    local _, distance, hazardous = GetSourceData(inst, target, "hot")
    local distancesq = DistanceSq(inst, target)
    return distance ~= nil and temperature.rate < 0 and distancesq <= (distance + .5)^2
        and (not hazardous or distancesq >= math.max(.25, distance - .75)^2)
end

function M.IsNearThermalSource(inst)
    local need = M.GetThermalNeed(inst)
    if need == "hot" then return IsCoolingInPlace(inst, inst.components.temperature) end
    if need == nil then return false end
    local source, distance, hazardous = M.FindThermalSource(inst, need)
    if source == nil then return false end
    local distancesq = DistanceSq(inst, source)
    return distancesq <= (distance + .75) ^ 2
        and (not hazardous or distancesq >= math.max(.25, distance - .75) ^ 2)
end

local function GetRetreatPoint(inst, source, distance)
    local x, y, z = inst.Transform:GetWorldPosition()
    local sx, _, sz = source.Transform:GetWorldPosition()
    local dx, dz = x - sx, z - sz
    local length = math.sqrt(dx * dx + dz * dz)
    if length < .01 then
        local angle = math.random() * PI2
        dx, dz, length = math.cos(angle), math.sin(angle), 1
    end
    local sourcepoint = Vector3(sx, y, sz)
    local angle = math.atan2 ~= nil and math.atan2(-dz, dx)
        or math.atan(-dz / dx) + (dx < 0 and PI or 0)
    local function IsSafeLandPoint(point)
        return TheWorld.Map:IsPassableAtPoint(point.x, point.y, point.z)
            and not Navigation.IsNearHole(point)
            and Navigation.IsClear(inst:GetPosition(), point, Navigation.Caps(inst))
    end
    local offset = FindWalkableOffset(sourcepoint, angle, distance, 12,
        false, true, IsSafeLandPoint, false, false, true)
    return offset ~= nil and sourcepoint + offset or nil
end

local function GetRecipe(inst, name)
    local builder = inst.components.builder
    local recipe = GetValidRecipe ~= nil and GetValidRecipe(name) or nil
    if builder == nil or recipe == nil or not builder:KnowsRecipe(recipe) then return end
    return recipe
end

local function CanCraft(inst, recipe)
    return recipe ~= nil and inst.components.builder:HasIngredients(recipe)
end

function M.IsFireClearPoint(inst, point)
    local nearby = TheSim:FindEntities(point.x, point.y, point.z,
        M.FIRE_CLEARANCE, nil, { "INLIMBO", "FX" })
    for _, entity in ipairs(nearby) do
        if entity ~= inst and (entity.components ~= nil and entity.components.burnable ~= nil
            or entity:HasAnyTag("canlight", "structure", "tree")) then return false end
    end
    return true
end

local function IsFireSafePoint(inst, point, recipe)
    return TheWorld.Map:CanDeployRecipeAtPoint(point,recipe,0,inst) and M.IsFireClearPoint(inst,point)
end
M.IsFireSafePoint = IsFireSafePoint

function M.FindSafeFirePoint(inst, recipe)
    if recipe == nil then return end
    local origin = inst:GetPosition()
    if IsFireSafePoint(inst, origin, recipe) then return origin end
    local startangle = math.random() * PI2
    for radius = 3, M.FIRE_POINT_SEARCH_RANGE, 2 do
        for attempt = 0, 15 do
            local angle = startangle + attempt * PI2 / 16
            local point = Vector3(origin.x + math.cos(angle) * radius,
                origin.y, origin.z + math.sin(angle) * radius)
            if IsFireSafePoint(inst, point, recipe) then return point end
        end
    end
end

local function GetMissingIngredients(inst, recipe)
    if recipe == nil then return end
    local missing = {}
    local modifier = inst.components.builder.ingredientmod or 1
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        local amount = math.max(1, math.ceil(ingredient.amount * modifier))
        local _, count = inst.components.inventory:Has(ingredient.type, amount, true)
        if (count or 0) < amount then missing[ingredient.type] = true end
    end
    return next(missing) ~= nil and missing or nil
end

local function CanPickUp(inst, item)
    local inventoryitem = item.components ~= nil and item.components.inventoryitem or nil
    return inventoryitem ~= nil and inventoryitem.owner == nil
        and inventoryitem.canbepickedup and not item:IsInLimbo()
        and inst.components.inventory:CanAcceptCount(item, 1) > 0
end

local function GetMaterialAction(inst, recipe)
    local missing = GetMissingIngredients(inst, recipe)
    if missing == nil then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local closest, closestdist
    for _, item in ipairs(TheSim:FindEntities(x, y, z, M.MATERIAL_SEARCH_RANGE,
        { "_inventoryitem" }, PICKUP_CANT_TAGS)) do
        if missing[item.prefab] and CanPickUp(inst, item) then
            local distance = DistanceSq(inst, item)
            if closestdist == nil or distance < closestdist then
                closest, closestdist = item, distance
            end
        end
    end
    return closest ~= nil and BufferedAction(inst, closest, ACTIONS.PICKUP) or nil
end

local function GetFixedFireFuelAction(inst, need)
    local base_ai = require("my_friend_base_ai")
    local x, y, z = inst.Transform:GetWorldPosition()
    local wanted = need == "cold" and "firepit" or "coldfirepit"
    local range = need == "hot" and M.COOLING_SEARCH_RANGE or M.THERMAL_SEARCH_RANGE
    local fuel_limit = need == "hot" and .5 or .35
    local best, best_distance
    for _, source in ipairs(TheSim:FindEntities(x, y, z, range, FIRE_TAGS, THERMAL_CANT_TAGS)) do
        if source.prefab == wanted then
            local fueled = source.components.fueled
            local distance = DistanceSq(inst, source)
            if fueled ~= nil and fueled:GetPercent() < fuel_limit
                and (best_distance == nil or distance < best_distance)
                and CanApproachCoolingPoint(inst, source:GetPosition()) then
                best, best_distance = source, distance
            end
        end
    end
    if best ~= nil then
        return base_ai.GetFireFuelAction(inst, best,
            need == "cold" or require("my_friend_policy").GetLeader(inst) ~= nil,
            fuel_limit)
    end
end

function M.GetTemperatureAction(inst)
    if not CanAct(inst) or inst._my_friend_under_threat then return end
    local temperature = inst.components.temperature
    if temperature ~= nil and temperature.current > M.FEATHERFAN_TEMPERATURE then
        local fan
        for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
            if item.prefab == "featherfan" and item.components ~= nil
                and item.components.fan ~= nil
                and item.components.finiteuses ~= nil
                and item.components.finiteuses:GetUses() > 0 then
                fan = item
                break
            end
        end
        if fan ~= nil then
            local equippable = fan.components.equippable
            if equippable ~= nil and not equippable:IsEquipped() then
                local action = BufferedAction(inst, nil, ACTIONS.EQUIP, fan)
                action.validfn = function()
                    return inst.components.temperature ~= nil
                        and inst.components.temperature.current > M.FEATHERFAN_TEMPERATURE
                        and fan:IsValid() and fan.components.finiteuses:GetUses() > 0
                end
                return MarkTemperatureAction(action)
            end
            local action = BufferedAction(inst, inst, ACTIONS.FAN, fan)
            action.validfn = function()
                return fan:IsValid() and fan.components.finiteuses:GetUses() > 0
                    and inst.components.temperature ~= nil
                    and inst.components.temperature.current > M.FEATHERFAN_TEMPERATURE
            end
            return MarkTemperatureAction(action)
        end
    end
    local need = M.GetThermalNeed(inst)
    if need == nil then return end
    if need == "hot" and IsCoolingInPlace(inst, temperature) then return end
    SetThermalTarget(inst, nil, need)
    local shade_tree, shade_point
    if need == "hot" then
        shade_tree, shade_point = FindBaseShade(inst)
        local under_shade = M.IsUnderRememberedShade(inst)
        if CanCoolInShade(inst, temperature) then return end
        if under_shade then
            shade_point = nil
        elseif shade_point ~= nil and temperature.current < temperature.overheattemp then
            return GetShadeAction(inst, shade_tree, shade_point)
        end
    end
    local source, distance, hazardous = M.FindThermalSource(inst, need)
    if source ~= nil then
        SetThermalTarget(inst, source, need)
        local distancesq = DistanceSq(inst, source)
        if hazardous and distancesq < math.max(.25, distance - .75) ^ 2 then
            local point = GetRetreatPoint(inst, source, distance)
            return point ~= nil
                and MarkTemperatureAction(BufferedAction(inst, nil, ACTIONS.WALKTO,
                    nil, point)) or nil
        elseif distancesq > (distance + (need == "hot" and .5 or .75)) ^ 2 then
            local action = BufferedAction(inst, source, ACTIONS.WALKTO, nil, nil, nil, distance)
            if need == "hot" then
                action.validfn = function() return GetSourceData(inst, source, "hot") ~= nil end
            end
            return MarkTemperatureAction(action)
        end
        return
    end
    local fixed_fire = GetFixedFireFuelAction(inst, need)
    if fixed_fire ~= nil then return MarkTemperatureAction(fixed_fire) end
    if shade_point ~= nil then return GetShadeAction(inst, shade_tree, shade_point) end

    local recipe = GetRecipe(inst, need == "cold" and "campfire" or "coldfire")
    if CanCraft(inst, recipe) then
        local point = M.FindSafeFirePoint(inst, recipe)
        if point ~= nil then
            local action = BufferedAction(inst, nil,
                ACTIONS.MY_FRIEND_BUILD or ACTIONS.BUILD, nil,
                point, recipe.name, recipe.build_distance)
            action.validfn = function(act)
                local actionpoint = act:GetActionPoint()
                return actionpoint ~= nil
                    and IsFireSafePoint(inst, actionpoint, recipe)
            end
            return MarkTemperatureAction(action)
        end
    end
    return MarkTemperatureAction(GetMaterialAction(inst, recipe))
end

return M
