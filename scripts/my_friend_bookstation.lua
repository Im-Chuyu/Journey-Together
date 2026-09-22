local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")
local Dialogue = require("my_friend_dialogue")

local M = {}
local CLEARANCE = 1.8

local function DistanceSq(entity, point)
    local x, _, z = entity.Transform:GetWorldPosition()
    return (x - point.x)^2 + (z - point.z)^2
end

function M.PrepareCommand(command)
    local x, _, z = command.player.Transform:GetWorldPosition()
    local tx, tz = TheWorld.Map:GetTileCoordsAtPoint(x, 0, z)
    local cx, cy, cz = TheWorld.Map:GetTileCenterPoint(tx, tz)
    if cx ~= nil then command.build_point = Vector3(cx, cy, cz) end
end

local function Blocks(player, point)
    return player:IsValid() and not player:HasTag("playerghost")
        and DistanceSq(player, point) < (CLEARANCE + player:GetPhysicsRadius(0))^2
end

function M.IsClear(command)
    if command.build_point == nil then return false end
    for _, player in ipairs(AllPlayers) do
        if Blocks(player, command.build_point) then return false end
    end
    return true
end

local function SafeStep(player, centre)
    if player:GetCurrentPlatform() ~= nil then return end
    local origin, caps = player:GetPosition(), Navigation.Caps(player)
    local angle = math.atan2(origin.z - centre.z, origin.x - centre.x)
    for index = 0, 15 do
        local a = angle + index * math.pi / 8
        local radius = CLEARANCE + player:GetPhysicsRadius(0) + .8
        local point = Vector3(centre.x + math.cos(a) * radius, 0, centre.z + math.sin(a) * radius)
        if Navigation.IsStepClear(player, origin, point, caps)
            and TheWorld.Map:IsDeployPointClear(point, player, player:GetPhysicsRadius(.5) + .2) then
            return point
        end
    end
end

function M.MakeRoom(act)
    local inst, player = act.doer, act.target
    local command = inst._my_friend_command
    if command == nil or command.recipe ~= "bookstation" or command.player ~= player
        or command.build_point == nil or not Policy.IsLocalPlayer(player)
        or Policy.GetLeader(inst) ~= player or inst:GetDistanceSqToInst(player) > 3^2 then return false end
    if not Blocks(player, command.build_point) then return true end
    if player.components.locomotor == nil or player.sg == nil or player.sg:HasStateTag("busy")
        or player:HasTag("playerghost") or player.components.health:IsDead()
        or player.components.rider ~= nil and player.components.rider:IsRiding() then return false end
    local point = SafeStep(player, command.build_point)
    if point == nil then return false end
    -- A normal WALKTO yields to player input and avoids knockback damage,
    -- forced equipment drops, and teleporting through nearby walls.
    player:ClearBufferedAction()
    player.components.locomotor:PushAction(BufferedAction(player, nil, ACTIONS.WALKTO, nil, point), false)
    command.room_until = GetTime() + 4
    return true
end

function M.GetPrepareAction(inst, command, recipe)
    local point = command.build_point
    if point == nil or not Navigation.IsLand(point) then
        return nil, "bookstation_blocked"
    end
    -- Resolve the leader's occupancy before asking the vanilla deploy test.
    -- Some game builds include players in the spacing query; that is exactly
    -- the case this command is meant to clear first.
    local player = command.player
    if Blocks(player, point) then
        if command.room_until ~= nil then
            if GetTime() < command.room_until then return nil, "waiting" end
            return nil, "bookstation_blocked"
        end
        local action = BufferedAction(inst, player, ACTIONS.MY_FRIEND_MAKE_ROOM)
        action.arrivedist = 2
        action.validfn = function() return inst._my_friend_command == command and player:IsValid() end
        action:AddFailAction(function()
            if not action._my_friend_cancelled and inst._my_friend_command == command then
                Dialogue.Reply(inst, "bookstation_blocked")
                require("my_friend_commands").Clear(inst)
            end
        end)
        Dialogue.Reply(inst, "bookstation_make_room")
        return Policy.GuardAction(inst, action)
    end
    if not TheWorld.Map:CanDeployRecipeAtPoint(point, recipe, 0, inst) then
        return nil, "bookstation_blocked"
    end
    if M.IsClear(command) then return end
    return nil, "bookstation_blocked"
end

return M
