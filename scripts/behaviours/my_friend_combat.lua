local BehaviourAI = require("my_friend_behavior_ai")
local BaseAI = require("my_friend_base_ai")
local Policy = require("my_friend_policy")

local MyFriendCombat = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendCombat")
    self.inst = inst
    self.target = nil
    self.dodge_started_at = nil
    self.commit_attack_until = nil
end)

local function DistanceSq(a, b)
    local ax, _, az = a.Transform:GetWorldPosition()
    local bx, _, bz = b.Transform:GetWorldPosition()
    local dx, dz = bx - ax, bz - az
    return dx * dx + dz * dz
end

local function IsBusy(inst)
    return inst.sg ~= nil and inst.sg:HasStateTag("busy")
end

local function IsValidThreat(inst, target)
    local player_attack_target = BehaviourAI.GetLeaderAttackCount(inst, target) > 0
    local assisting = target == inst._my_friend_assist_target
    return target ~= nil and target:IsValid()
        and (BehaviourAI.IsThreat(inst, target) or player_attack_target
            or target == inst._my_friend_assist_target)
        and Policy.InRange(inst, target, assisting and 32 or 7)
        and DistanceSq(inst, target) <= (assisting and 32 or BehaviourAI.THREAT_RANGE)^2
end

local function IsBoss(target)
    return target ~= nil and target.HasAnyTag ~= nil
        and target:HasAnyTag("epic", "largecreature", "boss")
end

local function Stop(inst)
    if inst.components.locomotor ~= nil then inst.components.locomotor:Stop() end
end

function MyFriendCombat:Visit()
    local combat = self.inst.components.combat
    if combat == nil then
        self.status = FAILED
        return
    end

    if not IsValidThreat(self.inst, self.target) then
        self.target = BehaviourAI.FindThreat(self.inst) or self.inst._my_friend_assist_target
        self.dodge_started_at = nil
        self.commit_attack_until = nil
    end
    if not IsValidThreat(self.inst, self.target)
        or not BehaviourAI.CanCounterAttack(self.inst, self.target) then
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
    if combat.target ~= self.target then
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
    if not Policy.InRange(self.inst, self.inst, 7) then
        local leader = Policy.GetLeader(self.inst)
        combat:SetTarget(nil)
        self.inst.components.locomotor:GoToPoint(leader:GetPosition(), nil, true)
        self:Sleep(.1)
        return
    end

    -- Moving during SGwilson's attack state can cancel the action before its
    -- damage frame. Dodge only after the current swing has completed.
    if self.inst.sg ~= nil and self.inst.sg:HasAnyStateTag("attack", "abouttoattack") then
        Stop(self.inst)
        self:Sleep(.05)
        return
    end

    local distance_sq = DistanceSq(self.inst, self.target)
    local now = GetTime()
    if self.commit_attack_until ~= nil
        and (combat:InCooldown() or now >= self.commit_attack_until) then
        self.commit_attack_until = nil
    end
    local should_dodge = self.commit_attack_until == nil
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
        local action = BufferedAction(self.inst, self.target, ACTIONS.ATTACK)
        action.validfn = function()
            return IsValidThreat(self.inst, self.target)
        end
        self.inst.components.locomotor:PushAction(action, true)
    end
    self:Sleep(.08)
end

function MyFriendCombat:OnStop()
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
