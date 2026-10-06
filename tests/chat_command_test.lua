-- Run from the mod root: lua tests/chat_command_test.lua
package.path = "scripts/?.lua;" .. package.path

local now, calls, forwarded = 10, {}, {}
GetTime = function() return now end
local friend = {components = {my_friend_affinity = {}}}
function friend:IsValid() return not self.removed end
local temporary = {components = {my_friend_affinity = {}}}
function temporary:IsValid() return true end
local player = {userid = "owner"}
function player:IsValid() return true end
local target
package.loaded.my_friend_policy = {IsLocalPlayer = function(p) return p == player end}
package.loaded.my_friend_possess = {GetCommandTarget = function() return target end}
package.loaded.my_friend_commands = {Dispatch = function(f, p, message)
    calls[#calls + 1] = {friend = f, player = p, message = message}
    return true
end}
TheWorld = {ismastersim = true, _my_friend = friend}
ThePlayer = player
GetModRPC = function(namespace, name) return namespace .. ":" .. name end
SendModRPCToServer = function(rpc, message)
    forwarded[#forwarded + 1] = {rpc = rpc, message = message}
end
local Chat = require("my_friend_chat")

Chat.Forward(player, "wendy follow", "input")
Chat.Forward(player, "wendy follow", "echo")
Chat.Forward({}, "wendy follow", "echo")
assert(#forwarded == 1, "only the sender forwards, without duplicating the echo")
assert(forwarded[1].rpc == "MyFriends:ChatCommand")
assert(Chat.Dispatch(player, "wendy follow", "rpc"))
assert(not Chat.Dispatch(player, "wendy follow", "native"))
assert(#calls == 1, "native callback and RPC must execute a command once")
now = now + 2
assert(Chat.Dispatch(player, "wendy follow", "native"))
assert(not Chat.Dispatch(player, "wendy follow", "rpc"))
assert(not Chat.Dispatch({}, "wendy follow", "rpc"))
target = temporary
TheWorld._my_friend = nil
assert(Chat.Dispatch(player, "wendy wait", "rpc"))
assert(calls[#calls].friend == temporary, "possessed players must address the AI body")
target = nil
friend._my_friend_possess_parked = true
TheWorld._my_friend = friend
assert(not Chat.Dispatch(player, "wendy wait", "rpc"))
for _, emote in ipairs({true, 1, "emote"}) do assert(not Chat.IsCommandChat(emote)) end
assert(Chat.IsCommandChat(false) and Chat.IsCommandChat(nil))
print("PASS: chat forwarding, authenticated routing, possession and duplicate suppression")
