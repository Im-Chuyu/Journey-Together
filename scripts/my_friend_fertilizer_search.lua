local Navigation = require("my_friend_navigation")
local Garden = require("my_friend_garden")
local M = {}

local function Regions()
    local world = TheWorld
    if world._my_friend_fertilizer_regions ~= nil then return world._my_friend_fertilizer_regions end
    local regions = {}
    local topology = world.topology or {}
    for index, node in ipairs(topology.nodes or {}) do
        local name = tostring((topology.ids or {})[index] or ""):lower()
        local x, z = node.x or node.cent and node.cent[1], node.y or node.cent and node.cent[2]
        if name:find("savanna", 1, true) or name:find("beefalo", 1, true)
            or name:find("plain", 1, true)
            or x ~= nil and z ~= nil and world.Map:GetTileAtPoint(x, 0, z) == WORLD_TILES.SAVANNA then
            if x ~= nil and z ~= nil then
                regions[#regions + 1] = {index = index, node = node, x = x, z = z}
            end
        end
    end
    world._my_friend_fertilizer_regions = regions
    return regions
end

local function Points(region)
    if region.points ~= nil then return region.points end
    local build = region.build
    if build == nil then
        local minx, maxx, minz, maxz = region.x, region.x, region.z, region.z
        for _, vertex in ipairs(region.node.poly or {}) do
            minx, maxx = math.min(minx, vertex[1]), math.max(maxx, vertex[1])
            minz, maxz = math.min(minz, vertex[2]), math.max(maxz, vertex[2])
        end
        build = {x = minx, z = minz, minz = minz, maxx = maxx, maxz = maxz, points = {}}
        region.build = build
    end
    -- Incremental coverage generation avoids a whole-map scan on a turn.
    for _ = 1, 128 do
        if build.x > build.maxx then
            if #build.points == 0 and Navigation.IsLand(region) then
                build.points[1] = {x = region.x, z = region.z}
            end
            region.points, region.build = build.points, nil
            return region.points
        end
        local point = {x = build.x, z = build.z}
        if TheWorld.Map:GetNodeIdAtPoint(point.x, 0, point.z) == region.index
            and Navigation.IsLand(point) then build.points[#build.points + 1] = point end
        build.z = build.z + 12
        if build.z > build.maxz then build.x, build.z = build.x + 12, build.minz end
    end
end

local function SearchStep(inst, trip)
    local state = inst._my_friend_base
    state.fertilizer_regions = state.fertilizer_regions or {}
    local day, region, nearest, rank = TheWorld.state.cycles
    for _, candidate in ipairs(Regions()) do
        local saved = state.fertilizer_regions[tostring(candidate.index)]
        if saved == nil or day >= (saved.after_day or 0) then
            local d = inst:GetDistanceSqToPoint(candidate.x, 0, candidate.z)
            local priority = saved == nil and 0 or not saved.finished and 1 or 2
            if rank == nil or priority < rank or priority == rank and d < nearest then
                region, nearest, rank = candidate, d, priority
            end
        end
    end
    if region == nil then return end
    local key = tostring(region.index)
    local saved = state.fertilizer_regions[key]
    if saved == nil then
        saved = {visited = {}, failed = {}}
        state.fertilizer_regions[key] = saved
    elseif saved.finished then
        saved = {visited = {}, failed = {}}
        state.fertilizer_regions[key] = saved
    end
    local points = Points(region)
    if points == nil then return nil, true end
    if #points == 0 then
        saved.after_day, saved.finished = day + 2, true
        return nil, true
    end
    local best, index, distance
    local unfinished = false
    for i, point in ipairs(points) do
        if not saved.visited[tostring(i)] then
            unfinished = true
            if day >= ((saved.failed or {})[tostring(i)] or 0)
                and not Navigation.IsBlocked(inst, point) then
                local d = inst:GetDistanceSqToPoint(point.x, 0, point.z)
                if distance == nil or d < distance then best, index, distance = point, i, d end
            end
        end
    end
    if best == nil then
        saved.after_day = day + (not unfinished and not saved.cattle and 20 or 2)
        saved.finished = not unfinished
        saved.no_manure = not unfinished and not saved.cattle
        return nil, true
    end
    local function Observe()
        saved.visited[tostring(index)] = true
        for _, entity in ipairs(TheSim:FindEntities(best.x, 0, best.z, 18, nil, {"INLIMBO"})) do
            if entity.prefab == "beefalo" or entity.prefab == "babybeefalo"
                or entity.prefab == "poop" then saved.cattle = true end
        end
    end
    if distance < 3^2 then Observe() return nil, true end
    local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, Vector3(best.x, 0, best.z))
    action._my_friend_dialogue_kind = "fertilizer_search"
    action.arrivedist = 2
    action.validfn = function()
        return state.fertilizer_trip == trip and GetTime() < trip.deadline
    end
    action:AddSuccessAction(Observe)
    action:AddFailAction(function()
        if not action._my_friend_cancelled then
            saved.failed = saved.failed or {}
            saved.failed[tostring(index)] = day + 2
        end
    end)
    return action, true
end

local function WaitAction(inst, trip)
    local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, inst:GetPosition())
    action.arrivedist = .1
    action._my_friend_fertilizer_wait = true
    action.validfn = function()
        return inst._my_friend_base ~= nil
            and inst._my_friend_base.fertilizer_trip == trip
            and GetTime() < trip.deadline
    end
    return action, true
end

function M.Action(inst, trip)
    require("my_friend_base_ai").SetTask(inst, "正在外出寻找肥料")
    -- Consume reached/exhausted checkpoints before yielding to the brain.
    -- Bound the work so generating a large region cannot freeze a tick.
    for _ = 1, 16 do
        local action, pending = SearchStep(inst, trip)
        if action ~= nil or not pending then return action, pending end
    end
    return WaitAction(inst, trip)
end

function M.Opportunity(inst)
    if require("my_friend_policy").IsBusy(inst) or inst._my_friend_under_threat
        or inst._my_friend_command ~= nil then return end
    local base = inst._my_friend_base
    local baseai = require("my_friend_base_ai")
    -- No garden to fertilise when the companion does not build a base.
    if base == nil or require("my_friend_home").NoConstruction(inst)
        or baseai.IsStockStorageFull(inst) then return end
    local inv, amount = inst.components.inventory, 0
    for _, item in ipairs(inv:ReferenceAllItems()) do amount = amount + Garden.Uses(item) end
    if amount >= 10 or inv:GetNumSlots() - inv:NumItems() < 2 then return end
    local item = Garden.FindLoose(inst, 8, function(entity)
        return require("my_friend_policy").InRange(inst, entity)
            and baseai.CountBaseStock(inst, entity.prefab) < 20
            and not Navigation.IsBlocked(inst, entity:GetPosition())
            and require("my_friend_recovery_safety").IsSafe(inst, entity:GetPosition())
    end)
    if item ~= nil then
        local action = BufferedAction(inst, item, ACTIONS.PICKUP)
        action._my_friend_dialogue_kind = "fertilizer_collect"
        return action
    end
end

return M
