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
    local assisting = target == inst._my_friend_assist_target
    local pending_player_attack = inst._my_friend_assist_scan ~= nil
        and inst._my_friend_assist_scan.target == target
    local self_defending = BehaviourAI.IsThreat(inst, target)
        or BehaviourAI.IsPriorityEngaged(inst, target)
    local engaged = assisting or self_defending
    return require("my_friend_combat_rules").CanAttack(target)
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

function MyFriendCombat:Visit()
    local combat = self.inst.components.combat
    if not self.inst:IsValid() or combat == nil or self.inst.components.locomotor == nil then
        self.status = FAILED
        return
    end

    if not IsValidThreat(self.inst, self.target) then
        self.target = BehaviourAI.FindThreat(self.inst) or self.inst._my_friend_assist_target
        self.dodge_started_at = nil
        self.commit_attack_until = nil
    end
    if not IsValidThreat(self.inst, self.target)
        or not BehaviourAI.CanContinueCombat(self.inst, self.target) then
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

    -- abouttoattack is removed at the damage frame, before attack recovery ends.
    -- Protect that hit, then let the native locomote event leave the recovery.
    if self.inst.sg ~= nil and self.inst.sg:HasStateTag("abouttoattack") then
        self:Sleep(1 / 30)
        return
    end

    local dodge_point, dodging, known_attack, hold_attack = Dodge.GetDecision(self.inst, self.target)
    if dodging then
        BaseAI.SetTask(self.inst, "正在躲避攻击")
        if dodge_point ~= nil then
            local now, previous = GetTime(), self.dodge_point
            if previous == nil or now >= (self.dodge_move_after or 0)
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
    -- A protected swing has finished, but its attack tag may remain. Wait for
    -- the native cooldown unless a dodge above needs to leave the recovery.
    if self.inst.sg ~= nil and self.inst.sg:HasStateTag("attack") then
        self:Sleep(1 / 30)
        return
    end

    local distance_sq = DistanceSq(self.inst, self.target)
    local now = GetTime()
    if self.commit_attack_until ~= nil
        and (combat:InCooldown() or now >= self.commit_attack_until) then
        self.commit_attack_until = nil
    end
    local should_dodge = not known_attack and self.commit_attack_until == nil
        and BehaviourAI.ShouldDodge(self.inst, self.target)
    if should_dodge then
        self.dodge_started_at = self.dodge_started_at or now
        local enemycombat = self.target.components ~= nil
            and self.target.components.combat or nil
        if BehaviourAI.ShouldCommitCounterAttack(combat:InCooldown(),
            now - self.dodge_started_at,
            enemycombat ~= nil and enemycombat.min_attack_period or nil) then
            self.dodge_started_at = nil
            self.commit_attack_until = now + 1.5
        else
            BaseAI.SetTask(self.inst, "正在躲避攻击")
            local safe_distance = BehaviourAI.GetCombatDodgeDistance(self.inst, self.target)
            if distance_sq < safe_distance * safe_distance then
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

    local target_position = self.target:GetPosition()
    local special, waiting = require("my_friend_wathgrithr").GetCombatAction(self.inst, self.target)
    if special ~= nil then
        local target = self.target
        local previous = special.validfn
        special.validfn = function(act)
            return self.target == target and IsValidThreat(self.inst, target)
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
