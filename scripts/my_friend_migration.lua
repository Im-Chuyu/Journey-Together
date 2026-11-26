local M = {}
-- Positions only make sense on the shard they were recorded on.
local LOCAL_FIELDS = {"my_friend_base", "my_friend_home", "my_friend_hold_memory", "my_friend_revive",
    "my_friend_fire_memory", "my_friend_resource_memory", "my_friend_bookstations", "my_friend_explored"}

function M.SaveWorldMemory(inst, data)
    local homes = inst._my_friend_shard_homes or {}
    local home = {}
    for _, field in ipairs(LOCAL_FIELDS) do home[field] = data[field] end
    home.my_friend_explored = home.my_friend_explored or false
    homes[tostring(TheShard:GetShardId())] = home
    inst._my_friend_shard_homes = homes
    data.my_friend_shard_homes = homes
    data.my_friend_saved_shard = tostring(TheShard:GetShardId())
end

function M.SelectWorldMemory(data)
    if data == nil or data.my_friend_companion ~= true then return end
    local shard = tostring(TheShard:GetShardId())
    local source = data.my_friend_saved_shard
    if source ~= nil and source ~= shard then
        local homes = data.my_friend_shard_homes or {}
        data.my_friend_shard_homes = homes
        local origin = homes[source] or {}
        homes[source] = origin
        -- Old records kept only one exploration map. Preserve it on the
        -- recorded source shard, even if selection is called again on load.
        if origin.my_friend_explored == nil then
            origin.my_friend_explored = data.my_friend_explored or false
        end
        local home = homes[shard] or {}
        for _, field in ipairs(LOCAL_FIELDS) do data[field] = home[field] end
    end
end

-- The moon portal drops follower inventories BEFORE ms_playerdespawnanddelete.
function M.HoldCompanion(player)
    local friend = TheWorld._my_friend
    if player == nil or player:HasTag("my_friend") or friend == nil
        or not friend:IsValid() or friend.components.follower == nil then return end
    local follower = friend.components.follower
    if follower:GetLeader() ~= player then return end
    if friend._my_friend_body ~= nil then require("my_friend_body_api").Close(friend, "entity_migration") end
    require("my_friend_commands").Clear(friend)
    local root = friend.brain ~= nil and friend.brain.bt ~= nil and friend.brain.bt.root or nil
    if root ~= nil and root.CancelActive ~= nil then root:CancelActive() end
    friend:ClearBufferedAction()
    if friend.components.locomotor ~= nil then
        friend.components.locomotor:Clear()
        friend.components.locomotor:Stop()
    end
    local affinity = friend.components.my_friend_affinity
    if affinity ~= nil then
        affinity.requests = {}
        affinity.staying = true
    end
    follower:SetLeader(nil)
    follower:ClearCachedPlayerLeader()
    friend._my_friend_last_leader_userid = nil
    require("my_friend_home").Hold(friend)
    friend._my_friend_replan_requested = true
end

local function AfterPlayerDespawn(inst, ...)
    require("my_friend_possess").OnPlayerDespawn(inst)
    return ...
end

function M.Attach(player, configure)
    if not TheWorld.ismastersim then return end
    M.ConfigureFriend = configure
    if player._my_friend_migration_attached then return end
    player._my_friend_migration_attached = true
    if player.components.my_friend_traveller == nil then player:AddComponent("my_friend_traveller") end
    local persist = player.SetPersistData
    player.SetPersistData = function(inst, data, ...)
        if data ~= nil and inst.userid ~= nil and inst.userid ~= "" and not data.my_friend_companion then
            data = require("my_friend_possess").PrepareLogin(inst, data)
        end
        return persist(inst, data, ...)
    end
    player:ListenForEvent("ms_playerreroll", function(inst)
        local swapper = inst.components.seamlessplayerswapper
        if swapper ~= nil and swapper._my_friend_swap_in_progress then return end
        M.HoldCompanion(inst)
        require("my_friend_possess").OnCharacterReroll(inst)
    end)
    local old = player.OnDespawn
    player.OnDespawn = function(inst, migrationdata)
        -- While the world is still loading, DST restores every snapshot
        -- session, despawns it again and removes it. Nobody is actually
        -- leaving, so the companion must not be captured or sent home.
        if TheWorld._my_friend_loading then
            if old ~= nil then return old(inst, migrationdata) end
            return
        end
        if migrationdata ~= nil and not inst:HasTag("my_friend") then
            inst._my_friend_migrating = true
            if migrationdata.worldid ~= nil then
                TheWorld._my_friend_known_shards = TheWorld._my_friend_known_shards or {}
                TheWorld._my_friend_known_shards[tostring(migrationdata.worldid)] = true
            end
            inst.components.my_friend_traveller:Capture()
        elseif not inst:HasTag("my_friend") and TheWorld.prefab == "cave" then
            local friend = TheWorld._my_friend
            if friend ~= nil and friend:IsValid()
                and friend.components.follower:GetLeader() == inst then
                require("my_friend_shard_home").ReturnHome(friend)
            end
        end
        if migrationdata == nil then M.HoldCompanion(inst) end
        local possess = require("my_friend_possess")
        -- Vanilla may drop irreplaceable items, wake sleepers and dismount here.
        -- Snapshot the remaining inventory after those ownership changes.
        if migrationdata ~= nil then
            possess.OnMigrate(inst, migrationdata.worldid)
            if old ~= nil then return old(inst, migrationdata) end
        elseif old ~= nil then
            return AfterPlayerDespawn(inst, old(inst, migrationdata))
        else
            AfterPlayerDespawn(inst)
        end
    end
end

return M
