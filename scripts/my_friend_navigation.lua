local M = {}
M.SEARCH_TIMEOUT = 12

local function DistanceSq(a, b)
    return (a.x - b.x)^2 + (a.z - b.z)^2
end

local function Key(point)
    return math.floor(point.x / 2)..":"..math.floor(point.z / 2)
end

function M.IsBlocked(inst, point)
    local blocked = inst._my_friend_unreachable
    local entry = blocked ~= nil and blocked[Key(point)] or nil
    if entry == nil then return false end
    if GetTime() >= entry.untiltime then
        blocked[Key(point)] = nil
        return false
    end
    return DistanceSq(inst:GetPosition(), entry.origin) < 64^2
end

function M.Block(inst, point, exhausted, local_only)
    local blocked = inst._my_friend_unreachable or {}
    inst._my_friend_unreachable = blocked
    local count = 0
    for key, entry in pairs(blocked) do
        if GetTime() >= entry.untiltime then blocked[key] = nil else count = count + 1 end
    end
    if count >= 64 then blocked = {} inst._my_friend_unreachable = blocked end
    blocked[Key(point)] = { origin = inst:GetPosition(),
        untiltime = GetTime() + (local_only and 20 or exhausted and 600 or 90) }
end

function M.Caps(inst)
    local caps = {}
    for key, value in pairs(inst.components.locomotor.pathcaps or {}) do caps[key] = value end
    caps.allowocean = false
    caps.ignorecreep = true
    return caps
end

-- Map:IsPointNearHole passes the point straight to GetDistanceSqToPoint, which
-- calls pt:Get() on it, so a bare {x=, z=} table throws. It only ever gets that
-- far when a "groundhole" entity is actually in range: above ground that is
-- almost nothing (ice fishing holes, the hermit spring), but every cave
-- sinkhole carries the tag, so underground it crashed the server as soon as the
-- companion pathed anywhere near one. Normalise every caller through here, and
-- reuse one scratch vector -- a single search probes thousands of cells.
local HOLE_PROBE = Vector3(0, 0, 0)

function M.IsNearHole(point)
    if point == nil or point.x == nil or point.z == nil then return false end
    HOLE_PROBE.x, HOLE_PROBE.y, HOLE_PROBE.z = point.x, 0, point.z
    return TheWorld.Map:IsPointNearHole(HOLE_PROBE)
end

function M.IsLand(point)
    return point ~= nil and point.x ~= nil and point.z ~= nil
        and TheWorld.Map:IsPassableAtPoint(point.x, 0, point.z)
        and not TheWorld.Map:IsOceanTileAtPoint(point.x, 0, point.z)
        and not M.IsNearHole(point)
end

function M.IsClear(a, b, caps)
    if not TheWorld.Pathfinder:IsClear(a.x, 0, a.z, b.x, 0, b.z, caps) then return false end
    local samples = math.max(1, math.ceil(math.sqrt(DistanceSq(a, b)) / .5))
    for index = 1, samples do
        local t = index / samples
        local point = Vector3(a.x + (b.x - a.x) * t, 0, a.z + (b.z - a.z) * t)
        if not M.IsLand(point) then return false end
    end
    return true
end

function M.InTravelRange(inst, point)
    local root = inst.brain ~= nil and inst.brain.bt ~= nil and inst.brain.bt.root or nil
    local action = inst._my_friend_navigation_action
        or root ~= nil and root.active ~= nil and root.active.node.action or nil
    if action ~= nil and action._my_friend_carry_backpack ~= nil then
        return require("my_friend_carry_backpack").IsTravelAction(inst, action)
    end
    if action ~= nil and action._my_friend_revive_return ~= nil
        and action._my_friend_revive_return == inst._my_friend_ghost_revive
        and GetTime() < action._my_friend_revive_return.deadline then return true end
    if action ~= nil and action._my_friend_wormhole ~= nil then
        return require("my_friend_wormhole").InTravelRange(inst, action, point)
    end
    if action ~= nil and action._my_friend_gather_command ~= nil then
        return inst._my_friend_command == action._my_friend_gather_command
    end
    if action ~= nil and action._my_friend_owned_recovery
        and GetTime() <= (inst._my_friend_backpack_deadline or 0) then return true end
    local command = inst._my_friend_command
    if command ~= nil and command.id == "chop" and action ~= nil
        and action._my_friend_chop_delivery then return true end
    if action ~= nil and action._my_friend_command_origin ~= nil
        and command ~= nil and command.id == "chop"
        and action._my_friend_command_origin == command.origin then
        -- Allow approach detours without moving the actual work area.
        return DistanceSq(command.origin, point) <= 32^2
            or DistanceSq(inst:GetPosition(), point) <= 20^2
    end
    local policy = require("my_friend_policy")
    if policy.IsRoaming(inst) then return true end
    if policy.IsDeathRecoveryAction(inst, action) then return true end
    -- While keeping vigil, the dead leader's position is meaningless.
    local vigil = policy.GetVigilPoint(inst)
    if vigil ~= nil then
        local limit = (require("my_friend_base_ai").VIGIL_RADIUS or 20) + 8
        return DistanceSq(vigil, point) <= limit * limit
    end
    local leader = policy.GetLeader(inst)
    if leader == nil then
        -- Safety net for "wait here" / "this is home": no route may ever be
        -- planned to a point outside the home circle.
        return require("my_friend_home").IsPointInRange(inst, point)
    end
    return DistanceSq(leader:GetPosition(), point) <= policy.ActivityRange(inst)^2
end

local function IsObstacle(inst, entity)
    return entity ~= inst and entity:IsValid() and entity.Physics ~= nil
        and entity.Physics:IsActive() and entity.components.locomotor == nil
        and entity.entity:GetParent() == nil and entity.components.placer == nil
        and checkbit(entity.Physics:GetCollisionMask(), inst.Physics:GetCollisionGroup())
        and checkbit(inst.Physics:GetCollisionMask(), entity.Physics:GetCollisionGroup())
end

-- Geometry only: passable ground, no water, nothing solid across the line.
-- Deliberately says nothing about whether the point is somewhere the companion
-- is allowed to be; IsWalkClear adds that, Unstick decides for itself.
function M.IsStepClear(inst, a, b, caps, obstacles)
    local dx, dz = b.x - a.x, b.z - a.z
    local lengthsq = dx * dx + dz * dz
    -- Long travel uses the native pathfinder; never scan an entire map-sized
    -- circle for entity collision during one route/turn decision.
    if lengthsq > 32^2 and obstacles == nil then return false end
    if not M.IsClear(a, b, caps) then return false end
    local entities = obstacles or TheSim:FindEntities((a.x + b.x) / 2, 0,
        (a.z + b.z) / 2, math.sqrt(lengthsq) / 2 + 5, nil, {"INLIMBO", "FX"})
    for _, entity in ipairs(entities) do
        if IsObstacle(inst, entity) then
            local p = entity:GetPosition()
            local radius = entity.Physics:GetRadius() + inst.Physics:GetRadius() + .03
            local t = lengthsq > 0 and math.max(0, math.min(1,
                ((p.x - a.x) * dx + (p.z - a.z) * dz) / lengthsq)) or 0
            local distance = (a.x + dx * t - p.x)^2 + (a.z + dz * t - p.z)^2
            -- Permit moving out of a touching/overlapping obstacle, never through it.
            if distance < radius^2 and not (t == 0 and lengthsq > 0
                and DistanceSq(b, p) > DistanceSq(a, p)) then return false end
        end
    end
    return true
end

function M.IsWalkClear(inst, a, b, caps, obstacles)
    return M.InTravelRange(inst, b) and M.IsStepClear(inst, a, b, caps, obstacles)
end

function M.ActionPoint(action)
    if action.target ~= nil and action.target:IsValid() then return action.target:GetPosition() end
    return action:GetActionPoint()
end

function M.PrepareInteraction(inst, action)
    local kind = action.action
    if action.target == nil or not action.target:IsValid() then return end
    if kind == ACTIONS.ADDFUEL or kind == ACTIONS.COOK or kind == ACTIONS.FERTILIZE
        or kind == ACTIONS.MY_FRIEND_STORE or kind == ACTIONS.MY_FRIEND_WITHDRAW
        or kind == ACTIONS.MY_FRIEND_ORGANIZE or kind == ACTIONS.MY_FRIEND_OPEN then
        action.arrivedist = math.max(2, action.target:GetPhysicsRadius(0)
            + inst:GetPhysicsRadius(0) + .6)
    end
end

function M.ArrivalDistance(inst, action)
    local target, kind = action.target, action.action
    local distance
    if target ~= nil then
        if action.arrivedist ~= nil then return action.arrivedist end
        local item = target.components.inventoryitem
        local owner = item ~= nil and item:GetGrandOwner() or target
        if action.distance ~= nil then
            -- GoToEntity uses actual collision radii for explicit distances.
            return math.max(action.distance, .15
                + (owner.Physics ~= nil and owner.Physics:GetRadius() or 0)
                + inst.Physics:GetRadius())
        end
        distance = .15 + owner:GetPhysicsRadius(0) + inst:GetPhysicsRadius(0)
    else
        distance = action.arrivedist or action.distance or math.max(kind.mindistance or 0, .15)
    end
    if kind.extra_arrive_dist ~= nil then
        distance = distance + kind.extra_arrive_dist(inst, Dest(target, nil, action), action, distance)
    end
    return target ~= nil and math.max(distance, kind.mindistance or 0) or distance
end

local function FailedApproach(point, failed)
    for _, previous in ipairs(failed or {}) do
        if DistanceSq(point, previous) < .65^2 then return true end
    end
    return false
end

function M.Approach(inst, action, caps, attempt, failed)
    local target = M.ActionPoint(action)
    if target == nil then return end
    local origin = inst:GetPosition()
    local angle = math.atan2(origin.z - target.z, origin.x - target.x) + (attempt or 0) * math.pi / 4
    local reach = M.ArrivalDistance(inst, action)
    -- Leave room for the final WALKTO's stopping tolerance. A deploy/build
    -- point is an interaction destination too, not necessarily a place to stand.
    local radius = math.max(0, math.min(reach - .1, 5))
    if reach <= .15 and action.target == nil then
        if not FailedApproach(target, failed) and M.IsLand(target)
            and M.IsWalkClear(inst, target, target, caps) then
            return target, M.IsWalkClear(inst, origin, target, caps)
        end
        return
    end
    local best, bestdistance
    for offset = 0, 15 do
        local a = angle + offset * 2 * math.pi / 16
        local point = Vector3(target.x + math.cos(a) * radius, 0,
            target.z + math.sin(a) * radius)
        if not FailedApproach(point, failed) and M.IsLand(point)
            and M.IsWalkClear(inst, point, point, caps) then
            if DistanceSq(origin, point) <= 32^2 and M.IsWalkClear(inst, origin, point, caps) then
                return point, offset == 0
            end
            local distance = DistanceSq(origin, point)
            if bestdistance == nil or distance < bestdistance then best, bestdistance = point, distance end
        end
    end
    return best, false
end

local function Push(heap, entry)
    local index = #heap + 1
    while index > 1 do
        local parent = math.floor(index / 2)
        if heap[parent].score <= entry.score then break end
        heap[index] = heap[parent]
        index = parent
    end
    heap[index] = entry
end

local function Pop(heap)
    local result, tail = heap[1], table.remove(heap)
    if #heap > 0 then
        local index = 1
        while index * 2 <= #heap do
            local child = index * 2
            if child < #heap and heap[child + 1].score < heap[child].score then child = child + 1 end
            if tail.score <= heap[child].score then break end
            heap[index] = heap[child]
            index = child
        end
        heap[index] = tail
    end
    return result
end

local function Cell(search, x, z)
    local key = x..":"..z
    local node = search.cells[key]
    if node == nil then
        local px, _, pz
        if search.localgrid then
            px, pz = search.origin.x + x * .75, search.origin.z + z * .75
        else
            px, _, pz = TheWorld.Map:GetTileCenterPoint(x, z)
        end
        node = { x = px, z = pz, tx = x, tz = z }
        node.land = M.IsLand(node) and M.InTravelRange(search.inst, node)
            and (not search.localgrid or DistanceSq(node, search.origin) <= search.localradius^2)
        search.cells[key] = node
    end
    return node
end

local function BeginLandSearch(search, localgrid)
    search.localgrid = localgrid == true
    search.cells, search.heap = {}, {}
    search.expanded = 0
    local tx, tz = TheWorld.Map:GetTileCoordsAtPoint(search.origin.x, 0, search.origin.z)
    if search.localgrid then
        tx, tz = 0, 0
        search.localradius = math.min(40, math.max(12, math.sqrt(DistanceSq(search.origin, search.goal)) + 8))
        search.obstacles = {}
        for _, entity in ipairs(TheSim:FindEntities(search.origin.x, 0, search.origin.z,
            search.localradius + 5, nil, {"INLIMBO", "FX"})) do
            if IsObstacle(search.inst, entity) then search.obstacles[#search.obstacles + 1] = entity end
        end
    else
        search.obstacles = nil
    end
    -- Seed nearby centers so a rock occupying the current center cannot trap us.
    for dx = -1, 1 do
        for dz = -1, 1 do
            local node = Cell(search, tx + dx, tz + dz)
            if node.land and M.IsWalkClear(search.inst, search.origin, node, search.caps, search.obstacles) then
                node.cost = math.sqrt(DistanceSq(search.origin, node))
                Push(search.heap, { node = node, cost = node.cost,
                    score = node.cost + math.sqrt(DistanceSq(node, search.goal)) })
            end
        end
    end
end

function M.Cancel(search)
    if search ~= nil and search.handle ~= nil then
        TheWorld.Pathfinder:KillSearch(search.handle)
        search.handle = nil
    end
end

function M.Start(inst, goal, land_only)
    inst.components.locomotor:AdjustPathCaps(true, "ignorecreep")
    local search = { origin = inst:GetPosition(), goal = goal,
        caps = M.Caps(inst), started = GetTime(), inst = inst }
    if land_only then inst._my_friend_land_route = nil end
    if DistanceSq(search.origin, goal) <= 24^2 and land_only then
        if M.IsWalkClear(inst, search.origin, goal, search.caps) then
            search.steps = {goal}
        else
            BeginLandSearch(search, true)
        end
        return search
    end
    if not land_only then
        local cache = inst._my_friend_land_route
        if cache ~= nil and GetTime() < cache.untiltime and DistanceSq(cache.goal, goal) < 4 then
            for index = #cache.steps, 1, -1 do
                local point = cache.steps[index]
                if DistanceSq(search.origin, point) < 16^2
                    and M.IsWalkClear(inst, search.origin, point, search.caps) then
                    local steps, previous, valid = {}, search.origin, true
                    for nextindex = index, #cache.steps do
                        local nextpoint = cache.steps[nextindex]
                        if not M.IsWalkClear(inst, previous, nextpoint, search.caps) then
                            valid = false
                            break
                        end
                        steps[#steps + 1], previous = nextpoint, nextpoint
                    end
                    -- A nearby new goal can be on the other side of a tree or
                    -- a shore corner. Validate that last connector as well.
                    if valid and M.IsWalkClear(inst, previous, goal, search.caps) then
                        steps[#steps + 1] = goal
                        search.steps = steps
                        return search
                    end
                end
            end
        end
    end
    if not land_only and DistanceSq(search.origin, goal) <= 32^2
        and M.IsWalkClear(inst, search.origin, goal, search.caps) then
        search.steps = { goal }
    elseif not land_only then
        search.handle = TheWorld.Pathfinder:SubmitSearch(search.origin.x, 0, search.origin.z,
            goal.x, 0, goal.z, search.caps)
    end
    if search.steps == nil and search.handle == nil then
        BeginLandSearch(search, DistanceSq(search.origin, goal) <= 24^2)
    end
    return search
end

local DIRECTIONS = {{1,0}, {-1,0}, {0,1}, {0,-1}, {1,1}, {1,-1}, {-1,1}, {-1,-1}}

local function Remember(search)
    search.inst._my_friend_land_route = {
        goal = search.goal, steps = search.steps, untiltime = GetTime() + 180,
    }
    return search.steps
end

local function ValidatePath(search, points)
    local steps, previous = {}, search.origin
    local function Append(point)
        if not M.IsLand(point) then return false end
        local start = previous
        local distance = math.sqrt(DistanceSq(start, point))
        -- Native paths can contain long straight edges. Validate them in the
        -- same bounded sections used for walking, not as one huge local scan.
        local count = math.max(1, math.ceil(distance / 24))
        for i = 1, count do
            local nextpoint = Vector3(start.x + (point.x - start.x) * i / count, 0,
                start.z + (point.z - start.z) * i / count)
            if not M.IsWalkClear(search.inst, previous, nextpoint, search.caps) then return false end
            if DistanceSq(previous, nextpoint) > .0001 then steps[#steps + 1] = nextpoint end
            previous = nextpoint
        end
        return true
    end
    for _, point in ipairs(points) do
        if not Append(point) then return end
    end
    if not Append(search.goal) then return end
    if #steps == 0 then steps[1] = search.goal end
    return steps
end

function M.Poll(search)
    if search.steps ~= nil then return search.steps end
    -- Incremental searches must yield back to survival decisions even when
    -- the destination is enclosed and the open set still has many cells.
    if GetTime() - search.started >= M.SEARCH_TIMEOUT then
        M.Cancel(search)
        return false, false
    end
    if search.handle ~= nil then
        local status = TheWorld.Pathfinder:GetSearchStatus(search.handle)
        if status == 0 and GetTime() - search.started < 6 then return end
        local result = status == 1 and TheWorld.Pathfinder:GetSearchResult(search.handle) or nil
        M.Cancel(search)
        if result ~= nil and result.steps ~= nil and #result.steps > 0 then
            search.steps = ValidatePath(search, result.steps)
            if search.steps ~= nil then return Remember(search) end
        end
        BeginLandSearch(search, DistanceSq(search.origin, search.goal) <= 24^2)
    end
    -- Incremental A* over land tiles. Every edge uses the engine's collision
    -- test, including diagonal edges at the coast; there is no water shortcut.
    if search.lastpoll == GetTime() then return end
    search.lastpoll = GetTime()
    for _ = 1, search.localgrid and 24 or 64 do
        local entry = Pop(search.heap)
        if entry == nil or search.localgrid and search.expanded >= 6000 then
            if search.localgrid then
                BeginLandSearch(search)
                return
            end
            return false, true
        end
        local node = entry.node
        if not node.closed and entry.cost == node.cost then
            node.closed = true
            search.expanded = search.expanded + 1
            local obstacles = search.obstacles or TheSim:FindEntities(node.x, 0, node.z,
                15, nil, {"INLIMBO", "FX"})
            if DistanceSq(node, search.goal) <= 100
                and M.IsWalkClear(search.inst, node, search.goal, search.caps, obstacles) then
                local reversed, steps = {}, {}
                local cursor = node
                while cursor ~= nil do
                    reversed[#reversed + 1] = { x = cursor.x, z = cursor.z }
                    cursor = cursor.parent
                end
                for index = #reversed, 1, -1 do steps[#steps + 1] = reversed[index] end
                steps[#steps + 1] = search.goal
                search.steps = steps
                return Remember(search)
            end
            if search.expanded >= 40000 then return false, false end
            for _, delta in ipairs(DIRECTIONS) do
                local neighbour = Cell(search, node.tx + delta[1], node.tz + delta[2])
                if neighbour.land and not neighbour.closed then
                    local cost = node.cost + math.sqrt(DistanceSq(node, neighbour))
                    if (neighbour.cost == nil or cost < neighbour.cost)
                        and M.IsWalkClear(search.inst, node, neighbour, search.caps, obstacles) then
                        neighbour.cost, neighbour.parent = cost, node
                        Push(search.heap, { node = neighbour, cost = cost,
                            score = cost + math.sqrt(DistanceSq(neighbour, search.goal)) })
                    end
                end
            end
        end
    end
end

function M.CancelSteering(inst)
    local state = inst._my_friend_local_walk
    if state ~= nil then M.Cancel(state.search) end
    inst._my_friend_local_walk = nil
end

-- ---------------------------------------------------------------------------
-- Stuck detection and sidestepping.
--
-- GetSteeringPoint below only plans a way round an obstacle when the goal is
-- within STEERING_RANGE, and it returns nil while its search is still running
-- or has failed -- which the callers read as "do not move at all". So a
-- companion chasing a leader who has run past that range, or waiting on a plan
-- that never arrives, just leans into the rock in front of it indefinitely.
--
-- This is the reactive half: no search, no range limit, it simply notices that
-- move orders are producing no movement and aims at a point off to one side
-- for a couple of seconds. Cheap enough to sit underneath every kind of
-- travel, which is what makes going round things look like basic competence
-- rather than a special case.
-- ---------------------------------------------------------------------------

-- Orders issued for this long...
M.STUCK_TIME = 1.2
-- ...having moved less than this, counts as stuck.
M.STUCK_DISTANCE = .75
-- How far to one side to aim. Has to clear the widest thing normally walked
-- into (a treeguard, a chest row) without leaving the leader's range.
M.SIDESTEP_DISTANCE = 6
-- Commit to a detour for this long, so the companion does not turn straight
-- back into the obstacle the instant it comes free.
M.SIDESTEP_COMMIT = 2
-- Re-aiming at a goal that moved further than this starts the timer over; a
-- leader walking normally must not read as progress that never happens.
M.STUCK_GOAL_DRIFT = 8

function M.ClearStuck(inst)
    inst._my_friend_stuck = nil
end

-- Returns a point to walk to instead of `goal`, or nil to carry on as normal.
function M.Unstick(inst, goal)
    if inst:HasTag("playerghost") then M.ClearStuck(inst) return end
    if goal == nil or inst.Physics == nil then
        M.ClearStuck(inst)
        return
    end
    local now, position = GetTime(), inst:GetPosition()
    local state = inst._my_friend_stuck
    if state == nil or DistanceSq(state.goal, goal) > M.STUCK_GOAL_DRIFT^2 then
        state = { goal = goal, since = now, mark = position }
        inst._my_friend_stuck = state
        return
    end
    state.goal = goal
    -- Only count time across consecutive move orders. A gap means the
    -- companion was not trying to go anywhere, and holding the stopwatch
    -- running through it would read a perfectly normal pause as an obstacle
    -- the moment it set off again.
    if state.lastcall == nil or now - state.lastcall > .5 then
        state.since, state.mark = now, position
    end
    state.lastcall = now

    if state.detour ~= nil then
        -- Run the detour out rather than re-deciding every tick.
        if now < state.expires and DistanceSq(position, state.detour) > 1.2^2 then
            return state.detour
        end
        state.detour, state.since, state.mark = nil, now, position
        return
    end

    if DistanceSq(position, state.mark) > M.STUCK_DISTANCE^2 then
        state.since, state.mark = now, position
        return
    end
    if now - state.since < M.STUCK_TIME then return end

    -- Pressed against something. Fan out from the direct heading and take the
    -- nearest side that is actually walkable.
    --
    -- The bounds test is geometry plus "am I allowed there", but only while the
    -- companion is in bounds to begin with. Catching up to a leader who ran off
    -- means being outside the activity range already, and insisting the detour
    -- be inside it would veto every candidate in exactly the situation this
    -- exists for.
    local locomotor = inst.components.locomotor
    if locomotor == nil then return end
    local caps = M.Caps(inst)
    local bounded = M.InTravelRange(inst, position)
    local heading = math.atan2(goal.z - position.z, goal.x - position.x)
    for index = 1, 10 do
        local offset = math.ceil(index / 2) * (index % 2 == 0 and 1 or -1)
        local angle = heading + offset * math.pi / 6
        local point = Vector3(position.x + math.cos(angle) * M.SIDESTEP_DISTANCE, 0,
            position.z + math.sin(angle) * M.SIDESTEP_DISTANCE)
        if M.IsLand(point) and M.IsStepClear(inst, position, point, caps)
            and (not bounded or M.InTravelRange(inst, point)) then
            state.detour, state.expires = point, now + M.SIDESTEP_COMMIT
            state.since, state.mark = now, position
            return point
        end
    end
    -- Boxed in on every side. Wait out another interval instead of rescanning
    -- sixteen directions every frame.
    state.since = now
end

function M.GetSteeringPoint(inst, goal)
    if inst:HasTag("playerghost") then
        M.CancelSteering(inst)
        inst._my_friend_steering_cache = nil
        return goal
    end
    local origin, caps = inst:GetPosition(), M.Caps(inst)
    local cached = inst._my_friend_steering_cache
    if cached ~= nil and GetTime() < cached.untiltime
        and DistanceSq(goal, cached.goal) < .25 and DistanceSq(origin, cached.origin) < 1 then
        return cached.point
    end
    if DistanceSq(origin, goal) > 24^2 or not M.InTravelRange(inst, origin)
        or not M.InTravelRange(inst, goal) or M.IsWalkClear(inst, origin, goal, caps) then
        M.CancelSteering(inst)
        inst._my_friend_steering_cache = {goal = goal, origin = origin, point = goal, untiltime = GetTime() + .25}
        return goal
    end
    local state = inst._my_friend_local_walk
    if state ~= nil and DistanceSq(state.goal, goal) > 1 then
        M.CancelSteering(inst)
        state = nil
    end
    if state == nil then
        state = {goal = goal, search = M.Start(inst, goal), started = GetTime()}
        inst._my_friend_local_walk = state
    end
    if state.failed then
        if GetTime() > state.started + 5 then M.CancelSteering(inst) end
        return
    end
    if GetTime() > state.started + 20 then
        M.CancelSteering(inst)
        return
    end
    if state.steps == nil then
        local steps = M.Poll(state.search)
        if steps == false then
            M.Cancel(state.search)
            state.failed, state.started = true, GetTime()
            return
        end
        if steps == nil then return end
        state.steps, state.index = steps, 1
    end
    while state.index <= #state.steps and DistanceSq(origin, state.steps[state.index]) < .25^2 do
        state.index = state.index + 1
    end
    if state.index > #state.steps then return goal end
    local last = state.index
    for index = state.index, #state.steps do
        if DistanceSq(origin, state.steps[index]) > 12^2 then break end
        if M.IsWalkClear(inst, origin, state.steps[index], caps) then last = index end
    end
    local point = state.steps[last]
    if not M.IsWalkClear(inst, origin, point, caps) then
        M.CancelSteering(inst)
        return
    end
    state.index = last
    return Vector3(point.x, 0, point.z)
end

return M
