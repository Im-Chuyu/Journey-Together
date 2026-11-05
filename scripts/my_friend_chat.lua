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
    if TheWorld ~= nil and TheWorld.ismastersim then
        return M.Dispatch(player, message, "rpc")
    end
    SendModRPCToServer(GetModRPC("MyFriends", "ChatCommand"), message)
end

function M.Dispatch(player, message, source)
    if TheWorld == nil or not TheWorld.ismastersim or not Policy.IsLocalPlayer(player)
        or type(message) ~= "string" or message == "" or #message > 2048 then return false end
    local friend = Possess.GetCommandTarget(player) or TheWorld._my_friend
    if friend == nil or not friend:IsValid() or friend._my_friend_possess_parked
        or friend.components == nil or friend.components.my_friend_affinity == nil then
        local relay = package.loaded.my_friend_body_chat
        if relay ~= nil then relay.Forward(player, message, source) end
        return false
    end
    local body = friend._my_friend_body
    -- Assistant input was already accepted with its real player identity.
    -- Its native public echo is presentation, not a second model command.
    if body ~= nil and body.owner == player then
        local clock = (GetStaticTime or GetTime)()
        for _, record in pairs(body.public_echoes or {}) do
            if record.text == message and clock < record.expires and not record.sources[source or "native"] then
                record.sources[source or "native"] = true
                if not record.confirmed then record.confirmed, record.expires = true, clock + 1 end
                return true
            end
        end
    end
    local previous = player._my_friend_last_chat_command
    local now = GetTime()
    -- Some hosts receive both the native chat callback and the sender's RPC.
    if previous ~= nil and previous.message == message and previous.friend == friend
        and previous.source ~= source and now - previous.time < 1 then return false end
    player._my_friend_last_chat_command = {
        message = message, friend = friend, source = source, time = now,
    }
    if body ~= nil and body.ready and require("my_friend_body_api").Valid(friend) == body then
        return require("my_friend_body_api").Input(friend, player, message)
    end
    local relay = package.loaded.my_friend_body_chat
    if relay ~= nil then relay.Forward(player, message, source) end
    return Commands.Dispatch(friend, player, message)
end

return M
