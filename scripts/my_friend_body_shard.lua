-- Authenticated shard-to-shard transport to a real player's local HTTP bridge.
-- Links, actor records and pending callbacks are runtime-only and bounded.
local json = require("json")
local Policy = require("my_friend_policy")
local M = {}
local rpc, hooks, enabled
local serial = 0
local outgoing, incoming, requests = {}, {}, {}
local function Now() return (GetStaticTime or GetTime)() end
local function Cancel(task) if task ~= nil then task:Cancel() end end
local function Online(shard)
    return Shard_IsWorldAvailable ~= nil and Shard_IsWorldAvailable(tostring(shard))
end
local function String(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum
end
local function Send(shards, data)
    if rpc == nil or rpc.SendModRPCToShard == nil or rpc.GetShardModRPC == nil then return false end
    if type(shards) ~= "table" then shards = {tostring(shards)} end
    if #shards == 0 then return false end
    local payload = json.encode(data)
    if #payload > 64000 then return false end
    rpc.SendModRPCToShard(rpc.GetShardModRPC("MyFriends", "BodyShardLink"), shards, payload)
    return true
end
local function Capture(player)
    local c = player.components or {}
    return {userid = player.userid, identity = require("my_friend_body_chat").Identity(player),
        speaker = {userid = player.userid, name = player:GetDisplayName(), prefab = player.prefab,
            character = {id = player.prefab, name = player:GetDisplayName()}, kind = "player", same_shard = false,
            ghost = player:HasTag("playerghost"), health = c.health ~= nil and c.health.currenthealth or nil,
            health_max = c.health ~= nil and c.health.maxhealth or nil,
            hunger = c.hunger ~= nil and c.hunger.current or nil, hunger_max = c.hunger ~= nil and c.hunger.max or nil,
            sanity = c.sanity ~= nil and c.sanity.current or nil, sanity_max = c.sanity ~= nil and c.sanity.max or nil},
        admin = require("my_friend_body_world").IsAdmin(player),
        world_control = require("my_friend_body_world").Status(player)}
end
local function ValidCapture(data, userid)
    return type(data) == "table" and data.userid == userid and String(data.identity, 100)
        and type(data.admin) == "boolean" and type(data.speaker) == "table"
        and data.speaker.userid == userid and String(data.speaker.name, 200)
        and type(data.world_control) == "table"
end
function M.Available(inst, actor)
    return actor ~= nil and actor._my_friend_remote_transport == true and actor.world == TheWorld
        and incoming[actor.key] == actor and Now() < actor.expires and Online(actor.shard)
        and (inst == nil or inst.GUID == actor.friend_guid)
end
function M.IsAdmin(actor) return M.Available(nil, actor) and actor.admin == true end
local function Update(actor, data)
    actor.speaker, actor.world_control, actor.admin = data.speaker, data.world_control, data.admin
    actor.identity, actor.expires = data.identity, Now() + 35
end
function M.Notify(actor, status, reason, attempt)
    Send(actor.shard, {op = "status", id = actor.link, userid = actor.userid,
        status = status, reason = reason, attempt = attempt})
    if status == "failed" or status == "disconnected" then
        incoming[actor.key] = nil
        for id, record in pairs(requests) do
            if record.actor == actor then requests[id] = nil; Cancel(record.timeout) end
        end
    end
end
local function Drop(record, reason, notify)
    if outgoing[record.player] ~= record then return end
    outgoing[record.player] = nil
    Cancel(record.timeout); Cancel(record.watch)
    for _, cancel in pairs(record.forwarding) do cancel() end
    if record.target ~= nil then
        Send(record.target, {op = "stop", id = record.id, userid = record.player.userid})
        -- Best effort close while the client is still changing shards. A new
        -- link never inherits pending commands or the previous actor identity.
        if record.last_exchange ~= nil then
            local last = record.last_exchange
            hooks.post(record.player, "exchange", {token = last.token, session = last.session,
                closing = reason, events = {}}, function() end, function() return true end)
        end
    end
    if notify and record.player:IsValid() then hooks.notify(record.player, notify, reason, record.attempt) end
end
local Watch
Watch = function(record)
    Cancel(record.watch)
    record.watch = record.player:DoStaticTaskInTime(10, function()
        record.watch = nil
        if outgoing[record.player] ~= record then return end
        if record.world ~= TheWorld or not Policy.IsLocalPlayer(record.player)
            or not Online(record.target) or Now() - record.seen > 30 then
            Drop(record, "bridge_unavailable", "disconnected")
            return
        end
        Send(record.target, {op = "ping", id = record.id, userid = record.player.userid, actor = Capture(record.player)})
        Watch(record)
    end)
end
function M.Request(player, code, attempt, server_http)
    if not enabled or not Policy.IsLocalPlayer(player) or type(player.userid) ~= "string"
        or type(code) ~= "string" or not code:match("^%d%d%d%d%d%d$") then return false, "permission_denied" end
    local old = outgoing[player]
    local count = 0
    for owner, record in pairs(outgoing) do
        if record.world ~= TheWorld or not owner:IsValid() then Drop(record, "owner_or_body_changed")
        else count = count + 1 end
    end
    if old == nil and count >= 32 then return false, "too_many_links" end
    if old ~= nil then
        if old.world == TheWorld and old.code == code and not (server_http and not old.connected and not old.server_http) then
            old.attempt = attempt
            hooks.notify(player, old.connected and "connected" or "connecting", nil, attempt)
            return true
        end
        Drop(old, "user_disconnected")
    end
    local shards, candidates = {}, {}
    for shard in pairs(Shard_GetConnectedShards ~= nil and Shard_GetConnectedShards() or {}) do
        if Online(shard) then shards[#shards + 1] = tostring(shard); candidates[tostring(shard)] = true end
    end
    if #shards == 0 then return false, "companion_missing" end
    serial = serial + 1
    local id = tostring(player.GUID) .. ":" .. Now() .. ":link:" .. serial
    local record = {id = id, player = player, code = code, attempt = attempt, world = TheWorld,
        candidates = candidates, forwarding = {}, echoes = {}, seen = Now(), server_http = server_http == true}
    outgoing[player] = record
    if not player._my_friend_shard_link_cleanup then
        player._my_friend_shard_link_cleanup = true
        player:ListenForEvent("onremove", function()
            local current = outgoing[player]
            if current ~= nil then Drop(current, "owner_or_body_changed") end
        end)
    end
    record.timeout = player:DoStaticTaskInTime(12, function()
        if outgoing[player] == record and not record.connected then Drop(record, "companion_missing", "failed") end
    end)
    Send(shards, {op = "connect", id = id, userid = player.userid, actor = Capture(player),
        code = code, attempt = attempt, server_http = server_http == true})
    return true
end
function M.Offer(code)
    if not enabled then return end
    local shards = {}
    for shard in pairs(Shard_GetConnectedShards ~= nil and Shard_GetConnectedShards() or {}) do
        if Online(shard) then shards[#shards + 1] = tostring(shard) end
    end
    Send(shards, {op = "offer", id = "server-offer", userid = "server", code = code})
end
function M.Disconnect(player)
    local record = outgoing[player]
    if record == nil then return false end
    Drop(record, "user_disconnected", "disconnected")
    return true
end
function M.Post(inst, actor, path, payload, callback)
    serial = serial + 1
    local id = actor.link .. ":http:" .. serial
    local record = {actor = actor, callback = callback, closing = payload.closing ~= nil}
    requests[id] = record
    local function Finish(reply, reason)
        if requests[id] ~= record then return end
        requests[id] = nil; Cancel(record.timeout)
        callback(reply, reason)
    end
    record.finish = Finish
    record.timeout = inst:DoStaticTaskInTime(8, function() Finish(nil, "timeout") end)
    if not Send(actor.shard, {op = "http", id = actor.link, userid = actor.userid,
        request = id, path = path, payload = payload, admin = actor.requires_admin}) then Finish(nil, "shard_unavailable") end
    return record.timeout
end
function M.Public(actor, payload, input)
    return Send(actor.shard, {op = "public", id = actor.link, userid = actor.userid, payload = payload, input = input})
end
function M.ConsumeEcho(player, text, source, whisper)
    local link = outgoing[player]
    if link == nil then return false end
    for id, record in pairs(link.echoes) do
        if Now() >= record.expires then link.echoes[id] = nil
        elseif record.text == text and record.whisper == (whisper == true) and not record.sources[source or "native"] then
            record.sources[source or "native"] = true
            Send(link.target, {op = "echo", id = link.id, userid = player.userid, input = id})
            return true
        end
    end
    return false
end
local function SourceRecord(source, data)
    for player, record in pairs(outgoing) do
        if record.id == data.id and player.userid == data.userid and record.world == TheWorld
            and Policy.IsLocalPlayer(player) and record.candidates[source]
            and (record.target == nil or record.target == source) then
            record.target, record.seen = source, Now()
            return record
        end
    end
end
local function Actor(source, data)
    local actor = incoming[source .. ":" .. data.id]
    return actor ~= nil and actor.userid == data.userid and actor.world == TheWorld and actor or nil
end
function M.Install(api, on, callbacks)
    rpc, enabled, hooks = api, on ~= false, callbacks
    if api.AddShardModRPCHandler == nil then return end
    api.AddShardModRPCHandler("MyFriends", "BodyShardLink", function(source, payload)
        source = tostring(source)
        if not enabled or TheWorld == nil or not TheWorld.ismastersim or not Online(source)
            or type(payload) ~= "string" or #payload > 64000 then return end
        local ok, data = pcall(json.decode, payload)
        if not ok or type(data) ~= "table" or not String(data.id, 160) or not String(data.userid, 128) then return end
        if data.op == "offer" then
            if type(data.code) ~= "string" or not data.code:match("^%d%d%d%d%d%d$") then return end
            for _, player in ipairs(AllPlayers or {}) do
                local record = outgoing[player]
                if Policy.IsLocalPlayer(player) and (record == nil or not record.connected and not record.server_http) then
                    M.Request(player, data.code, nil, true)
                    break
                end
            end
        elseif data.op == "connect" then
            local inst = TheWorld._my_friend
            if inst == nil or not inst:IsValid() or inst._my_friend_model_enabled ~= true
                or inst:HasTag("playerghost") or not ValidCapture(data.actor, data.userid)
                or type(data.code) ~= "string" or not data.code:match("^%d%d%d%d%d%d$")
                or data.attempt ~= nil and (type(data.attempt) ~= "number" or data.attempt < 1
                    or data.attempt > 1000000 or data.attempt % 1 ~= 0) then return end
            local count = 0
            for key, old in pairs(incoming) do
                if old.world ~= TheWorld or Now() >= old.expires then incoming[key] = nil else count = count + 1 end
            end
            local key = source .. ":" .. data.id
            local actor = incoming[key]
            if actor == nil and count >= 32 then return end
            actor = actor or {_my_friend_remote_speaker = true, _my_friend_remote_transport = true,
                world = TheWorld, link = data.id, key = key, shard = source, userid = data.userid, friend_guid = inst.GUID}
            function actor:IsValid() return M.Available(nil, self) end
            function actor:GetDisplayName() return self.speaker.name end
            function actor:HasTag(tag) return tag == "playerghost" and self.speaker.ghost == true end
            incoming[key] = actor; Update(actor, data.actor)
            local accepted, reason = hooks.connect(inst, actor, data.code, data.attempt, data.server_http == true)
            M.Notify(actor, accepted and "connecting" or "failed", reason, data.attempt)
        elseif data.op == "status" or data.op == "pong" or data.op == "http" or data.op == "public" then
            local record = SourceRecord(source, data)
            if record == nil then return end
            if data.op == "status" then
                if data.status == "connected" then
                    record.connected = true; Cancel(record.timeout); Watch(record)
                elseif data.status == "failed" or data.status == "disconnected" then
                    Drop(record, data.reason or "bridge_unavailable", data.status); return
                elseif data.status ~= "connecting" then return end
                hooks.notify(record.player, data.status, data.reason, record.attempt)
            elseif data.op == "public" then
                local p = data.payload
                if type(p) ~= "table" or not String(p.id, 160) or not String(data.input, 80)
                    or not String(p.text, 1200) then return end
                record.echoes[data.input] = {text = p.text, whisper = p.whisper == true, expires = Now() + 8, sources = {}}
                local count = 0
                for id, echo in pairs(record.echoes) do
                    if Now() >= echo.expires then record.echoes[id] = nil else count = count + 1 end
                end
                if count <= 64 then hooks.say(record.player, p) else record.echoes[data.input] = nil end
            elseif data.op == "http" then
                if not String(data.request, 160) or not ({connect = true, exchange = true})[data.path]
                    or type(data.payload) ~= "table" or record.forwarding[data.request] ~= nil then return end
                if data.path == "connect" and data.payload.code ~= record.code then return end
                local count = 0; for _ in pairs(record.forwarding) do count = count + 1 end
                if count >= 8 then return end
                if data.admin == true and not require("my_friend_body_world").IsAdmin(record.player) then
                    Send(source, {op = "result", id = data.id, userid = data.userid,
                        request = data.request, reason = "relay_admin_required", actor = Capture(record.player)}); return
                end
                if data.path == "exchange" then record.last_exchange = {token = data.payload.token, session = data.payload.session} end
                record.forwarding[data.request] = function() end
                local cancel = hooks.post(record.player, data.path, data.payload, function(reply, reason)
                    record.forwarding[data.request] = nil
                    if outgoing[record.player] ~= record then return end
                    Send(source, {op = "result", id = data.id, userid = data.userid, request = data.request,
                        reply = reply, reason = reason, actor = Capture(record.player)})
                end, function() return outgoing[record.player] == record and Policy.IsLocalPlayer(record.player) end)
                if record.forwarding[data.request] ~= nil then record.forwarding[data.request] = cancel end
            end
        else
            local actor = Actor(source, data)
            if actor == nil then return end
            if data.op == "result" then
                if not String(data.request, 160) then return end
                local request = requests[data.request]
                if request == nil or request.actor ~= actor then return end
                if ValidCapture(data.actor, data.userid) then Update(actor, data.actor) end
                request.finish(type(data.reply) == "table" and data.reply or nil, data.reason)
            elseif data.op == "ping" then
                if not ValidCapture(data.actor, data.userid) then return end
                Update(actor, data.actor)
                local inst = TheWorld._my_friend
                local state = inst ~= nil and inst._my_friend_body or nil
                if state == nil or (state.owner ~= actor and (state.observers or {})[actor] == nil) then
                    M.Notify(actor, "disconnected", "owner_or_body_changed")
                else Send(source, {op = "pong", id = data.id, userid = data.userid}) end
            elseif data.op == "echo" then
                if not String(data.input, 80) then return end
                local inst = TheWorld._my_friend
                local state = inst ~= nil and inst._my_friend_body or nil
                local echo = state ~= nil and state.owner == actor and (state.public_echoes or {})[data.input] or nil
                if echo ~= nil then echo.confirmed = true end
            elseif data.op == "stop" then
                local inst = TheWorld._my_friend
                if inst ~= nil and inst._my_friend_body ~= nil and inst._my_friend_body.owner == actor then
                    require("my_friend_body_api").Close(inst, "owner_or_body_changed")
                end
                incoming[actor.key] = nil
            end
        end
    end)
end
return M
