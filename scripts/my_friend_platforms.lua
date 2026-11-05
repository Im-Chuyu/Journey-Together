local M = {}

function M.Surface(point, entity)
    local platform = entity ~= nil and entity.components.walkableplatform ~= nil and entity
        or entity ~= nil and entity.GetCurrentPlatform ~= nil and entity:GetCurrentPlatform() or nil
    if platform ~= nil then return "boat", platform end
    local map = TheWorld ~= nil and TheWorld.Map or nil
    if point == nil or map == nil then return "unknown" end
    if entity == nil and map.GetPlatformAtPoint ~= nil then
        platform = map:GetPlatformAtPoint(point.x, point.z)
        if platform ~= nil then return "boat", platform end
    end
    if map.IsVisualGroundAtPoint ~= nil and map:IsVisualGroundAtPoint(point.x, 0, point.z)
        or map.IsVisualGroundAtPoint == nil and require("my_friend_navigation").IsLand(point) then return "land" end
    if map.IsOceanTileAtPoint ~= nil and map:IsOceanTileAtPoint(point.x, 0, point.z) then return "water" end
    return "unknown"
end

-- A companion can remain in a boat's follower list after a native hop even
-- though it is standing on land outside every deck. Clear that membership
-- through the vanilla platform API once the landing animation has finished.
function M.ConfirmLanding(inst, platform)
    if platform == nil or not platform:IsValid() or inst.platform ~= platform or inst.components.locomotor.hopping
        or inst.sg ~= nil and inst.sg:HasStateTag("jumping")
        or M.Surface(inst:GetPosition()) ~= "land" then return platform end
    local walkable = platform.components.walkableplatform
    if walkable ~= nil then walkable:RemoveObject(inst) end
    if inst.platform == platform then platform:RemovePlatformFollower(inst) end
    return inst:GetCurrentPlatform()
end

function M.ConfirmBoarding(inst, expected)
    local current = inst:GetCurrentPlatform()
    if current == expected or not expected:IsValid() or inst.components.locomotor.hopping
        or inst.sg ~= nil and inst.sg:HasStateTag("jumping") then return current end
    local _, deck = M.Surface(inst:GetPosition())
    if deck == expected then
        if current ~= nil and inst.platform == current then
            local old = current.components.walkableplatform
            if old ~= nil then old:RemoveObject(inst) end
        end
        deck.components.walkableplatform:AddEntityToPlatform(inst)
        return inst:GetCurrentPlatform()
    end
    return current
end

local function Capture(point, platform)
    if platform ~= nil and platform:IsValid() then
        local x, y, z = platform.entity:WorldToLocalSpace(point:Get())
        return {point = Vector3(x, y, z), platform = platform}
    end
    return {point = Vector3(point:Get())}
end

local function Resolve(location)
    if location.platform ~= nil then
        if not location.platform:IsValid() then return end
        return Vector3(location.platform.entity:LocalToWorldSpace(location.point:Get()))
    end
    return location.point
end

-- Like vanilla Follow: platform identity only matters for the current target.
-- Never replay where the leader boarded or disembarked in the past.
function M.NeedsCrossing(inst, leader)
    return leader ~= nil and leader:IsValid()
        and inst:GetCurrentPlatform() ~= leader:GetCurrentPlatform()
end

function M.NeedsBoardingStep(inst)
    local platform = inst:GetCurrentPlatform()
    return inst._my_friend_boarding_step ~= nil
        or platform ~= nil and platform ~= inst._my_friend_move_platform
            and platform.components ~= nil and platform.components.walkableplatform ~= nil
end

function M.ResetRoute(inst)
    local navigation = require("my_friend_navigation")
    navigation.CancelSteering(inst)
    navigation.ClearStuck(inst)
    inst._my_friend_land_route = nil
    inst._my_friend_long_follow = nil
    inst._my_friend_last_move = nil
    local locomotor = inst.components.locomotor
    locomotor:ResetPath()
    locomotor.lastdesttile = nil
end

function M.ResetAfterPlatformChange(inst, leader)
    local platform = inst:GetCurrentPlatform()
    local leader_platform = leader ~= nil and leader:GetCurrentPlatform() or nil
    local leader_guid = leader ~= nil and leader.GUID or nil
    local leader_platform_guid = leader_platform ~= nil and leader_platform.GUID or nil
    if inst._my_friend_move_platform == platform
        and inst._my_friend_move_leader_guid == leader_guid
        and inst._my_friend_move_leader_platform_guid == leader_platform_guid then return end
    local boarded = platform ~= nil and inst._my_friend_move_platform ~= platform
    inst._my_friend_move_platform = platform
    inst._my_friend_move_leader_guid = leader_guid
    inst._my_friend_move_leader_platform_guid = leader_platform_guid
    M.ResetRoute(inst)
    if boarded then
        inst._my_friend_boarding_step = nil
        local walkable = platform.components ~= nil and platform.components.walkableplatform or nil
        if leader ~= nil and walkable ~= nil then
            local origin, target = inst:GetPosition(), leader:GetPosition()
            local dx, dz = target.x - origin.x, target.z - origin.z
            local distance = math.sqrt(dx * dx + dz * dz)
            local radius = math.max(0, walkable.platform_radius - inst:GetPhysicsRadius(.5) - .25)
            local point
            local ox, _, oz = platform.entity:WorldToLocalSpace(origin:Get())
            local previous_radius_sq, entered = ox^2 + oz^2, false
            -- One bounded deck check at boarding. Never turn this move into
            -- another hop, even if the leader has already disembarked.
            if distance > .5 then
                for step = 1, math.ceil(math.min(4, distance) / .25) do
                    local length = math.min(step * .25, distance, 4)
                    local candidate = Vector3(origin.x + dx / distance * length, 0,
                        origin.z + dz / distance * length)
                    local lx, _, lz = platform.entity:WorldToLocalSpace(candidate:Get())
                    local radius_sq = lx^2 + lz^2
                    if radius_sq > radius^2 then
                        -- Vanilla lands half a unit from the edge, sometimes
                        -- just outside our extra margin. Allow moving inward.
                        if entered or radius_sq >= previous_radius_sq then break end
                    else
                        point, entered = candidate, true
                    end
                    previous_radius_sq = radius_sq
                end
            end
            if point ~= nil then
                inst._my_friend_boarding_step = {location = Capture(point, platform),
                    leader_guid = leader.GUID, deadline = GetTime() + 6}
            end
        end
    elseif platform == nil then
        inst._my_friend_boarding_step = nil
    end
end

function M.FollowBoardingStep(inst, leader)
    local step = inst._my_friend_boarding_step
    if step == nil then return false end
    local point = Resolve(step.location)
    if leader == nil or leader.GUID ~= step.leader_guid or point == nil
        or inst:GetCurrentPlatform() ~= step.location.platform
        or GetTime() >= step.deadline or inst:GetDistanceSqToPoint(point) <= .5^2 then
        inst._my_friend_boarding_step = nil
        M.ResetRoute(inst)
        return false
    end
    M.Run(inst, point)
    return true
end

-- Retry a stale destination only after lack of progress. Measure progress in
-- platform coordinates so a moving boat cannot disguise a stuck companion.
function M.Run(inst, target, run, direct)
    run = run ~= false
    local now, old = GetTime(), inst._my_friend_last_move
    local locomotor = inst.components.locomotor
    local stalled = false
    local due = old == nil or now >= old.untiltime
    if old ~= nil and due then
        local mark = old.mark ~= nil and Resolve(old.mark) or nil
        if mark == nil or old.progress == nil or inst:GetDistanceSqToPoint(mark) > .25^2 then
            old.mark = Capture(inst:GetPosition(), inst:GetCurrentPlatform())
            old.progress = now
        else
            stalled = now - (old.progress or now) >= 1.5
        end
        old.untiltime = now + .5
    end
    if old == nil or old.run ~= run or old.direct ~= direct or due and locomotor.dest == nil or stalled
        or due and (old.point.x - target.x)^2 + (old.point.z - target.z)^2 > .25^2
        or (old.point.x - target.x)^2 + (old.point.z - target.z)^2 > 1 then
        if stalled then locomotor:ResetPath(); locomotor.lastdesttile = nil end
        if direct then
            require("my_friend_navigation").MoveToPoint(inst, target, run, true)
        else
            locomotor:GoToPoint(target, nil, run)
        end
        inst._my_friend_last_move = {point = target, run = run, direct = direct, untiltime = now + .5,
            mark = Capture(inst:GetPosition(), inst:GetCurrentPlatform()), progress = now}
    end
end

return M
