-- Run from the mod root: lua tests/possession_rebind_test.lua
package.path = "scripts/?.lua;" .. package.path
package.loaded.my_friend_characters = {}
package.loaded.my_friend_wx78 = {}
package.loaded.my_friend_abigail = {}
package.loaded.my_friend_inventory_transfer = {}
package.loaded.my_friend_skills = {}
local refreshes = 0
package.loaded.my_friend_wortox = {RefreshLinkedHearts = function() refreshes = refreshes + 1 end}
local session = {phase = "exit_ready", companion_id = "companion"}
TheWorld = {_my_friend_possessions = {owner = session}}
local player = {userid = "owner", prefab = "wathgrithr", components = {}, tags = {}}
function player:IsValid() return true end
function player:AddTag(tag) self.tags[tag] = true end
local Possess = require("my_friend_possess")
assert(Possess.Rebind(player))
assert(player._my_friend_id == nil and not player.tags.my_friend_possessed and refreshes == 0,
    "a spawn task during return must not mark the restored player as the departing companion")
session.phase = "enter_ready"
assert(Possess.Rebind(player))
assert(player._my_friend_id == "companion" and player.tags.my_friend_possessed and refreshes == 1)
print("PASS: spawn-time rebind preserves returning player identity and only marks the entering body")
