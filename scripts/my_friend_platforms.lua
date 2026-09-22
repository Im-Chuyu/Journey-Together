local Policy = require("my_friend_policy")
local M = {}

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

-- Observe only. The follow node is the sole owner of locomotion.
function M.Observe(inst)
    local leader = Policy.GetLeader(inst)
    if leader == nil or leader:HasTag("playerghost") then
        inst._my_friend_platform_track = nil
        return
    end
    local track = inst._my_friend_platform_track
    if track == nil or track.leader ~= leader then
        track = {leader = leader}
        inst._my_friend_platform_track = track
    end
    local platform = leader:GetCurrentPlatform()
    local embarker = leader.components.embarker
    if embarker ~= nil and embarker:HasDestination() then
        if track.hop == nil then
            local x, z = embarker:GetEmbarkPosition()
            track.hop = {
                source = track.platform or platform,
                departure = track.position or Capture(leader:GetPosition(), platform),
                landing = Capture(Vector3(x, 0, z), embarker.embarkable),
                expires = GetTime() + 60,
            }
        end
        return
    end
    if track.platform ~= platform then
        local hop = track.hop
        if hop ~= nil then
            hop.destination = platform
            hop.landing = Capture(leader:GetPosition(), platform)
            track.crossing = hop
        elseif track.position ~= nil then
            track.crossing = {
                source = track.platform, destination = platform,
                departure = track.position, landing = Capture(leader:GetPosition(), platform),
                expires = GetTime() + 60,
            }
        end
    end
    track.hop = nil
    track.platform = platform
    track.position = Capture(leader:GetPosition(), platform)
end

function M.NeedsCrossing(inst, leader)
    return leader ~= nil and leader:IsValid()
        and inst:GetCurrentPlatform() ~= leader:GetCurrentPlatform()
end

function M.Target(inst, leader)
    local track = inst._my_friend_platform_track
    local crossing = track ~= nil and track.leader == leader and track.crossing or nil
    local platform = inst:GetCurrentPlatform()
    if crossing ~= nil and GetTime() < crossing.expires
        and crossing.source == platform and crossing.destination == leader:GetCurrentPlatform() then
        local departure = Resolve(crossing.departure)
        if departure ~= nil and not crossing.at_departure then
            if inst:GetDistanceSqToPoint(departure) > 1 then return departure end
            crossing.at_departure = true
        end
        local landing = Resolve(crossing.landing)
        if landing ~= nil then return landing end
    end
    return leader:GetPosition()
end

function M.FollowCrossing(inst, leader)
    if not M.NeedsCrossing(inst, leader) then return false end
    -- Let vanilla hopping own movement until landing. The destination may
    -- briefly share the leader's platform while the hop animation is active.
    if inst.sg ~= nil and inst.sg:HasStateTag("busy") then return true end
    local embarker = inst.components.embarker
    if embarker ~= nil and embarker:HasDestination() then return true end
    local target = M.Target(inst, leader)
    if inst.sg ~= nil and inst.sg:HasStateTag("my_friend_walk") then
        inst.sg:GoToState("idle")
    end
    local now, old = GetTime(), inst._my_friend_last_move
    -- Keep one destination while approaching the edge so locomotor can scan
    -- for a hop. Resolve again when the boat moves or the destination ends.
    if old == nil or not old.run
        or now >= old.untiltime and inst.components.locomotor.dest == nil
        or (old.point.x - target.x)^2 + (old.point.z - target.z)^2 > 1 then
        inst.components.locomotor:GoToPoint(target, nil, true)
        inst._my_friend_last_move = {point = target, run = true, untiltime = now + 1}
    end
    return true
end

return M
