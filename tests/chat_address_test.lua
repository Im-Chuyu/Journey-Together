-- Run from the mod root: lua tests/chat_address_test.lua
package.path = "scripts/?.lua;" .. package.path
package.loaded.my_friend_equip_slots = {}
package.loaded.my_friend_backpacks = {}
package.loaded.my_friend_policy = {
    IsLocalPlayer = function() return true end,
    GetLeader = function() return nil end,
}
package.loaded.my_friend_home = {IsAskPending = function() return false end}
package.loaded.my_friend_dialogue = {Reply = function() end, Say = function() end}
package.loaded.my_friend_beefalo = {Riding = {}}
package.loaded.my_friend_special_commands = {Parse = function() end}
package.loaded.my_friend_characters = {List = function() return {"wendy"} end}
package.loaded.my_friend_carry_backpack = {Answer = function() return false end}
package.loaded.my_friend_pets = {Parse = function() end}
STRINGS = {CHARACTER_TITLES = {}}
local random = math.random
math.random = function() return 1 end

local requests = 0
local friend = {prefab = "wendy", components = {
    health = {}, my_friend_affinity = {RequestFollow = function()
        requests = requests + 1
        return true
    end},
}}
function friend:IsValid() return true end
function friend:HasTag() return false end
function friend:GetDisplayName() return "Wendy" end
local Commands = require("my_friend_commands")
local player = {}
for _, message in ipairs({
    "跟着我温蒂", "温蒂跟着我", "跟着我，温蒂", "温蒂，跟着我",
    "请温蒂跟着我", "@温蒂 跟着我", "@ 温蒂 跟着我", "温迪跟着我",
}) do
    local before = requests
    assert(Commands.Dispatch(friend, player, message), message)
    assert(requests == before + 1, message)
end
friend._my_friend_custom_name = "小温蒂"
assert(Commands.Dispatch(friend, player, "跟着我小温蒂"))
assert(not Commands.Dispatch(friend, player, "跟着我"))
assert(not Commands.Dispatch(friend, player, "跟着我Wilson"))
assert(not Commands.Dispatch(friend, player, "newendy 跟着我"))
assert(not Commands.Dispatch(friend, player, "wendyish 跟着我"))
assert(Commands.DispatchWheel(friend, player, "follow"))
-- Setting a base uses the sender's exact position and retains following.
-- A nearby facility must no longer replace that command's centre.
local policy, home = package.loaded.my_friend_policy, package.loaded.my_friend_home
local selected, calls = nil, 0
policy.GetLeader = function() return player end
function player:GetPosition() return {x = 23, y = 0, z = -17} end
function friend:GetPosition() return {x = -50, y = 0, z = 10} end
home.FindAnchor = function() error("base selection must not snap to a facility") end
home.Set = function(_, point, mode) selected = {x = point.x, z = point.z, mode = mode}; calls = calls + 1 end
package.loaded.my_friend_carry_backpack.Cancel = function() end
package.loaded.my_friend_recipe_cooking = {Cancel = function() end}
friend._my_friend_command = {id = "chop"}
assert(Commands.DispatchWheel(friend, player, "set_base"))
assert(calls == 1 and selected.x == 23 and selected.z == -17 and selected.mode == "base")
assert(friend._my_friend_command == nil and policy.GetLeader(friend) == player)
policy.GetLeader = function() return nil end
assert(not Commands.DispatchWheel(friend, player, "set_base") and calls == 1,
    "the base command still requires the sender to be the current leader")
math.random = random
print("PASS: historical suffix/middle addresses, prefix addresses, mentions and wheel parsing")
