-- Run from the mod root: lua tests/tower_command_test.lua
package.path = "scripts/?.lua;" .. package.path

package.loaded.my_friend_policy = {
    IsBusy = function() return false end,
    GuardAction = function(_, action) return action end,
}
package.loaded.my_friend_commands = {
    Get = function(inst) return inst._my_friend_command end,
    Clear = function(inst) inst._my_friend_command = nil end,
}
package.loaded.my_friend_base_ai = {
    GetBasePoint = function() return nil end,
}
package.loaded.my_friend_dialogue = {RandomReply = function() end}

ACTIONS = {STARTCHANNELING = {}, TELEPORT = {}, DISMOUNT = {}}
BufferedAction = function(doer, target, action)
    local value = {doer = doer, target = target, action = action, success = {}}
    function value:AddSuccessAction(fn) self.success[#self.success + 1] = fn end
    function value:AddFailAction() end
    return value
end

local tower = {
    prefab = "townportal",
    components = {
        channelable = {
            GetEnabled = function() return false end,
            IsChanneling = function() return false end,
        },
        teleporter = {IsActive = function() return true end},
    },
}
function tower:IsValid() return true end
function tower:HasAnyTag() return false end

local friend = {
    _my_friend_command = {id = "touch_tower", target = tower},
    components = {rider = {IsRiding = function() return false end}},
}
function friend:IsValid() return true end
function friend:GetDistanceSqToInst() return 0 end

local Tower = require("my_friend_command_tower")
local action = Tower.GetAction(friend)
assert(action ~= nil and action.action == ACTIONS.TELEPORT,
    "an activated tower should use the vanilla teleport action")
assert(action.validfn(), "the activated tower action should remain valid")

print("PASS: activated town portals are valid touch targets")
