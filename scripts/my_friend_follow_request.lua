-- Shared legacy/model follow transition. Following is a mode, not a body job.
local Policy = require("my_friend_policy")
local M = {}
function M.Apply(inst, player, clear, resume_current)
    local affinity = inst.components.my_friend_affinity
    -- An authorized model task resumes an existing leader relationship; it does
    -- not arbitrate a new follow request using the normal 25-affinity gate.
    local current = resume_current == true and Policy.GetLeader(inst) == player
    if affinity == nil or not current and not affinity:RequestFollow(player) then return false, "follow_unfamiliar" end
    if Policy.GetLeader(inst) ~= player then return true, "follow_busy" end
    inst._my_friend_pending_recipe = nil
    require("my_friend_contextual_events").RecordFollowStarted(inst, player)
    require("my_friend_combat_rules").DisengageForFollow(inst, player)
    require("my_friend_ghost_commands").Cancel(inst)
    if clear ~= nil then clear(inst) end
    require("my_friend_riding").AllowAutoRide(inst)
    inst._my_friend_greeting_pause_until = nil
    inst._my_friend_follow_requested_until = GetTime() + 30
    inst._my_friend_follow_route_reset = true
    return true, "follow_ok"
end
return M
