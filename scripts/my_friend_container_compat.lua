local M = {}

local function TrashRPC()
    return MOD_RPC ~= nil and MOD_RPC.trash ~= nil and MOD_RPC.trash.client_join or nil
end

function M.ConfigureWorld(world)
    if world.ismastersim or world._my_friend_container_config ~= nil or TrashRPC() == nil then return end
    local reply = CLIENT_MOD_RPC ~= nil and CLIENT_MOD_RPC.trash ~= nil
        and CLIENT_MOD_RPC.trash.send_config or nil
    local handlers = reply ~= nil and CLIENT_MOD_RPC_HANDLERS[reply.namespace] or nil
    local original = handlers ~= nil and handlers[reply.id] or nil
    if original == nil then return end

    local state = {ready = false, requested = false}
    world._my_friend_container_config = state
    -- Keep the registered RPC id unchanged on both peers.
    handlers[reply.id] = function(...)
        -- The original early request can also arrive late. Configuration is
        -- fixed for this world; initializing twice duplicates Trash's RPCs.
        if state.ready then return end
        original(...)
        state.ready = true
    end
    local function OnActivated(_, player)
        if player == nil or player ~= ThePlayer or player:HasTag("my_friend")
            or state.ready or state.requested then return end
        state.requested = true
        -- Trash sends its first request from AddPlayerPostInit, which can run
        -- for a companion before the client's real player can send RPCs.
        player:DoTaskInTime(1, function()
            if player:IsValid() and player == ThePlayer and not state.ready then
                SendModRPCToServer(TrashRPC())
            end
        end)
    end
    world:ListenForEvent("playeractivated", OnActivated)
    if ThePlayer ~= nil then OnActivated(world, ThePlayer) end
end

function M.WrapReplica(replica)
    if TheWorld == nil or TheWorld.ismastersim or TrashRPC() == nil then return end
    local open, close, setup = replica.Open, replica.Close, replica.WidgetSetup
    replica.Open = function(self, doer)
        local state = TheWorld._my_friend_container_config
        if doer ~= nil and doer == ThePlayer and self:GetWidget() == nil
            and state ~= nil and not state.ready then
            self._my_friend_pending_container_opener = doer
            return
        end
        return open(self, doer)
    end
    replica.Close = function(self, ...)
        self._my_friend_pending_container_opener = nil
        return close(self, ...)
    end
    replica.WidgetSetup = function(self, ...)
        setup(self, ...)
        local doer = self._my_friend_pending_container_opener
        if doer ~= nil and self:GetWidget() ~= nil then
            self._my_friend_pending_container_opener = nil
            -- Opening is still authorized by the server's container_opener.
            if self.inst:IsValid() and self.opener ~= nil and self.classified ~= nil
                and doer:IsValid() and doer == ThePlayer then
                self:Open(doer)
            end
        end
    end
end

return M
