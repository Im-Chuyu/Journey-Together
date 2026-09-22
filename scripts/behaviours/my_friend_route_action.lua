require "behaviours/doaction"
local Navigation = require("my_friend_navigation")
local Policy = require("my_friend_policy")

local function PreserveIdleMovement(inst)
    local locomotor = inst.components.locomotor
    if locomotor._my_friend_preserves_movement or locomotor.Clear == nil then return end
    locomotor._my_friend_preserves_movement = true
    local clear = locomotor.Clear
    locomotor.Clear = function(self, ...)
        local node, sg = inst._my_friend_movement_owner, inst.sg
        local action = self.bufferedaction
        -- Vanilla idle preserves travel when arriving from a non-busy state.
        -- If another mod clears it anyway, detach our queued action before
        -- Clear calls Fail(), so the node can resume without blocking the site.
        if node ~= nil and node.pendingstatus == nil and action ~= nil
            and (node.action == action or node.walk == action and not node.walk_done)
            and not action._my_friend_cancelled and not action._my_friend_path_failed
            and sg ~= nil and sg.currentstate.name == "idle"
            and sg.lasttags ~= nil and not sg.lasttags.busy
            and sg.timeinstate == 0 and action:IsValid() then
            self.bufferedaction = nil
        end
        return clear(self, ...)
    end
end

local RouteAction = Class(DoAction, function(self, inst, getter, name, run, timeout, enabled)
    DoAction._ctor(self, inst, getter, name, run, timeout)
    self.route_enabled = enabled
    PreserveIdleMovement(inst)
end)

RouteAction.STALL_TIMEOUT = Navigation.SEARCH_TIMEOUT + 6

function RouteAction:OnFail()
    -- Rider state changes can clear doshortaction before its success callback.
    if self.action ~= nil and self.action._my_friend_explore_ride ~= nil
        and require("my_friend_exploration_riding").TransitionSucceeded(self.inst, self.action) then
        self:OnSucceed()
    else
        DoAction.OnFail(self)
    end
end

local function DetachMovement(inst, action)
    if action == nil then return end
    local locomotor = inst.components.locomotor
    if locomotor.bufferedaction == action then locomotor.bufferedaction = nil end
    if inst.bufferedaction == action then inst.bufferedaction = nil end
end

function RouteAction:ClearRoute()
    Navigation.Cancel(self.search)
    DetachMovement(self.inst, self.walk)
    self.search, self.steps, self.walk = nil, nil, nil
    self.routing = false
    self.inst._my_friend_route_planning = nil
    if self.inst._my_friend_navigation_action == self.action then
        self.inst._my_friend_navigation_action = nil
    end
end

function RouteAction:FailRoute(exhausted, already_blocked)
    local point = Navigation.ActionPoint(self.action)
    if point ~= nil and not already_blocked then
        local position = self.inst:GetPosition()
        Navigation.Block(self.inst, point, exhausted,
            (point.x - position.x)^2 + (point.z - position.z)^2 <= 24^2)
    end
    self.action._my_friend_path_failed = true
    self.inst._my_friend_land_route = nil
    self:ClearRoute()
    DetachMovement(self.inst, self.action)
    self.inst:ClearBufferedAction()
    self.inst.components.locomotor:Stop()
    self.action:Fail()
    self.pendingstatus, self.status = FAILED, FAILED
end

function RouteAction:RetryLocalApproach()
    if not self.route_enabled or self.routing or self.pendingstatus ~= nil
        or (self.local_retries or 0) >= 3 or Policy.IsBusy(self.inst) then return false end
    local point, position = Navigation.ActionPoint(self.action), self.inst:GetPosition()
    if point == nil or (point.x - position.x)^2 + (point.z - position.z)^2 > 24^2 then return false end
    local attempt = (self.local_retries or 0) + 1
    self.failed_approaches = self.failed_approaches or {}
    self.failed_approaches[#self.failed_approaches + 1] = self.goal or position
    local goal = Navigation.Approach(self.inst, self.action, Navigation.Caps(self.inst),
        attempt, self.failed_approaches)
    if goal == nil then return false end
    self.local_retries, self.goal = attempt, goal
    local locomotor = self.inst.components.locomotor
    -- Detach the same pending action before rerouting, retaining its callbacks.
    if locomotor.bufferedaction == self.action then locomotor.bufferedaction = nil end
    if self.inst.bufferedaction == self.action then self.inst.bufferedaction = nil end
    self:BeginRoute(true)
    return true
end

function RouteAction:BeginRoute(land_only)
    Navigation.Cancel(self.search)
    DetachMovement(self.inst, self.walk)
    self.routing = true
    self.walk = nil
    self.inst:ClearBufferedAction()
    self.inst.components.locomotor:Stop()
    self.search = Navigation.Start(self.inst, self.goal, land_only)
    self.inst._my_friend_route_planning = true
    self.walk, self.steps = nil, nil
    self.walk_done, self.walk_failed = nil, nil
    self.progress_position = self.inst:GetPosition()
    self.progress_time = GetTime()
    self:UpdateTravelProgress()
end

function RouteAction:UpdateTravelProgress()
    local position = self.inst:GetPosition()
    -- Replanning is not physical progress. Keep this clock across alternate
    -- approaches, but give a new action or a moving companion a fresh budget.
    if self.stall_action ~= self.action or self.stall_position == nil
        or (position.x - self.stall_position.x)^2 + (position.z - self.stall_position.z)^2 >= .25 then
        self.stall_action, self.stall_position, self.stall_since = self.action, position, GetTime()
    end
end

function RouteAction:PushMovement(action)
    self.last_movement_push = GetTime()
    self.inst._my_friend_movement_owner = self
    if not action:TestForStart() then
        action:Fail()
        return
    end
    self.inst.components.locomotor:PushAction(action, FunctionOrValue(self.shouldrun))
end

function RouteAction:ResumeMovement(action)
    local inst, locomotor = self.inst, self.inst.components.locomotor
    -- Some equipment mods clear locomotor on every idle transition, including
    -- a walk-stop transition after the next destination has already been set.
    -- Resume only an unperformed action, never an animation or another owner.
    if action == nil or self.pendingstatus ~= nil or self.walk_failed
        or (self.movement_resumes or 0) >= 2
        or GetTime() - (self.last_movement_push or GetTime()) < .25
        or Policy.IsBusy(inst) or inst.sg == nil or not inst.sg:HasStateTag("idle")
        or inst.bufferedaction ~= nil
        or locomotor.bufferedaction ~= nil and locomotor.bufferedaction ~= action
        or locomotor.dest ~= nil or action.action.instant or action.action.do_not_locomote
        or action._my_friend_cancelled or action._my_friend_path_failed
        or action.options.instant or not action:IsValid() then return false end
    self.movement_resumes = (self.movement_resumes or 0) + 1
    -- Stop() removes the destination but retains the queued action. Detach it
    -- before PushAction's Clear() can fail the very action we are resuming.
    DetachMovement(inst, action)
    self:PushMovement(action)
    return true
end

function RouteAction:PushOriginal()
    self:ClearRoute()
    self.time = GetTime()
    self.action._my_friend_travel_finished = self.time
    local kind, tool = self.action.action, self.action.invobject
    if kind == ACTIONS.FISH and self.action._my_friend_roaming ~= nil
        and not require("my_friend_fishing").PrepareCast(self.inst, self.action) then
        self.action._my_friend_cancelled = true
        self.action:Fail()
        self.pendingstatus, self.status = FAILED, FAILED
        return
    end
    if kind == ACTIONS.TILL or kind == ACTIONS.MY_FRIEND_LEVELSOIL or kind == ACTIONS.POUR_WATER_GROUNDTILE
        or kind == ACTIONS.FILL and self.inst._my_friend_command ~= nil then
        local work = kind == ACTIONS.FILL and ACTIONS.POUR_WATER_GROUNDTILE
            or kind == ACTIONS.MY_FRIEND_LEVELSOIL and ACTIONS.TILL or kind
        if not require("my_friend_base_ai").CanUseHandToolInCurrentLight(self.inst)
            or not require("my_friend_command_work").IsUsableTool(self.inst, tool, work, kind == ACTIONS.FILL)
            or self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS) ~= tool
                and self.inst.components.inventory:Equip(tool) ~= true then
            self.action._my_friend_cancelled = true
            self.action:Fail()
            self.pendingstatus, self.status = FAILED, FAILED
            return
        end
        self.inst._my_friend_hand_tool_lock_until = GetTime() + 3
    end
    if kind == ACTIONS.CHOP or kind == ACTIONS.MINE or kind == ACTIONS.DIG or kind == ACTIONS.HAMMER then
        if not require("my_friend_base_ai").CanUseHandToolInCurrentLight(self.inst)
            or not require("my_friend_inventory").IsUsableTool(self.inst, tool, kind)
            or self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS) ~= tool
                and self.inst.components.inventory:Equip(tool) ~= true then
            self.action._my_friend_cancelled = true
            self.action:Fail()
            self.pendingstatus, self.status = FAILED, FAILED
            return
        end
        local action = self.action
        self.inst._my_friend_tool_action = action
        local function ReleaseTool()
            if self.inst._my_friend_tool_action == action then
                self.inst._my_friend_tool_action = nil
            end
        end
        action:AddSuccessAction(ReleaseTool)
        action:AddFailAction(ReleaseTool)
    end
    self:PushMovement(self.action)
end

function RouteAction:VisitRoute()
    local now = GetTime()
    self:UpdateTravelProgress()
    if now - self.stall_since >= self.STALL_TIMEOUT then
        self:FailRoute(false)
        return
    end
    self.action._my_friend_travel_until = now + 2
    if self.inst._my_friend_work_target == self.action.target then
        self.inst._my_friend_work_stall_deadline = now + 45
    end
    for id in pairs(self.inst._my_friend_tool_needs or {}) do
        self.inst._my_friend_tool_needs[id] = now + 90
    end
    if self.action.target ~= nil and not self.action.target:IsValid()
        or not self.action:IsValid()
        or not Navigation.InTravelRange(self.inst, self.inst:GetPosition())
        or not Navigation.InTravelRange(self.inst, self.goal) then
        self.action._my_friend_cancelled = true
        self:ClearRoute()
        self.inst:ClearBufferedAction()
        self.inst.components.locomotor:Stop()
        self.action:Fail()
        self.pendingstatus, self.status = FAILED, FAILED
        return
    end
    if self.steps == nil then
        local steps, exhausted = Navigation.Poll(self.search)
        if steps == false then self:FailRoute(exhausted) return end
        if steps == nil then return end
        self.steps, self.step = steps, 1
        self.inst._my_friend_route_planning = nil
        self.progress_time = now
    end
    local position = self.inst:GetPosition()
    if (position.x - self.progress_position.x)^2 + (position.z - self.progress_position.z)^2 > .25 then
        self.progress_position, self.progress_time = position, now
    end
    if self.walk ~= nil and not self.walk_done then
        self:ResumeMovement(self.walk)
        local destination = self.walk:GetActionPoint()
        local distance = math.sqrt((position.x - destination.x)^2 + (position.z - destination.z)^2)
        -- Hand off intermediate waypoints before locomotor stops at their
        -- centre. The next segment is checked from our actual position below.
        if self.step <= #self.steps and distance <= 1.5
            and Navigation.IsWalkClear(self.inst, position, self.steps[self.step], self.search.caps) then
            local walk = self.walk
            self.walk, self.walk_done = nil, true
            if self.inst.components.locomotor.bufferedaction == walk then
                self.inst.components.locomotor.bufferedaction = nil
            end
            if self.inst.bufferedaction == walk then self.inst.bufferedaction = nil end
        end
        if self.walk_best == nil or distance < self.walk_best - .5 then
            self.walk_best, self.walk_progress = distance, now
        elseif now - self.walk_progress > 12 then
            self.walk_failed = true
        end
    end
    if now - self.progress_time > 6 or self.walk_failed then
        self.walk_failed = nil
        self.replans = (self.replans or 0) + 1
        if self.replans > 2 then self:FailRoute(false) return end
        Navigation.Cancel(self.search)
        self:BeginRoute(true)
        return
    end
    if self.walk ~= nil and not self.walk_done then return end
    self.walk, self.walk_done = nil, nil
    if self.step > #self.steps then self:PushOriginal() return end
    local last = self.step
    -- Smooth only verified short sections, never the line across the bay.
    for index = self.step, math.min(#self.steps, self.step + 24) do
        local point = self.steps[index]
        if (point.x - position.x)^2 + (point.z - position.z)^2 > 24^2 then break end
        if Navigation.IsWalkClear(self.inst, position, point, self.search.caps) then last = index end
    end
    local point = self.steps[last]
    if not Navigation.IsWalkClear(self.inst, position, point, self.search.caps) then
        self.walk_failed = true
        return
    end
    local walk = BufferedAction(self.inst, nil, ACTIONS.WALKTO, nil, Vector3(point.x, 0, point.z))
    walk.arrivedist = .05
    walk:AddSuccessAction(function() if self.walk == walk then self.walk_done = true end end)
    walk:AddFailAction(function() if self.walk == walk then self.walk_failed = true end end)
    self.walk, self.step = walk, last + 1
    self.walk_best, self.walk_progress = nil, now
    self:PushMovement(walk)
end

function RouteAction:Visit()
    if self.status == READY then
        self:ClearRoute()
        Navigation.CancelSteering(self.inst)
        self.goal, self.replans, self.walk_failed, self.walk_done = nil, 0, nil, nil
        self.local_retries = 0
        self.failed_approaches = nil
        self.movement_resumes = 0
        self.stall_action, self.stall_position, self.stall_since = nil, nil, nil
        self.action = self.getactionfn(self.inst)
        self.inst._my_friend_navigation_action = self.action
        self.pendingstatus = nil
        local action = self.action
        if action == nil then self.status = FAILED return end
        require("my_friend_progress").Track(self.inst, action)
        require("my_friend_resource_safety").GuardAction(self.inst, action)
        Navigation.PrepareInteraction(self.inst, action)
        action:AddFailAction(function()
            if self.action == action and self.pendingstatus == nil then self:OnFail() end
        end)
        action:AddSuccessAction(function() if self.action == action then self:OnSucceed() end end)
        self.status, self.time = RUNNING, GetTime()
        local point = Navigation.ActionPoint(action)
        local position = self.inst:GetPosition()
        -- Out of bounds for the current mode (home circle or leader range):
        -- fail now and remember the point, so the planner does not hand us the
        -- same far target again every tick and start a pathfind for it.
        if self.route_enabled and point ~= nil then
            local blocked = Navigation.IsBlocked(self.inst, point)
            if blocked or not Navigation.InTravelRange(self.inst, point) then
                self:FailRoute(false, blocked)
                return
            end
        end
        local distance = point ~= nil
            and (point.x - position.x)^2 + (point.z - position.z)^2 or 0
        local caps = Navigation.Caps(self.inst)
        local approach, direct
        if self.route_enabled and point ~= nil then
            approach, direct = Navigation.Approach(self.inst, action, caps)
        end
        self.goal = approach
        if self.route_enabled
            and not self.inst:HasTag("playerghost") and point ~= nil
            and (distance > 24^2 or approach == nil and distance > .5^2
                or approach ~= nil
                    and (approach.x - position.x)^2 + (approach.z - position.z)^2 > .25^2
                    and (not direct or not Navigation.IsWalkClear(self.inst, position, approach, caps)
                        or action.target == nil and not Navigation.IsWalkClear(self.inst, position, point, caps))) then
            if self.goal == nil then
                self:FailRoute(false)
                return
            end
            self:BeginRoute(false)
        else
            self:PushOriginal()
        end
    end
    if self.status == RUNNING then
        if self.pendingstatus ~= nil then
            self.status = self.pendingstatus
            self:ClearRoute()
        elseif self.routing then
            self:VisitRoute()
        else
            DoAction.Visit(self)
            if self.status == RUNNING then self:ResumeMovement(self.action) end
        end
    end
end

function RouteAction:OnStop()
    if self.inst._my_friend_movement_owner == self then
        self.inst._my_friend_movement_owner = nil
    end
    if self.inst._my_friend_tool_action == self.action then
        self.inst._my_friend_tool_action = nil
    end
    local locomotor = self.inst.components.locomotor
    local owns_movement = self.routing or locomotor.bufferedaction ~= nil
        and (locomotor.bufferedaction == self.action or locomotor.bufferedaction == self.walk)
    self:ClearRoute()
    if owns_movement and not Policy.IsBusy(self.inst) then
        Navigation.CancelSteering(self.inst)
        locomotor:Clear()
        locomotor:Stop()
    end
end

return RouteAction
