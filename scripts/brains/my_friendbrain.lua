require "behaviours/doaction"
require "behaviours/runaway"
require "behaviours/standstill"
local MyFriendCombat = require("behaviours/my_friend_combat")
local FoodAI = require("my_friend_food_ai")
local BehaviourAI = require("my_friend_behavior_ai")
local LightAI = require("my_friend_light_ai")
local ContainerAI = require("my_friend_container_ai")
local SurvivalAI = require("my_friend_survival_ai")
local BaseAI = require("my_friend_base_ai")
local Backpacks = require("my_friend_backpacks")
local ReviveAI = require("my_friend_revive_ai")
local GhostCommands = require("my_friend_ghost_commands")
local CoreAI = require("my_friend_core_ai")
local Policy = require("my_friend_policy")
local CookingAI = require("my_friend_cooking_ai")
local RecipeCooking = require("my_friend_recipe_cooking")
local Tidy = require("my_friend_tidy")
local Utility = require("behaviours/my_friend_utility")
local RouteAction = require("behaviours/my_friend_route_action")
local Navigation = require("my_friend_navigation")
local Commands = require("my_friend_commands")
local SocialAI = require("my_friend_social_ai")
local Emotes = require("my_friend_emotes")
local Sitting = require("my_friend_sitting")
local BeefaloAI = require("my_friend_beefalo")
local Riding = BeefaloAI.Riding
local Fishing = require("my_friend_fishing")
local Exploration = require("my_friend_exploration")
local SpecialGather = require("my_friend_command_special_gather")
local FriendEmote = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "FriendEmote")
    self.inst = inst
end)

function FriendEmote:Visit()
    local inst = self.inst
    if self.status == READY then
        local request = inst._my_friend_pending_emote
        if request == nil or Emotes.Score(inst) == 0 or Policy.IsBusy(inst) then
            self.status = FAILED
            return
        end
        self.request = request
        -- Only queued requests and one-shot animations expire. Looping emotes
        -- yield through the utility selector when another behaviour is needed.
        request.expires = request.idle_duration ~= nil and GetTime() + request.idle_duration
            or not request.data.loop and GetTime() + 8 or nil
        inst.components.locomotor:Clear()
        inst.sg:GoToState("emote", request.data)
        self.memory = inst.sg.statemem
        self.status = RUNNING
    end
    if Emotes.Score(inst) == 0 or inst.sg.currentstate.name ~= "emote"
        or inst.sg.statemem ~= self.memory then self.status = SUCCESS return end
    self:Sleep(.1)
end

function FriendEmote:OnStop()
    local inst = self.inst
    if inst._my_friend_pending_emote == self.request then inst._my_friend_pending_emote = nil end
    if self.memory ~= nil and inst.sg.currentstate.name == "emote"
        and inst.sg.statemem == self.memory then inst.sg:GoToState("idle") end
    self.request, self.memory = nil, nil
end
local Platforms = require("my_friend_platforms")

local MyFriendFollow = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendFollow")
    self.inst = inst
    self.next_stroll = nil
    self.stroll_target = nil
    self.chasing = false
end)

-- Extra wait between two "push" strolls (walking right into the player's
-- spot). Ordinary strolls keep their 4-8 second rhythm.
local FOLLOW_PUSH_COOLDOWN = 30

local function IsFriendWalking(inst)
    return inst.sg ~= nil and inst.sg:HasStateTag("my_friend_walk")
end

local function StartFriendWalk(inst, target)
    local goal = target
    if inst:GetCurrentPlatform() == nil then target = Navigation.GetSteeringPoint(inst, target) end
    local detour = Navigation.Unstick(inst, goal)
    if detour ~= nil then target = detour end
    if target == nil then inst.components.locomotor:Stop() return end
    if inst.sg ~= nil then
        if not IsFriendWalking(inst) then
            inst.sg:GoToState("my_friend_walk_start", target)
            return
        end
    end
    local old = inst._my_friend_last_move
    if old == nil or old.run or GetTime() >= old.untiltime
        or (old.point - target):LengthSq() > .25 then
        inst.components.locomotor:GoToPoint(target, nil, false)
        inst._my_friend_last_move = {point = target, run = false, untiltime = GetTime() + .75}
    end
end

local function StopFriendWalk(inst)
    inst._my_friend_last_move = nil
    Navigation.CancelSteering(inst)
    Navigation.ClearStuck(inst)
    inst.components.locomotor:Stop()
    if IsFriendWalking(inst) then
        inst.sg:GoToState("my_friend_walk_stop")
    end
end

local function StartFriendRun(inst, target)
    local goal = target
    if inst:GetCurrentPlatform() == nil then
        target = Navigation.GetSteeringPoint(inst, target)
    end
    -- Independent of the local planner, which is skipped entirely once the
    -- leader is past its range and returns nil while it is still thinking.
    -- Either way the companion would otherwise stand still or push into the
    -- obstacle; this notices that and goes round.
    local detour = Navigation.Unstick(inst, goal)
    if detour ~= nil then target = detour end
    if target == nil then return end
    -- Do not bounce the stategraph between walk/idle while a nearby leader
    -- keeps moving. Locomotor can switch to running without cancelling itself.
    if IsFriendWalking(inst) and inst.sg ~= nil
        and not inst.sg:HasStateTag("busy") then
        inst.sg:GoToState("idle")
    end
    local old = inst._my_friend_last_move
    local platform_move = inst:GetCurrentPlatform() ~= nil
    local refresh = old ~= nil and GetTime() >= old.untiltime
        and (not platform_move or inst.components.locomotor.dest == nil)
    if old == nil or not old.run or refresh
        or (old.point - target):LengthSq() > 1 then
        inst.components.locomotor:GoToPoint(target, nil, true)
        inst._my_friend_last_move = {point = target, run = true,
            untiltime = GetTime() + (platform_move and 1 or .45)}
    end
end

function MyFriendFollow:FinishStroll(now)
    self.stroll_target = nil
    self.stroll_push = nil
    self.stroll_deadline = nil
    self.stroll_progress = nil
    self.stroll_best = nil
    self.stroll_previous = nil
    self.next_stroll = now + math.random(4, 8)
    StopFriendWalk(self.inst)
end

function MyFriendFollow:Visit()
    -- The real Wendy prefab uses SGwilson/SGwilsonghost. Do not issue
    -- locomotion requests while an original player action, death, ghost, or
    -- resurrection state owns the animation.
    -- Never call locomotor:Stop while SGwilson owns a busy action. Stop()
    -- sends a locomote event and can cancel the vanilla eat/quickeat,
    -- revive, attack, or hit animation before it reaches its timeline.
    if self.inst.sg ~= nil and self.inst.sg:HasStateTag("busy") then
        self.status = RUNNING
        self:Sleep(0.25)
        return
    end
    local ghost = self.inst:HasTag("playerghost")
        or self.inst.components.health ~= nil and self.inst.components.health:IsDead()
    if ghost then
        local follower = self.inst.components.follower
        local leader = follower ~= nil and follower:GetLeader() or nil
        if leader == nil or not leader:IsValid() then
            self.inst.components.locomotor:Stop()
            self.status = RUNNING
            self:Sleep(0.25)
            return
        end
        -- A ghost with a leader still follows. Removing the leader naturally
        -- returns it to the stationary ghost branch.
    end
    if self.inst._my_friend_backpack_action then
        self.status = RUNNING
        self:Sleep(0.1)
        return
    end
    if self.inst._my_friend_container_action then
        self.status = RUNNING
        self:Sleep(0.1)
        return
    end
    if self.inst._my_friend_storage_action then
        self.status = RUNNING
        self:Sleep(0.1)
        return
    end
    local follower = self.inst.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    if leader == nil or not leader:IsValid() then
        self:FinishStroll(GetTime())
        self.leader = nil
        self.chasing = false
        self.status = FAILED
        self:Sleep(0.5)
        return
    end
    BaseAI.SetTask(self.inst, "正在跟随玩家")
    local x, y, z = self.inst.Transform:GetWorldPosition()
    local tx, ty, tz = leader.Transform:GetWorldPosition()
    local dx, dz = tx - x, tz - z
    local dist_sq = dx * dx + dz * dz
    local now = GetTime()
    if self.leader ~= leader then
        self:FinishStroll(now)
        self.leader = leader
        self.chasing = false
    end
    if Platforms.NeedsCrossing(self.inst, leader) then
        self.stroll_target, self.next_stroll = nil, nil
        self.chasing = true
        Platforms.FollowCrossing(self.inst, leader)
        self.status = RUNNING
        self:Sleep(.1)
        return
    end
    -- Crossing seven units starts a chase. Once started, keep running until
    -- the companion is within three units; do not stop at the seven-unit
    -- boundary on the way back.
    if dist_sq >= 49 or dist_sq > 9
        and now < (self.inst._my_friend_follow_requested_until or 0) then
        self.chasing = true
    end
    if self.chasing and dist_sq > 6.25 then
        self.next_stroll = nil
        self.stroll_target = nil
        if IsFriendWalking(self.inst) then
            self.inst.sg:GoToState("idle")
        end
        StartFriendRun(self.inst, Vector3(tx, ty, tz))
        self.status = RUNNING
        self:Sleep(0.1)
        return
    end
    if self.chasing then self:FinishStroll(now) end
    self.chasing = false
    -- Arrival is consumed by Snapshot, even when a higher-priority node wins.

    -- Only the push branch walks to the player's captured position.
    -- Running strolls keep one destination until arrival or a bounded timeout.
    if self.stroll_target ~= nil then
        if (self.stroll_target.x - tx)^2 + (self.stroll_target.z - tz)^2 > 49 then
            self:FinishStroll(now)
        end
    end
    if self.stroll_target ~= nil then
        local sdx, sdz = self.stroll_target.x - x, self.stroll_target.z - z
        local distance = math.sqrt(sdx * sdx + sdz * sdz)
        local previous = self.stroll_previous
        local crossed = not self.stroll_push and previous ~= nil
            and previous.x * sdx + previous.z * sdz <= 0
            and distance <= 2
        if self.stroll_best == nil or distance < self.stroll_best - .25 then
            self.stroll_best, self.stroll_progress = distance, now
        end
        local reached = distance <= (self.stroll_push and .2 or 1)
        local stalled = now - (self.stroll_progress or now) >= 3
        if reached or crossed or stalled or now >= (self.stroll_deadline or now) then
            self:FinishStroll(now)
        else
            self.stroll_previous = {x = sdx, z = sdz}
            if self.stroll_push then
                StartFriendWalk(self.inst, self.stroll_target)
            else
                StartFriendRun(self.inst, self.stroll_target)
            end
        end
        self.status = RUNNING
        self:Sleep(0.1)
        return
    end

    if self.next_stroll == nil then self.next_stroll = now + math.random(4, 8) end
    if now >= self.next_stroll then
        local origin = Vector3(tx, ty, tz)
        self.stroll_push = math.random() < .2
            and now >= (self.inst._my_friend_push_after or 0)
        if self.stroll_push then
            self.stroll_target = origin
            self.inst._my_friend_push_after = now + FOLLOW_PUSH_COOLDOWN
        else
            for _ = 1, 4 do
                local offset = FindWalkableOffset(origin, math.random() * PI2,
                    math.random(2, 6), 12, true, false)
                local point = offset ~= nil and origin + offset or nil
                if point ~= nil and TheWorld.Map:GetPlatformAtPoint(point.x, point.z)
                    == self.inst:GetCurrentPlatform()
                    and (point.x - x)^2 + (point.z - z)^2 >= 4 then
                    self.stroll_target = point
                    break
                end
            end
        end
        self.next_stroll = now + math.random(4, 8)
        if self.stroll_target ~= nil then
            self.stroll_deadline, self.stroll_progress = now + 10, now
            self.stroll_best, self.stroll_previous = nil, nil
            if self.stroll_push then
                StartFriendWalk(self.inst, self.stroll_target)
            else
                StartFriendRun(self.inst, self.stroll_target)
            end
        else
            StopFriendWalk(self.inst)
        end
    else
        StopFriendWalk(self.inst)
    end
    self.status = RUNNING
    self:Sleep(0.1)
end

function MyFriendFollow:OnStop()
    -- Brief utility interruptions must not restart the 4-8 second timer.
    local next_stroll = self.next_stroll
    self:FinishStroll(GetTime())
    self.next_stroll = next_stroll
    self.chasing = false
end

local MyFriendExplore = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendExplore")
    self.inst = inst
    self.target = nil
    self.target_timeout = nil
    self.next_move = nil
    self.recent_targets = {}
    self.best_distance = nil
    self.stall_since = nil
end)

local EXPLORE_REST_MIN = 30
local EXPLORE_REST_MAX = 60
local EXPLORE_REST_TIME = 3
local EXPLORE_STALL_TIMEOUT = 4
local EXPLORE_PROGRESS_DISTANCE = .75
local EXPLORE_TARGET_TIMEOUT = 12
local EXPLORE_TARGET_COOLDOWN = 1

local function RememberExploreTarget(self, target)
    if target == nil then return end
    local recent = self.recent_targets
    recent[#recent + 1] = Vector3(target.x, target.y, target.z)
    while #recent > 8 do table.remove(recent, 1) end
end

function MyFriendExplore:Visit()
    if self.inst.sg ~= nil and self.inst.sg:HasStateTag("busy") then
        self.status = RUNNING
        self:Sleep(.25)
        return
    end
    local now = GetTime()
    BaseAI.SetTask(self.inst, Policy.GetVigilPoint(self.inst) ~= nil
        and "正在原地等待倒下的玩家" or "正在基地附近巡视")
    if self.target ~= nil and BaseAI.ShouldPreferBaseFire(self.inst)
        and not LightAI.IsPointExternallyLit(self.inst, self.target) then
        self.target, self.target_timeout, self.next_move = nil, nil, nil
        self.best_distance, self.stall_since = nil, nil
        StopFriendWalk(self.inst)
    end
    if now < (self.inst._my_friend_explore_pause_until or 0) then
        StopFriendWalk(self.inst)
        self.status = RUNNING
        self:Sleep(math.min(.5, self.inst._my_friend_explore_pause_until - now))
        return
    end
    if self.inst._my_friend_next_explore_rest == nil then
        self.inst._my_friend_next_explore_rest = now
            + math.random(EXPLORE_REST_MIN, EXPLORE_REST_MAX)
    elseif self.target ~= nil and now >= self.inst._my_friend_next_explore_rest then
        self.inst._my_friend_explore_pause_until = now + EXPLORE_REST_TIME
        self.inst._my_friend_next_explore_rest = now + EXPLORE_REST_TIME
            + math.random(EXPLORE_REST_MIN, EXPLORE_REST_MAX)
        self.stall_since = now
        StopFriendWalk(self.inst)
        self.status = RUNNING
        self:Sleep(.25)
        return
    end
    if self.target ~= nil then
        local position = self.inst:GetPosition()
        local dx, dz = self.target.x - position.x, self.target.z - position.z
        local distance = math.sqrt(dx * dx + dz * dz)
        if self.best_distance == nil or distance <= self.best_distance - EXPLORE_PROGRESS_DISTANCE then
            self.best_distance = distance
            self.stall_since = now
        elseif self.stall_since == nil then
            self.stall_since = now
        end
        local reached = distance <= .25
        local timed_out = self.target_timeout ~= nil and now >= self.target_timeout
        local stalled = self.stall_since ~= nil
            and now - self.stall_since >= EXPLORE_STALL_TIMEOUT
        if not reached and not timed_out and not stalled then
            StartFriendRun(self.inst, self.target)
            self.status = RUNNING
            self:Sleep(.1)
            return
        end
        StopFriendWalk(self.inst)
        RememberExploreTarget(self, self.target)
        self.target = nil
        self.target_timeout = nil
        self.best_distance = nil
        self.stall_since = nil
        self.next_move = now + EXPLORE_TARGET_COOLDOWN
    end
    if self.next_move ~= nil and now < self.next_move then
        StopFriendWalk(self.inst)
        self.status = RUNNING
        self:Sleep(math.min(.5, self.next_move - now))
        return
    end
    self.target = BaseAI.GetWanderPoint(self.inst, self.recent_targets)
    if self.target == nil then
        self.next_move = now + 2
    else
        self.best_distance = nil
        self.stall_since = now
        self.target_timeout = now + EXPLORE_TARGET_TIMEOUT
        StartFriendRun(self.inst, self.target)
    end
    self.status = RUNNING
    self:Sleep(.1)
end

function MyFriendExplore:OnStop()
    self.target = nil
    self.target_timeout = nil
    self.next_move = nil
    self.recent_targets = {}
    self.best_distance = nil
    self.stall_since = nil
    StopFriendWalk(self.inst)
end

local MyFriendBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local function FindThreat(inst)
    return BehaviourAI.FindThreat(inst)
end

function MyFriendBrain:OnStart()
    local inst = self.inst
    local entries = {}
    local function Add(id, score, node)
        local function ScopedScore(c)
            if Policy.IsRoaming(inst) and (id == "follow" or id == "catch_up"
                or id == "catch_up_mount" or id == "wormhole" or id == "assist"
                or id == "vigil" or id == "sit") then return 0 end
            if c.hurt_evade and id ~= "hurt" and id ~= "hurt_wait"
                and id ~= "light" and id ~= "farewell" and not c.ghost then return 0 end
            return score(c)
        end
        entries[#entries + 1] = { id = id, score = ScopedScore, node = node,
            passive = id == "follow" or id == "free" or id == "catch_up"
                or id == "catch_up_mount" or id == "vigil"
                or id == "light_wait" or id == "thermal_wait" or id == "greeting"
                or id == "construction_wait" or id == "command_wait" or id == "emote"
                or id == "sit" or id == "expedition" or id == "fishing_wait"
                or id == "expedition_wait" }
    end
    local function Action(id, score, getter, text, timeout, unrestricted)
        Add(id, score, RouteAction(inst, function()
            local command = Commands.Get(inst)
            if Policy.IsFollowGatheringPaused(inst)
                and id ~= "farewell"
                and id ~= "command" and id ~= "wormhole" and id ~= "revive" and id ~= "rescue" and id ~= "light"
                and id ~= "hurt" and id ~= "eat" and id ~= "temperature"
                and id ~= "seek_light" and id ~= "emergency_light_supply"
                and id ~= "emergency_fire" and id ~= "backpack_recovery" and id ~= "revive_return"
                and id ~= "carry_backpack"
                and not ((id == "food" or id == "container_food" or id == "cook")
                    and inst.components.hunger:GetPercent() < .2) then return end
            if command ~= nil and (command.id == "seeds" or command.id == "tidy" or command.id == "equipment")
                and id ~= "farewell"
                and id ~= "command" and id ~= "wormhole" and id ~= "revive" and id ~= "rescue" and id ~= "light"
                and id ~= "hurt" and id ~= "eat" and id ~= "temperature"
                and id ~= "seek_light" and id ~= "emergency_fire" and id ~= "revive_return" then return end
            if LightAI.IsDark(inst) and id ~= "farewell" and id ~= "light" and id ~= "seek_light"
                and id ~= "emergency_light_supply" and id ~= "emergency_fire"
                and id ~= "base_fire" and id ~= "hurt" and id ~= "eat"
                and id ~= "revive" then return end
            local action = getter(inst)
            if action ~= nil and Policy.IsRoaming(inst) then
                action = require("my_friend_exploration_riding").PrepareAction(inst, action)
            end
            if action ~= nil then
                if id ~= "expedition" and Fishing.IsWaiting(inst) then
                    Fishing.Cancel(inst, inst._my_friend_command)
                end
                if Policy.GetLeader(inst) ~= nil and id ~= "command"
                    and (action.action == ACTIONS.CHOP or action.action == ACTIONS.MINE) then
                    action._my_friend_cancelled = true
                    action:Fail()
                    return
                end
                require("my_friend_dialogue").OnAction(inst, action)
                if text ~= nil then BaseAI.SetTask(inst, text) end
                return unrestricted and action or Policy.GuardAction(inst, action)
            end
        end, id, true, timeout or 12, (not unrestricted or id == "revive_return") and id ~= "hurt"
            -- "temperature" walks to a fire or a thermal stone that can easily
            -- sit behind a wall of chests, and with routing off it had neither
            -- a path nor the local retry that RetryLocalApproach provides -- it
            -- simply leaned on whatever was in the way until the action timed
            -- out, then tried the identical straight line again. "hurt" is a
            -- deliberate short dash away from a spot and "eat" does not travel.
            and id ~= "eat"))
    end
    local function Alive(score)
        return function(c) return not c.ghost and (type(score) == "function" and score(c) or score) or 0 end
    end
    Action("revive", function(c) return c.ghost and math.max(150, GhostCommands.Score(inst)) or 0 end,
        GhostCommands.GetAction, nil, GhostCommands.TIMEOUT, true)
    Action("revive_return", Alive(function(c) return GhostCommands.ReturnScore(inst, c) end),
        GhostCommands.GetReturnAction, nil, GhostCommands.TIMEOUT, true)
    Add("ghost_follow", function(c)
        return c.ghost and c.leader ~= nil and 151 or 0
    end, require("behaviours/my_friend_ghost_follow")(inst))
    Add("ghost", function(c) return c.ghost and 149 or 0 end, StandStill(inst))
    -- Saying goodbye before a character change: walk away from everyone and
    -- let nothing else get in the way.
    Action("farewell", Alive(function() return require("my_friend_farewell").Score(inst) end),
        require("my_friend_farewell").GetAction, "正在与大家告别并离开", 20)
    Action("light", Alive(function(c) return c.dark and 140 or 84 end),
        LightAI.GetLightAction, "正在保证照明", 5, true)
    Action("hurt", Alive(function(c) return c.hurt and 135 or 0 end),
        BehaviourAI.GetHurtRetreatAction, "正在离开受伤的位置", 3)
    Add("hurt_wait", Alive(function(c) return c.hurt_evade and 134 or 0 end), StandStill(inst))
    Action("wormhole", Alive(function()
        return require("my_friend_wormhole").Score(inst)
    end), require("my_friend_wormhole").GetAction, "正在跟随玩家穿过传送入口", 20)
    Add("combat", Alive(function(c) return not c.hurt and not c.hurt_evade
            and c.threat ~= nil
            and c.canfight and not c.urgent_repair and 125 or 0 end),
        WhileNode(function()
            local threat = BehaviourAI.FindThreat(inst)
            if threat == nil or not Policy.InRange(inst, threat, 32)
                or not BehaviourAI.CanCounterAttack(inst, threat) then return false end
            inst.components.combat:SetTarget(threat)
            return true
        end, "CounterAttack", MyFriendCombat(inst)))
    Action("recover_combat_item", Alive(function(c)
        return not c.hurt and not c.hurt_evade and c.threat ~= nil
            and inst._my_friend_combat_hand_item ~= nil and 126 or 0
    end), require("my_friend_equipment").GetDroppedCombatItemAction,
        "正在捡回战斗装备", 4)
    Add("escape", Alive(function(c) return not c.hurt and not c.hurt_evade
            and c.threat ~= nil
            and 124 or 0 end),
        WhileNode(function() return BehaviourAI.FindThreat(inst) ~= nil end, "Escape",
            RunAway(inst, {getfn = FindThreat}, BehaviourAI.THREAT_RANGE,
                BehaviourAI.THREAT_SAFE_DISTANCE, nil, nil, true, false,
                BehaviourAI.GetLeaderSafetyPoint)))
    Action("seek_light", Alive(function(c) return c.dark and 120 or 0 end),
        LightAI.GetSeekLightAction, "正在寻找光源", 12, true)
    Action("emergency_light_supply", Alive(function(c) return c.dark and 119 or 0 end),
        ContainerAI.GetEmergencyLightAction, "正在寻找照明物资")
    Action("emergency_fire", Alive(function(c) return c.dark and c.leader == nil and 118 or 0 end),
        CookingAI.GetCampfireAction, "正在制作应急营火")
    Action("eat", Alive(function(c) return c.emergency_food and 122 or c.hunger < .4 and 118 or 85 end),
        FoodAI.GetEatAction, "正在进食", 5)
    Action("temperature", Alive(function(c) return c.thermal and 115 or 0 end),
        SurvivalAI.GetTemperatureAction, "正在处理体温问题")
    Action("repair", Alive(function(c)
        return c.repair and (c.urgent_repair and 139 or 113) or 0
    end), require("my_friend_equipment").GetRepairAction,
        "正在修补装备", 12)
    Add("thermal_wait", Alive(function(c)
        return c.thermal and SurvivalAI.IsNearThermalSource(inst) and 114 or 0
    end), StandStill(inst))
    Action("base_fire", Alive(function(c)
        if c.leader == nil and BaseAI.ShouldPreferBaseFire(inst) then return 123 end
        return c.leader == nil and (c.dark or TheWorld.state.isnight
            or TheWorld.state.isdusk or TheWorld:HasTag("cave")) and 121 or 0
    end),
        BaseAI.GetBaseFireAction, nil)
    Add("light_wait", Alive(function(c) return c.waitlight and 90 or 0 end), StandStill(inst))
    Add("greeting", Alive(function(c)
        return c.greeting and CoreAI.CanPauseForGreeting(inst) and 89 or 0
    end), StandStill(inst, nil, function() return CoreAI.IsGreetingPauseActive(inst) end))
    Action("social_distance", Alive(105), SocialAI.GetAvoidAction, "正在和不熟悉的玩家保持距离", 12)
    Action("command_drop", Alive(function(c)
        return c.leader ~= nil and (inst._my_friend_drop_backpack or inst._my_friend_command_drop) and 93 or 0
    end), SocialAI.GetDropAction, nil)
    Add("catch_up_mount", Alive(function(c) return Riding.Score(inst, c) end),
        Riding.Behaviour(inst))
    Add("catch_up", Alive(function(c)
        local command = Commands.Get(inst)
        if command ~= nil and command.id == "chop" then return 0 end
        return c.leader ~= nil and not c.leaderdead and not c.waitlight
            and (Platforms.NeedsCrossing(inst, c.leader)
                or c.distance > Policy.ActivityRange(inst)^2
                or c.rejoining)
            and 110 or 0
    end),
        MyFriendFollow(inst))
    -- Freshly revived: fetch the death drops before any foraging or fridge
    -- raid (food 86-98, container_food 95). Only real starvation comes first.
    Action("recover", Alive(function(c)
        if not inst._my_friend_recover_death_drops then return 0 end
        return c.hunger < .2 and 82 or inst._my_friend_auto_recovery_point ~= nil and 117 or 100
    end), ReviveAI.GetRecoveryAction, nil, 120)
    Action("rescue", Alive(function(c) return require("my_friend_rescue").Score(inst) end),
        require("my_friend_rescue").GetAction, "正在救助附近死去的玩家", 20)
    Action("recovery_delivery", Alive(function(c) return c.leader == nil and 79 or 0 end),
        BaseAI.GetRecoveryDeliveryAction, "正在把找回的物资送回基地", 120)
    Action("container_food", Alive(function(c) return c.emergency_food and 121 or c.hunger < .4 and 95 or 61 end),
        ContainerAI.GetFoodAction, "正在从容器进食")
    Action("butterfly_hunt", Alive(function(c)
        return require("my_friend_butterfly").Score(inst, c)
    end), require("my_friend_butterfly").GetSurvivalAction, "正在捕蝶并收集掉落物", 18)
    Action("food", Alive(function(c)
        return c.needsfood and (c.hunger < .4 and 98 or 86) or 0
    end), BehaviourAI.GetFoodAction, "正在收集食物")
    Action("food_route", Alive(function(c)
        return c.leader == nil and c.needsfood
            and (c.hunger < .4 and 96 or c.constructing and 62 or 71) or 0
    end), BaseAI.GetFoodSearchAction, "正在前往食物所在的位置", 45)
    Action("cook", Alive(function(c)
        if GetTime() < (inst._my_friend_cook_until or 0) then
            return c.hunger < .4 and 101 or 92
        end
        return c.hunger < .4 and 93 or 63
    end),
        CookingAI.GetAction, "正在准备烤制食物", 60)
    Action("beefalo_care", Alive(function(c)
        return BeefaloAI.Score(inst, c)
    end), BeefaloAI.GetAction, "正在照料皮弗牛", 35)
    Action("recipe_cooking", Alive(function(c) return RecipeCooking.Score(inst, c) end),
        RecipeCooking.GetAction, "正在准备料理", 35)
    Action("carry_backpack", Alive(function() return require("my_friend_carry_backpack").Score(inst) end),
        require("my_friend_carry_backpack").GetAction, "正在取回搬重物时留下的背包", 180)
    Action("backpack_recovery", Alive(function() return Backpacks.Priority(inst) end),
        Backpacks.GetAction, "正在找回自己的背包", 30)
    Action("cleanup", Alive(function()
        return inst._my_friend_work_cleanup ~= nil and 88 or 0
    end), BaseAI.GetCleanupAction, "正在收集本次工作掉落的物资")
    Action("fertilizer_opportunity", Alive(79),
        require("my_friend_fertilizer_search").Opportunity, "正在顺路收集肥料")
    Action("inventory_relief", Alive(function(c)
        return c.leader == nil and c.full and 88 or 0
    end), BaseAI.GetInventoryReliefAction, nil, 120)
    Action("surplus_store", Alive(function(c)
        return c.leader == nil and not c.constructing and 72 or 0
    end), BaseAI.GetSurplusStoreAction, nil, 120)
    Action("nearby_tidy", Alive(function(c) return Tidy.Score(inst, c) end),
        Tidy.GetNearbyRelaxedAction, "正在顺手整理物资")
    Action("store_books", Alive(function(c)
        return inst.prefab == "wickerbottom" and not c.threat and not c.dark
            and not c.thermal and c.hunger >= .4 and 60 or 0
    end), require("my_friend_books").GetStoreAction, "正在把旧书放回书架")
    Action("food_return", Alive(function(c)
        return not c.threat and not c.dark and not c.thermal and 59 or 0
    end), ContainerAI.GetReturnFoodAction, nil)
    -- Finished items on the new container-based drying racks are collected
    -- during relaxed movement.  The low score keeps this behind survival,
    -- combat, lighting, meals and active work.
    Action("dryingrack_collect", Alive(function(c)
        return not c.threat and not c.dark and not c.thermal
            and c.hunger >= .4 and 58 or 0
    end), SpecialGather.GetNearbyDryingRackAction, "正在收集晾好的食材", 12)
    Action("light_supply", Alive(function(c) return (c.reserve or c.constructing) and 0 or 66 end),
        ContainerAI.GetLightSupplyAction, "正在储备照明物资")
    Action("reserve", Alive(function(c) return (c.reserve or c.constructing) and 0 or 65 end),
        BaseAI.GetReserveAction, "正在补充生存材料", 120)
    Action("backpack_craft", Alive(function(c) return c.leader ~= nil and 64 or 0 end),
        BaseAI.GetBackpackCraftAction, "正在准备自己的背包", 30)
    Action("command", Alive(function(c)
        local command = Commands.Get(inst)
        if Policy.IsRoaming(inst) then return 0 end
        return c.leader ~= nil and command ~= nil
            and (command.special ~= nil and 132 or command.id == "carry_statue" and 117 or 104) or 0
    end), function(actor) return Commands.Commit(actor, BaseAI.GetCommandAction(actor)) end, nil, 180)
    local function ExpeditionScore(c)
        return Policy.IsRoaming(inst) and not c.threat and not c.dark and not c.thermal
            and not c.hurt and 50 or 0
    end
    Action("expedition", Alive(function(c)
        return not Fishing.IsWaiting(inst) and ExpeditionScore(c) or 0
    end), function(actor)
        local command = Commands.Get(actor)
        if command == nil then return end
        BaseAI.SetTask(actor, command.id == "adopt_pet" and "正在前往宠物巢穴领养"
            or command.id == "fish" and "正在寻找池塘并钓鱼" or "正在探索未去过的地方")
        return Commands.Commit(actor, command.id == "fish" and Fishing.GetAction(actor)
            or command.id == "adopt_pet" and require("my_friend_pets").GetAction(actor)
            or command.id == "explore" and Exploration.GetAction(actor) or nil)
    end, nil, 60)
    Add("fishing_wait", Alive(function(c)
        return Fishing.IsWaiting(inst) and ExpeditionScore(c) or 0
    end), require("behaviours/my_friend_fishing")(inst))
    Add("expedition_wait", Alive(function()
        return Policy.IsRoaming(inst) and 9 or 0
    end), StandStill(inst))
    Add("command_wait", Alive(function()
        local command = Commands.Get(inst)
        return command ~= nil and (command.id == "seeds" or command.id == "tidy"
            or command.id == "equipment" or command.waiting)
            and (command.special ~= nil and 131 or 103) or 0
    end), StandStill(inst))
    Add("assist", Alive(function(c)
        if c.leader == nil or c.leaderdead
            or GetTime() < (inst._my_friend_next_assist or 0) then return 0 end
        local target = BehaviourAI.FindAssistTarget(inst)
        return target ~= nil and BehaviourAI.CanCounterAttack(inst, target) and 128 or 0
    end), WhileNode(function()
        local target = BehaviourAI.FindAssistTarget(inst)
        if target == nil or not BehaviourAI.CanCounterAttack(inst, target) then
            inst._my_friend_assist_target = nil
            inst._my_friend_assist_started = nil
            return false
        end
        inst._my_friend_assist_target = target
        inst._my_friend_assist_started = inst._my_friend_assist_started or GetTime()
        inst.components.combat:SetTarget(target)
        return true
    end, "AssistLeader", MyFriendCombat(inst)))
    Action("feed_player", Alive(function(c)
        if c.leaderdead then return 0 end
        return require("my_friend_feed_player").Score(inst, c.leader)
    end), require("my_friend_feed_player").GetAction, "正在给玩家喂食", 15)
    Action("base", Alive(function(c)
        return c.leader == nil and (BaseAI.IsComplete(inst)
            and not Backpacks.NeedsCraftedBackpack(inst) and 45 or 78) or 0
    end), BaseAI.GetAction, nil, 120)
    Action("basic_equipment", Alive(function(c)
        return require("my_friend_basic_equipment").Score(inst, c)
    end), require("my_friend_basic_equipment").GetAction, nil, 20)
    Action("opportunity", Alive(function(c)
        return c.leader ~= nil and 40 or 0
    end), CoreAI.GetOpportunityAction, "正在收集路过的物资")
    Action("feed_pet", Alive(function(c)
        return require("my_friend_pet_care").Score(inst, c)
    end), require("my_friend_pet_care").GetAction, "正在给自己的宠物喂食", 10)
    Add("emote", Alive(function() return Emotes.Score(inst) end), FriendEmote(inst))
    Add("sit", Alive(function(c) return Sitting.Score(inst, c) end), Sitting.Behaviour(inst))
    Add("follow", Alive(function(c)
        return c.leader ~= nil and not c.leaderdead and not c.hurt_evade and 10 or 0
    end), MyFriendFollow(inst))
    -- Leader died: wait for them near where they fell instead of trailing the
    -- ghost. Survival, rescue and commands still outrank this.
    Add("vigil", Alive(function(c) return c.leaderdead and not c.dark and 10 or 0 end),
        MyFriendExplore(inst))
    Add("dark_standby", Alive(function(c) return c.leader == nil and c.dark and 11 or 0 end), StandStill(inst))
    -- If no construction step is executable, survey the base with the same
    -- bounded movement as ordinary idle life. Available work preempts it.
    Add("construction_wait", Alive(function(c)
        return c.constructing and 10 or 0
    end), MyFriendExplore(inst))
    Add("free", Alive(function(c)
        return c.leader == nil and not c.constructing and not c.dark and 10 or 0
    end), MyFriendExplore(inst))
    local function Snapshot()
        Commands.Get(inst)
        Exploration.Observe(inst)
        local leader = Policy.GetLeader(inst)
        Policy.UpdateVigil(inst)
        local leaderdead = Policy.IsLeaderDead(inst)
        local rejoining = Policy.UpdateFollowRequest(inst, leader)
        local ghost = inst:HasTag("playerghost") or inst.components.health:IsDead()
        if ghost then
            inst._my_friend_under_threat, inst._my_friend_can_fight = false, false
            return {ghost = true, leader = leader, leaderdead = leaderdead, hunger = 1,
                distance = leader ~= nil and Policy.DistanceSq(inst, leader) or 0}
        end
        if leader == nil and not ghost then BaseAI.EnsureBase(inst) end
        local hurt_evade = GetTime() < (inst._my_friend_hurt_evade_until or 0)
        local threat = not ghost and not hurt_evade
            and BehaviourAI.FindThreat(inst) or nil
        inst._my_friend_under_threat = threat ~= nil
        if Fishing.IsWaiting(inst) and (ghost or threat ~= nil or hurt_evade or LightAI.IsDark(inst)) then
            Fishing.Cancel(inst, inst._my_friend_command)
        end
        if inst._my_friend_container_target ~= nil and (ghost or threat ~= nil
            or not inst._my_friend_container_target:IsValid()
            or not ContainerAI.IsOwnFoodContainer(inst, inst._my_friend_container_target)
                and not Policy.InRange(inst, inst._my_friend_container_target)
            or inst._my_friend_container_target:IsValid()
                and inst._my_friend_container_target.components.container ~= nil
                and inst._my_friend_container_target.components.container:IsOpenedBy(inst)
                and not ContainerAI.IsOwnFoodContainer(inst, inst._my_friend_container_target)
                and not require("my_friend_inventory").CanReachContainer(inst, inst._my_friend_container_target)
            or inst._my_friend_meal ~= nil and GetTime() > inst._my_friend_meal.deadline
            or LightAI.IsDark(inst)) then ContainerAI.Cancel(inst) end
        if not Policy.IsBusy(inst) then
            inst._my_friend_can_fight = threat ~= nil and Policy.InRange(inst, threat, 7)
                and BehaviourAI.CanCounterAttack(inst, threat) or false
        end
        if inst.components.combat.target ~= nil and threat == nil
            and inst._my_friend_assist_target == nil then inst.components.combat:SetTarget(nil) end
        local dark = not ghost and LightAI.IsDark(inst)
        if not ghost and (not Policy.IsBusy(inst) or dark) then
            BaseAI.RefreshWorkTarget(inst)
            -- Light first: it owns whichever slot is lighting the way, and the
            -- loadout arbiter reads that as a lock.
            LightAI.UpdateEquipment(inst)
            if not dark then require("my_friend_equipment").UpdateLoadout(inst) end
        end
        local repair, urgent_repair = false, false
        if not ghost then
            repair, urgent_repair = require("my_friend_equipment").GetRepairStatus(inst)
        end
        return {
            leader = leader, rejoining = rejoining, leaderdead = leaderdead,
            ghost = ghost, threat = threat, canfight = inst._my_friend_can_fight,
            -- A companion with a manual home, or one that joined a world past
            -- day 200, has nothing to construct and goes straight to living.
            constructing = leader == nil and not BaseAI.IsComplete(inst)
                and not require("my_friend_home").NoConstruction(inst),
            distance = leader ~= nil and Policy.DistanceSq(inst, leader) or 0,
            hunger = inst.components.hunger:GetPercent(),
            emergency_food = not ghost and FoodAI.IsEmergency(inst),
            dark = dark,
            thermal = not ghost and SurvivalAI.NeedsTemperatureHelp(inst),
            needsfood = not ghost and FoodAI.NeedsFoodSupply(inst),
            reserve = ghost or LightAI.HasLightReserve(inst),
            full = not ghost and BaseAI.GetStoragePressure(inst),
            waitlight = not ghost and LightAI.ShouldWaitInLight(inst),
            repair = repair,
            urgent_repair = urgent_repair,
            greeting = CoreAI.IsGreetingPauseActive(inst),
            hurt = GetTime() < (inst._my_friend_hurt_until or 0),
            hurt_evade = hurt_evade,
        }
    end
    self.bt = BT(inst, Utility(inst, entries, Snapshot))
end

return MyFriendBrain
