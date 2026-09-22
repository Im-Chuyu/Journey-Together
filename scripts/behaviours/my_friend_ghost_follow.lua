local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")

local GhostFollow = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendGhostFollow")
    self.inst = inst
end)

local GHOST_SPEED = 6

local function DriftTo(inst, target, dt)
    local x, y, z = inst.Transform:GetWorldPosition()
    local tx, ty, tz = target.Transform:GetWorldPosition()
    local dx, dz = tx - x, tz - z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance <= .001 then return true end
    local step = math.min(distance, GHOST_SPEED * dt)
    local nx, nz = x + dx / distance * step, z + dz / distance * step
    -- Ghosts have no collision body. Move the transform directly instead of
    -- asking the locomotor for a routed path, which makes terrain and walls
    -- incorrectly block a following ghost.
    if inst.Physics ~= nil and inst.Physics.Teleport ~= nil then
        inst.Physics:Teleport(nx, y, nz)
    else
        inst.Transform:SetPosition(nx, y, nz)
    end
    return distance <= step
end

function GhostFollow:Visit()
    local inst, now = self.inst, GetTime()
    if self.status == READY then
        Navigation.CancelSteering(inst)
        Navigation.ClearStuck(inst)
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
        -- Do not use locomotor here. Its route finder still honours land
        -- blockers even though a player ghost has no collision volume.
        inst.components.locomotor:Stop()
        local elapsed = self.last_update ~= nil and math.min(.1, math.max(.02, now - self.last_update)) or .05
        DriftTo(inst, leader, elapsed)
        self.last_update = now
        self.goal, self.refresh, self.moving = leader:GetPosition(), now + .05, true
    elseif self.moving then
        inst.components.locomotor:Stop()
        self.goal, self.moving = nil, false
    end
    self:Sleep(.05)
end

function GhostFollow:OnStop()
    if not Policy.IsBusy(self.inst) then self.inst.components.locomotor:Stop() end
    self.goal, self.moving, self.chasing, self.last_update = nil, nil, nil, nil
end

return GhostFollow
