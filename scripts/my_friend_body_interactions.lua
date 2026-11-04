-- Explicit native scene capabilities, shared by observations and execution.
local M = {}
function M.Supports(target, action)
    if target == nil or not target:IsValid() or target:IsInLimbo()
        or target:HasAnyTag("fire", "burnt") then return false end
    local c = target.components
    return action == "SITON" and c.sittable ~= nil and target:HasTag("cansit")
        or action == "ACTIVATE" and c.activatable ~= nil
        or (action == "TURNON" or action == "TURNOFF") and c.machine ~= nil
end
function M.Describe(inst, target)
    local actions = {}
    for _, action in ipairs({"SITON", "TURNON", "TURNOFF", "ACTIVATE"}) do
        if M.Supports(target, action) then actions[#actions + 1] = action end
    end
    if #actions == 0 then return end
    local c = target.components
    local occupied, on
    if c.sittable ~= nil then occupied = c.sittable:IsOccupied() end
    if c.machine ~= nil then on = c.machine:IsOn() end
    return actions, occupied, on
end
function M.Validate(inst, target, action, player)
    if not M.Supports(target, action) then return false, "unsupported_interaction" end
    if target:GetCurrentPlatform() ~= inst:GetCurrentPlatform() then return false, "different_platform" end
    if action == "SITON" then
        local sitting = require("my_friend_sitting")
        local leader = require("my_friend_policy").GetLeader(inst) or player
        return leader ~= nil and sitting.CanUseSeat(inst, target, leader, 20), "seat_unavailable"
    end
    if action == "ACTIVATE" then
        local allowed = target.components.activatable:CanActivate(inst)
        if allowed == false then return false, "cannot_activate" end
    elseif action == "TURNON" or action == "TURNOFF" then
        local machine = target.components.machine
        if machine.CanInteract ~= nil and not machine:CanInteract() then return false, "machine_disabled" end
        if machine.oncooldown then return false, "machine_cooldown" end
    end
    return true
end
return M
