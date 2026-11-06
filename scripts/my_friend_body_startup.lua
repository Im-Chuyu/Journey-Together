-- Disabled model mode keeps RPC IDs and named companion chat, without loading
-- the model API, HTTP transport, world tools or cross-shard assistant links.
local M = {}

local function Ignore() end
local function Reserve(register, name)
    if register ~= nil then register("MyFriends", name, Ignore) end
end

function M.Install(api, enabled, options)
    if enabled then
        return require("my_friend_body_bridge").Install(api, true, options)
    end
    -- Match the enabled transport's registration order in every direction.
    Reserve(api.AddShardModRPCHandler, "BodyWorldRequest")
    Reserve(api.AddShardModRPCHandler, "BodyWorldReply")
    require("my_friend_body_chat").Install(api, false)
    Reserve(api.AddClientModRPCHandler, "BodyPublicInput")
    Reserve(api.AddModRPCHandler, "BodyRelayReply")
    Reserve(api.AddClientModRPCHandler, "BodyRelay")
    Reserve(api.AddModRPCHandler, "BodyControl")
    Reserve(api.AddClientModRPCHandler, "BodyEvent")
    Reserve(api.AddShardModRPCHandler, "BodyShardLink")
end

return M
