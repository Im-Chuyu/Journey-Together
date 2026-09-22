local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")

local GhostFollow = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendGhostFollow")
    self.inst = inst
end)

local GHOST_SPEED = 6

local function DriftTo(inst, target, dt)
    local x, y, z = inst.Transform:GetWorldPosition()
    local tx, _, tz = target.Transform:GetWorldPosition()
    local dx, dz = tx - x, tz - z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance <= .001 then return end
    local step = math.min(distance, GHOST_SPEED * dt)
    local nx, nz = x + dx / distance * step, z + dz / distance * step
    if inst.Physics ~= nil and inst.Physics.Teleport ~= nil then
        inst.Physics:Teleport(nx, y, nz)
    else
        inst.Transform:SetPosition(nx, y, nz)
    end
end

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
        -- Ghosts have no collision body, so move directly to the player's
        -- current position instead of routing around terrain or buildings.
        DriftTo(inst, leader, self.last_update ~= nil
            and math.min(.1, math.max(.02, now - self.last_update)) or .05)
        self.last_update = now
        self.goal, self.refresh = leader:GetPosition(), now + .03
        self.moving = true
    elseif self.moving then
        inst.components.locomotor:Stop()
        self.goal, self.moving = nil, false
    end
    self:Sleep(.03)
end

function GhostFollow:OnStop()
    if not Policy.IsBusy(self.inst) then self.inst.components.locomotor:Stop() end
    self.goal, self.moving, self.chasing, self.last_update = nil, nil, nil, nil
end

return GhostFollow
