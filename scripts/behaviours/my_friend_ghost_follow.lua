local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")

local GhostFollow = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendGhostFollow")
    self.inst = inst
end)

function GhostFollow:Visit()
    local inst, now = self.inst, GetTime()
    if self.status == READY then
        Navigation.CancelSteering(inst)
        Navigation.ClearStuck(inst)
        if inst.components.locomotor ~= nil then inst.components.locomotor:Stop() end
        inst._my_friend_steering_cache, inst._my_friend_last_move = nil, nil
        self.goal, self.moving = nil, false
    end
    self.status = RUNNING
    if Policy.IsBusy(inst) then self:Sleep(.25) return end
    local leader = Policy.GetLeader(inst)
    if not inst:HasTag("playerghost") or leader == nil then
        self.status = SUCCESS
        return
    end
    local distance = inst:GetDistanceSqToInst(leader)
    if distance >= 7^2 then self.chasing = true end
    if distance <= 3^2 then self.chasing = false end
    if self.chasing then
        -- Use the same locomotor/stategraph path as ordinary companion
        -- movement. Ghost physics is already configured by SGwilsonghost, so
        -- direct transform stepping only introduced visible network stutter.
        local target = leader:GetPosition()
        if self.goal == nil or now >= (self.refresh or 0)
            or (self.goal - target):LengthSq() > 1 then
            inst.components.locomotor:GoToPoint(target, nil, true)
            self.goal, self.refresh = target, now + .1
        end
        self.moving = true
    elseif self.moving then
        inst.components.locomotor:Stop()
        self.goal, self.moving = nil, false
    end
    self:Sleep(.1)
end

function GhostFollow:OnStop()
    if not Policy.IsBusy(self.inst) then self.inst.components.locomotor:Stop() end
    self.goal, self.moving, self.chasing = nil, nil, nil
end

return GhostFollow
