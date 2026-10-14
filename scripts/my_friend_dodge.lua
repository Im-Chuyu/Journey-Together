local Profiles = require("my_friend_dodge_profiles")
local Navigation = require("my_friend_navigation")
local M = {OBSTACLE_PERIOD = .25, ATTACK_MARGIN_FRAMES = 11, MOVE_MARGIN_FRAMES = 3}

local function Copy(point) return Vector3(point.x, 0, point.z) end
local function DistanceSq(a, b) return (a.x - b.x)^2 + (a.z - b.z)^2 end

function M.Reset(inst)
    local state = inst._my_friend_dodge
    if state ~= nil then
        state.target, state.row, state.enemypos, state.friendpos = nil, nil, nil, nil
        state.idle_since, state.lastframe = nil, nil
        state.monitoring, state.hold_attack = nil, nil
        state.obstacles, state.obstaclepos, state.obstacle_until = nil, nil, nil
    end
end

local function Match(inst, target, state)
    local context = state.profiles
    context.distance = math.sqrt(DistanceSq(inst:GetPosition(), target:GetPosition()))
    context.p_range = Profiles.AttackRange(inst)
    local entries = context.targetanimtable[target.prefab] or {}
    local frame = target.AnimState:GetCurrentAnimationFrame() or 0
    local known, matching_animation = false, false
    state.monitoring, state.hold_attack = false, false
    for _, row in ipairs(entries) do
        if not row.noused then
            known = true
            local animation = Profiles.Value(row.atkanim, nil, target)
            local same_animation = animation ~= nil and target.AnimState:IsCurrentAnimation(animation)
            matching_animation = matching_animation or same_animation
            local stop = same_animation and Profiles.Value(row.atk_stop_frame, 1000, target) or 1000
            local start = same_animation and Profiles.Value(row.atk_start_frame, 0, target) or 0
            if same_animation and row.atk_frame_calculate ~= nil then
                start = math.min(stop, Profiles.Value(row.atk_frame_calculate, start,
                    target, start, stop, true, row) - M.MOVE_MARGIN_FRAMES)
            end
            if same_animation and frame <= stop then
                state.monitoring = true
                -- Do not start a new protected attack windup immediately before
                -- the retreat deadline. The existing swing still gets its hit.
                if frame < start and start - frame <= M.ATTACK_MARGIN_FRAMES then
                    state.hold_attack = true
                end
            end
            local continuing = state.row == row and state.lastframe ~= nil and frame >= state.lastframe
            local attacking = same_animation
                and frame <= stop and (continuing or frame >= start)
            local idleframes = (GetTime() - (state.idle_since or GetTime())) * 30
            local idle = Profiles.Value(row.idledodge, nil, target)
            if row.resetidle ~= nil and Profiles.Value(row.resetidle, false, target) then
                state.idle_since = GetTime()
            end
            if (attacking or idle ~= nil and idleframes >= idle)
                and not (row.checkatktag and not target:HasTag("attack")
                    and not (target.sg ~= nil and target.sg:HasStateTag("attack")))
                and not Profiles.Value(row.breakdodgefn, false, target) then
                state.lastframe, state.idle_since = frame, GetTime()
                return row, known
            end
        end
    end
    if state.row ~= nil and Profiles.Value(state.row.avoid_break, false, target) then return state.row, known end
    if known and not matching_animation and target.sg ~= nil and target.sg.HasAnyStateTag ~= nil
        and target.sg:HasAnyStateTag("attack", "abouttoattack") then known = false end
    return nil, known
end

local function Aim(inst, target, state, row)
    if state.row ~= row and not (state.row ~= nil and state.row.legacypos) then
        state.enemypos, state.friendpos = Copy(target:GetPosition()), Copy(inst:GetPosition())
    end
    state.row = row
    local own = inst:GetPosition()
    local enemypos = row.update ~= false and target:GetPosition() or state.enemypos
    local friendpos = row.update ~= false and own or state.friendpos
    local anchor, other = enemypos, friendpos
    if Profiles.Value(row.point, "target", target) ~= "target" then anchor, other = friendpos, enemypos end
    local distance = Profiles.Value(row.dist, nil, target)
    if distance == nil then
        distance = (Profiles.Value(row.combatdist, nil, target) or Profiles.AttackRange(target))
            * (row.combat_scale or 1) + inst:GetPhysicsRadius(0)
            + (row.calculate_offset or .4) + .1 + (row.extradist or 0)
            + Profiles.Value(row.combat_offset, 0, target)
    end
    local angle = Profiles.Value(row.angle, 0, target)
    if anchor == enemypos and angle == 0 and distance >= 0
        and DistanceSq(enemypos, own) >= distance^2 then return Copy(own) end
    local dx, dz = other.x - anchor.x, other.z - anchor.z
    local length = math.sqrt(dx * dx + dz * dz)
    if length < .001 then dx, dz, length = 1, 0, 1 end
    local cosine, sine = math.cos(angle), math.sin(angle)
    return Vector3(anchor.x + distance * (dx * cosine - dz * sine) / length,
        0, anchor.z + distance * (dx * sine + dz * cosine) / length)
end

local function SafeStep(inst, state, from, point)
    local platform = inst:GetCurrentPlatform()
    if platform ~= nil then
        local map = TheWorld.Map
        return map:GetPlatformAtPoint(point.x, point.z) == platform
            and map:GetPlatformAtPoint((from.x + point.x) / 2, (from.z + point.z) / 2) == platform
    end
    -- All five alternatives share one small collision query. Keep it across
    -- frame checks; terrain/platform safety is still checked for every step.
    local now = GetTime()
    if state.obstacles == nil or now >= (state.obstacle_until or 0)
        or DistanceSq(from, state.obstaclepos) > 2^2 then
        state.obstacles = TheSim:FindEntities(from.x, 0, from.z, 8, nil, {"INLIMBO", "FX"})
        state.obstaclepos, state.obstacle_until = Copy(from), now + M.OBSTACLE_PERIOD
    end
    return Navigation.IsStepClear(inst, from, point, Navigation.Caps(inst), state.obstacles, true)
end

function M.GetDecision(inst, target)
    if target == nil or not target:IsValid() or target.AnimState == nil
        or target.AnimState.GetCurrentAnimationFrame == nil
        or target.components.health == nil or target.components.health:IsDead() then return nil, false, false end
    local state = inst._my_friend_dodge
    if state == nil then
        state = {profiles = Profiles.Create(inst)}
        inst._my_friend_dodge = state
    end
    if state.target ~= target then
        M.Reset(inst)
        state.target = target
        state.idle_since = GetTime() - (target.prefab == "tallbird" and 50 / 30 or 0)
    end
    local row, known = Match(inst, target, state)
    if row == nil then
        state.row, state.lastframe = nil, nil
        return nil, false, known, state.hold_attack
    end
    local from, aim = inst:GetPosition(), Aim(inst, target, state, row)
    local dx, dz = aim.x - from.x, aim.z - from.z
    local length = math.sqrt(dx * dx + dz * dz)
    if length <= .1 then return nil, true, known end
    -- Move in short verified steps toward the dodge destination. Rotation
    -- alternatives let a side-step avoid a wall without running into water.
    local distance = math.min(length, 2)
    for _, angle in ipairs({0, math.pi / 4, -math.pi / 4, math.pi / 2, -math.pi / 2}) do
        local c, s = math.cos(angle), math.sin(angle)
        local point = Vector3(from.x + distance * (dx * c - dz * s) / length,
            0, from.z + distance * (dx * s + dz * c) / length)
        if SafeStep(inst, state, from, point) then return point, true, known end
    end
    return nil, true, known
end

return M
