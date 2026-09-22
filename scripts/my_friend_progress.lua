local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")
local M = {TIMEOUT = 7, DISTANCE = .75}

local WAITING = {light_wait = true, thermal_wait = true, dark_standby = true,
    hurt_wait = true, vigil = true, emote = true, sit = true, farewell = true, command_wait = true}

function M.Mark(inst)
    inst._my_friend_progress_at = GetTime()
end

function M.Track(inst, action)
    if action == nil or action._my_friend_progress_tracked then return end
    action._my_friend_progress_tracked = true
    action:AddSuccessAction(function()
        action._my_friend_progress_finished = true
        -- Reaching a repeatedly regenerated WALKTO is not productive work.
        -- Movement itself is measured across actions instead.
        if action.action ~= ACTIONS.WALKTO then M.Mark(inst) end
    end)
    action:AddFailAction(function() action._my_friend_progress_finished = true end)
end

local function HasLocks(inst)
    return inst._my_friend_storage_action ~= nil or inst._my_friend_chest_transfer ~= nil or inst._my_friend_container_action
        or inst._my_friend_backpack_action or inst._my_friend_backpack_target ~= nil
        or inst._my_friend_work_target ~= nil
end

local function Reset(root, now, point)
    root.progress = {since = now, point = point, marked = root.inst._my_friend_progress_at}
end

local function Fail(action, path_failed)
    if action == nil or action._my_friend_progress_finished then return end
    action._my_friend_path_failed = path_failed or action._my_friend_path_failed
    action._my_friend_cancelled = not action._my_friend_path_failed
    action:Fail()
end

function M.Recover(root)
    local inst, entry = root.inst, root.active
    local node = entry ~= nil and entry.node or nil
    local action = node ~= nil and node.action or inst:GetBufferedAction()
    local storage = inst._my_friend_storage_action
    local target = action ~= nil and action.target or inst._my_friend_work_target
        or inst._my_friend_backpack_target or storage ~= nil and storage.target or nil
    local point = action ~= nil and Navigation.ActionPoint(action)
        or target ~= nil and target:IsValid() and target:GetPosition() or nil
    local position = inst:GetPosition()
    local travelling = not Policy.IsBusy(inst) and point ~= nil
        and (point.x - position.x)^2 + (point.z - position.z)^2 >= M.DISTANCE^2
    if travelling then
        Navigation.Block(inst, point, false, true)
    end
    inst._my_friend_last_stall = {time = GetTime(), task = entry ~= nil and entry.id,
        action = action ~= nil and action.action.id, target = target ~= nil and target.prefab}
    -- Use existing cancellation callbacks before releasing orphaned locks.
    Fail(action, travelling)
    if storage ~= action then Fail(storage) end
    root:CancelActive()
    inst:ClearBufferedAction()
    inst.components.locomotor:Clear()
    inst.components.locomotor:Stop()
    Navigation.CancelSteering(inst)
    Navigation.ClearStuck(inst)
    inst._my_friend_navigation_action, inst._my_friend_route_planning = nil, nil
    inst._my_friend_last_move, inst._my_friend_tool_action = nil, nil
    if storage ~= nil then require("my_friend_storage").Cancel(inst, storage) end
    local orphaned = action == nil and (entry == nil or entry.passive)
    if inst._my_friend_work_target ~= nil and (orphaned or inst._my_friend_work_target == target) then
        require("my_friend_base_ai").AbandonStalledWork(inst, target)
    end
    if (orphaned or entry ~= nil and (entry.id == "container_food" or entry.id == "eat"))
        and (inst._my_friend_container_action or inst._my_friend_meal ~= nil
        or inst._my_friend_container_target ~= nil) then
        require("my_friend_container_ai").Cancel(inst)
    end
    if (orphaned or entry ~= nil and entry.id == "backpack_recovery")
        and (inst._my_friend_backpack_action or inst._my_friend_backpack_target ~= nil) then
        require("my_friend_backpacks").CancelRecovery(inst)
    end
    if entry ~= nil and entry.id == "recipe_cooking" then require("my_friend_recipe_cooking").Cancel(inst) end
    if entry ~= nil and entry.id == "butterfly_hunt" then require("my_friend_butterfly").Cancel(inst) end
    local sg = inst.sg
    if sg ~= nil and Policy.IsBusy(inst)
        and (sg:HasStateTag("doing") or sg:HasStateTag("working")) then sg:GoToState("idle") end
    inst._my_friend_replan_requested = true
    require("my_friend_base_ai").SetTask(inst, "正在重新安排任务")
    Reset(root, GetTime(), inst:GetPosition())
end

function M.Check(root)
    local inst, entry, now = root.inst, root.active, GetTime()
    local sg, health = inst.sg, inst.components.health
    if Policy.GetLeader(inst) ~= nil or inst:HasTag("playerghost")
        or health ~= nil and health:IsDead() or inst._my_friend_command ~= nil
        or entry ~= nil and WAITING[entry.id]
        or sg ~= nil and (sg:HasStateTag("sleeping") or sg:HasStateTag("frozen")
            or sg:HasStateTag("dead") or sg:HasStateTag("jumping") or sg:HasStateTag("nopredict")) then
        root.progress = nil
        return false
    end
    local node = entry ~= nil and entry.node or nil
    local action = node ~= nil and node.action or inst:GetBufferedAction()
    M.Track(inst, action)
    local point, state = inst:GetPosition(), root.progress
    if state == nil or (point.x - state.point.x)^2 + (point.z - state.point.z)^2 >= M.DISTANCE^2
        or state.marked ~= inst._my_friend_progress_at then
        Reset(root, now, point)
        state = root.progress
    end
    if node ~= nil and node.routing and node.search ~= nil and node.steps == nil then
        -- Native pathfinding and its land-search fallback have a twelve-second
        -- budget. Give it once per progress window, never once per replan.
        state.route_until = state.route_until or now + Navigation.SEARCH_TIMEOUT + 1
        if now < state.route_until then return false end
    end
    -- A finite long animation may legitimately take longer than seven seconds.
    -- Changing actions or SG states does not reset the overall progress clock.
    if Policy.IsBusy(inst) then
        if state.busy_until == nil then
            local duration = sg ~= nil and sg.timeout or 0
            if inst.AnimState ~= nil and inst.AnimState.GetCurrentAnimationLength ~= nil then
                duration = math.max(duration or 0, inst.AnimState:GetCurrentAnimationLength())
            end
            state.busy_until = now + math.min(60, math.max(M.TIMEOUT, (duration or 0) + 1))
        end
        if now < (state.busy_until or state.since + M.TIMEOUT) then return false end
        -- Never force a combat, mount or world transition into idle.
        if sg == nil or not (sg:HasStateTag("doing") or sg:HasStateTag("working")) then return false end
    end
    local moving = node ~= nil and (node.target ~= nil or node.routing)
        or inst.components.locomotor ~= nil and inst.components.locomotor.dest ~= nil
    if action == nil and not HasLocks(inst) and not moving then
        Reset(root, now, point)
        return false
    end
    if now - state.since < M.TIMEOUT then return false end
    M.Recover(root)
    return true
end

return M
