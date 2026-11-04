local Navigation = require("my_friend_navigation")
local Platforms = require("my_friend_platforms")
local Observation = require("my_friend_body_observation")
local M = {}

local function DistanceSq(a, b)
    return (a.x - b.x)^2 + (a.z - b.z)^2
end
local function IsShore(point)
    local map = TheWorld.Map
    return Navigation.IsLand(point)
        and (map.GetPlatformAtPoint == nil or map:GetPlatformAtPoint(point.x, point.z) == nil)
end

function M.Prepare(inst, job)
    local args = job.args
    if args.target ~= nil or args.position ~= nil then return false, "choose_one_destination" end
    if args.destination == "base" then
        local base = require("my_friend_home").Status(inst)
        if not base.known then return false, "base_unknown_in_this_shard" end
        job.point = Vector3(base.position.x, 0, base.position.z)
        if not Navigation.IsLand(job.point) then return false, "invalid_terrain" end
    elseif args.destination == "speaker" then
        if not require("my_friend_policy").IsLocalPlayer(job.issuer) then return false, "speaker_in_other_shard" end
        job.target = job.issuer.GUID
    elseif args.destination == "shore" then
        local origin = inst:GetPosition()
        if inst:GetCurrentPlatform() == nil then
            if not Navigation.IsLand(origin) then return false, "invalid_terrain" end
            job.point = origin
        else
            -- Sample from the current deck. The native locomotor decides
            -- whether it can actually hop the gap to the selected shore.
            for radius = 1, 12 do
                for i = 0, 15 do
                    local angle = i * math.pi / 8
                    local dx, dz = math.cos(angle), math.sin(angle)
                    local point = Vector3(origin.x + radius * dx, 0, origin.z + radius * dz)
                    local inland = Vector3(point.x + dx, 0, point.z + dz)
                    if IsShore(point) and IsShore(inland) then job.point = inland; break end
                end
                if job.point ~= nil then break end
            end
            if job.point == nil then return false, "no_shore_near_boat" end
        end
    else return false, "invalid_destination" end
    return true
end

function M.Crossing(inst, target)
    local platform = target ~= nil and (target.components.walkableplatform ~= nil and target
        or target.GetCurrentPlatform ~= nil and target:GetCurrentPlatform()) or nil
    return inst:GetCurrentPlatform() ~= platform, platform
end

function M.Needed(inst, job, target, point)
    if job.travel ~= nil or job.args.destination ~= nil then return true end
    if target ~= nil and target.components.walkableplatform ~= nil then return true end
    local aboard = inst.GetCurrentPlatform ~= nil and inst:GetCurrentPlatform() ~= nil
    return aboard or target ~= nil and target.GetCurrentPlatform ~= nil and target:GetCurrentPlatform() ~= nil
        or DistanceSq(inst:GetPosition(), point) > 32^2
end

function M.Step(inst, state, job, target, point)
    local current = inst:GetPosition()
    local crossing, platform = M.Crossing(inst, target)
    if not crossing and (target == platform and platform ~= nil or DistanceSq(current, point) <= job.distance^2) then
        return {position = {x = current.x, z = current.z}, target = job.args.target,
            destination = job.args.destination, gait = job.gait,
            surface = platform ~= nil and "boat" or "land", platform = Observation.Handle(state, platform)}
    end
    local now = GetTime()
    local aboard = inst:GetCurrentPlatform()
    local mark = current
    if aboard ~= nil then mark = Vector3(aboard.entity:WorldToLocalSpace(current:Get())) end
    local route = job.travel
    if route == nil then
        route = {platform = aboard, position = mark, progress_at = now}
        job.travel = route
        local cleanup = job.cleanup
        job.cleanup = function()
            if inst:IsValid() then
                Platforms.ResetRoute(inst)
                if not require("my_friend_policy").IsBusy(inst) then inst.components.locomotor:Stop() end
            end
            if cleanup ~= nil then cleanup() end
        end
        Platforms.ResetRoute(inst)
        local locomotor = inst.components.locomotor
        -- An explicit new hop order may return to the surface just left.
        -- Vanilla resets its last-platform exclusion on new buffered input.
        if crossing and locomotor.allow_platform_hopping then locomotor:SetAllowPlatformHopping(true) end
    end
    if route.platform ~= aboard then
        Platforms.ResetRoute(inst)
        route.platform, route.position, route.progress_at = aboard, mark, now
        route.step = nil
    elseif DistanceSq(mark, route.position) >= .5^2 then
        route.position, route.progress_at = mark, now
    end
    if now - route.progress_at > (crossing and 16 or aboard == nil and 28 or 16) then return nil, "unreachable" end
    if crossing or aboard ~= nil then
        job.stage = crossing and (platform ~= nil and "boarding" or "going_ashore") or "moving_on_boat"
        -- Run stores progress in platform coordinates and retries a stale hop.
        Platforms.Run(inst, point, job.gait ~= "walk")
        return
    end
    job.stage = "travelling"
    local waypoint = Navigation.GetLongFollowPoint(inst, point)
    if waypoint == nil then inst.components.locomotor:Stop(); return end
    local step = Navigation.GetSteeringPoint(inst, waypoint, true)
    step = Navigation.Unstick(inst, step or waypoint) or step
    if step == nil then inst.components.locomotor:Stop(); return end
    if route.step == nil or now >= route.refresh or DistanceSq(route.step, step) > 1 then
        Navigation.MoveToPoint(inst, step, job.gait ~= "walk")
        route.step, route.refresh = step, now + .45
    end
end

return M
