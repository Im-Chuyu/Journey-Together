local Policy = require("my_friend_policy")
local Memory = require("my_friend_resource_memory")
local Behaviour = require("my_friend_behavior_ai")
local Navigation = require("my_friend_navigation")
local M = {}

function M.RegionAtPoint(x, z)
    local map, topology = TheWorld.Map, TheWorld.topology
    if topology == nil or topology.nodes == nil then return end
    local node, index
    if map.FindVisualNodeAtPoint ~= nil then
        node, index = map:FindVisualNodeAtPoint(x, 0, z)
    elseif map.GetNodeIdAtPoint ~= nil then
        index = map:GetNodeIdAtPoint(x, 0, z)
        node = topology.nodes[index]
    end
    if node == nil then return end
    local id = topology.ids ~= nil and topology.ids[index] or ""
    local name = string.lower(tostring(id))
    local kind
    local function Has(word) return string.find(name, word, 1, true) ~= nil end
    -- Room ids describe generated regions, not the turf under one entity.
    if Has("marsh") or Has("swamp") then kind = "marsh"
    elseif Has("desert") or Has("badland") then kind = "desert"
    elseif Has("rock") or Has("quarry") or Has("bare") or Has("mosaic") then kind = "rocky"
    elseif Has("deciduous") or Has("pigking") or Has("magical") then kind = "deciduous"
    elseif Has("forest") or Has("spider") then kind = "forest"
    elseif Has("savanna") or Has("beefalo") then kind = "savanna"
    elseif Has("grass") or Has("plain") or Has("clearing") then kind = "grass"
    end
    return { id = id, index = index, node = node, kind = kind }
end

function M.RegionScore(region, needs)
    if region == nil then return 0 end
    local tiles = WORLD_TILES or GROUND or {}
    local tile = ({ grass = tiles.GRASS, savanna = tiles.SAVANNA,
        forest = tiles.FOREST, deciduous = tiles.DECIDUOUS,
        rocky = tiles.ROCKY, desert = tiles.DESERT_DIRT, marsh = tiles.MARSH })[region.kind]
    return tile ~= nil and M.TileScore(tile, needs) or 0
end

function M.TileScore(tile, needs)
    local tiles = WORLD_TILES or GROUND or {}
    local score = 0
    local function Has(...) for i = 1, select("#", ...) do
        if needs[select(i, ...)] ~= nil then return true end
    end end
    if tile == tiles.GRASS then
        if Has("cutgrass", "twigs", "dug_grass", "dug_sapling", "food") then score = score + 12 end
        if Has("flint", "log") then score = score + 3 end
    elseif tile == tiles.SAVANNA then
        if Has("cutgrass", "dug_grass") then score = score + 14 end
    elseif tile == tiles.FOREST then
        if Has("log", "pinecone") then score = score + 14 end
        if Has("twigs", "food") then score = score + 3 end
    elseif tile == tiles.DECIDUOUS then
        if Has("log", "acorn") then score = score + 14 end
        if Has("food") then score = score + 6 end
    elseif tile == tiles.ROCKY or tile == tiles.DIRT or tile == tiles.DESERT_DIRT then
        if Has("rocks", "flint", "goldnugget", "nitre") then score = score + 14 end
    elseif tile == tiles.MARSH then
        score = Has("cutreeds") and 16 or 0
    end
    return score
end

local function Available(inst, entity, needs, blocked)
    if entity == inst or not entity:IsValid() or entity.Transform == nil or entity.components == nil
        or entity:HasAnyTag("INLIMBO", "NOCLICK", "fire", "burnt", "outofreach")
        or blocked ~= nil and blocked(entity)
        or Navigation.IsBlocked(inst, entity:GetPosition()) then return end
    local c = entity.components
    if c.inventoryitem ~= nil and (c.inventoryitem.owner ~= nil
        or not c.inventoryitem.canbepickedup
        or inst.components.inventory:CanAcceptCount(entity, 1) <= 0) then return end
    if needs.food then
        if Policy.IsBaseCacheItem(inst, entity) and inst.components.hunger:GetPercent() >= .4 then return end
        if c.edible ~= nil and c.inventoryitem ~= nil
            and inst.components.eater:CanEat(entity)
            and inst.components.inventory:CanAcceptCount(entity, 1) > 0 then return { food = 1 } end
        if c.pickable ~= nil and c.pickable.caninteractwith and c.pickable:CanBePicked()
            and Behaviour.IsFoodProduct(c.pickable.product) then return { food = 1 } end
        if c.crop ~= nil and c.crop:IsReadyForHarvest() then return { food = 1 } end
        return
    end
    local products = Memory.Products(entity)
    local matched = false
    for prefab in pairs(needs) do if products[prefab] ~= nil then matched = true break end end
    return matched and products or nil
end

function M.Find(inst, needs, blocked)
    local now = GetTime()
    local keys = {}
    for prefab in pairs(needs) do keys[#keys + 1] = prefab end
    table.sort(keys)
    local key = table.concat(keys, ",")
    local queries = inst._my_friend_world_resource_query or {}
    inst._my_friend_world_resource_query = queries
    local cache = queries[key]
    if cache ~= nil and now < cache.untiltime then
        if cache.target == nil then return end
        if Available(inst, cache.target, needs, blocked) ~= nil
            and not Behaviour.IsTargetUnsafe(inst, cache.target) then return cache.target end
    end
    local x, _, z = inst.Transform:GetWorldPosition()
    local candidates = {}
    for _, entity in pairs(Ents or {}) do
        local products = Available(inst, entity, needs, blocked)
        if products ~= nil and Policy.InRange(inst, entity) then
            local p = entity:GetPosition()
            if TheWorld.Map:IsPassableAtPoint(p.x, 0, p.z)
                and not Navigation.IsNearHole(p) then
                local value = 0
                for prefab in pairs(needs) do if products[prefab] ~= nil then value = value + 1 end end
                local region = M.RegionAtPoint(p.x, p.z)
                local tile = TheWorld.Map:GetTileAtPoint(p.x, 0, p.z)
                candidates[#candidates + 1] = { entity = entity,
                    score = math.sqrt((p.x - x)^2 + (p.z - z)^2)
                        - value * 3 - M.RegionScore(region, needs) * .5
                        - M.TileScore(tile, needs) * .1 }
            end
        end
    end
    table.sort(candidates, function(a, b) return a.score < b.score end)
    local best
    for _, candidate in ipairs(candidates) do
        if not Behaviour.IsTargetUnsafe(inst, candidate.entity) then best = candidate.entity break end
    end
    queries[key] = { target = best, untiltime = now + 3 }
    for oldkey, query in pairs(queries) do
        if now >= query.untiltime then queries[oldkey] = nil end
    end
    return best
end

return M
