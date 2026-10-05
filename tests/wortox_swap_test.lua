-- Run from the mod root: lua tests/wortox_swap_test.lua
package.path = "scripts/?.lua;" .. package.path

local replies, cleared, spawned = 0, 0, 0
package.loaded.my_friend_policy = {IsBusy = function() return false end}
package.loaded.my_friend_dialogue = {RandomReply = function() replies = replies + 1 end}
package.loaded.my_friend_commands = {
    Get = function() return {id = "make_heart"} end,
    Clear = function() cleared = cleared + 1 end,
}
SpawnPrefab = function() spawned = spawned + 1 end
TheWorld = {_my_friend_possession_active = true}
local Wortox = require("my_friend_wortox")
local friend = {
    prefab = "wortox",
    components = {
        health = {IsDead = function() return false end},
        inventory = {Has = function() return true end},
    },
    HasTag = function(_, tag) return tag == "my_friend" end,
}

assert(not Wortox.CanMakeHeart(friend))
assert(Wortox.MakeHeart(friend) == false)
assert(Wortox.GetMakeHeartCommandAction(friend) == nil)
assert(replies == 0 and cleared == 0 and spawned == 0)
TheWorld._my_friend_possession_active = nil
assert(Wortox.CanMakeHeart(friend))
friend._my_friend_possess_parked = true
assert(not Wortox.CanMakeHeart(friend))
print("PASS: swapping and parked Wortox cannot craft or speak about hearts")
