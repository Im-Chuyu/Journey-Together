local LightAI = require("my_friend_light_ai")
local Navigation = require("my_friend_navigation")

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
M.COLD_EQUIPMENT_RELEASE = 32
-- Worn out gear is taken off and kept rather than destroyed on the body.
M.EQUIPMENT_WEAR_LIMIT = .05
M.THERMAL_SEARCH_RANGE = 20
M.MATERIAL_SEARCH_RANGE = 15
M.FIRE_CLEARANCE = 4
M.FIRE_POINT_SEARCH_RANGE = 14

local THERMAL_CANT_TAGS = {
    "INLIMBO", "burnt", "playerghost",
}

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
    inst._my_friend_thermal_need = M.UpdateThermalNeed(
        temperature.current, temperature.overheattemp,
        inst._my_friend_thermal_need)
    return inst._my_friend_thermal_need
end

function M.NeedsTemperatureHelp(inst)
    return M.GetThermalNeed(inst) ~= nil
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
    inst._my_friend_thermal_equipment_state = M.UpdateEquipmentThermalState(
        temperature.current, inst._my_friend_thermal_equipment_state)
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

function M.FindDamagingHeatSource(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local best, bestscore
    local temperature = inst.components.temperature
    for _, source in ipairs(TheSim:FindEntities(x, y, z, 16, nil, THERMAL_CANT_TAGS)) do
        if source ~= inst and source.entity:GetParent() == nil then
            local heater = source.components.heater
            local heat = heater ~= nil and heater:IsExothermic() and heater:GetHeat(inst) or nil
            local damage = GetDamageDistance(source)
            local cutoff = heater ~= nil and (heater:GetHeatRadiusCutoff() or 10) or damage
            local p = source:GetPosition()
            local distance = (p.x - x)^2 + (p.z - z)^2
            if (damage > 0 or temperature ~= nil and heat ~= nil and heat > temperature.current)
                and distance < math.max(cutoff, damage)^2 then
                local score = distance - damage * 2
                if bestscore == nil or score < bestscore then best, bestscore = source, score end
            end
        end
    end
    return best
end

local function GetSourceData(inst, source, need)
    local heater = source.components ~= nil and source.components.heater or nil
    if heater == nil or IsHostileHeater(inst, source) then return end
    local heat = heater:GetHeat(inst)
    local current = inst.components.temperature.current
    if heat == nil
        or need == "cold" and (not heater:IsExothermic() or heat <= current)
        or need == "hot" and (not heater:IsEndothermic() or heat >= current) then
        return
    end
    local damage_distance = GetDamageDistance(source)
    local distance = damage_distance > 0 and damage_distance or 2
    local cutoff = heater:GetHeatRadiusCutoff() or 10
    if distance >= cutoff then return end
    return heat, distance, damage_distance > 0
end

function M.FindThermalSource(inst, need)
    need = need or M.GetThermalNeed(inst)
    if need == nil then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local best, bestdistance, besthazardous, bestscore
    for _, source in ipairs(TheSim:FindEntities(x, y, z,
        M.THERMAL_SEARCH_RANGE, { "HASHEATER" }, THERMAL_CANT_TAGS)) do
        if source ~= inst then
            local heat, distance, hazardous = GetSourceData(inst, source, need)
            if heat ~= nil then
                local sx, _, sz = source.Transform:GetWorldPosition()
                local dx, dz = sx - x, sz - z
                local score = dx * dx + dz * dz + (hazardous and 12 or 0)
                    - math.min(math.abs(heat - inst.components.temperature.current), 100) * .05
                if bestscore == nil or score < bestscore then
                    best, bestdistance, besthazardous, bestscore =
                        source, distance, hazardous, score
                end
            end
        end
    end
    return best, bestdistance, besthazardous
end

local function DistanceSq(inst, target)
    local x, _, z = inst.Transform:GetWorldPosition()
    local tx, _, tz = target.Transform:GetWorldPosition()
    local dx, dz = tx - x, tz - z
    return dx * dx + dz * dz
end

function M.IsNearThermalSource(inst)
    local source, distance, hazardous = M.FindThermalSource(inst)
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

local function IsFireSafePoint(inst, point, recipe)
    if not TheWorld.Map:CanDeployRecipeAtPoint(point, recipe, 0, inst) then return false end
    local nearby = TheSim:FindEntities(point.x, point.y, point.z,
        M.FIRE_CLEARANCE, nil, { "INLIMBO", "FX" })
    for _, entity in ipairs(nearby) do
        if entity ~= inst and (entity.components ~= nil and entity.components.burnable ~= nil
            or entity:HasAnyTag("canlight", "structure", "tree")) then return false end
    end
    return true
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
    local x, y, z = inst.Transform:GetWorldPosition()
    local wanted = need == "cold" and "firepit" or "coldfirepit"
    local source
    for _, entity in ipairs(TheSim:FindEntities(x, y, z,
        M.THERMAL_SEARCH_RANGE, { "campfire" }, THERMAL_CANT_TAGS)) do
        if entity.prefab == wanted and entity.components.fueled ~= nil
            and entity.components.fueled:GetPercent() < .35 then
            source = entity
            break
        end
    end
    if source == nil then return end
    local fuel = inst.components.inventory:FindItem(function(item)
        return item.prefab == "log" and source.components.fueled:CanAcceptFuelItem(item)
    end)
    return fuel ~= nil and BufferedAction(inst, source, ACTIONS.ADDFUEL, fuel) or nil
end

function M.GetTemperatureAction(inst)
    if not CanAct(inst) or inst._my_friend_under_threat then return end
    local need = M.GetThermalNeed(inst)
    if need == nil then return end
    if need == "hot" and inst.components.temperature.current >= inst.components.temperature.overheattemp then
        local hot = M.FindDamagingHeatSource(inst)
        if hot ~= nil then
            local heater = hot.components.heater
            local radius = math.max(GetDamageDistance(hot) + 2,
                heater ~= nil and (heater:GetHeatRadiusCutoff() or 10) + 2 or 8)
            local point = GetRetreatPoint(inst, hot, radius)
            if point ~= nil then return BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point) end
        end
    end

    local source, distance, hazardous = M.FindThermalSource(inst, need)
    if source ~= nil then
        local distancesq = DistanceSq(inst, source)
        if hazardous and distancesq < math.max(.25, distance - .75) ^ 2 then
            local point = GetRetreatPoint(inst, source, distance)
            return point ~= nil
                and BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point) or nil
        elseif distancesq > (distance + .75) ^ 2 then
            return BufferedAction(inst, source, ACTIONS.WALKTO,
                nil, nil, nil, distance)
        end
        return
    end


    local fixed_fire = GetFixedFireFuelAction(inst, need)
    if fixed_fire ~= nil then return fixed_fire end

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
            return action
        end
    end
    return GetMaterialAction(inst, recipe)
end

return M
