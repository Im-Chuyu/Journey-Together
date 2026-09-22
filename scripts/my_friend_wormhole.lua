local Policy = require("my_friend_policy")
local M = {}

M.RANGE = 20
M.TIMEOUT = 30

local function Request(inst)
    local request = inst._my_friend_wormhole
    if request == nil then return end
    local entrance = request.entrance
    if Policy.GetLeader(inst) ~= request.leader or not Policy.IsLocalPlayer(request.leader)
        or request.leader:HasTag("playerghost") or inst:HasTag("playerghost")
        or GetTime() >= request.expires or not entrance:IsValid()
        or request.exit == nil or not request.exit:IsValid()
        or entrance.components.teleporter == nil or not entrance.components.teleporter:IsActive()
        or entrance.components.teleporter.targetTeleporter ~= request.exit
        or inst:GetDistanceSqToInst(entrance) > (M.RANGE + 4)^2 then
        inst._my_friend_wormhole = nil
        return
    end
    return request
end

function M.Score(inst)
    return Request(inst) ~= nil and 128 or 0
end

function M.InTravelRange(inst, action, point)
    local request = Request(inst)
    if request == nil or action._my_friend_wormhole ~= request or point == nil then return false end
    -- Navigation cells are plain x/z tables, not Vector3 objects with Get().
    local x, _, z = request.entrance.Transform:GetWorldPosition()
    return (point.x - x)^2 + (point.z - z)^2 <= (M.RANGE + 4)^2
end

function M.GetAction(inst)
    local request = Request(inst)
    if request == nil then return end
    local rider = inst.components.rider
    local dismount = rider ~= nil and rider:IsRiding()
    local action = dismount and require("my_friend_riding").GetDismountAction(inst)
        or BufferedAction(inst, request.entrance, ACTIONS.JUMPIN)
    action._my_friend_wormhole = request
    action.validfn = function() return Request(inst) == request end
    local function Finish()
        if inst._my_friend_wormhole == request then inst._my_friend_wormhole = nil end
    end
    if not dismount then action:AddSuccessAction(Finish) end
    action:AddFailAction(function()
        if dismount and (not rider:IsRiding()
            or inst.sg ~= nil and inst.sg:HasStateTag("dismounting")) then return end
        if not action._my_friend_cancelled then Finish() end
    end)
    if not dismount then
        action._my_friend_dialogue_kind = request.entrance.prefab == "pocketwatch_portal_entrance"
            and "rift_follow" or "wormhole_follow"
    end
    return action
end

function M.Configure(teleporter)
    if teleporter._my_friend_follow_wrapped then return end
    teleporter._my_friend_follow_wrapped = true
    local activate = teleporter.Activate
    teleporter.Activate = function(self, doer, ...)
        local friend = TheWorld._my_friend
        local entrance, exit = self.inst, self.targetTeleporter
        local is_rift = entrance.prefab == "pocketwatch_portal_entrance"
        -- Cross-shard rifts already travel through my_friend_traveller with
        -- the player's migration record; never migrate the NPC as a player.
        local accompany = (entrance:HasTag("wormhole") or is_rift) and self.migration_data == nil
            and self.targetTeleporterTemporary == nil and exit ~= nil
            and Policy.IsLocalPlayer(doer) and friend ~= nil and friend:IsValid()
            and Policy.GetLeader(friend) == doer and not friend:HasTag("playerghost")
            and not Policy.IsRoaming(friend)
            and not friend.components.health:IsDead()
            and friend:GetDistanceSqToInst(entrance) <= M.RANGE^2
        local success = activate(self, doer, ...)
        if success and accompany and friend:IsValid() and Policy.GetLeader(friend) == doer then
            require("my_friend_commands").Clear(friend)
            local timer = is_rift and entrance.components.timer or nil
            local remaining = timer ~= nil and timer:GetTimeLeft("closeportal") or nil
            -- Leave noleashing intact: the companion walks to the entrance and
            -- uses Wilson's jumpin/teleporter/jumpout sequence itself.
            friend._my_friend_wormhole = {
                leader = doer, entrance = entrance, exit = exit,
                expires = GetTime() + math.min(M.TIMEOUT, remaining or M.TIMEOUT),
            }
            friend._my_friend_replan_requested = true
        end
        return success
    end
end

return M
