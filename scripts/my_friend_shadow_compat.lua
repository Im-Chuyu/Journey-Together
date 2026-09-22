local M = {}
local installed = false

local function Listeners(world, event)
    local listeners = world.event_listeners ~= nil and world.event_listeners[event] or nil
    return listeners ~= nil and listeners[world] or {}
end

local function Snapshot(world, event)
    local before = {}
    for _, fn in ipairs(Listeners(world, event)) do before[fn] = true end
    return before
end

local function AddedListener(world, event, before)
    local added
    for _, fn in ipairs(Listeners(world, event)) do
        if not before[fn] then
            if added ~= nil then return end
            added = fn
        end
    end
    return added
end

local function Configure(spawner, joined, left)
    local world = spawner.inst
    local tracked = setmetatable({}, {__mode = "k"})
    local spawn = spawner.SpawnShadowCreature
    spawner.SpawnShadowCreature = function(self, player, params, ...)
        if params == nil and player ~= nil and player:HasTag("my_friend") then
            if joined == nil or left == nil then
                if not self._my_friend_registration_warning then
                    self._my_friend_registration_warning = true
                    print("[MyFriends] Shadow spawner registration callbacks unavailable; skipping unsafe companion shadow spawn")
                end
                return
            end
            -- Join is idempotent. It also restores the record if another mod
            -- issued a player-left event while this companion is still alive.
            joined(world, player)
            if not tracked[player] then
                tracked[player] = true
                world:ListenForEvent("onremove", function()
                    left(world, player)
                    tracked[player] = nil
                end, player)
            end
        end
        return spawn(self, player, params, ...)
    end
end

function M.Install()
    if installed then return end
    installed = true
    local Spawner = require("components/shadowcreaturespawner")
    local constructor = Spawner._ctor
    Spawner._ctor = function(self, world, ...)
        -- Vanilla exposes registration only as world event callbacks. Capture
        -- just this component's newly installed handlers, so an NPC can reuse
        -- its population, land/ocean exchange and cleanup lifecycle without
        -- broadcasting a fake player join to every other world component.
        local joined = Snapshot(world, "ms_playerjoined")
        local left = Snapshot(world, "ms_playerleft")
        constructor(self, world, ...)
        Configure(self, AddedListener(world, "ms_playerjoined", joined),
            AddedListener(world, "ms_playerleft", left))
    end
end

return M
