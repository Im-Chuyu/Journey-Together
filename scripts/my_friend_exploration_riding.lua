local Policy = require("my_friend_policy")
local Riding = require("my_friend_riding")
local Navigation = require("my_friend_navigation")
local Safety = require("my_friend_recovery_safety")
local M = {}
local RETRY = 30

local function Command(inst)
    local command = inst._my_friend_command
    return Policy.IsRoaming(inst) and command.id == "explore" and command or nil
end

local function IsRiding(inst)
    return inst.components.rider ~= nil and inst.components.rider:IsRiding()
end

local function Health(mount)
    local health = mount ~= nil and mount.components.health or nil
    return health ~= nil and health:GetPercent() or 1
end

function M.Configure(inst)
    if inst._my_friend_explore_riding_configured then return end
    inst._my_friend_explore_riding_configured = true
    inst:ListenForEvent("dismounted", function()
        local command = Command(inst)
        if command == nil then return end
        -- Natural bucking and interrupted dismounts also need a settling period.
        command.ride_after = GetTime() + RETRY
        inst._my_friend_riding = nil
        inst._my_friend_mount_started, inst._my_friend_mount_keep_riding = nil, nil
    end)
end

function M.TransitionSucceeded(inst, action)
    if action._my_friend_explore_ride == "mount" then return IsRiding(inst) end
    return action._my_friend_explore_ride == "dismount" and (not IsRiding(inst)
        or inst.sg ~= nil and inst.sg:HasStateTag("dismounting"))
end

local function TrackTransition(inst, command, action, kind)
    action._my_friend_roaming = command
    action._my_friend_explore_ride = kind
    action._my_friend_dialogue_kind = kind == "mount" and "explore_mount" or "explore_dismount"
    local function Finished()
        if M.TransitionSucceeded(inst, action) then
            if kind == "mount" then
                if command.resting_mount == action.target then command.resting_mount = nil end
                inst._my_friend_riding = true
                inst._my_friend_mount_started = GetTime()
                inst._my_friend_mount_keep_riding = nil
            else
                command.ride_after = GetTime() + RETRY
            end
        elseif not action._my_friend_cancelled then
            command.ride_after = GetTime() + RETRY
        end
    end
    action:AddSuccessAction(Finished)
    action:AddFailAction(Finished)
    return action
end

local function DismountAction(inst, command)
    local origin, caps = inst:GetPosition(), Navigation.Caps(inst)
    local function Clear(point)
        return Safety.IsSafe(inst, point)
            and Navigation.IsWalkClear(inst, point, point, caps)
    end
    -- Wilson dismounts at the rider's current position. Move off obstructed
    -- shorelines first; never teleport the rider or manually detach the cow.
    if not Clear(origin) then
        for radius = 2, 6, 2 do
            for index = 0, 7 do
                local angle = index * math.pi / 4
                local point = origin + Vector3(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                if Clear(point) and Navigation.IsWalkClear(inst, origin, point, caps) then
                    local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point)
                    action.arrivedist = .3
                    action._my_friend_roaming = command
                    action._my_friend_dialogue_kind = "explore_dismount"
                    return action
                end
            end
        end
        return
    end
    local action = Riding.GetDismountAction(inst)
    if action == nil then return end
    action.validfn = function()
        return Command(inst) == command and IsRiding(inst) and Clear(inst:GetPosition())
    end
    return TrackTransition(inst, command, action, "dismount")
end

function M.GetTravelAction(inst)
    local command = Command(inst)
    if command == nil or Policy.IsBusy(inst) or inst.components.rider == nil then return end
    M.Configure(inst)
    local now = GetTime()
    if IsRiding(inst) then
        local mount = inst.components.rider:GetMount()
        if Health(mount) < .2 then command.resting_mount = mount end
        if inst._my_friend_mount_stop_requested or command.resting_mount == mount
            or now < (command.ride_walk_until or 0) then return DismountAction(inst, command) end
        return
    end
    if inst._my_friend_mount_disabled and inst._my_friend_mount_disabled_until == nil
        or now < (inst._my_friend_mount_disabled_until or 0)
        or now < (inst._my_friend_mount_retry_after or 0)
        or now < (command.ride_after or 0) or now < (command.ride_walk_until or 0)
        or inst._my_friend_under_threat or now < (inst._my_friend_hurt_until or 0)
        or now < (inst._my_friend_hurt_evade_until or 0)
        or inst.components.hunger:GetPercent() < .4
        or require("my_friend_light_ai").IsDark(inst)
        or require("my_friend_survival_ai").NeedsTemperatureHelp(inst) then return end
    local mount = Riding.GetBeefalo(inst, function(beefalo)
        return beefalo:GetCurrentPlatform() == inst:GetCurrentPlatform()
            and inst:GetDistanceSqToInst(beefalo) <= 32^2
            and Health(beefalo) >= (command.resting_mount == beefalo and .35 or .2)
            and Safety.IsSafe(inst, beefalo:GetPosition())
    end)
    if mount == nil then return end
    local action = Riding.GetMountAction(inst, mount)
    if action == nil then return end
    action.validfn = function()
        return Command(inst) == command and not inst._my_friend_under_threat
            and Riding.GetBeefalo(inst, function(beefalo) return beefalo == mount end) == mount
            and mount:GetCurrentPlatform() == inst:GetCurrentPlatform()
            and Safety.IsSafe(inst, mount:GetPosition())
    end
    return TrackTransition(inst, command, action, "mount")
end

function M.PrepareAction(inst, action)
    local command = Command(inst)
    if command == nil or not IsRiding(inst)
        or action.action.mount_valid and not action._my_friend_requires_dismount
        or action._my_friend_explore_ride ~= nil then return action end
    M.Configure(inst)
    -- Release any container/work reservation made by the getter. Once on foot,
    -- the same survival node selects a fresh, still-valid action before travel.
    action._my_friend_cancelled = true
    action:Fail()
    return DismountAction(inst, command)
end

function M.OnTravelFailed(inst)
    local command = Command(inst)
    if command ~= nil and IsRiding(inst) then
        command.ride_walk_until = GetTime() + RETRY
    end
end

return M
