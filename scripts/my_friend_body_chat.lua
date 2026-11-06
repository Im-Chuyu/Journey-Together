-- Server-to-server public chat relay. Never accepts a client-supplied identity.
local json = require("json")
local Policy = require("my_friend_policy")
local M = {}
local rpc, serial = nil, 0
local pending = {}
local displayed, display_order = {}, {}
local function Display(data)
    if type(data) ~= "table" or type(data.id) ~= "string" or #data.id > 160
        or type(data.name) ~= "string" or #data.name > 200 or type(data.text) ~= "string" or #data.text > 600
        or displayed[data.id] then return end
    displayed[data.id], display_order[#display_order + 1] = true, data.id
    if #display_order > 64 then displayed[table.remove(display_order, 1)] = nil end
    if ChatHistory ~= nil and ChatHistory.OnSay ~= nil then
        ChatHistory:OnSay(0, nil, nil, data.name, data.prefab, data.text, WHITE or {1,1,1,1}, false, false)
    end
end
local function Send(name, shard, data)
    local targets = {}
    if shard ~= nil then targets[1] = tostring(shard)
    else
        for id in pairs(Shard_GetConnectedShards ~= nil and Shard_GetConnectedShards() or {}) do targets[#targets + 1] = tostring(id) end
    end
    if #targets > 0 then rpc.SendModRPCToShard(rpc.GetShardModRPC("MyFriends", name), targets, json.encode(data)) end
end
local function Online(source)
    return Shard_IsWorldAvailable ~= nil and Shard_IsWorldAvailable(tostring(source))
end
local function Identity(player)
    if player._my_friend_model_chat_identity == nil then
        serial = serial + 1
        player._my_friend_model_chat_identity = tostring(player.GUID) .. ":" .. GetTime() .. ":" .. serial
        player:ListenForEvent("onremove", function()
            if rpc ~= nil then Send("BodyChat", nil, {left = true, identity = player._my_friend_model_chat_identity}) end
        end)
    end
    return player._my_friend_model_chat_identity
end
function M.Forward(player, text, source, whisper)
    if whisper == true or rpc == nil or rpc.SendModRPCToShard == nil or TheWorld == nil
        or not TheWorld.ismastersim or not Policy.IsLocalPlayer(player) then return false end
    local previous, now = player._my_friend_model_chat_forward, (GetStaticTime or GetTime)()
    if previous ~= nil and previous.text == text and previous.source ~= source and now - previous.time < 1 then return true end
    if previous ~= nil and now - previous.time < .5 then return false end
    player._my_friend_model_chat_forward = {text = text, source = source, time = now}
    local c = player.components or {}
    local speaker = {userid = player.userid, name = player:GetDisplayName(), kind = "player", same_shard = false,
        character = {id = player.prefab, name = player:GetDisplayName()},
        health = c.health ~= nil and c.health.currenthealth or nil,
        health_max = c.health ~= nil and c.health.maxhealth or nil,
        hunger = c.hunger ~= nil and c.hunger.current or nil, hunger_max = c.hunger ~= nil and c.hunger.max or nil,
        sanity = c.sanity ~= nil and c.sanity.current or nil, sanity_max = c.sanity ~= nil and c.sanity.max or nil}
    serial = serial + 1
    Send("BodyChat", nil, {identity = Identity(player), id = tostring(player.GUID) .. ":" .. serial,
        text = text, speaker = speaker, world_control = require("my_friend_body_world").Status(player)})
    return true
end
function M.Available(inst, actor)
    local state = inst ~= nil and inst._my_friend_body or nil
    return state ~= nil and type(actor) == "table" and actor._my_friend_remote_speaker == true and state.remote_speakers ~= nil
        and state.remote_speakers[actor.key] == actor and not actor.left and GetTime() < actor.expires and Online(actor.shard)
end
function M.Reply(inst, actor, id, text)
    if rpc ~= nil and M.Available(inst, actor) then
        Send("BodyChatSpeech", actor.shard, {identity = actor.identity, userid = actor.userid,
            id = id, name = inst:GetDisplayName(), prefab = inst.prefab, text = text})
    end
end
function M.CanBroadcast()
    return rpc ~= nil and rpc.GetClientModRPC ~= nil and rpc.SendModRPCToClient ~= nil
end
local function BroadcastLocal(data)
    if not M.CanBroadcast() then return false end
    local targets = {}
    for _, player in ipairs(AllPlayers or {}) do
        if Policy.IsLocalPlayer(player) then
            if player == ThePlayer then Display(data)
            elseif type(player.userid) == "string" then targets[#targets + 1] = player.userid end
        end
    end
    if #targets > 0 then rpc.SendModRPCToClient(rpc.GetClientModRPC("MyFriends", "BodyChatSpeech"), targets, json.encode(data)) end
    return true
end
function M.Broadcast(inst, id, text)
    local data = {id = id, name = inst:GetDisplayName(), prefab = inst.prefab, text = text, public = true}
    if not BroadcastLocal(data) then return false end
    if rpc.SendModRPCToShard ~= nil then Send("BodyChatSpeech", nil, data) end
    return true
end
function M.WorldCall(actor, skill, args, callback, dialogue)
    if rpc == nil or not Online(actor.shard) then callback(false, nil, "speaker_shard_unavailable"); return end
    local count = 0; for _ in pairs(pending) do count = count + 1 end
    if count >= 32 then callback(false, nil, "world_control_busy"); return end
    serial = serial + 1
    local id, world = tostring(GetTime()) .. ":" .. serial, TheWorld
    local record = {callback = callback, world = world, source = actor.shard}
    pending[id] = record
    if not world._my_friend_chat_world_cleanup then
        world._my_friend_chat_world_cleanup = true
        world:ListenForEvent("onremove", function()
            for key, request in pairs(pending) do
                if request.world == world then
                    pending[key] = nil; request.timeout:Cancel(); request.callback(false, nil, "world_removed")
                end
            end
        end)
    end
    record.timeout = world:DoStaticTaskInTime(10, function()
        if pending[id] == record then pending[id] = nil; callback(false, nil, "speaker_shard_timeout") end
    end)
    Send("BodyChatWorld", actor.shard, {id = id, identity = actor.identity, userid = actor.userid, skill = skill, args = args, dialogue=dialogue})
end
function M.Install(api)
    rpc = api
    if api.AddClientModRPCHandler ~= nil then
        api.AddClientModRPCHandler("MyFriends", "BodyChatSpeech", function(payload)
            if type(payload) ~= "string" or #payload > 10000 then return end
            local ok, data = pcall(json.decode, payload)
            if ok then Display(data) end
        end)
    end
    if api.AddShardModRPCHandler == nil then return end
    api.AddShardModRPCHandler("MyFriends", "BodyChatSpeech", function(source, payload)
        if TheWorld == nil or not TheWorld.ismastersim or not Online(source) or type(payload) ~= "string" or #payload > 10000 then return end
        local ok, data = pcall(json.decode, payload)
        if not ok or type(data) ~= "table" then return end
        if data.public == true then BroadcastLocal(data); return end
        for _, player in ipairs(AllPlayers or {}) do
            if Policy.IsLocalPlayer(player) and player.userid == data.userid and player._my_friend_model_chat_identity == data.identity then
                if player == ThePlayer then Display(data)
                elseif rpc.GetClientModRPC ~= nil and rpc.SendModRPCToClient ~= nil then
                    rpc.SendModRPCToClient(rpc.GetClientModRPC("MyFriends", "BodyChatSpeech"), {player.userid}, payload)
                end
                return
            end
        end
    end)
    api.AddShardModRPCHandler("MyFriends", "BodyChat", function(source, payload)
        if TheWorld == nil or not TheWorld.ismastersim or not Online(source) or type(payload) ~= "string" or #payload > 16000 then return end
        local ok, data = pcall(json.decode, payload)
        if not ok or type(data) ~= "table" or type(data.identity) ~= "string" or #data.identity > 100 then return end
        local inst = TheWorld._my_friend
        local body_api = require("my_friend_body_api")
        local state = inst ~= nil and body_api.Valid(inst) or nil
        if state == nil or not state.ready then return end
        local key = tostring(source) .. ":" .. data.identity
        state.remote_speakers = state.remote_speakers or {}
        if data.left == true then
            local actor = state.remote_speakers[key]
            if actor ~= nil then actor.left = true end
            return
        end
        if type(data.id) ~= "string" or #data.id > 100 or type(data.text) ~= "string" or #data.text > 2048
            or type(data.speaker) ~= "table" or type(data.speaker.userid) ~= "string" or #data.speaker.userid > 128
            or type(data.speaker.name) ~= "string" or type(data.world_control) ~= "table" then return end
        if require("my_friend_commands").AddressedMessage(inst, data.text) == nil then return end
        state.remote_seen, state.remote_order = state.remote_seen or {}, state.remote_order or {}
        local event_key = tostring(source) .. ":" .. data.id
        if state.remote_seen[event_key] then return end
        state.remote_seen[event_key], state.remote_order[#state.remote_order + 1] = true, event_key
        if #state.remote_order > 128 then state.remote_seen[table.remove(state.remote_order, 1)] = nil end
        for old, actor in pairs(state.remote_speakers) do
            if actor.left or GetTime() >= actor.expires then state.remote_speakers[old] = nil end
        end
        local count = 0; for _ in pairs(state.remote_speakers) do count = count + 1 end
        local actor = state.remote_speakers[key]
        if actor == nil and count >= 64 then return end
        actor = actor or {_my_friend_remote_speaker = true, key = key, shard = tostring(source), identity = data.identity, userid = data.speaker.userid}
        actor.expires, actor.speaker, actor.world_control = GetTime() + 900, data.speaker, data.world_control
        state.remote_speakers[key] = actor
        body_api.Input(inst, actor, data.text)
    end)
    api.AddShardModRPCHandler("MyFriends", "BodyChatWorld", function(source, payload)
        if TheWorld == nil or not TheWorld.ismastersim or not Online(source) or type(payload) ~= "string" or #payload > 10000 then return end
        local ok, data = pcall(json.decode, payload)
        if not ok or type(data) ~= "table" or type(data.id) ~= "string" or #data.id > 100
            or type(data.args) ~= "table" or not require("my_friend_body_world").SKILLS[data.skill] then return end
        local player
        for _, candidate in ipairs(AllPlayers or {}) do
            if Policy.IsLocalPlayer(candidate) and candidate.userid == data.userid
                and candidate._my_friend_model_chat_identity == data.identity then player = candidate; break end
        end
        if player == nil then Send("BodyChatWorldReply", source, {id = data.id, reason = "speaker_left"}); return end
        local world = TheWorld
        local receipts = world._my_friend_chat_world_receipts or {order = {}, results = {}, inflight = {}}
        world._my_friend_chat_world_receipts = receipts
        local key = tostring(source) .. ":" .. data.id
        if receipts.results[key] ~= nil then Send("BodyChatWorldReply", source, receipts.results[key]); return end
        if receipts.inflight[key] then return end
        receipts.inflight[key] = true
        require("my_friend_body_world").Call(player, data.skill, data.args, function(accepted, result, reason)
            if TheWorld ~= world or not world:IsValid() then return end
            receipts.inflight[key] = nil
            local reply = {id = data.id, accepted = accepted, result = result, reason = reason}
            receipts.order[#receipts.order + 1], receipts.results[key] = key, reply
            if #receipts.order > 64 then receipts.results[table.remove(receipts.order, 1)] = nil end
            Send("BodyChatWorldReply", source, reply)
        end,data.dialogue)
    end)
    api.AddShardModRPCHandler("MyFriends", "BodyChatWorldReply", function(source, payload)
        if type(payload) ~= "string" or #payload > 10000 then return end
        local ok, data = pcall(json.decode, payload)
        local record = ok and type(data) == "table" and pending[data.id] or nil
        if record == nil or tostring(source) ~= record.source then return end
        pending[data.id] = nil; record.timeout:Cancel()
        if TheWorld == record.world and record.world:IsValid() then record.callback(data.accepted == true, data.result, data.reason) end
    end)
end
return M
