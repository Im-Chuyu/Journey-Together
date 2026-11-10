-- Picks the four farm tiles a farming command works on. They should touch
-- each other: a two by two square or a straight line reads as one tidy plot
-- instead of four scattered patches. Smaller contiguous shapes are used when
-- four neighbours are not available, and only then does it fall back to the
-- plain "nearest tiles" order.
local M = {}

M.LIMIT = 4
M.SLOT_TOLERANCE = .12

function M.GridSpacing()
    return (TILE_SCALE or 4) / 3
end

function M.IsOpenHole(entity)
    return entity.prefab == "farm_soil" and entity:IsValid() and entity._plow == nil
        and entity:HasTag("soil") and not entity:HasAnyTag("NOCLICK", "NOBLOCK", "INLIMBO")
end

function M.IsWeed(entity)
    return entity:HasTag("weed") or entity.weed_def ~= nil
end

function M.FindHoles(x, z, radius)
    local holes = {}
    for _, entity in ipairs(TheSim:FindEntities(x, 0, z, radius, {"soil"}, {"NOCLICK", "NOBLOCK", "INLIMBO"})) do
        if M.IsOpenHole(entity) then holes[#holes + 1] = entity end
    end
    return holes
end

local function DistanceSq(entity, point)
    local p = entity:GetPosition()
    return (p.x - point.x)^2 + (p.z - point.z)^2
end

function M.MatchesSlot(entity, point)
    return DistanceSq(entity, point) <= M.SLOT_TOLERANCE^2
end

function M.BlockingHole(point, spacing, holes)
    local best, distance
    for _, soil in ipairs(holes or M.FindHoles(point.x, point.z, spacing)) do
        local d = DistanceSq(soil, point)
        if d <= spacing^2 and (distance == nil or d < distance or d == distance and soil.GUID < best.GUID) then
            best, distance = soil, d
        end
    end
    return best, distance ~= nil and distance <= M.SLOT_TOLERANCE^2
end

function M.CanTill(point)
    return TheWorld.Map:CanTillSoilAtPoint(point.x, 0, point.z, false)
end

-- Offsets are {column, row}. Squares first, then lines, then shorter runs.
local SHAPES = {
    { size = 4, offsets = {{0, 0}, {1, 0}, {0, 1}, {1, 1}} },
    { size = 4, offsets = {{0, 0}, {1, 0}, {2, 0}, {3, 0}} },
    { size = 4, offsets = {{0, 0}, {0, 1}, {0, 2}, {0, 3}} },
    { size = 3, offsets = {{0, 0}, {1, 0}, {2, 0}} },
    { size = 3, offsets = {{0, 0}, {0, 1}, {0, 2}} },
    { size = 2, offsets = {{0, 0}, {1, 0}} },
    { size = 2, offsets = {{0, 0}, {0, 1}} },
}

local function Key(tx, tz)
    return tostring(tx) .. ":" .. tostring(tz)
end

M.Key = Key

-- tiles: array of {tx, tz, distance}. Returns the chosen subset, nearest first.
function M.Select(tiles, limit)
    limit = math.min(limit or M.LIMIT, M.LIMIT)
    if #tiles <= 1 or limit <= 1 then
        local single = {}
        for index = 1, math.min(limit, #tiles) do single[index] = tiles[index] end
        return single
    end
    local index = {}
    for _, tile in ipairs(tiles) do index[Key(tile.tx, tile.tz)] = tile end

    local best, bestsize, bestscore
    for _, shape in ipairs(SHAPES) do
        if shape.size <= limit and (bestsize == nil or shape.size >= bestsize) then
            for _, tile in ipairs(tiles) do
                local group, complete, score = {}, true, 0
                for _, offset in ipairs(shape.offsets) do
                    local found = index[Key(tile.tx + offset[1], tile.tz + offset[2])]
                    if found == nil then complete = false break end
                    group[#group + 1] = found
                    score = score + found.distance
                end
                -- Prefer the largest connected shape, then the closest one.
                if complete and (bestsize == nil or shape.size > bestsize
                    or shape.size == bestsize and score < bestscore) then
                    best, bestsize, bestscore = group, shape.size, score
                end
            end
        end
    end
    if best == nil then
        local nearest = {}
        for i = 1, math.min(limit, #tiles) do nearest[i] = tiles[i] end
        return nearest
    end
    table.sort(best, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.tx == b.tx and a.tz < b.tz or a.tx < b.tx
    end)
    return best
end

return M
