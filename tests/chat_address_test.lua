-- Run from the mod root: lua tests/chat_address_test.lua
package.path = "scripts/?.lua;" .. package.path
package.loaded.my_friend_equip_slots = {}
package.loaded.my_friend_backpacks = {}
package.loaded.my_friend_policy = {
    IsLocalPlayer = function() return true end,
    GetLeader = function() return nil end,
}
package.loaded.my_friend_home = {IsAskPending = function() return false end}
package.loaded.my_friend_dialogue = {Reply = function() end}
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
math.random = random
print("PASS: historical suffix/middle addresses, prefix addresses, mentions and wheel parsing")
