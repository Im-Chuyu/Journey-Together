local M = {}
local Policy = require("my_friend_policy")
local Commands = require("my_friend_commands")
local Possess = require("my_friend_possess")

function M.IsCommandChat(isemote)
    return isemote ~= true and isemote ~= 1 and isemote ~= "emote"
end

function M.Forward(player, message, source)
    if player == nil or player ~= ThePlayer or not player:IsValid()
        or type(message) ~= "string" or message == "" or #message > 2048 then return end
    local previous = player._my_friend_last_chat_forward
    local now = GetTime()
    if previous ~= nil and previous.message == message
        and previous.source ~= source and now - previous.time < 1 then return end
    player._my_friend_last_chat_forward = {message = message, source = source, time = now}
    SendModRPCToServer(GetModRPC("MyFriends", "ChatCommand"), message)
end

function M.Dispatch(player, message, source)
    if TheWorld == nil or not TheWorld.ismastersim or not Policy.IsLocalPlayer(player)
        or type(message) ~= "string" or message == "" or #message > 2048 then return false end
    local friend = Possess.GetCommandTarget(player) or TheWorld._my_friend
    if friend == nil or not friend:IsValid() or friend._my_friend_possess_parked
        or friend.components == nil or friend.components.my_friend_affinity == nil then return false end
    local previous = player._my_friend_last_chat_command
    local now = GetTime()
    -- Some hosts receive both the native chat callback and the sender's RPC.
    if previous ~= nil and previous.message == message and previous.friend == friend
        and previous.source ~= source and now - previous.time < 1 then return false end
    player._my_friend_last_chat_command = {
        message = message, friend = friend, source = source, time = now,
    }
    return Commands.Dispatch(friend, player, message)
end

return M
