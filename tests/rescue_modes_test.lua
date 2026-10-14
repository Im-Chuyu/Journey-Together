-- Run from the mod root: lua tests/rescue_modes_test.lua
package.path = "scripts/?.lua;" .. package.path
GetTime = function() return 10 end
local point_methods = {}
function point_methods:LengthSq() return self.x^2 + self.z^2 end
Vector3 = function(x, y, z)
    return setmetatable({x = x, y = y, z = z}, {__index = point_methods,
        __sub = function(a, b) return Vector3(a.x - b.x, 0, a.z - b.z) end})
end
ACTIONS = {GIVE = {}, DROP = {}, WALKTO = {}, CAST_POCKETWATCH = {}, MY_FRIEND_MAKE_HEART = {}}
BufferedAction = function(inst, target, action, item, point)
    local value = {doer = inst, target = target, action = action, invobject = item, pos = point, options = {}}
    function value:GetActionPoint() return self.pos or self.target and self.target:GetPosition() end
    function value:AddSuccessAction() end
    function value:AddFailAction() end
    return value
end
package.loaded.my_friend_possess = {IsPossessing = function() return false end}
package.loaded.my_friend_dialogue = {Say = function() end}
package.loaded.my_friend_commands = {Get = function(inst) return inst._my_friend_command end}
FindWalkableOffset = function() return nil end
local function entity(prefab, x, tags)
    local value = {prefab = prefab, pos = Vector3(x, 0, 0), tags = tags or {}, components = {}}
    function value:IsValid() return true end
    function value:HasTag(tag) return self.tags[tag] == true end
    function value:GetPosition() return self.pos end
    function value:GetDistanceSqToPoint(p) return (self.pos - p):LengthSq() end
    function value:GetDistanceSqToInst(e) return self:GetDistanceSqToPoint(e.pos) end
    value.Transform = {GetWorldPosition = function() return value.pos.x, 0, 0 end}
    value.sg = {currentstate = {name = "idle"}, HasStateTag = function() return false end,
        HasAnyStateTag = function() return false end}
    value.components.health = {IsDead = function() return false end}
    return value
end
local ghost = entity("wilson", 50, {playerghost = true})
ghost.userid, ghost._my_friend_rescue_ready_after = "ghost", 0
ghost.components.trader = {AbleToAccept = function() return true end}
AllPlayers = {ghost}
TheWorld = {ismastersim = true}
TheSim = {FindEntities = function(_, _, _, _, _, tags)
    return tags ~= nil and tags[1] == "playerghost" and {ghost} or {}
end}
local Rescue = require("my_friend_rescue")
local Navigation = require("my_friend_navigation")
local Home = require("my_friend_home")
local function fixture(prefab, mode)
    local inst = entity(prefab, 35, {my_friend = true})
    local leader = mode == "follow" and entity("wendy", 0) or nil
    inst.components.follower = {GetLeader = function() return leader end}
    inst._my_friend_home = {x = 0, z = 0, mode = mode == "wait" and "hold" or "base"}
    inst._my_friend_wait_until = 30
    local item
    if prefab ~= "wortox" then
        item = entity(prefab == "wanda" and "pocketwatch_revive" or "reviver", 0)
        item.tags.reviver = prefab ~= "wanda"
        item.components.inventoryitem = {GetGrandOwner = function() return inst end}
        if prefab == "wanda" then
            item.components.pocketwatch = {inactive = true, CanCast = function() return true end}
        end
    end
    inst.components.inventory = {ReferenceAllItems = function() return item and {item} or {} end,
        Has = function(_, name, count) return name == "wortox_soul" and count <= 18, 18 end}
    return inst
end
for _, mode in ipairs({"follow", "wait", "base", "wander"}) do
    for _, prefab in ipairs({"wendy", "wanda", "wortox"}) do
        local inst = fixture(prefab, mode)
        assert(Rescue.Score(inst) == Rescue.SCORE, prefab .. ":" .. mode)
        local action = Rescue.GetAction(inst)
        assert(action ~= nil and action._my_friend_rescue_target == ghost)
        assert(action:validfn(), "rescue should remain valid beyond leader/home range")
        inst._my_friend_navigation_action = action
        assert(not Home.IsPointInRange(inst, ghost.pos))
        assert(Navigation.InTravelRange(inst, ghost.pos), "all roles get the rescue route exemption")
        ghost.tags.playerghost = false
        assert(not action:validfn(), "another player's resurrection cancels stale revival")
        ghost.tags.playerghost = true
    end
end
assert(Rescue.SCORE > 133 + 10, "rescue must preempt wait and special commands in Utility")
local no_resources = fixture("wendy", "base")
no_resources.components.inventory.ReferenceAllItems = function() return {} end
assert(Rescue.Score(no_resources) == 0 and Rescue.GetAction(no_resources) == nil)
print("PASS: generic hearts, Wanda watches and Wortox crafting rescue in follow/wait/base/wander modes with valid routes")
