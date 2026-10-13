-- Run from the mod root: lua tests/affinity_follow_test.lua
package.path = "scripts/?.lua;" .. package.path

TUNING = {TOTAL_DAY_TIME = 480}
GetTime = function() return 10 end
AllPlayers = {}
Class = function(ctor)
    return setmetatable({_ctor = ctor}, {__call = function(cls, ...)
        local value = {}
        setmetatable(value, {__index = cls})
        cls._ctor(value, ...)
        return value
    end})
end
package.loaded.my_friend_policy = {
    IsLocalPlayer = function(player)
        return player ~= nil and player.online == true
    end,
    GetLeader = function(inst)
        return inst.components.follower:GetLeader()
    end,
}
package.loaded.my_friend_home = {Resume = function() end}

local function player(userid)
    local value = {userid = userid, online = true}
    function value:IsValid() return true end
    function value:HasTag() return false end
    return value
end

local leader = player("A")
local challenger = player("B")
AllPlayers = {leader, challenger}
local current_leader
local friend = {components = {}, events = {}}
function friend:IsValid() return true end
function friend:HasTag() return false end
function friend:GetDistanceSqToInst() return 0 end
function friend:PushEvent() end
friend.components.health = {IsDead = function() return false end}
friend.components.follower = {
    GetLeader = function() return current_leader end,
    SetLeader = function(_, value) current_leader = value end,
}
friend.DoPeriodicTask = function() return {Cancel = function() end} end

local Affinity = require("components/my_friend_affinity")
local affinity = Affinity(friend)
friend.components.my_friend_affinity = affinity
affinity.values.A, affinity.values.B = 30, 50

assert(affinity:RequestFollow(leader))
assert(current_leader == leader, "A should become the initial leader")
assert(affinity:RequestFollow(challenger))
assert(current_leader == challenger, "B should replace A at the same priority tier")

affinity.values.A, affinity.values.B = 90, 50
assert(affinity:RequestFollow(leader))
assert(current_leader == leader, "A at 90 affinity should take priority")
assert(affinity:RequestFollow(challenger))
assert(current_leader == leader, "B at 50 must not replace a 90-affinity leader")

print("PASS: affinity 30/50 switches leader, while 90 affinity retains priority")
