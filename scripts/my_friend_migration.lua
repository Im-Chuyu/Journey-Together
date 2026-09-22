local M = {}
-- Positions only make sense on the shard they were recorded on.
local LOCAL_FIELDS = {"my_friend_base", "my_friend_home", "my_friend_revive",
    "my_friend_fire_memory", "my_friend_resource_memory"}

function M.SaveWorldMemory(inst, data)
    local homes = inst._my_friend_shard_homes or {}
    local home = {}
    for _, field in ipairs(LOCAL_FIELDS) do home[field] = data[field] end
    homes[tostring(TheShard:GetShardId())] = home
    inst._my_friend_shard_homes = homes
    data.my_friend_shard_homes = homes
    data.my_friend_saved_shard = tostring(TheShard:GetShardId())
end

function M.SelectWorldMemory(data)
    if data == nil or data.my_friend_companion ~= true then return end
    local shard = tostring(TheShard:GetShardId())
    if data.my_friend_saved_shard ~= nil and data.my_friend_saved_shard ~= shard then
        local home = (data.my_friend_shard_homes or {})[shard] or {}
        for _, field in ipairs(LOCAL_FIELDS) do data[field] = home[field] end
    end
end

function M.Attach(player, configure)
    if not TheWorld.ismastersim then return end
    M.ConfigureFriend = configure
    if player.components.my_friend_traveller == nil then player:AddComponent("my_friend_traveller") end
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
        if old ~= nil then return old(inst, migrationdata) end
    end
end

return M
