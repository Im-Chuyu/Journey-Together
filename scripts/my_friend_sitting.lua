local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")
local RouteAction = require("behaviours/my_friend_route_action")
local M = {}

local SEAT_RANGE = 7
local COMMAND_RANGE = 20

function M.StopSitting(inst)
    inst._my_friend_seat_request = nil
    inst._my_friend_sit_choice = nil
    inst._my_friend_sit_suppressed_until = GetTime() + 30
    inst._my_friend_replan_requested = true
end

function M.Request(inst, player)
    local chair = M.FindSeat(inst, player, false, COMMAND_RANGE)
    if chair == nil then return false end
    inst._my_friend_seat_request = {leader = player, chair = chair, expires = GetTime() + 30}
    return true
end

local function Request(inst, leader)
    local request = inst._my_friend_seat_request
    if request ~= nil and (request.leader ~= leader or GetTime() >= request.expires) then
        inst._my_friend_seat_request = nil
        return
    end
    return request
end
local function PlayerSeat(leader)
    local sg = leader ~= nil and leader.sg or nil
    local chair = sg ~= nil and sg.currentstate.name == "sitting" and sg.statemem.chair or nil
    if chair ~= nil and chair:IsValid() and chair.components.sittable ~= nil
        and chair.components.sittable:IsOccupiedBy(leader) then
        return sg.statemem
    end
end

local function Choice(inst, leader)
    local session = PlayerSeat(leader)
    local choice = inst._my_friend_sit_choice
    -- SG creates a new statemem for every seating, even on the same chair.
    if choice == nil or choice.leader ~= leader or choice.session ~= session then
        choice = {leader = leader, session = session,
            allowed = session == nil or math.random() < .6}
        inst._my_friend_sit_choice = choice
    end
    return choice
end

function M.Available(inst, context)
    local leader = Policy.GetLeader(inst)
    local c = context or {}
    return leader ~= nil and Policy.IsLocalPlayer(leader)
        and not leader:HasTag("playerghost") and not inst:HasTag("playerghost")
        and not inst.components.health:IsDead()
        and (leader.components.health == nil or not leader.components.health:IsDead())
        and inst.sg ~= nil and not inst.sg:HasAnyStateTag("sleeping", "floating")
        and inst:GetCurrentPlatform() == leader:GetCurrentPlatform()
        and not inst.components.inventory:IsHeavyLifting()
        and not (inst.components.rider ~= nil and inst.components.rider:IsRiding())
        and inst._my_friend_command == nil and inst.components.combat.target == nil
        and not inst._my_friend_under_threat and not c.threat and not c.hurt
        and not c.dark and not c.thermal and not c.greeting and not c.leaderdead
        and GetTime() >= (inst._my_friend_hurt_until or 0)
        and not inst._my_friend_container_action and inst._my_friend_storage_action == nil
        and inst._my_friend_backpack_target == nil
        and not inst._my_friend_riding_dismounting
        and not Policy.IsFollowGatheringPaused(inst)
        and inst.components.hunger:GetPercent() >= .4
        and not require("my_friend_light_ai").IsDark(inst)
        and not require("my_friend_survival_ai").NeedsTemperatureHelp(inst)
end

function M.CanUseSeat(inst, chair, leader, range)
    range = range or SEAT_RANGE
    return chair ~= nil and chair:IsValid() and chair.components.sittable ~= nil
        and chair:HasTag("cansit") and not chair:HasAnyTag("INLIMBO", "fire", "burnt")
        and not chair.components.sittable:IsOccupied()
        and chair:GetCurrentPlatform() == inst:GetCurrentPlatform()
        and chair:GetDistanceSqToInst(leader) <= range^2
        and chair:GetDistanceSqToInst(inst) <= math.max(12, range)^2
        and not Navigation.IsBlocked(inst, chair:GetPosition())
        and not require("my_friend_behavior_ai").IsTargetUnsafe(inst, chair)
end

function M.FindSeat(inst, leader, together, range)
    local x, y, z = (range ~= nil and inst or leader).Transform:GetWorldPosition()
    local best, distance
    for _, chair in ipairs(TheSim:FindEntities(x, y, z, range or SEAT_RANGE,
        {"cansit"}, {"INLIMBO", "fire", "burnt"})) do
        if M.CanUseSeat(inst, chair, leader, range) then
            local d = chair:GetDistanceSqToInst(together and leader or inst)
            if distance == nil or d < distance then best, distance = chair, d end
        end
    end
    return best
end

function M.Score(inst, context)
    local leader = Policy.GetLeader(inst)
    if leader == nil then return 0 end
    local request = Request(inst, leader)
    if request == nil and GetTime() < (inst._my_friend_sit_suppressed_until or 0) then return 0 end
    if not M.Available(inst, context) then return 0 end
    local active = inst._my_friend_sitting
    if active ~= nil then
        if active.leader ~= leader or active.request ~= nil and active.request ~= request then return 0 end
        return active.request ~= nil and 104 or 11
    end
    if request ~= nil then return not Policy.IsBusy(inst) and 104 or 0 end
    local choice = Choice(inst, leader)
    if not choice.allowed or choice.used or Policy.IsBusy(inst)
        or inst:HasTag("sitting_on_chair")
        or inst:GetDistanceSqToInst(leader) > SEAT_RANGE^2
        or leader.sg ~= nil and leader.sg:HasStateTag("moving")
        or GetTime() < (inst._my_friend_next_seat_scan or 0)
        or choice.session == nil and GetTime() < (inst._my_friend_next_rest or 0) then return 0 end
    return 11
end

local Sit = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "FriendSit")
    self.inst = inst
end)

function Sit:Visit()
    local inst, now = self.inst, GetTime()
    if self.status == READY then
        if M.Score(inst) == 0 then self.status = FAILED return end
        local leader = Policy.GetLeader(inst)
        local request = Request(inst, leader)
        local choice = Choice(inst, leader)
        local range = request ~= nil and COMMAND_RANGE or SEAT_RANGE
        local chair = request ~= nil and request.chair
            or M.FindSeat(inst, leader, choice.session ~= nil)
        if not M.CanUseSeat(inst, chair, leader, range) then
            chair = request ~= nil and M.FindSeat(inst, leader, false, range) or nil
        end
        inst._my_friend_next_seat_scan = now + 5
        if chair == nil then
            if request ~= nil then
                inst._my_friend_seat_request = nil
                require("my_friend_dialogue").Reply(inst, "sit_unavailable")
            end
            self.status = FAILED
            return
        end
        self.leader, self.chair, self.request, self.range = leader, chair, request, range
        self.session = request == nil and choice.session or nil
        if choice.session ~= nil then choice.used = true end
        self.deadline = now + 20
        self.status = RUNNING
        inst._my_friend_sitting = self
        -- The inner action ends on mounting the chair; this parent owns the
        -- rest afterwards so the selector does not immediately resume walking.
        self.route = RouteAction(inst, function()
            if not M.CanUseSeat(inst, chair, leader, range) then return end
            return BufferedAction(inst, chair, ACTIONS.SITON)
        end, "WalkToSeat", false, 12, true)
    end
    if self.status ~= RUNNING then return end
    local sg = inst.sg
    local seated = sg.currentstate.name == "sitting" and sg.statemem.chair == self.chair
    if self.leaving then
        if not inst:HasTag("sitting_on_chair") and not Policy.IsBusy(inst) then self.status = SUCCESS end
    elseif seated then
        if self.rest_until == nil then
            self.route:Visit()
            self.route:Stop()
            self.route = nil
            self.rest_until = now + ((self.session ~= nil or self.request ~= nil) and 60 or math.random(20, 35))
            if self.request ~= nil then self.request.expires = self.rest_until + 5 end
            require("my_friend_dialogue").Say(inst, self.session ~= nil and "sit_together" or "sit_rest")
        end
        if now >= self.rest_until or inst:GetDistanceSqToInst(self.leader) > self.range^2
            or self.session ~= nil and PlayerSeat(self.leader) ~= self.session then
            self.leaving = true
            inst:PushEvent("locomote", {remoteoverridelocomote = true})
        end
    elseif self.rest_until ~= nil or now >= self.deadline
        or not self.chair:IsValid() or inst:GetDistanceSqToInst(self.leader) > self.range^2
        or self.session ~= nil and PlayerSeat(self.leader) ~= self.session then
        self.status = FAILED
    else
        self.route:Visit()
        if self.route.status == FAILED or self.route.status == SUCCESS
            and not inst:HasTag("sitting_on_chair") then self.status = FAILED end
    end
    self:Sleep(.25)
end

function Sit:OnStop()
    local inst, route = self.inst, self.route
    if route ~= nil then
        local action = route.action
        if action ~= nil and route.pendingstatus == nil then
            action._my_friend_cancelled = true
            action:Fail()
        end
        if action ~= nil and inst:GetBufferedAction() == action then inst:ClearBufferedAction() end
        route:Stop()
    end
    local sg = inst.sg
    -- Urgent actions may already be prepared by the selector. Native onexit
    -- releases the chair and restores physics without a busy exit animation.
    if self.chair ~= nil and sg ~= nil and sg.statemem.chair == self.chair
        and (sg.currentstate.name == "sitting" or sg.currentstate.name == "start_sitting"
            or sg.currentstate.name == "sit_jumpon") then sg:GoToState("idle") end
    if inst._my_friend_sitting == self then
        inst._my_friend_sitting = nil
        inst._my_friend_next_rest = GetTime() + 45
    end
    if self.request ~= nil and inst._my_friend_seat_request == self.request then
        inst._my_friend_seat_request = nil
    end
    self.route, self.chair, self.leader, self.session = nil, nil, nil, nil
    self.request, self.range = nil, nil
    self.rest_until, self.leaving, self.deadline = nil, nil, nil
end

M.Behaviour = Sit
return M
