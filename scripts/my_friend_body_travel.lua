local Navigation = require("my_friend_navigation")
local Platforms = require("my_friend_platforms")
local Observation = require("my_friend_body_observation")
local M = {}

local function DistanceSq(a, b)
    return (a.x - b.x)^2 + (a.z - b.z)^2
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
        job.point = inst:GetPosition()
    else return false, "invalid_destination" end
    return true
end

function M.SetPosition(job, point)
    local surface, platform = Platforms.Surface(point)
    if surface ~= "boat" and (surface ~= "land" or not Navigation.IsLand(point)) then return false end
    job.point, job.point_platform = point, platform
    if platform ~= nil then job.deck_point = Vector3(platform.entity:WorldToLocalSpace(point:Get())) end
    return true
end

function M.Point(job, target)
    if target ~= nil then return target:GetPosition() end
    local platform = job.point_platform
    if platform == nil then return job.point end
    if platform:IsValid() then return Vector3(platform.entity:LocalToWorldSpace(job.deck_point:Get())) end
end

function M.Needed(inst, job, surface, point)
    return job.travel ~= nil or job.args.destination ~= nil or surface == "boat" or surface == "water"
        or inst:GetCurrentPlatform() ~= nil
        or DistanceSq(inst:GetPosition(), point) > 32^2
end

local function WithinJob(job, point)
    return job.skill == "move_to" or DistanceSq(job.origin, point) <= 96^2
end

local function CurrentPlatform(inst, job)
    local platform = inst:GetCurrentPlatform()
    local crossing = job.travel ~= nil and job.travel.crossing or nil
    if crossing == "land" then return Platforms.ConfirmLanding(inst, platform) end
    if crossing ~= nil then return Platforms.ConfirmBoarding(inst, crossing) end
    return platform
end

local function Begin(inst, job)
    local current = inst:GetPosition()
    local now, aboard = GetTime(), inst:GetCurrentPlatform()
    local mark = current
    if aboard ~= nil then mark = Vector3(aboard.entity:WorldToLocalSpace(current:Get())) end
    local route = job.travel
    if route == nil then
        route = {platform = aboard, position = mark, progress_at = now, choices = {}}
        job.travel = route
        local cleanup = job.cleanup
        job.cleanup = function()
            job.travel = nil
            if inst:IsValid() then
                Platforms.ResetRoute(inst)
                if not require("my_friend_policy").IsBusy(inst) then inst.components.locomotor:Stop() end
            end
            if cleanup ~= nil then cleanup() end
        end
        Platforms.ResetRoute(inst)
    end
    if route.platform ~= aboard then
        Platforms.ResetRoute(inst)
        route.platform, route.position, route.progress_at = aboard, mark, now
        route.step, route.crossing = nil, nil
    elseif DistanceSq(mark, route.position) >= .5^2 then
        route.position, route.progress_at = mark, now
    end
    return route, now
end

local function WalkLand(inst, job, route, point, now)
    local waypoint = Navigation.GetLongFollowPoint(inst, point)
    if waypoint == nil then inst.components.locomotor:Stop(); return end
    local step = Navigation.GetSteeringPoint(inst, waypoint, true)
    step = Navigation.Unstick(inst, step or waypoint) or step
    if step == nil or not WithinJob(job, step) then inst.components.locomotor:Stop(); return end
    if route.step == nil or now >= route.refresh or DistanceSq(route.step, step) > 1 then
        Navigation.MoveToPoint(inst, step, job.gait ~= "walk")
        route.step, route.refresh = step, now + .45
    end
end

-- Keep a live standing point until it moves out of range, changes surface,
-- or stalls. Retrying excludes the failed point, including near duplicates.
local function StandingPoint(inst, route, key, center, radius, expected_platform, aim, now)
    local choice = route.choices[key]
    if choice == nil or DistanceSq(center, choice.center) > .75^2 then
        choice = {center = center, failed = {}}
        route.choices[key] = choice
    end
    if choice.point ~= nil then
        local kind, platform = Platforms.Surface(choice.point)
        if platform == choice.platform and (expected_platform == nil or expected_platform == (platform or false))
            and (kind == "boat" or kind == "land" and Navigation.IsLand(choice.point))
            and DistanceSq(choice.point, center) <= radius^2 then return choice.point, platform end
        choice.point = nil
    end
    local aboard = inst:GetCurrentPlatform()
    local best, best_platform, best_score, other, other_platform, other_score
    local angle = math.atan2(aim.z - center.z, aim.x - center.x)
    for _, fraction in ipairs({.35, .65, .85, .95}) do
        for i = 0, 15 do
            local a, r = angle + i * math.pi / 8, radius * fraction
            local point = Vector3(center.x + math.cos(a) * r, 0, center.z + math.sin(a) * r)
            local kind, platform = Platforms.Surface(point)
            if (expected_platform == nil or expected_platform == (platform or false))
                and (kind == "boat" or kind == "land" and Navigation.IsLand(point)) then
                local score = math.sqrt(DistanceSq(point, aim))
                -- Never approach from a point already rejected by this job.
                for _, failed in ipairs(choice.failed) do
                    if DistanceSq(point, failed) <= .55^2 then score = math.huge; break end
                end
                if expected_platform == nil and platform ~= aboard then
                    score = score + 8
                    if score < (other_score or math.huge) then other, other_platform, other_score = point, platform, score end
                elseif score < (best_score or math.huge) then
                    best, best_platform, best_score = point, platform, score
                end
            end
        end
    end
    if other ~= nil then
        -- A point on the far side of a bay can be close as the crow flies.
        -- Prefer the alternate deck when the land approach needs a detour.
        if best ~= nil and aboard == nil and not Navigation.IsClear(aim, best, Navigation.Caps(inst)) then
            best_score = best_score + 12
        end
        if best == nil or other_score < best_score then best, best_platform = other, other_platform end
    end
    choice.point, choice.platform = best, best_platform
    if best ~= nil then choice.chosen_at = now end
    return best, best_platform
end

local function RetryPoint(inst, route, key, now, wait)
    local choice = route.choices[key]
    if choice == nil or choice.point == nil or now - math.max(choice.chosen_at, route.progress_at) < wait
        or #choice.failed >= 4 then return false end
    choice.failed[#choice.failed + 1], choice.point = choice.point, nil
    route.crossing, route.step = nil, nil
    Platforms.ResetRoute(inst)
    inst.components.locomotor:Stop()
    return true
end

local function HopRadius(inst, boat)
    local locomotor = inst.components.locomotor
    local walkable = boat.components.walkableplatform
    local hop = locomotor:GetHopDistance(locomotor:GetSpeedMultiplier())
    if walkable.max_hop_distance ~= nil then hop = math.min(hop, walkable.max_hop_distance) end
    -- Leave room for vanilla to find two valid landing samples.
    return walkable.platform_radius + math.max(.5, hop - .75)
end

local function Hop(inst, job, route, point, platform)
    if not WithinJob(job, point) then return "target_out_of_range" end
    local locomotor = inst.components.locomotor
    if not locomotor.allow_platform_hopping then return "platform_hopping_unavailable" end
    if route.crossing ~= (platform or "land") then
        locomotor:SetAllowPlatformHopping(true)
        route.crossing = platform or "land"
    end
    Platforms.Run(inst, point, job.gait ~= "walk", true)
end

local function DeckClear(inst, current, point, platform)
    local distance = math.sqrt(DistanceSq(current, point))
    local samples = math.max(1, math.ceil(distance / .5))
    local map = TheWorld.Map
    for index = 1, samples do
        local t = index / samples
        if map:GetPlatformAtPoint(current.x + (point.x - current.x) * t,
            current.z + (point.z - current.z) * t) ~= platform then return false end
    end
    return Navigation.IsPhysicalStepClear(inst, current, point, nil, platform)
end

local function WalkDeck(inst, job, route, current, point, platform, now)
    local step = point
    if not DeckClear(inst, current, point, platform) then
        if now < (route.deck_retry_at or 0) then return end
        route.deck_retry_at = now + .6
        step = nil
        local angle = math.atan2(point.z - current.z, point.x - current.x)
        -- One short sidestep can go around deck fixtures while staying aboard.
        for _, turn in ipairs({1, -1, 2, -2, 3, -3}) do
            local a = angle + turn * math.pi / 4
            local offset = Vector3(current.x + 1.5 * math.cos(a), 0, current.z + 1.5 * math.sin(a))
            if WithinJob(job, offset) and DeckClear(inst, current, offset, platform) then step = offset; break end
        end
    end
    if step ~= nil then Platforms.Run(inst, step, job.gait ~= "walk", true)
    else inst.components.locomotor:Stop() end
end

local function Advance(inst, job, route, current, aboard, point, platform, now)
    if not WithinJob(job, point) then return "target_out_of_range" end
    if platform ~= nil and platform ~= aboard
        and not inst.components.locomotor:IsValidDestinationPlatform(aboard, platform) then return "boat_unavailable" end
    if aboard == platform then
        if now - route.progress_at > (aboard ~= nil and 12 or 28) then return "unreachable" end
        job.stage = aboard ~= nil and "moving_on_boat" or "travelling"
        if aboard ~= nil then WalkDeck(inst, job, route, current, point, aboard, now)
        else WalkLand(inst, job, route, point, now) end
    elseif aboard == nil then
        job.stage = "boarding"
        local center = platform:GetPosition()
        local shore = StandingPoint(inst, route, "board", center, HopRadius(inst, platform), false, current, now)
        if shore == nil then return "no_boarding_point" end
        if RetryPoint(inst, route, "board", now, 8) then return end
        if now - route.progress_at > 12 then return "boat_unreachable" end
        if DistanceSq(current, shore) > .4^2 then WalkLand(inst, job, route, shore, now)
        else return Hop(inst, job, route, center, platform) end
    else
        job.stage = platform ~= nil and "boarding" or "going_ashore"
        if now - route.progress_at > 12 then return platform ~= nil and "boat_unreachable" or "no_shore_near_boat" end
        if platform == nil then
            local shore = StandingPoint(inst, route, "shore", aboard:GetPosition(), HopRadius(inst, aboard), false, point, now)
            if shore == nil then return "no_shore_near_boat" end
            if RetryPoint(inst, route, "shore", now, 5) then return end
            point = shore
        else
            point = platform:GetPosition()
        end
        return Hop(inst, job, route, point, platform)
    end
end

local function Approach(inst, job, point, surface, platform, reach, stand_near)
    local current, aboard = inst:GetPosition(), CurrentPlatform(inst, job)
    if not WithinJob(job, point) then return nil, "target_out_of_range" end
    if inst.components.locomotor.hopping then return end
    local stand = Platforms.Surface(current, inst)
    if stand == "water" then return nil, "no_walkable_surface" end
    if (stand == "land" or stand == "boat") and (surface == "water" or aboard == platform)
        and DistanceSq(current, point) <= reach^2 then
        if job.travel ~= nil and not job.travel.arrived then
            Platforms.ResetRoute(inst)
            inst.components.locomotor:Stop()
            job.travel.arrived = true
        end
        return true
    end
    local route, now = Begin(inst, job)
    route.arrived = nil
    local goal, key = point, nil
    if surface == "water" or stand_near then
        key = surface == "water" and "water" or "interaction"
        local expected_platform
        if surface ~= "water" then expected_platform = platform or false end
        local candidate, deck = StandingPoint(inst, route, key, point, reach, expected_platform, current, now)
        if candidate ~= nil then goal, platform = candidate, deck
        elseif surface == "water" then return nil, "no_surface_in_reach" end
        if RetryPoint(inst, route, key, now, 8) then return end
    end
    local reason = Advance(inst, job, route, current, aboard, goal, platform, now)
    if reason ~= nil and key ~= nil and RetryPoint(inst, route, key, now, 0) then return end
    return nil, reason
end

function M.Step(inst, state, job, target, point, surface, platform)
    local current, aboard = inst:GetPosition(), CurrentPlatform(inst, job)
    if job.args.destination == "shore" then
        if aboard == nil then
            if Platforms.Surface(current, inst) ~= "land" then return nil, "invalid_terrain" end
            point, surface, platform = current, "land", nil
        else
            local route, now = Begin(inst, job)
            if inst.components.locomotor.hopping then return end
            return nil, Advance(inst, job, route, current, aboard, current, nil, now)
        end
    end
    if surface == "unknown" then return nil, "invalid_terrain" end
    local reached, reason
    if platform == nil or target ~= platform or aboard ~= platform then
        reached, reason = Approach(inst, job, point, surface, platform, target == platform and platform ~= nil and .5 or job.distance)
    else reached = true end
    if not reached then return nil, reason end
    local actual = Platforms.Surface(current, inst)
    return {position = {x = current.x, z = current.z}, target = job.args.target,
        destination = job.args.destination, gait = job.gait, surface = actual, platform = Observation.Handle(state, aboard),
        distance = Observation.Distance(current, point), target_surface = surface}
end

-- Shared by single actions, batches and sequence steps. Keep the original
-- BufferedAction and its checks until the companion can actually reach it.
function M.ApproachAction(inst, action)
    local target, kind = action.target, action.action
    if TheWorld == nil or TheWorld.Map == nil or target == inst or action._my_friend_cast_in_place
        or action._my_friend_native_range and (target == nil or kind.distance ~= nil or kind.customarrivecheck ~= nil)
        or kind.do_not_locomote or kind.instant or kind.disable_platform_hopping then return action end
    local point = target ~= nil and target:IsValid() and target:GetPosition() or action:GetActionPoint()
    if point == nil then return action end
    local surface, platform = Platforms.Surface(point, target)
    if surface == "unknown" or surface == "land" and inst:GetCurrentPlatform() == nil
        and action._body_job.travel == nil and not action._my_friend_surface_ready then return action end
    if not action:IsValid() then return nil, action._body_job.operation_error or "target_unavailable", surface, point end
    if surface == "water" and target ~= nil and target == action.invobject
        and action._body_job.skill == "pickup" then
        -- Ground pickup is wrapped for stack accounting. Restore the native
        -- pickup reach for a floating item instead of using the wrapper's 2.2.
        action.arrivedist = Navigation.ArrivalDistance(inst, {target = target, action = ACTIONS.PICKUP})
    elseif action._body_job.skill == "pickup" and action._body_operation == "transfer"
        and target ~= nil and target == action.invobject then
        action.arrivedist = 2.2
    end
    local reach = action.arrivedist or Navigation.ArrivalDistance(inst, action)
    local reached, reason = Approach(inst, action._body_job, point, surface, platform, reach, true)
    if not reached then return nil, reason, surface, point end
    action._my_friend_surface_ready = true
    return action
end

function M.CanOperate(inst, action)
    local target = action.target
    if target == nil then return true end
    local current, point = inst:GetPosition(), target:GetPosition()
    local surface, platform = Platforms.Surface(point, target)
    local stand, aboard = Platforms.Surface(current, inst)
    return (stand == "land" or stand == "boat") and surface ~= "unknown" and (surface == "water" or aboard == platform)
        and DistanceSq(current, point) <= ((action.arrivedist or 2.2) + .15)^2
end

return M
