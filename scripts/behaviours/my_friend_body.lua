local API = require("my_friend_body_api")
local RouteAction = require("behaviours/my_friend_route_action")
local Combat = require("behaviours/my_friend_combat")
local Body = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendBody")
    self.inst = inst
end)
function Body:Release()
    if self.route ~= nil then self.route:Stop(); self.route = nil end
    if self.combat ~= nil then self.combat:Stop(); self.combat = nil end
end
function Body:Visit()
    API.Tick(self.inst)
    local state = API.Valid(self.inst)
    if state == nil then self:Release(); self.status = FAILED; return end
    local job = state.active
    if self.job ~= job then self:Release(); self.job = job end
    self.status = RUNNING
    if job == nil then self:Sleep(.3); return end
    if require("my_friend_policy").IsBusy(self.inst) and (job.skill ~= "engage" or job.cancel_requested) then self:Sleep(.1); return end
    if job.skill == "engage" then
        if job.status == "accepted" then job.status = "running"; API.Emit(self.inst, API.Result(job)) end
        local target = require("my_friend_body_actions").CombatTarget(self.inst, job)
        if target == nil then self:Release(); return end
        self.inst.components.combat:SetTarget(target)
        self.combat = self.combat or Combat(self.inst, function()
            return require("my_friend_body_actions").CombatTarget(self.inst, job)
        end)
        self.combat:Visit()
        if self.combat.status == FAILED then
            API.Finish(self.inst, job, "failed", nil, self.combat.failure_reason or "combat_rejected")
            self:Release()
        end
        self:Sleep(FRAMES or 1 / 30)
        return
    end
    if self.route == nil then
        local action = API.GetAction(self.inst)
        if action == nil then self:Sleep(.3); return end
        self.route = RouteAction(self.inst, function() return API.GetAction(self.inst) end,
            "MyFriendBodyRoute", job.gait ~= "walk", 120, action._my_friend_cast_in_place ~= true and action._my_friend_native_range ~= true)
    end
    self.route:Visit()
    if self.route.status == SUCCESS or self.route.status == FAILED then self.route:Stop(); self.route = nil end
    self:Sleep(.1)
end
function Body:OnStop()
    local state = self.inst._my_friend_body
    if state ~= nil and state.active ~= nil and state.active == self.job then
        local reason = self.job.cancel_reason or "preempted"
        local status = reason == "manual_command" and "interrupted" or self.job.cancel_requested and "cancelled" or "interrupted"
        API.Finish(self.inst, self.job, status, nil, reason)
    end
    self:Release(); self.job = nil
end
return Body
