local Policy = require("my_friend_policy")
local Dialogue = require("my_friend_dialogue")
local M = {}
M.RANGE = 16
M.TIMEOUT = 600
local PORTALS = {multiplayer_portal = true, multiplayer_portal_moonrock = true}

local function IsGhost(inst)
    return inst:IsValid() and inst:HasTag("playerghost")
end

local function Portal(target)
    return target ~= nil and target:IsValid() and PORTALS[target.prefab] == true
        and not target:IsInLimbo()
end

function M.IsUsable(inst, target, portal)
    if target == nil or not target:IsValid() or target:IsInLimbo()
        or target:HasAnyTag("haunted", "catchable") then return false end
    local c = target.components
    if c == nil or c.inventoryitem ~= nil and c.inventoryitem:IsHeld() then return false end
    if portal then return Portal(target) end
    local hauntable = c.hauntable
    if hauntable == nil or hauntable.hauntvalue ~= TUNING.HAUNT_INSTANT_REZ
        or (hauntable.cooldowntimer or 0) > 0 then return false end
    if target.prefab == "resurrectionstone" then
        return inst.CanUseTouchStone ~= nil and inst:CanUseTouchStone(target)
            and target._task == nil and target.AnimState:IsCurrentAnimation("idle_activate")
    end
    return true
end

local function FindTarget(inst, request)
    local candidates
    if request.portal then candidates = Ents or {}
    else
        local p = request.origin
        candidates = TheSim:FindEntities(p.x, 0, p.z, M.RANGE, nil, {"INLIMBO", "FX"})
    end
    local best, distance
    for _, target in pairs(candidates) do
        if M.IsUsable(inst, target, request.portal)
            and not request.failed[target.GUID or target] then
            local d = inst:GetDistanceSqToInst(target)
            if (request.portal or d <= M.RANGE^2)
                and (distance == nil or d < distance) then best, distance = target, d end
        end
    end
    return best
end

function M.Cancel(inst)
    if inst._my_friend_ghost_revive ~= nil then inst._my_friend_replan_requested = true end
    inst._my_friend_ghost_revive = nil
    inst._my_friend_portal_revive_requested, inst._my_friend_portal_target = nil, nil
end

function M.Request(inst, player, portal)
    if not IsGhost(inst) or not Policy.IsLocalPlayer(player) then return false end
    local leader = Policy.GetLeader(inst)
    if leader ~= nil and leader ~= player
        or leader == nil and inst:GetDistanceSqToInst(player) > M.RANGE^2 then return false end
    local request = {player = player, leader = leader, portal = portal == true,
        origin = inst:GetPosition(), failed = {}, deadline = GetTime() + (portal and M.TIMEOUT or 60)}
    request.target = FindTarget(inst, request)
    if request.target == nil then
        Dialogue.Reply(inst, portal and "ghost_revive_no_portal" or "ghost_revive_none")
        return false
    end
    require("my_friend_commands").Clear(inst)
    M.Cancel(inst)
    inst._my_friend_ghost_revive = request
    Dialogue.Reply(inst, portal and "ghost_revive_portal" or "ghost_revive_nearby")
    return true
end

local function GetRequest(inst)
    local request = inst._my_friend_ghost_revive
    if request == nil then return end
    if GetTime() >= request.deadline or not request.automatic
        and (not Policy.IsLocalPlayer(request.player) or Policy.GetLeader(inst) ~= request.leader) then
        M.Cancel(inst)
        return
    end
    return request
end

function M.RequestAutomatic(inst)
    if not IsGhost(inst) or GetRequest(inst) ~= nil then return false end
    local request = {automatic = true, portal = true, origin = inst:GetPosition(),
        failed = {}, deadline = GetTime() + M.TIMEOUT}
    request.target = FindTarget(inst, request)
    if request.target == nil then return false end
    require("my_friend_commands").Clear(inst)
    M.Cancel(inst)
    inst._my_friend_ghost_revive = request
    inst._my_friend_replan_requested = true
    return true
end

function M.Score(inst)
    local request = GetRequest(inst)
    return request ~= nil and IsGhost(inst) and 165 or 0
end

function M.GetAction(inst)
    local request = GetRequest(inst)
    if request == nil then return require("my_friend_revive_ai").GetPortalAction(inst) end
    if not IsGhost(inst) or Policy.IsBusy(inst) then return end
    if request.wait_until ~= nil then
        if GetTime() < request.wait_until then return end
        request.failed[request.target.GUID or request.target] = true
        request.wait_until, request.target = nil, nil
    end
    if not M.IsUsable(inst, request.target, request.portal) then request.target = FindTarget(inst, request) end
    local target = request.target
    if target == nil then
        M.Cancel(inst)
        Dialogue.Reply(inst, "ghost_revive_failed")
        return
    end
    local action = BufferedAction(inst, target, ACTIONS.HAUNT)
    action._my_friend_ghost_revive = request
    action.validfn = function()
        return GetRequest(inst) == request and IsGhost(inst) and M.IsUsable(inst, target, request.portal)
            and (request.portal or (target:GetPosition() - request.origin):LengthSq() <= M.RANGE^2)
    end
    action:AddSuccessAction(function()
        -- HAUNT succeeding does not guarantee resurrection: the target's
        -- callback may refuse. Wait for the real respawn event, with a limit.
        if inst._my_friend_ghost_revive == request and not request.returning then
            request.wait_until = GetTime() + 10
        end
    end)
    action:AddFailAction(function()
        if inst._my_friend_ghost_revive == request and not request.returning
            and not action._my_friend_cancelled then
            request.failed[target.GUID or target] = true
            request.target = nil
        end
    end)
    require("my_friend_base_ai").SetTask(inst, request.portal
        and "正在前往大门作祟复活" or "正在寻找附近的复活物品")
    return action
end

function M.OnRespawned(inst)
    local request = GetRequest(inst)
    if request == nil then return end
    request.returning, request.wait_until = true, nil
    request.deadline = GetTime() + M.TIMEOUT
    if request.automatic then
        local point = inst._my_friend_death_point
        if point == nil then M.Cancel(inst) return end
        request.origin = Vector3(point.x, 0, point.z)
        inst._my_friend_auto_recovery_point = request.origin
    end
    inst._my_friend_replan_requested = true
    if not request.automatic then Dialogue.Reply(inst, "ghost_revive_return") end
end

function M.ReturnScore(inst, context)
    local request = GetRequest(inst)
    if context ~= nil and (context.dark or context.thermal or (context.hunger or 1) < .4) then return 0 end
    return request ~= nil and request.returning and not IsGhost(inst)
        and (request.automatic and 118 or 112) or 0
end

function M.GetReturnAction(inst)
    local request = GetRequest(inst)
    if request == nil or not request.returning or IsGhost(inst) or Policy.IsBusy(inst) then return end
    if request.automatic and not require("my_friend_recovery_safety").IsSafe(inst, request.origin) then return end
    local distance = request.automatic and (inst:GetPosition() - request.origin):LengthSq()
        or inst:GetDistanceSqToInst(request.player)
    if distance <= (request.automatic and 3^2 or 5^2) then M.Cancel(inst) return end
    local action = request.automatic and BufferedAction(inst, nil, ACTIONS.WALKTO, nil, request.origin)
        or BufferedAction(inst, request.player, ACTIONS.WALKTO)
    action.arrivedist = request.automatic and 2 or 4
    require("my_friend_base_ai").SetTask(inst, request.automatic
        and "正在复活后返回死亡地点" or "正在复活后返回玩家身边")
    action._my_friend_revive_return = request
    action.validfn = function()
        return GetRequest(inst) == request and not IsGhost(inst)
            and (not request.automatic or require("my_friend_recovery_safety").IsSafe(inst, request.origin))
    end
    action:AddSuccessAction(function()
        if inst._my_friend_ghost_revive == request then M.Cancel(inst) end
    end)
    action:AddFailAction(function()
        if inst._my_friend_ghost_revive == request and not action._my_friend_cancelled then
            M.Cancel(inst)
            if not request.automatic then Dialogue.Reply(inst, "ghost_revive_return_blocked") end
        end
    end)
    return action
end

function M.OnPerform(inst, data)
    local action = data ~= nil and data.action or nil
    local request = GetRequest(inst)
    if action == nil or request == nil or action._my_friend_ghost_revive ~= request
        or action.action ~= ACTIONS.HAUNT or not request.portal or not IsGhost(inst)
        or not Portal(action.target) or action.target.components.hauntable ~= nil then return end
    -- Survival worlds have no portal hauntable. Enable it only for this native
    -- HAUNT execution, then remove our exact component on the next tick.
    -- This leaves player resurrection and the world's portal setting intact.
    local target = action.target
    target:AddComponent("hauntable")
    local hauntable = target.components.hauntable
    hauntable:SetHauntValue(TUNING.HAUNT_INSTANT_REZ)
    hauntable:SetOnHauntFn(function(_, doer) return doer == inst and IsGhost(inst) end)
    target:DoTaskInTime(0, function()
        if target:IsValid() and target.components.hauntable == hauntable then
            target:RemoveComponent("hauntable")
            target:RemoveTag("haunted")
        end
    end)
end

function M.Configure(inst)
    if inst._my_friend_ghost_commands_configured then return end
    inst._my_friend_ghost_commands_configured = true
    inst:ListenForEvent("performaction", M.OnPerform)
end

return M
