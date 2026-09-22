local M = {}

M.ACTIVITY_RANGE = 20
M.FOLLOW_RANGE = 7

function M.IsLocalPlayer(player)
    if player == nil or not player:IsValid() or player:HasTag("my_friend")
        or player._despawning then return false end
    for _, online in ipairs(AllPlayers or {}) do
        if online == player then return true end
    end
    return false
end

function M.ActivityRange(inst)
    local command = inst._my_friend_command
    return command ~= nil and command.player == M.GetLeader(inst) and 32 or M.ACTIVITY_RANGE
end

-- A leader who died stays the leader (keepdeadleader), but must not be
-- followed around as a ghost. The companion keeps vigil instead; see
-- my_friend_base_ai.GetWanderPoint and the "vigil" brain entry.
function M.IsLeaderDead(inst)
    local leader = M.GetLeader(inst)
    if leader == nil then return false end
    return leader:HasTag("playerghost")
        or leader.components ~= nil and leader.components.health ~= nil
            and leader.components.health:IsDead()
end

-- Centre and radius the companion is confined to while keeping vigil.
function M.GetVigilPoint(inst)
    local point = inst ~= nil and inst._my_friend_vigil_point or nil
    if point == nil or not M.IsLeaderDead(inst) then return end
    return Vector3(point.x, 0, point.z)
end

function M.UpdateVigil(inst)
    if not M.IsLeaderDead(inst) then
        inst._my_friend_vigil_point = nil
        return
    end
    if inst._my_friend_vigil_point == nil then
        -- Remember where we were standing when they fell, not wherever the
        -- ghost drifts to afterwards.
        local x, _, z = inst.Transform:GetWorldPosition()
        inst._my_friend_vigil_point = {x = x, z = z}
    end
end

function M.GetLeader(inst)
    local follower = inst.components ~= nil and inst.components.follower or nil
    local leader = follower ~= nil and follower:GetLeader() or nil
    return leader ~= nil and leader:IsValid() and leader or nil
end

function M.IsRoaming(inst)
    local command = inst._my_friend_command
    return command ~= nil and (command.id == "explore" or command.id == "fish" or command.id == "adopt_pet")
        and command.player == M.GetLeader(inst) and M.IsLocalPlayer(command.player)
        and GetTime() < command.deadline and not inst:HasTag("playerghost")
end

function M.UpdateFollowRequest(inst, leader)
    if leader == nil then
        inst._my_friend_follow_requested_until = nil
        inst._my_friend_follow_settle_until = nil
        return false
    end
    local deadline = inst._my_friend_follow_requested_until
    if deadline == nil then return false end
    local now = GetTime()
    local arrived = inst:GetCurrentPlatform() == leader:GetCurrentPlatform()
        and M.DistanceSq(inst, leader) <= 9
    if arrived or now >= deadline then
        inst._my_friend_follow_requested_until = nil
        inst._my_friend_follow_settle_until = now + 6
        return false
    end
    return true
end

function M.IsFollowGatheringPaused(inst)
    return M.GetLeader(inst) ~= nil
        and (GetTime() < (inst._my_friend_follow_requested_until or 0)
            or GetTime() < (inst._my_friend_follow_settle_until or 0))
end

function M.DistanceSq(a, b)
    local ax, _, az = a.Transform:GetWorldPosition()
    local bx, _, bz = b.Transform:GetWorldPosition()
    return (ax - bx)^2 + (az - bz)^2
end

function M.InRange(inst, target, radius)
    local point = inst._my_friend_auto_recovery_point
    if point ~= nil and inst._my_friend_recover_death_drops and target ~= nil then
        if target == inst then return true end
        if target:HasTag("my_friend_death_drop") or target:HasTag("my_friend_remains") then
            local x, _, z = target.Transform:GetWorldPosition()
            if (x - point.x)^2 + (z - point.z)^2 <= 18^2 then return true end
        end
    end
    local leader = M.GetLeader(inst)
    if M.IsRoaming(inst) then
        return target ~= nil and M.DistanceSq(inst, target) <= (radius or M.ACTIVITY_RANGE)^2
    end
    return leader == nil or target ~= nil
        and M.DistanceSq(leader, target) <= (radius or M.ActivityRange(inst))^2
end

function M.IsDeathRecoveryAction(inst, action)
    return action ~= nil and action._my_friend_death_recovery ~= nil
        and inst._my_friend_recover_death_drops == true
end

function M.SearchOrigin(inst, free_range)
    local leader = not M.IsRoaming(inst) and M.GetLeader(inst) or nil
    local x, y, z = (leader or inst).Transform:GetWorldPosition()
    return x, y, z, leader ~= nil and M.ACTIVITY_RANGE or free_range
end

function M.IsBaseCacheItem(inst, item)
    local base = inst._my_friend_base
    if base == nil or base.cache_x == nil or item == nil or item.Transform == nil then return false end
    local inventoryitem = item.components ~= nil and item.components.inventoryitem or nil
    if inventoryitem == nil or inventoryitem.owner ~= nil then return false end
    local x, _, z = item.Transform:GetWorldPosition()
    return (x - base.cache_x)^2 + (z - base.cache_z)^2 <= 9
end

function M.GuardAction(inst, action, radius)
    if action == nil then return end
    local leader = M.GetLeader(inst)
    local previous = action.validfn
    action.validfn = function(act)
        if M.GetLeader(inst) ~= leader then return false end
        local target = act.target
        local point = act.GetActionPoint ~= nil and act:GetActionPoint() or nil
        if act._my_friend_wormhole ~= nil then
            local wormhole = require("my_friend_wormhole")
            if target ~= nil and not wormhole.InTravelRange(inst, act, target:GetPosition()) then return false end
            if point ~= nil and not wormhole.InTravelRange(inst, act, point) then return false end
        elseif act._my_friend_chop_delivery then
            local command = inst._my_friend_command
            if command == nil or command.id ~= "chop" or target ~= leader then return false end
        elseif act._my_friend_chop_loot ~= nil then
            if target == nil or target:GetDistanceSqToPoint(act._my_friend_chop_loot) > 5^2 then return false end
        elseif act._my_friend_command_origin ~= nil then
            local origin = act._my_friend_command_origin
            if target ~= nil and target:GetDistanceSqToPoint(origin) > 16^2 then return false end
            if point ~= nil and (point - origin):LengthSq() > 16^2 then return false end
        elseif act._my_friend_roaming ~= nil then
            if not M.IsRoaming(inst) or inst._my_friend_command ~= act._my_friend_roaming then return false end
        elseif act._my_friend_gather_command ~= nil then
            if inst._my_friend_command ~= act._my_friend_gather_command then return false end
        elseif leader ~= nil and not act._my_friend_owned_recovery
            and not M.IsDeathRecoveryAction(inst, act) then
            if target ~= nil and not M.InRange(inst, target, radius) then return false end
            if point ~= nil then
                local x, _, z = (M.IsRoaming(inst) and inst or leader).Transform:GetWorldPosition()
                if (point.x - x)^2 + (point.z - z)^2 > (radius or M.ActivityRange(inst))^2 then
                    return false
                end
            end
        end
        return previous == nil or previous(act)
    end
    return action
end

function M.IsBusy(inst)
    local state = inst.sg ~= nil and inst.sg.currentstate or nil
    -- Wilson's pocket loop is waiting for the next inventory action after
    -- frame 7. This is input waiting, even if a mode change cancelled the meal.
    -- Treating its remaining "doing" tag as busy would prevent replanning
    -- until an external equip event (such as the night-time torch) ends it.
    if state ~= nil and state.name == "start_pocket_rummage"
        and not inst.sg:HasStateTag("busy") then return false end
    return inst.sg ~= nil and (inst:HasTag("my_friend") and state ~= nil
        and (state.name == "eat" or state.name == "quickeat")
        or inst.sg:HasStateTag("busy")
        or inst.sg:HasStateTag("doing")
        or inst.sg:HasStateTag("working")
        or inst.sg:HasStateTag("prechop") or inst.sg:HasStateTag("premine")
        or inst.sg:HasStateTag("predig") or inst.sg:HasStateTag("prehammer"))
end

return M
