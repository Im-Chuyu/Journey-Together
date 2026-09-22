local M = {}
local CHUNK_SIZE = 6000

local function Send(name, shard, ...)
    SendModRPCToShard(GetShardModRPC("MyFriends", name), {tostring(shard)}, ...)
end

local function HasCompanion(ignore_departure)
    local friend = TheWorld._my_friend
    if friend ~= nil and friend:IsValid() then return true end
    if TheWorld._my_friend_home_pending ~= nil then return true end
    for _, player in ipairs(AllPlayers or {}) do
        local traveller = player.components.my_friend_traveller
        if traveller ~= nil and traveller.record ~= nil then return true end
    end
    return not ignore_departure and GetTime() < (TheWorld._my_friend_departing_until or 0)
end

function M.MarkDeparture()
    TheWorld._my_friend_departing_until = GetTime() + 90
end

function M.CanCreateFirstCompanion()
    local world = TheWorld
    -- Only the surface creates companions. Once one has existed, retain the
    -- cross-shard check even if its current entity is absent during migration.
    return world:HasTag("forest")
        and not world._my_friend_initialized and not world._my_friend_saved
        and not HasCompanion()
end

function M.ReturnHome(friend)
    if TheWorld.prefab ~= "cave" or friend == nil or not friend:IsValid()
        or TheWorld._my_friend_home_pending ~= nil then return end
    require("my_friend_commands").Clear(friend)
    local root = friend.brain ~= nil and friend.brain.bt ~= nil and friend.brain.bt.root or nil
    if root ~= nil then root:CancelActive() end
    if friend.sg ~= nil and friend.sg.statemem.feed ~= nil then friend.sg:GoToState("idle") end
    friend.components.locomotor:Clear()
    friend.components.inventory:CloseAllChestContainers()
    local affinity = friend.components.my_friend_affinity
    affinity.requests, affinity.staying = {}, true
    friend.components.follower:SetLeader(nil)
    friend.components.follower:ClearCachedPlayerLeader()
    local record = friend:GetSaveRecord()
    if record == nil then return end
    local token = friend._my_friend_id .. ":" .. tostring(GetTime()) .. ":" .. tostring(friend.GUID)
    TheWorld._my_friend_home_pending = {token = token, record = record}
    TheWorld._my_friend = nil
    require("my_friend_abigail").RemoveSource(friend)
    friend:Remove()
    M.SendPending()
end

function M.SendPending()
    local pending = TheWorld._my_friend_home_pending
    if pending == nil or not Shard_IsWorldAvailable(SHARDID.MASTER) then return end
    local cached = TheWorld._my_friend_home_payload
    if cached == nil or cached.token ~= pending.token then
        -- Native save encoding preserves sparse numeric inventory slot keys.
        cached = {token = pending.token, text = DataDumper(pending.record, nil, true)}
        TheWorld._my_friend_home_payload = cached
    end
    local payload = cached.text
    local total = math.ceil(#payload / CHUNK_SIZE)
    -- Bound messages per tick even when backpacks contain complex modded items.
    local index = pending.next_chunk or 1
    for _ = 1, 4 do
        Send("HomeChunk", SHARDID.MASTER, pending.token, index, total,
            payload:sub((index - 1) * CHUNK_SIZE + 1, index * CHUNK_SIZE))
        index = index + 1
        if index > total then index = 1 break end
    end
    pending.next_chunk = index
end

function M.ReceiveChunk(source, token, index, total, chunk)
    if TheWorld.prefab ~= "forest" or type(token) ~= "string" or #token > 256
        or type(index) ~= "number" or type(total) ~= "number"
        or total < 1 or total > 4096 or total % 1 ~= 0 or index % 1 ~= 0
        or index < 1 or index > total or type(chunk) ~= "string" or #chunk > CHUNK_SIZE then return end
    local received = TheWorld._my_friend_home_received or {}
    TheWorld._my_friend_home_received = received
    if received[token] then Send("HomeAck", source, token) return end
    local buffers = TheWorld._my_friend_home_buffers or {}
    TheWorld._my_friend_home_buffers = buffers
    local key = tostring(source)
    local buffer = buffers[key]
    if buffer == nil or buffer.token ~= token or buffer.total ~= total then
        buffer = {token = token, total = total, parts = {}, count = 0}
        buffers[key] = buffer
    end
    if buffer.parts[index] == nil then buffer.count = buffer.count + 1 end
    buffer.parts[index] = chunk
    if buffer.count ~= total then return end
    local ok, record = RunInSandboxSafe(table.concat(buffer.parts))
    if not ok or type(record) ~= "table"
        or not require("my_friend_characters").IsCharacter(record.prefab)
        or type(record.data) ~= "table" or record.data.my_friend_companion ~= true then
        buffers[key] = nil
        return
    end
    -- A live companion already exists here: the arriving copy is stale.
    -- Acknowledge anyway, otherwise the cave keeps a pending record forever
    -- and can never send the companion home again.
    if HasCompanion(true) then
        received[token] = true
        buffers[key] = nil
        Send("HomeAck", source, token)
        return
    end
    local migration = require("my_friend_migration")
    migration.SelectWorldMemory(record.data)
    local base = record.data.my_friend_base
    local portal = TheSim:FindFirstEntityWithTag("multiplayer_portal")
    local point = base ~= nil and type(base.x) == "number" and type(base.z) == "number"
        and Vector3(base.x, 0, base.z) or portal ~= nil and portal:GetPosition() or nil
    if point == nil then return end
    local offset = FindWalkableOffset(point, math.random() * 2 * math.pi, 3, 16, true, false)
    if offset ~= nil then point = point + offset end
    if not TheWorld.Map:IsPassableAtPoint(point.x, 0, point.z) then
        if portal == nil then return end
        point = portal:GetPosition()
    end
    record.x, record.y, record.z = point:Get()
    local friend = SpawnSaveRecord(record)
    if friend == nil then return end
    migration.ConfigureFriend(friend)
    require("my_friend_abigail").Place(friend)
    friend.components.my_friend_affinity.requests = {}
    friend.components.my_friend_affinity.staying = true
    friend.components.follower:SetLeader(nil)
    friend.components.follower:ClearCachedPlayerLeader()
    friend._my_friend_replan_requested = true
    TheWorld._my_friend_saved = true
    received[token] = true
    buffers[key] = nil
    Send("HomeAck", source, token)
end

function M.ReceiveAck(source, token)
    local pending = TheWorld._my_friend_home_pending
    if tostring(source) == tostring(SHARDID.MASTER) and pending ~= nil and pending.token == token then
        TheWorld._my_friend_home_pending = nil
        TheWorld._my_friend_home_payload = nil
    end
end

function M.ReceiveProbe(source, token)
    -- Reply outside the incoming RPC dispatch frame.
    TheWorld:DoTaskInTime(0, function()
        Send("Presence", source, token, HasCompanion())
    end)
end

function M.ReceivePresence(source, token, present)
    local probe = TheWorld._my_friend_presence_probe
    if probe ~= nil and probe.token == token and probe.waiting[tostring(source)] ~= nil then
        probe.waiting[tostring(source)] = false
        probe.present = probe.present or present == true
    end
end

function M.CheckMissing(callback)
    local world = TheWorld
    if HasCompanion() or world._my_friend_presence_probe ~= nil then return end
    local probe = {token = tostring(GetTime()), waiting = {}, present = false}
    world._my_friend_presence_probe = probe
    local known = world._my_friend_known_shards or {}
    world._my_friend_known_shards = known
    for shard in pairs(Shard_GetConnectedShards()) do known[tostring(shard)] = true end
    for shard in pairs(known) do
        if tostring(shard) ~= tostring(TheShard:GetShardId()) then
            probe.waiting[shard] = true
            if Shard_IsWorldAvailable(shard) then Send("PresenceProbe", shard, probe.token) end
        end
    end
    world:DoTaskInTime(5, function()
        if world._my_friend_presence_probe ~= probe then return end
        world._my_friend_presence_probe = nil
        if HasCompanion() or probe.present then return end
        for shard, waiting in pairs(probe.waiting) do
            if waiting then
                if GetTime() >= (world._my_friend_probe_log_after or 0) then
                    world._my_friend_probe_log_after = GetTime() + 60
                    print("[MyFriends] Missing-companion check waiting for shard " .. tostring(shard))
                end
                return
            end
        end
        callback()
    end)
end

function M.AttachWorld(world)
    world:ListenForEvent("ms_playerleft", function(_, player)
        if world.prefab ~= "cave" or player == nil or player:HasTag("my_friend")
            or player._my_friend_migrating or world._my_friend_loading then return end
        local friend = world._my_friend
        if friend ~= nil and friend:IsValid()
            and (friend.components.follower:GetLeader() == player
                or friend._my_friend_last_leader_userid == player.userid) then
            M.ReturnHome(friend)
        end
    end)
    world:DoStaticPeriodicTask(2, M.SendPending)
end

return M
