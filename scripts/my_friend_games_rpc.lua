local json = require("json")
local Games = require("my_friend_games")
local M = {}
function M.Install(api)
    local function Service()
        local world = TheWorld
        if world == nil or not world.ismastersim then return end
        if world._my_friend_games == nil then
            world._my_friend_games = Games.New(world, function(userid, kind, data)
                api.SendModRPCToClient(api.GetClientModRPC("MyFriends", "GameEvent"), userid, kind, json.encode(data))
            end)
            world:ListenForEvent("onremove", function() world._my_friend_games:Shutdown() end)
        end
        return world._my_friend_games
    end
    api.AddModRPCHandler("MyFriends", "GameRequest", function(player, action, payload, friend)
        if type(action) ~= "string" or #action > 16 or type(payload) ~= "string" or #payload > 1024
            or friend ~= nil and (type(friend) ~= "table" or type(friend.IsValid) ~= "function") then return end
        local ok, data = pcall(json.decode, payload)
        if not ok or type(data) ~= "table" then return end
        local service = Service()
        if service ~= nil then service:Request(player, action, data, friend) end
    end)
    api.AddClientModRPCHandler("MyFriends", "GameEvent", function(kind, payload)
        require("my_friend_games_client").Receive(kind, payload)
    end)
end
return M
