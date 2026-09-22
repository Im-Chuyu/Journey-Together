local Policy = require("my_friend_policy")
local BaseAI = require("my_friend_base_ai")
local Progress = require("my_friend_progress")

local Utility = Class(BehaviourNode, function(self, inst, entries, snapshot)
    local children = {}
    for _, entry in ipairs(entries) do children[#children + 1] = entry.node end
    BehaviourNode._ctor(self, "MyFriendUtility", children)
    self.inst = inst
    self.entries = entries
    self.snapshot = snapshot
end)

function Utility:GetSleepTime()
    -- BehaviourNode ignores Sleep() on composite nodes. Without this override
    -- BrainManager hibernates us as soon as the last leaf finishes.
    return math.max(0, (self.nextupdatetime or GetTime()) - GetTime())
end

function Utility:GetTreeSleepTime()
    return self:GetSleepTime()
end

function Utility:RepeatWork(previous)
    local entry = self.active
    local node = entry ~= nil and entry.node or nil
    local inst = self.inst
    if previous == nil or node == nil or node.action ~= previous or node.pendingstatus ~= SUCCESS
        or inst._my_friend_replan_requested or Policy.IsFollowGatheringPaused(inst)
        or self.leader ~= Policy.GetLeader(inst) then return end
    -- Refresh survival decisions between swings without forcing an idle cycle.
    -- A stale greeting snapshot must not suppress every subsequent work swing.
    if GetTime() >= (self.work_check_at or 0) then
        self.context = self.snapshot(inst)
        self.work_check_at = GetTime() + 1
    end
    if self.context == nil or self.context.ghost or self.context.threat ~= nil
        or self.context.dark or self.context.thermal
        or (self.context.hunger or 1) < .4 or self.context.hurt or self.context.hurt_evade then return end
    local buffered = inst:GetBufferedAction()
    if buffered ~= nil and buffered ~= previous then return end
    -- A successful BufferedAction has consumed its callbacks. Never adopt a
    -- requeued old swing: the last hit must still run work/loot cleanup.
    if buffered == previous then inst.bufferedaction = nil end
    local action = BaseAI.GetRepeatWorkAction(inst, previous.target, previous.action)
    if action == nil or not action:IsValid() then return end
    action.options.no_predict_fastforward = true
    Progress.Track(inst, action)
    node.action, node.pendingstatus, node.time = action, nil, GetTime()
    node.status = RUNNING
    action:AddSuccessAction(function()
        if node.action == action then node.pendingstatus = SUCCESS end
    end)
    action:AddFailAction(function()
        if node.action == action then node.pendingstatus = FAILED end
    end)
    inst:PushBufferedAction(action)
    self:Sleep(.1)
end

function Utility:WatchAction(retry_only)
    local node = self.active ~= nil and self.active.node or nil
    if node ~= nil and node.routing then self.motion = nil return end
    local action = node ~= nil and node.action or nil
    if action == nil or node.pendingstatus ~= nil then self.motion = nil return end
    local now = GetTime()
    local x, _, z = self.inst.Transform:GetWorldPosition()
    local motion = self.motion
    if motion == nil or motion.action ~= action then
        self.motion = { action = action, x = x, z = z, since = now }
    elseif (x - motion.x)^2 + (z - motion.z)^2 >= .25 then
        motion.x, motion.z, motion.since = x, z, now
    elseif now - motion.since > 3 and node.RetryLocalApproach ~= nil
        and node:RetryLocalApproach() then
        self.motion = nil
    elseif now - motion.since > 6 and not retry_only then
        if node.FailRoute ~= nil then
            node:FailRoute(false)
        else
            action._my_friend_path_failed = true
            action:Fail()
            node.pendingstatus = FAILED
        end
        self.motion = nil
    end
end

function Utility:ReleaseNode(node, passive)
    local action = node.action
    if action ~= nil and node.pendingstatus == nil then
        action._my_friend_cancelled = not action._my_friend_path_failed
            and node.status ~= FAILED
        action:Fail()
    end
    if not passive then
        if node.pendingstatus ~= SUCCESS and self.inst.ClearBufferedAction ~= nil then
            self.inst:ClearBufferedAction()
        end
        node:Stop()
    else
        node:Stop()
    end
    node:Reset()
    node.action = nil
    node.pendingstatus = nil
end

function Utility:CancelActive()
    if self.active == nil then return end
    self:ReleaseNode(self.active.node, self.active.passive)
    self.motion, self.work_check_at = nil, nil
    if self.active.id == "assist" then
        self.inst._my_friend_next_assist = GetTime() + 1
        self.inst._my_friend_assist_target = nil
        self.inst._my_friend_assist_started = nil
    end
    self.active = nil
end

function Utility:Visit()
    require("my_friend_behavior_ai").ObservePlayerAttack(self.inst)
    Progress.Check(self)
    -- Eating/working owns the stategraph: do not scan food, equipment and the
    -- world every animation tick only to discard the snapshot immediately.
    if Policy.IsBusy(self.inst) then
        self.motion = nil
        self.status = RUNNING
        self:Sleep(.1)
        return
    end
    if self.inst._my_friend_replan_requested then
        self.inst._my_friend_replan_requested = nil
        self:CancelActive()
        self.inst.components.locomotor:Clear()
        self.inst.components.locomotor:Stop()
    end
    local active = self.active ~= nil and self.active.node or nil
    if active ~= nil and (active.pendingstatus ~= nil
        or active.status == FAILED or active.status == SUCCESS) then
        self:CancelActive()
    end
    local context = self.snapshot(self.inst)
    self.context = context
    self:WatchAction(context.leader == nil)
    local ranked = {}
    for index, entry in ipairs(self.entries) do
        local score = entry.score(context)
        if score ~= nil and score > 0 then
            ranked[#ranked + 1] = { entry = entry, score = score, index = index }
        end
    end
    table.sort(ranked, function(a, b)
        return a.score == b.score and a.index < b.index or a.score > b.score
    end)

    if self.active ~= nil then
        local score = self.active.score(context) or 0
        local mode_changed = self.leader ~= context.leader
        local urgent = false
        local prepared
        if not Policy.IsBusy(self.inst) then
            for _, candidate in ipairs(ranked) do
                if candidate.entry == self.active then break end
                if candidate.score > score and (self.active.passive
                    or candidate.score >= 80 and candidate.score > score + 10) then
                    local node = candidate.entry.node
                    if node.getactionfn ~= nil then
                        local action = node.getactionfn(self.inst)
                        if action ~= nil then
                            local getter = node.getactionfn
                            node.getactionfn = function(actor)
                                node.getactionfn = getter
                                return action
                            end
                            urgent = true
                            prepared = candidate
                            break
                        end
                        candidate.unavailable = true
                    else
                        urgent = true
                        break
                    end
                end
            end
        end
        -- Let SGwilson finish its damage/eat/build frame before changing owners.
        if not Policy.IsBusy(self.inst) and (mode_changed or score <= 0 or urgent) then
            self:CancelActive()
            if prepared ~= nil then
                local entry = prepared.entry
                entry.node:Reset()
                entry.node:Visit()
                if entry.node.status == RUNNING or entry.node.status == SUCCESS then
                    self.active = entry
                    self.leader = context.leader
                    self.inst._my_friend_decision = { task = entry.id, score = prepared.score,
                        mode = context.leader ~= nil and "follow" or "free" }
                    self.status = RUNNING
                    self:Sleep(.25)
                    return
                end
                self:ReleaseNode(entry.node, entry.passive)
                prepared.unavailable = true
            end
        else
            self.active.node:Visit()
            if self.active.node.status == RUNNING then
                self.status = RUNNING
                self:Sleep(.25)
                return
            end
            if Policy.IsBusy(self.inst) then
                self.status = RUNNING
                self:Sleep(.1)
                return
            end
            self:CancelActive()
        end
    end
    self.leader = context.leader
    for _, candidate in ipairs(ranked) do
        local entry = candidate.entry
        if not candidate.unavailable then
            entry.node:Reset()
            entry.node:Visit()
        end
        if not candidate.unavailable
            and (entry.node.status == RUNNING or entry.node.status == SUCCESS) then
            self.active = entry
            if entry.id ~= nil then require("my_friend_dialogue").OnDecision(self.inst, entry.id) end
            self.inst._my_friend_decision = { task = entry.id, score = candidate.score,
                mode = context.leader ~= nil and "follow" or "free" }
            self.status = RUNNING
            self:Sleep(.25)
            return
        end
        if not candidate.unavailable then
            -- A node can fail on its first Visit (invalid action or route).
            -- It never becomes active, so CancelActive cannot release its locks.
            self:ReleaseNode(entry.node, entry.passive)
        end
    end
    self.status = RUNNING
    self:Sleep(.25)
end

function Utility:Step()
    -- DoAction reports success at the hit frame. Keep that result until Visit
    -- consumes it after SGwilson finishes; the default Step resets it too early.
    if self.active ~= nil and self.active.node.status == RUNNING then
        self.active.node:Step()
    end
end

function Utility:OnStop()
    self:CancelActive()
    self.progress = nil
end

return Utility
