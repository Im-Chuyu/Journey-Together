local BehaviourAI = require("my_friend_behavior_ai")
local BaseAI = require("my_friend_base_ai")
local Policy = require("my_friend_policy")
local Dodge = require("my_friend_dodge")

local MyFriendCombat = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendCombat")
    self.inst = inst
    self.target = nil
    self.dodge_started_at = nil
    self.commit_attack_until = nil
end)

local DistanceSq = Policy.DistanceSq

local function IsBusy(inst)
    return inst.sg ~= nil and inst.sg:HasStateTag("busy")
end

local function IsValidThreat(inst, target)
    if inst == nil or not inst:IsValid() or inst:HasTag("playerghost")
        or inst.components.health == nil or inst.components.health:IsDead()
        or target == nil or not target:IsValid() or target.Transform == nil
        or target:IsInLimbo() or target:HasTag("playerghost")
        or target.components == nil or target.components.health == nil
        or target.components.health:IsDead() or target.components.combat == nil then return false end
    local player_attack_target = BehaviourAI.GetLeaderAttackCount(inst, target) > 0
    local leader = Policy.GetLeader(inst)
    local scan = inst._my_friend_assist_scan
    local action = leader ~= nil and leader.GetBufferedAction ~= nil and leader:GetBufferedAction() or nil
    local pending_player_attack = leader ~= nil and not leader:HasTag("playerghost")
        and scan ~= nil and scan.leader == leader and GetTime() < scan.untiltime
        and scan.target == target and action ~= nil
        and action.action == ACTIONS.ATTACK and action.target == target
    local assisting = target == inst._my_friend_assist_target
        and (player_attack_target or pending_player_attack)
    local self_defending = BehaviourAI.IsThreat(inst, target)
        or BehaviourAI.IsPriorityEngaged(inst, target)
    local engaged = assisting or self_defending
    return require("my_friend_combat_rules").CanAttack(target, inst)
        and (self_defending or player_attack_target
            or pending_player_attack)
        and (engaged or Policy.InRange(inst, target, 7))
        and (not engaged or DistanceSq(inst, target) <= BehaviourAI.ASSIST_RANGE
            * BehaviourAI.ASSIST_RANGE)
        and DistanceSq(inst, target) <= (engaged and BehaviourAI.ASSIST_RANGE
            or BehaviourAI.THREAT_RANGE)^2
end

local function IsBoss(target)
    return target ~= nil and target.HasAnyTag ~= nil
        and target:HasAnyTag("epic", "largecreature", "boss")
end

local function Stop(inst)
    if inst:IsValid() and inst.components.locomotor ~= nil then inst.components.locomotor:Stop() end
end

local function InterruptAttackForDodge(inst)
    local sg = inst.sg
    if sg == nil or not sg:HasAnyStateTag("attack", "abouttoattack") then return false end
    local action = inst:GetBufferedAction()
    if action ~= nil and action.action == ACTIONS.ATTACK then inst:ClearBufferedAction() end
    -- Movement's native locomote handler leaves an interruptible attack. Never
    -- force idle or remove busy tags from eating, casting or revival states.
    return true
end

function MyFriendCombat:Visit()
    local combat = self.inst.components.combat
    if not self.inst:IsValid() or combat == nil or self.inst.components.locomotor == nil then
        self.status = FAILED
        return
    end

    -- This also runs on the combat fast path, before a cached snapshot can
    -- submit another attack after contact or re-entry into a remembered area.
    if BehaviourAI.IsHazardRetreatActive(self.inst) then
        if Policy.IsBusy(self.inst) then self:Sleep(.1) return end
        InterruptAttackForDodge(self.inst)
        self.inst._my_friend_replan_requested = true
        self.status = RUNNING
        Stop(self.inst)
        self:Sleep(.1)
        return
    end

    if not IsValidThreat(self.inst, self.target) then
        self.target = BehaviourAI.FindThreat(self.inst) or self.inst._my_friend_assist_target
        self.dodge_started_at = nil
        self.commit_attack_until = nil
    end
    if not IsValidThreat(self.inst, self.target)
        or not BehaviourAI.CanContinueCombat(self.inst, self.target) then
        if self.target ~= nil and BehaviourAI.ShouldRetreatUnequipped(self.inst, self.target) then
            BehaviourAI.RememberUnequippedRetreat(self.inst, self.target)
            InterruptAttackForDodge(self.inst)
            self.inst._my_friend_replan_requested = true
            if combat.target == self.target then combat:SetTarget(nil) end
            if self.inst._my_friend_assist_target == self.target then self.inst._my_friend_assist_target = nil end
        end
        self.target = nil
        self.status = FAILED
        Stop(self.inst)
        return
    end

    if self.announced_target ~= self.target then
        self.announced_target = self.target
        require("my_friend_dialogue").Say(self.inst,
            IsBoss(self.target) and "fight_boss" or "fight")
    end

    self.inst._my_friend_under_threat = true
    BaseAI.SetTask(self.inst, "正在战斗")
    if combat.target ~= self.target then combat:SetTarget(self.target) end
    -- SetTarget refuses silently for anything the combat component will not
    -- aggro -- another player with PvP off is the usual one, and a frog that
    -- went into limbo between the threat scan and here is another -- leaving
    -- combat.target nil. CalcAttackRangeSq() then indexes that nil and takes
    -- the server down. Nothing below can work on a target combat rejected, so
    -- hand the tick back instead.
    if combat.target ~= self.target or not IsValidThreat(self.inst, self.target) then
        self.target = nil
        self.status = FAILED
        Stop(self.inst)
        return
    end
    self.status = RUNNING

    if IsBusy(self.inst) then
        self:Sleep(.1)
        return
    end
    local assisting = self.target == self.inst._my_friend_assist_target
    local self_defending = BehaviourAI.IsThreat(self.inst, self.target)
        or BehaviourAI.IsPriorityEngaged(self.inst, self.target)
    if not assisting and not self_defending
        and not Policy.InRange(self.inst, self.inst, 7) then
        local leader = Policy.GetLeader(self.inst)
        combat:SetTarget(nil)
        if leader ~= nil then
            self.inst.components.locomotor:GoToPoint(leader:GetPosition(), nil, true)
        else
            Stop(self.inst)
        end
        self:Sleep(.1)
        return
    end

    local dodge_point, dodging, known_attack, hold_attack = Dodge.GetDecision(self.inst, self.target)
    if dodging then
        BaseAI.SetTask(self.inst, "正在躲避攻击")
        if dodge_point ~= nil
            and BehaviourAI.IsHazardousPath(self.inst, self.inst:GetPosition(), dodge_point) then
            dodge_point = nil
        end
        if dodge_point ~= nil then
            local interrupting = InterruptAttackForDodge(self.inst)
            local now, previous = GetTime(), self.dodge_point
            if interrupting or previous == nil or now >= (self.dodge_move_after or 0)
                and (self.inst.components.locomotor.dest == nil
                    or (previous.x - dodge_point.x)^2 + (previous.z - dodge_point.z)^2 >= .5^2
                    or (previous.x - self.inst:GetPosition().x)^2
                        + (previous.z - self.inst:GetPosition().z)^2 <= .3^2) then
                self.inst.components.locomotor:GoToPoint(dodge_point, nil, true)
                self.dodge_point, self.dodge_move_after = dodge_point, now + .15
            end
        else
            Stop(self.inst)
            self.dodge_point, self.dodge_move_after = nil, nil
        end
        self.dodge_started_at, self.commit_attack_until = nil, nil
        self:Sleep(1 / 30)
        return
    end
    self.dodge_point, self.dodge_move_after = nil, nil
    if hold_attack then
        BaseAI.SetTask(self.inst, "正在等待躲避时机")
        Stop(self.inst)
        self:Sleep(1 / 30)
        return
    end
    local distance_sq = DistanceSq(self.inst, self.target)
    local now = GetTime()
    if self.commit_attack_until ~= nil
        and (combat:InCooldown() or now >= self.commit_attack_until) then
        self.commit_attack_until = nil
    end
    local enemy_attacking = self.target.sg ~= nil
        and self.target.sg:HasAnyStateTag("attack", "abouttoattack")
    local own_attacking = self.inst.sg ~= nil
        and self.inst.sg:HasAnyStateTag("attack", "abouttoattack")
    local should_dodge = not known_attack and (self.commit_attack_until == nil or enemy_attacking)
        and (not own_attacking or enemy_attacking)
        and BehaviourAI.ShouldDodge(self.inst, self.target)
    if should_dodge then
        self.dodge_started_at = self.dodge_started_at or now
        local enemycombat = self.target.components ~= nil
            and self.target.components.combat or nil
        if not enemy_attacking and BehaviourAI.ShouldCommitCounterAttack(combat:InCooldown(),
            now - self.dodge_started_at,
            enemycombat ~= nil and enemycombat.min_attack_period or nil) then
            self.dodge_started_at = nil
            self.commit_attack_until = now + 1.5
        else
            BaseAI.SetTask(self.inst, "正在躲避攻击")
            local safe_distance = BehaviourAI.GetCombatDodgeDistance(self.inst, self.target)
            if distance_sq < safe_distance * safe_distance then
                InterruptAttackForDodge(self.inst)
                local leader = Policy.GetLeader(self.inst)
                if leader ~= nil and Policy.DistanceSq(self.inst, leader) >= 36 then
                    self.inst.components.locomotor:GoToPoint(leader:GetPosition(), nil, true)
                    self:Sleep(.08)
                    return
                end
                local angle = self.inst:GetAngleToPoint(self.target:GetPosition()) + 180
                if angle >= 360 then angle = angle - 360 end
                self.inst.components.locomotor:RunInDirection(angle)
            else
                Stop(self.inst)
            end
            self:Sleep(.08)
            return
        end
    elseif self.commit_attack_until == nil then
        self.dodge_started_at = nil
    end

    -- Ordinary attacks remain stable only when no dangerous dodge above needs
    -- to interrupt them. This applies to both frame profiles and unknown foes.
    if own_attacking then
        self:Sleep(1 / 30)
        return
    end

    local target_position = self.target:GetPosition()
    local unsafe_approach = BehaviourAI.IsHazardousPath(self.inst, self.inst:GetPosition(), target_position)
    local special, waiting
    if not unsafe_approach then
        special, waiting = require("my_friend_wathgrithr").GetCombatAction(self.inst, self.target)
    end
    if special ~= nil then
        local target = self.target
        local previous = special.validfn
        special.validfn = function(act)
            return self.target == target and IsValidThreat(self.inst, target)
                and not BehaviourAI.IsHazardousPath(self.inst, self.inst:GetPosition(), target:GetPosition())
                and (previous == nil or previous(act))
        end
        self.inst.components.locomotor:PushAction(special, true)
        self:Sleep(.1)
        return
    elseif waiting then
        Stop(self.inst)
        self:Sleep(.1)
        return
    end
    -- Pass the target explicitly. The no-argument form falls back to
    -- combat.target, which is not necessarily the one this node is working on.
    if distance_sq > combat:CalcAttackRangeSq(self.target) then
        if unsafe_approach then
            BaseAI.SetTask(self.inst, "正在避开受伤的位置")
            Stop(self.inst)
            self:Sleep(.1)
            return
        end
        BaseAI.SetTask(self.inst, "正在接近敌人")
        self.inst.components.locomotor:GoToPoint(target_position, nil, true)
    else
        BaseAI.SetTask(self.inst, "正在反击")
        if self.inst.sg == nil or self.inst.sg:HasStateTag("canrotate") then
            self.inst:FacePoint(target_position)
        end
        local target = self.target
        local action = BufferedAction(self.inst, target, ACTIONS.ATTACK)
        action.validfn = function()
            -- Validate the target this action was created for. self.target may
            -- already refer to a different enemy when the SG runs the action.
            return self.target == target and combat.target == target
                and IsValidThreat(self.inst, target)
                and not BehaviourAI.IsHazardRetreatActive(self.inst)
                and (DistanceSq(self.inst, target) <= combat:CalcAttackRangeSq(target)
                    or not BehaviourAI.IsHazardousPath(self.inst, self.inst:GetPosition(), target:GetPosition()))
        end
        self.inst.components.locomotor:PushAction(action, true)
    end
    self:Sleep(.08)
end

function MyFriendCombat:OnStop()
    Dodge.Reset(self.inst)
    self.inst._my_friend_combat_check = nil
    self.dodge_point, self.dodge_move_after = nil, nil
    if not self.inst:IsValid() then
        self.target, self.announced_target = nil, nil
        self.dodge_started_at, self.commit_attack_until = nil, nil
        return
    end
    Stop(self.inst)
    if self.target == nil or not IsValidThreat(self.inst, self.target) then
        if self.inst.components.combat ~= nil then self.inst.components.combat:SetTarget(nil) end
    end
    self.target = nil
    self.dodge_started_at = nil
    self.commit_attack_until = nil
    self.announced_target = nil
end

return MyFriendCombat
