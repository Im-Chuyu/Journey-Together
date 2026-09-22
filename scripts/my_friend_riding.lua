local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")
local Platforms = require("my_friend_platforms")

local M = {}

M.MOUNT_DISTANCE_SQ = 36 * 36
M.DISMOUNT_DISTANCE_SQ = 7 * 7
M.DISMOUNT_RESET_DISTANCE_SQ = 9 * 9
M.MIN_RIDE_TIME = 2
M.RETRY_DELAY = 10
M.ACTION_TIMEOUT = 14
M.RIDE_REQUEST_TIME = 480
M.PATROL_MIN_DISTANCE = 2.5
M.PATROL_MAX_DISTANCE = 6
M.PATROL_RETRY = 2

local function IsRiding(inst)
    return inst.components.rider ~= nil
        and inst.components.rider:IsRiding()
end

local function BellOwnerIsFriend(bell, inst)
    local inventoryitem = bell.components ~= nil and bell.components.inventoryitem or nil
    if inventoryitem == nil then return false end
    local owner = inventoryitem.GetGrandOwner ~= nil
        and inventoryitem:GetGrandOwner() or inventoryitem.owner
    return owner == inst
end

local function GetBoundBeefalo(bell)
    if bell == nil or bell.GetBeefalo == nil then return nil end
    local ok, beefalo = pcall(bell.GetBeefalo, bell)
    return ok and beefalo or nil
end

local function IsAvailableBeefalo(inst, beefalo)
    if beefalo == nil or not beefalo:IsValid()
        or beefalo.components == nil or beefalo.components.rideable == nil then
        return false
    end
    local rideable = beefalo.components.rideable
    if not rideable.canride or rideable.saddle == nil
        or rideable:IsBeingRidden() then return false end
    if beefalo.components.health ~= nil and beefalo.components.health:IsDead() then
        return false
    end
    if beefalo.components.combat ~= nil and beefalo.components.combat:HasTarget() then
        return false
    end
    if beefalo.components.freezable ~= nil and beefalo.components.freezable:IsFrozen() then
        return false
    end
    if beefalo.components.hitchable ~= nil and beefalo.components.hitchable:GetHitch() ~= nil then
        return false
    end
    if beefalo.hitchingspot ~= nil then return false end
    return true
end

function M.GetBeefalo(inst, predicate)
    return M.GetBoundBeefalo(inst, function(beefalo)
        return IsAvailableBeefalo(inst, beefalo) and (predicate == nil or predicate(beefalo))
    end)
end

function M.GetBoundBeefalo(inst, predicate)
    local inventory = inst ~= nil and inst.components ~= nil and inst.components.inventory or nil
    if inventory == nil or inventory.ReferenceAllItems == nil then return nil end
    for _, bell in ipairs(inventory:ReferenceAllItems()) do
        if bell ~= nil and bell:IsValid() and bell:HasTag("bell")
            and BellOwnerIsFriend(bell, inst) then
            local beefalo = GetBoundBeefalo(bell)
            if beefalo ~= nil and beefalo:IsValid()
                and (predicate == nil or predicate(beefalo)) then return beefalo end
        end
    end
end

function M.IsRideRequested(inst, leader)
    local untiltime = inst ~= nil and inst._my_friend_mount_requested_until or nil
    if untiltime == nil or GetTime() >= untiltime then
        if inst ~= nil then
            inst._my_friend_manual_ride = nil
            inst._my_friend_mount_requested_until = nil
            inst._my_friend_mount_request_player = nil
        end
        return false
    end
    return inst._my_friend_mount_request_player == nil
        or inst._my_friend_mount_request_player == leader
end

function M.AllowAutoRide(inst)
    if inst == nil then return end
    if inst._my_friend_mount_disabled_until ~= nil
        and GetTime() < inst._my_friend_mount_disabled_until then
        -- A normal follow command must not cancel the stop-ride cooldown.
        inst._my_friend_mount_disabled = true
    else
        inst._my_friend_mount_disabled = nil
        inst._my_friend_mount_disabled_until = nil
    end
    inst._my_friend_mount_stop_requested = nil
    inst._my_friend_mount_retry_after = nil
end

function M.RequestRide(inst, player)
    if inst == nil or player == nil or Policy.GetLeader(inst) ~= player then
        return false
    end
    if inst._my_friend_mount_disabled_until ~= nil
        and GetTime() < inst._my_friend_mount_disabled_until
        and Policy.DistanceSq(inst, player) <= 40 * 40 then
        return false
    end
    -- Once the leader is far enough away, an explicit ride command can clear
    -- the old stop-ride restriction and start a new riding window.
    inst._my_friend_mount_disabled = nil
    inst._my_friend_mount_disabled_until = nil
    M.AllowAutoRide(inst)
    inst._my_friend_manual_ride = true
    inst._my_friend_mount_requested_until = GetTime() + M.RIDE_REQUEST_TIME
    inst._my_friend_mount_request_player = player
    inst._my_friend_mount_keep_riding = nil
    return true
end

function M.StopRide(inst)
    if inst == nil then return false end
    inst._my_friend_manual_ride = nil
    inst._my_friend_mount_requested_until = nil
    inst._my_friend_mount_request_player = nil
    inst._my_friend_mount_disabled = true
    inst._my_friend_mount_disabled_until = GetTime() + M.RIDE_REQUEST_TIME
    inst._my_friend_mount_stop_requested = true
    return true
end

function M.OnAttacked(inst)
    if inst == nil or not IsRiding(inst) then return end
    -- An attack forced the rider off. Treat this as a loss of the manual ride
    -- request so the companion does not remount in the same danger.
    inst._my_friend_manual_ride = nil
    inst._my_friend_mount_requested_until = nil
    inst._my_friend_mount_request_player = nil
    inst._my_friend_mount_disabled = true
    inst._my_friend_mount_disabled_until = nil
    inst._my_friend_mount_stop_requested = nil
    inst._my_friend_mount_keep_riding = nil
end

function M.CanRideToLeader(inst, context)
    if inst == nil or context == nil or context.leader == nil
        or context.leaderdead or context.ghost or context.threat ~= nil
        or context.hurt or context.hurt_evade or context.dark or context.thermal
        or context.hunger < .4 or IsRiding(inst)
        or inst._my_friend_mount_disabled
            and inst._my_friend_mount_disabled_until == nil
        or inst._my_friend_mount_disabled_until ~= nil
            and GetTime() < inst._my_friend_mount_disabled_until
            and context.distance <= 40 * 40
        or inst._my_friend_command ~= nil and inst._my_friend_command.id ~= "carry_statue"
        or GetTime() < (inst._my_friend_mount_retry_after or 0)
        or Policy.IsBusy(inst) then return false end
    if not M.IsRideRequested(inst, context.leader)
        and context.distance <= M.MOUNT_DISTANCE_SQ
        or inst:GetCurrentPlatform() ~= context.leader:GetCurrentPlatform() then
        return false
    end
    return M.GetBeefalo(inst) ~= nil
end

function M.Score(inst, context)
    if IsRiding(inst) then
        -- Yield to the existing emote node only while its request remains
        -- valid. Urgent work still outranks both idle follow and emotes.
        if require("my_friend_emotes").Score(inst) > 0 then return 10 end
        -- Keep the riding node selected until it explicitly starts dismounting.
        -- A zero score at close range would make Utility call OnStop() and
        -- dismount before the arrival decision gets a chance to run.
        return 116
    end
    return M.CanRideToLeader(inst, context) and 116 or 0
end

function M.GetMountAction(inst, beefalo)
    if beefalo == nil or ACTIONS.MOUNT == nil then return nil end
    return BufferedAction(inst, beefalo, ACTIONS.MOUNT)
end

function M.GetDismountAction(inst)
    if ACTIONS.DISMOUNT == nil then return nil end
    return BufferedAction(inst, inst, ACTIONS.DISMOUNT)
end

local RideToLeader = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendRideToLeader")
    self.inst = inst
    self.phase = nil
    self.mount = nil
    self.action = nil
    self.pendingstatus = nil
end)

function RideToLeader:Fail()
    self.inst._my_friend_mount_retry_after = GetTime() + M.RETRY_DELAY
    self.pendingstatus = FAILED
end

function RideToLeader:BeginDismount()
    if self.phase == "dismount" then return end
    self.phase = "dismount"
    self.time = GetTime()
    self.inst._my_friend_riding_dismounting = true
    self.inst.components.locomotor:Stop()
    local action = M.GetDismountAction(self.inst)
    if action == nil then self:Fail() return end
    self.action = action
    require("my_friend_dialogue").OnAction(self.inst, action)
    action:AddFailAction(function()
        if self.action == action then
            -- SGwilson exits doshortaction before the dismount animation ends.
            if not IsRiding(self.inst) or self.inst.sg ~= nil
                and self.inst.sg:HasStateTag("dismounting") then self.action = nil
            else self:Fail() end
        end
    end)
    action:AddSuccessAction(function()
        if self.action == action then self.action = nil end
    end)
    self.inst.components.locomotor:PushAction(action, false)
end

function RideToLeader:CheckArrivalDecision(leader)
    local inst = self.inst
    if Platforms.NeedsCrossing(inst, leader) then
        inst._my_friend_mount_keep_riding = nil
        return
    end
    if M.IsRideRequested(inst, leader) then return end
    local distance = Policy.DistanceSq(inst, leader)
    if distance > M.DISMOUNT_RESET_DISTANCE_SQ then
        inst._my_friend_mount_keep_riding = nil
        return
    end
    if distance > M.DISMOUNT_DISTANCE_SQ
        or GetTime() - (inst._my_friend_mount_started or GetTime()) < M.MIN_RIDE_TIME then
        return
    end
    -- Decide once on arrival. Keeping the result on the companion prevents
    -- the brain's frequent reevaluation from causing mount/dismount jitter.
    if inst._my_friend_mount_keep_riding == nil then
        inst._my_friend_mount_keep_riding = math.random() >= .5
    end
    -- A failed dismount must retry the chosen action, not become a permanent
    -- keep-riding decision. Do not reroll on each brain tick.
    if not inst._my_friend_mount_keep_riding
        and GetTime() >= (inst._my_friend_mount_retry_after or 0) then self:BeginDismount() end
end

local function FindPatrolPoint(inst, leader)
    if inst:GetCurrentPlatform() ~= leader:GetCurrentPlatform() then return end
    local origin = leader:GetPosition()
    for _ = 1, 8 do
        local offset = FindWalkableOffset(origin, math.random() * 2 * math.pi,
            M.PATROL_MIN_DISTANCE
                + math.random() * (M.PATROL_MAX_DISTANCE - M.PATROL_MIN_DISTANCE),
            12, true, false)
        if offset ~= nil then
            local point = origin + offset
            local ix, _, iz = inst.Transform:GetWorldPosition()
            if TheWorld.Map:GetPlatformAtPoint(point.x, point.z) == inst:GetCurrentPlatform()
                and (ix - point.x)^2 + (iz - point.z)^2 > 1.5 * 1.5 then
                return point
            end
        end
    end
end

function RideToLeader:FollowMounted(leader)
    local inst, now = self.inst, GetTime()
    if inst.sg ~= nil and inst.sg:HasStateTag("busy") then return end
    if Platforms.FollowCrossing(inst, leader) then
        self.patrol_target, self.next_patrol = nil, nil
        self.chasing = true
        return
    end
    local origin, position = leader:GetPosition(), inst:GetPosition()
    local distance = Policy.DistanceSq(inst, leader)
    if distance > M.DISMOUNT_DISTANCE_SQ then self.chasing = true end
    if distance <= M.PATROL_MIN_DISTANCE^2 then self.chasing = false end
    local point
    if self.chasing then
        self.patrol_target = nil
        self.next_patrol = now + M.PATROL_RETRY
        point = origin
    else
        local target = self.patrol_target
        if target ~= nil and ((position.x - target.x)^2 + (position.z - target.z)^2 <= 1.25^2
            or (origin.x - target.x)^2 + (origin.z - target.z)^2 > M.DISMOUNT_RESET_DISTANCE_SQ
            or now >= (self.patrol_deadline or 0)) then
            self.patrol_target = nil
            self.next_patrol = now + math.random(4, 8)
        end
        if self.patrol_target == nil and now >= (self.next_patrol or 0) then
            self.patrol_target = FindPatrolPoint(inst, leader)
            self.patrol_deadline = now + 6
            self.next_patrol = now + M.PATROL_RETRY
        end
        point = self.patrol_target
    end
    if point ~= nil and inst:GetCurrentPlatform() == nil then
        point = Navigation.GetSteeringPoint(inst, point)
    end
    if point ~= nil then
        inst.components.locomotor:GoToPoint(point, nil, true)
    else
        inst.components.locomotor:Stop()
    end
end

function RideToLeader:Visit()
    local inst = self.inst
    if self.status == READY then
        if inst._my_friend_mount_stop_requested and IsRiding(inst) then
            self.phase = "ride"
            self.time = GetTime()
            self.status = RUNNING
            self:BeginDismount()
        elseif inst._my_friend_mount_stop_requested then
            self.status = SUCCESS
        elseif IsRiding(inst) then
            self.phase, self.time, self.status = "ride", GetTime(), RUNNING
            inst._my_friend_mount_started = inst._my_friend_mount_started or GetTime()
        else
            self.phase = "mount"
            self.mount = M.GetBeefalo(inst)
            if self.mount == nil then self:Fail() end
            if self.pendingstatus == nil then
                local action = M.GetMountAction(inst, self.mount)
                if action == nil then self:Fail() end
                if self.pendingstatus == nil then
                    self.action = action
                    require("my_friend_dialogue").OnAction(inst, action)
                    action:AddFailAction(function()
                        if self.action == action then
                            -- Rider:Mount sets riding before changing SG state.
                            -- doshortaction.onexit clears the buffered action,
                            -- which calls Fail even though mounting succeeded.
                            if IsRiding(inst) then self.action = nil
                            else self:Fail() end
                        end
                    end)
                    action:AddSuccessAction(function()
                        if self.action == action then
                            self.action = nil
                            -- MOUNT can succeed even when the cow refuses its rider.
                            if not IsRiding(inst) then self:Fail() end
                        end
                    end)
                    inst.components.locomotor:PushAction(action, true)
                    self.time = GetTime()
                    self.status = RUNNING
                end
            end
        end
    end

    if self.status == RUNNING then
        if self.pendingstatus ~= nil then
            self.status = self.pendingstatus
            return
        end
        if self.phase == "mount" then
            if IsRiding(inst) then
                self.action = nil
                self.phase = "ride"
                inst._my_friend_riding = true
                inst._my_friend_mount_started = GetTime()
                inst._my_friend_mount_keep_riding = nil
            elseif GetTime() - self.time > M.ACTION_TIMEOUT then
                self:Fail()
            end
        elseif self.phase == "ride" then
            local leader = Policy.GetLeader(inst)
            if inst._my_friend_mount_stop_requested then
                if IsRiding(inst) then self:BeginDismount() else self.status = SUCCESS end
            elseif inst._my_friend_under_threat
                or GetTime() < (inst._my_friend_hurt_evade_until or 0)
                or require("my_friend_light_ai").IsDark(inst)
                or require("my_friend_survival_ai").NeedsTemperatureHelp(inst)
                or inst.components.hunger ~= nil
                    and inst.components.hunger:GetPercent() < .2 then
                -- The manual ride window only suppresses casual arrival
                -- dismounts. Survival emergencies still take priority.
                if IsRiding(inst) then self:BeginDismount() else self.status = SUCCESS end
            elseif leader == nil or not leader:IsValid() or Policy.IsLeaderDead(inst)
                or not IsRiding(inst) then
                if IsRiding(inst) then self:BeginDismount() else self.status = SUCCESS end
            else
                local platform = leader:GetCurrentPlatform()
                local walkable = platform ~= nil and platform.components.walkableplatform or nil
                if Platforms.NeedsCrossing(inst, leader) and walkable ~= nil and walkable.no_mounts then
                    self:BeginDismount()
                else
                    self:CheckArrivalDecision(leader)
                end
                if self.phase == "ride" then
                    self:FollowMounted(leader)
                end
            end
        elseif self.phase == "dismount" then
            if not IsRiding(inst) then self.status = SUCCESS end
        end
        if self.status == RUNNING and GetTime() - self.time > M.ACTION_TIMEOUT
            and self.phase ~= "ride" then self:Fail() end
    end
end

function RideToLeader:Reset()
    BehaviourNode.Reset(self)
    self.phase, self.mount, self.action, self.pendingstatus = nil, nil, nil, nil
    self.patrol_target, self.next_patrol = nil, nil
    self.chasing, self.patrol_deadline = nil, nil
end

function RideToLeader:OnStop()
    local inst = self.inst
    if self.action ~= nil and self.pendingstatus == nil then self.action:Fail() end
    -- Utility replans after inventory changes and urgent actions. Stopping a
    -- behaviour is not a request to dismount; the next visit adopts the mount.
    inst._my_friend_riding = IsRiding(inst) or nil
    inst._my_friend_riding_dismounting = nil
    if not IsRiding(inst) then
        inst._my_friend_mount_started = nil
        inst._my_friend_mount_keep_riding = nil
        inst._my_friend_mount_stop_requested = nil
    end
    self.action, self.mount, self.phase = nil, nil, nil
    self.patrol_target, self.next_patrol = nil, nil
    self.chasing, self.patrol_deadline = nil, nil
end

function M.UpdateLeashing(inst)
    if inst:IsAsleep() or inst:HasTag("playerghost") or inst.components.health:IsDead() then return end
    local beefalo = M.GetBoundBeefalo(inst)
    if beefalo == nil or not beefalo:IsAsleep() or beefalo:HasTag("INLIMBO")
        or inst:GetDistanceSqToInst(beefalo) <= 40 * 40 then return end
    local follower = beefalo.components.follower
    if follower == nil or follower:GetLeader() ~= inst
        or follower.porttask ~= nil
        or beefalo.components.health ~= nil and beefalo.components.health:IsDead()
        or beefalo.components.rideable ~= nil and beefalo.components.rideable:IsBeingRidden()
        or beefalo.components.hitchable ~= nil and beefalo.components.hitchable:GetHitch() ~= nil then return end
    -- A bell transferred after the cow fell asleep misses the owner's wake
    -- event. Restart vanilla leashing; it chooses a walkable point and retries.
    -- Companions intentionally keep vanilla leashing disabled so ordinary
    -- follow logic cannot teleport them. A linked bell is the one exception:
    -- temporarily enable the vanilla wake/port retry, then restore the flag.
    local noleashing = follower.noleashing
    follower.noleashing = nil
    follower:StartLeashing()
    follower.noleashing = noleashing
    beefalo:PushEvent("entitysleep")
end

function M.Behaviour(inst)
    return RideToLeader(inst)
end

return M
