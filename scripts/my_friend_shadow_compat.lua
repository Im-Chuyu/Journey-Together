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
    spawner._my_friend_register = function(player)
        if joined == nil or left == nil then return false end
        joined(world, player)
        if not tracked[player] then
            tracked[player] = true
            world:ListenForEvent("onremove", function()
                left(world, player)
                tracked[player] = nil
            end, player)
        end
        return true
    end
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
            self._my_friend_register(player)
        end
        return spawn(self, player, params, ...)
    end
end

function M.RegisterCompanion(inst)
    local spawner = TheWorld.components.shadowcreaturespawner
    if spawner ~= nil and spawner._my_friend_register ~= nil then
        spawner._my_friend_register(inst)
    end
end

function M.ConfigureCreature(inst)
    if not inst:HasTag("shadowcreature") or TheWorld == nil or not TheWorld.ismastersim
        or inst._my_friend_shadow_targeting then return end
    local combat = inst.components.combat
    if combat == nil or combat.targetfn == nil then return end
    inst._my_friend_shadow_targeting = true
    local retarget = combat.targetfn
    combat.targetfn = function(creature, ...)
        local friend = TheWorld._my_friend
        if friend == nil or not friend:IsValid() or not friend:HasTag("my_friend")
            or friend:HasTag("playerghost") or friend.components.sanity == nil
            or not friend.components.sanity:IsCrazy()
            or friend.components.health == nil or friend.components.health:IsDead()
            or creature:GetDistanceSqToInst(friend) > TUNING.SHADOWCREATURE_TARGET_DIST^2 then
            return retarget(creature, ...)
        end
        local players = {}
        for _, player in ipairs(AllPlayers) do
            if player == friend then return retarget(creature, ...) end
            players[#players + 1] = player
        end
        players[#players + 1] = friend
        -- Keep the native dominance rules and both return values, without
        -- registering a fake connected player or adding another scan task.
        local env = getfenv(retarget)
        setfenv(retarget, setmetatable({AllPlayers = players}, {__index = env}))
        local ok, target, forcechange = pcall(retarget, creature, ...)
        setfenv(retarget, env)
        if not ok then error(target) end
        return target, forcechange
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
