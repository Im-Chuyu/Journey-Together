-- Opt-in loopback transport. The local app chooses a model adapter; Lua never executes model code.
local json = require("json")
local API = require("my_friend_body_api")
local M = {}
local ROOT = "http://127.0.0.1:18766/v1/game/"
local serial = 0
local rpc
local pending = {}
local automatic
local dedicated_transport, dedicated_pair_code
local stopped_worlds = setmetatable({}, {__mode = "k"})
local ACTIVE_INTERVAL, IDLE_INTERVAL, EVENT_DELAY = .5, 2, .05
local function Clock() return (GetStaticTime or GetTime)() end
local function Dedicated()
    return TheNet ~= nil and TheNet.IsDedicated ~= nil and TheNet:IsDedicated()
end
local function AdminRelayMode()
    return dedicated_transport == "admin_client" and Dedicated()
end
local function RelayAuthorized(inst, state)
    if not state.admin_relay or require("my_friend_body_world").IsAdmin(state.owner) then return true end
    API.Close(inst, "relay_admin_required")
    return false
end
local function Log(message) print("[MyFriendsBody] " .. message) end
local function Report(status, reason)
    local messages = {
        permission_denied = "无权连接：请开启AI大模型模式，并确认当前分片存在活动伙伴。",
        relay_admin_required = "当前专服仅允许管理员连接本机助手。公屏仍可使用已连接的助手。",
        relay_client_required = "当前专服使用管理员客户端中继。请由同分片管理员在游戏客户端连接助手。",
        companion_missing = "当前分片没有找到活动伙伴。",
        too_far_to_connect = "离伙伴太远，请靠近至20游戏单位内。",
        command_in_progress = "伙伴正在执行原有任务，请先结束任务再连接。",
        already_connected = "伙伴已有连接，无需重复配对。",
        shared_connection = "伙伴已由房间里的助手接入，公屏带伙伴名字即可聊天。",
        invalid_pairing_code = "游戏配对码必须是助手窗口本次显示的六位数字。",
        pairing_code_mismatch = "游戏与助手的配对码不同，已取消本次自动配对。请对齐配对码后重新连接。",
        connecting = "正在连接本机助手，请查看助手的游戏连接状态。",
        connected = "本机助手已连接，游戏与模型任务可互相接替。",
        disconnected = "伙伴接口已断开，原有行为已恢复。",
        request_sent = "连接请求已发往服务器，等待配对结果。",
        invalid_operation = "使用 c_myfriend_ai(\"start\", \"六位码\") 或 c_myfriend_ai(\"stop\")。",
    }
    Log(messages[reason or status] or (tostring(status) .. ": " .. tostring(reason)))
end
local function Cancel(task) if task ~= nil then task:Cancel() end end
local public_sent, public_order = {}, {}
local function ValidPublicText(text)
    if type(text) ~= "string" or text == "" or #text > 1200 or text:find("[%c]") then return false end
    local _, count = text:gsub("[^\128-\191]", "")
    return count <= (MAX_CHAT_INPUT_LENGTH or 150)
end
local function ClientPublicInput(data)
    local player = ThePlayer
    if type(data) ~= "table" or type(data.id) ~= "string" or #data.id > 160
        or not ValidPublicText(data.text) or player == nil or not player:IsValid()
        or data.userid ~= player.userid
        or TheNet == nil or TheNet.Say == nil or public_sent[data.id] then return end
    -- Mark before Say: an echo can arrive synchronously on a listen host.
    public_sent[data.id], public_order[#public_order + 1] = true, data.id
    if #public_order > 64 then public_sent[table.remove(public_order, 1)] = nil end
    local ok, result = pcall(TheNet.Say, TheNet, data.text, false)
    return ok and result ~= false
end
local function SendPublicInput(inst, state, input)
    state.public_echoes = state.public_echoes or {}
    local record = {text = input.text, expires = Clock() + 8, sources = {}}
    state.public_echoes[input.id] = record
    record.timeout = inst:DoStaticTaskInTime(8, function()
        if state.public_echoes == nil or state.public_echoes[input.id] ~= record then return end
        state.public_echoes[input.id] = nil
        if inst:IsValid() and inst._my_friend_body == state and not record.confirmed then
            API.Emit(inst, {kind = "input_broadcast_failed", input_id = input.id})
        end
    end)
    local payload = {id = state.session .. ":public:" .. input.id, text = input.text, userid = state.owner.userid}
    local ok
    if state.owner == ThePlayer then ok = ClientPublicInput(payload)
    else
        ok = pcall(function()
            rpc.SendModRPCToClient(rpc.GetClientModRPC("MyFriends", "BodyPublicInput"), {state.owner.userid}, json.encode(payload))
        end)
    end
    if not ok then
        Cancel(record.timeout)
        state.public_echoes[input.id] = nil
        API.Emit(inst, {kind = "input_broadcast_failed", input_id = input.id})
    end
end
local function Notify(player, status, reason, attempt)
    if player == ThePlayer then
        if automatic ~= nil then automatic:Result(status, reason, attempt) end
        Report(status, reason)
    elseif rpc ~= nil and player ~= nil and player:IsValid() and type(player.userid) == "string" then
        rpc.SendModRPCToClient(rpc.GetClientModRPC("MyFriends", "BodyEvent"), {player.userid},
            json.encode({status = status, reason = reason, attempt = attempt}))
    end
end
local function DecodeResponse(path, body, successful, code, limit, failure)
    if path == "connect" and code == 403 then return nil, "pairing_code_mismatch" end
    if type(body) == "string" and #body <= limit and (code == 200 or path == "connect" and code == 400) then
        local ok, value = pcall(json.decode, body)
        if ok and type(value) == "table" then
            if code == 200 and successful then return value end
            if path == "connect" and value.error == "配对码不正确" then return nil, "pairing_code_mismatch" end
        end
    end
    return nil, failure
end
local function Post(inst, state, path, payload, callback)
    local done = false
    local relay_id
    local function Finish(reply, reason)
        if done then return end
        done = true
        if relay_id ~= nil then pending[relay_id] = nil end
        callback(reply, reason)
    end
    local timer = inst:DoStaticTaskInTime(8, function()
        if done then return end
        Finish(nil, "timeout")
    end)
    if state.relay_owner ~= nil then
        serial = serial + 1
        relay_id = state.session .. ":http:" .. serial
        pending[relay_id] = {owner = state.relay_owner, state = state, inst = inst,
            closing = payload.closing ~= nil, callback = function(reply, reason)
            Cancel(timer); Finish(reply, reason)
        end}
        local ok = pcall(function()
            local packet = json.encode({id = relay_id, path = path, payload = payload})
            if #packet > 60000 then error("relay_payload_too_large") end
            rpc.SendModRPCToClient(rpc.GetClientModRPC("MyFriends", "BodyRelay"), {state.relay_owner.userid},
                packet)
        end)
        if not ok then Cancel(timer); Finish(nil, "client_relay_error") end
        return timer
    end
    local ok = pcall(function()
        TheSim:QueryServer(ROOT .. path, function(body, successful, code)
            if done then return end
            done = true; Cancel(timer)
            callback(DecodeResponse(path, body, successful, code, 32768, "http_or_protocol_error"))
        end, "POST", json.encode(payload))
    end)
    if not ok and not done then done = true; Cancel(timer); callback(nil, "http_api_error") end
    return timer
end
local function Clean(value, depth)
    if value == json.null then return nil end
    if type(value) ~= "table" then return value end
    if depth > 8 then return {} end
    local out, count = {}, 0
    for key, entry in pairs(value) do
        count = count + 1; if count > (type(key) == "number" and 100 or 40) then break end
        if type(key) == "string" or type(key) == "number" then out[key] = Clean(entry, depth + 1) end
    end
    return out
end
local Poll
local function Schedule(inst, state, delay)
    Cancel(state.poll)
    local task
    task = inst:DoStaticTaskInTime(delay, function()
        if state.poll ~= task then return end
        state.poll = nil
        state.flush_scheduled = false
        if inst:IsValid() and inst._my_friend_body == state then Poll(inst, state) end
    end)
    state.poll = task
end
local function FlushDelay(state)
    -- Coalesce bursts and keep the existing maximum of two exchanges/second.
    return math.max(EVENT_DELAY, ACTIVE_INTERVAL - (Clock() - (state.last_exchange or -math.huge)))
end
local function RequestFlush(inst, state)
    if state.transport_closed or not inst:IsValid() or inst._my_friend_body ~= state then return end
    state.flush_pending = true
    state.transport_active_until = Clock() + IDLE_INTERVAL
    if state.ready and state.token ~= nil and not state.exchanging and not state.flush_scheduled
        and (state.failures or 0) == 0 then
        Schedule(inst, state, FlushDelay(state))
        state.flush_scheduled = true
    end
end
local function PollInterval(inst, state)
    if state.active ~= nil or state.pending ~= nil or API.PlanActive(inst)
        or next(state.inputs) ~= nil or #state.events > 0
        or GetTime() < (inst._my_friend_body_speaking or 0)
        or Clock() < (state.transport_active_until or 0) then return ACTIVE_INTERVAL end
    return IDLE_INTERVAL
end
Poll = function(inst, state)
    if state.transport_closed or state.exchanging then return end
    if not RelayAuthorized(inst, state) then return end
    state.exchanging, state.last_exchange = true, Clock()
    API.Tick(inst)
    if inst._my_friend_body ~= state then return end
    if GetTime() >= (state.next_context or math.huge) then
        state.next_context = GetTime() + math.random(60, 120)
        API.Observation.RefreshEnvironment(inst, state)
        API.Emit(inst, {kind = "ambient_context"})
    elseif state.environment == nil then
        API.Observation.RefreshEnvironment(inst, state)
    end
    local snapshot = API.Observation.Snapshot(inst, state)
    local request_revision = state.revision
    local signature = json.encode(snapshot)
    local events = {}; for i = 1, math.min(12, #state.events) do events[#events + 1] = state.events[i] end
    state.flush_pending = false
    local timeout = Post(inst, state, "exchange", {token = state.token, session = state.session,
        snapshot = signature ~= state.snapshot_signature and snapshot or nil, events = events}, function(reply, reason)
        state.http_timeout = nil
        if not inst:IsValid() or inst._my_friend_body ~= state then return end
        if reply == nil then
            state.exchanging = false
            state.failures = (state.failures or 0) + 1
            if state.failures >= 3 then Log("Disconnected: " .. tostring(reason)); API.Close(inst, "bridge_unavailable"); return end
            Schedule(inst, state, 1); return
        end
        if reply.closed then API.Close(inst, "assistant_stopped"); return end
        if not state.ready then
            state.ready = true
            if not state.dedicated then Notify(state.owner, "connected", nil, state.connection_attempt) end
            Log("Connected to local assistant.")
        end
        state.failures, state.snapshot_signature = 0, signature
        if type(reply.playback) == "table" then for i = 1, math.min(40, #reply.playback) do
            local entry = reply.playback[i]
            if type(entry) == "table" and type(entry.action_id) == "string" then API.Playback(inst, entry.action_id, entry.status) end
        end end
        local ack = {}
        if type(reply.ack) == "table" then for i = 1, math.min(64, #reply.ack) do ack[reply.ack[i]] = true end end
        for i = #state.events, 1, -1 do if ack[state.events[i].event_id] then table.remove(state.events, i) end end
        if type(reply.inputs) == "table" then for i = 1, math.min(8, #reply.inputs) do
            local input = reply.inputs[i]
            if type(input) == "table" and type(input.id) == "string" and #input.id <= 80
                and not state.input_requests[input.id] then
                state.input_requests[input.id] = true
                state.input_request_order = state.input_request_order or {}
                state.input_request_order[#state.input_request_order + 1] = input.id
                if #state.input_request_order > 64 then state.input_requests[table.remove(state.input_request_order, 1)] = nil end
                local accepted, why
                if input.broadcast ~= nil and type(input.broadcast) ~= "boolean" then
                    accepted, why = false, "invalid_broadcast"
                elseif input.broadcast and not ValidPublicText(input.text) then
                    accepted, why = false, "invalid_public_text"
                elseif input.broadcast and (state.owner == ThePlayer and (TheNet == nil or TheNet.Say == nil)
                    or state.owner ~= ThePlayer and (rpc == nil or rpc.SendModRPCToClient == nil or rpc.GetClientModRPC == nil)) then
                    accepted, why = false, "public_chat_unavailable"
                else
                    accepted, why = API.Input(inst, state.owner, input.text, input.id, false)
                end
                if not accepted then API.Emit(inst, {kind = "input_rejected", input_id = input.id, reason = why}) end
                if accepted and input.broadcast then SendPublicInput(inst, state, input) end
            end
        end end
        if type(reply.commands) == "table" then for i = 1, math.min(4, #reply.commands) do
            local command = reply.commands[i]
            if type(command) == "table" and type(command.request_id) == "string" and #command.request_id <= 80 then
                local cached = state.requests[command.request_id] ~= nil
                local ok, result
                if command.source == "user" and command.turn_id == nil then ok, result = true, {status = "failed", reason = "invalid_input_context"}
                else ok, result = pcall(API.Call, inst, state.owner, command.request_id, command.skill,
                    Clean(command.arguments or {}, 0), command.revision ~= nil and command.revision or request_revision, command.source, command.plan_id, command.turn_id) end
                result = ok and result or {status = "failed", reason = "internal_error"}
                if command.skill == "get_action_status" or command.skill == "cancel" then result = {status = "completed", result = result} end
                -- New jobs already publish their own receipt. Replays and
                -- immediate control/error responses need an explicit receipt.
                if cached or result.request_id ~= command.request_id then
                    API.Emit(inst, {request_id = command.request_id, action_id = result.action_id,
                        skill = command.skill, status = result.status, result = result.result, reason = result.reason})
                end
            end
        end end
        if type(reply.finished_inputs) == "table" then for i = 1, math.min(64, #reply.finished_inputs) do
            local id = reply.finished_inputs[i]
            if type(id) == "string" then state.inputs[id] = nil end
        end end
        API.UpdatePlan(inst, reply.plan)
        state.exchanging = false
        if inst._my_friend_body == state then
            local delay = state.flush_pending and FlushDelay(state) or PollInterval(inst, state)
            Schedule(inst, state, delay)
            state.flush_scheduled = state.flush_pending
        end
    end)
    -- QueryServer may invoke its callback synchronously; do not retain a
    -- completed timeout or overwrite a new exchange started by that callback.
    if state.exchanging then state.http_timeout = timeout end
end
function M.Connect(inst, player, code, relay, attempt, dedicated)
    if type(code) ~= "string" or not code:match("^%d%d%d%d%d%d$") then return false, "invalid_pairing_code" end
    local admin_relay = AdminRelayMode()
    if admin_relay then
        if not relay then return false, "relay_client_required" end
        if not require("my_friend_body_world").IsAdmin(player) then return false, "relay_admin_required" end
        if code ~= dedicated_pair_code then return false, "pairing_code_mismatch" end
    end
    local existing = inst ~= nil and inst._my_friend_body or nil
    if existing ~= nil and existing.owner == player and API.CanConnect(inst, player) then
        existing.connection_attempt = attempt
        if not dedicated then Notify(player, existing.ready and "connected" or "connecting", nil, attempt) end
        return true
    end
    if existing ~= nil and existing.ready and API.Valid(inst) == existing and API.CanConnect(inst, player) then
        if not dedicated then
            existing.observers = existing.observers or {}
            existing.observers[player] = attempt or false
            Notify(player, "connected", "shared_connection", attempt)
        end
        return true
    end
    local state, reason = API.Open(inst, player)
    if state == nil then return false, reason end
    state.connection_attempt = attempt
    state.relay_owner = relay and player or nil
    state.admin_relay = admin_relay
    state.dedicated = dedicated == true
    state.on_emit = function() RequestFlush(inst, state) end
    local world = TheWorld
    state.cleanup = function(why)
        state.transport_closed, state.on_emit = true, nil
        state.exchanging, state.flush_pending, state.flush_scheduled = false, false, false
        Cancel(state.poll); Cancel(state.http_timeout)
        state.poll, state.http_timeout = nil, nil
        for _, record in pairs(state.public_echoes or {}) do Cancel(record.timeout) end
        state.public_echoes = nil
        for id, record in pairs(pending) do
            if record.state == state then pending[id] = nil end
        end
        if state.token ~= nil and inst:IsValid() then
            -- Best-effort final receipts let the app stop its plan when a
            -- manual command takes control. Late responses cannot issue actions.
            Post(inst, state, "exchange", {token = state.token, session = state.session,
                events = state.events, closing = why}, function() end)
        end
        if state.dedicated then
            if why == "pairing_code_mismatch" then stopped_worlds[world] = true end
            if state.ready or why == "pairing_code_mismatch" then Report("disconnected", why) end
        else
            Notify(player, "disconnected", why, state.connection_attempt)
        end
        for observer, observer_attempt in pairs(state.observers or {}) do
            if observer:IsValid() then Notify(observer, "disconnected", why, observer_attempt or nil) end
        end
    end
    state.http_timeout = Post(inst, state, "connect", {code = code, session = state.session,
        capabilities = API.NAMES, input_protocol = 2, companion = inst.prefab, owner = player:GetDisplayName()}, function(reply, err)
        state.http_timeout = nil
        if not inst:IsValid() or inst._my_friend_body ~= state then return end
        if reply == nil or type(reply.token) ~= "string" or #reply.token > 128 then
            API.Close(inst, err or "pairing_failed")
            if not state.dedicated and err ~= "pairing_code_mismatch" then Log("Pairing failed; check the local app and code.") end
            return
        end
        state.token = reply.token
        Poll(inst, state)
    end)
    return true
end
local function DedicatedOwner(friend)
    local leader = require("my_friend_policy").GetLeader(friend)
    if API.CanConnect(friend, leader) then return leader end
    for _, player in ipairs(AllPlayers or {}) do
        if API.CanConnect(friend, player) then return player end
    end
end

function M.TryDedicated(friend, code)
    local world = TheWorld
    if not Dedicated() or AdminRelayMode() or world == nil or not world.ismastersim or stopped_worlds[world]
        or friend == nil or friend._my_friend_body ~= nil then return end
    local now = (GetStaticTime or GetTime)()
    if now < (world._my_friend_dedicated_pair_after or 0) then return end
    local player = DedicatedOwner(friend)
    if player == nil then return end
    world._my_friend_dedicated_pair_after = now + 10
    return M.Connect(friend, player, code, false, nil, true)
end

function M.Control(operation, code, from_automatic, attempt)
    operation = operation == "start" and "connect" or operation == "stop" and "disconnect" or operation
    if operation == "disconnect" and not from_automatic then
        if TheWorld ~= nil then stopped_worlds[TheWorld] = true end
        if automatic ~= nil then automatic:Stop() end
    elseif operation == "connect" and not from_automatic and TheWorld ~= nil then stopped_worlds[TheWorld] = nil end
    if operation ~= "connect" and operation ~= "disconnect" then Report("failed", "invalid_operation"); return false end
    if operation == "connect" and (type(code) ~= "string" or not code:match("^%d%d%d%d%d%d$")) then
        Report("failed", "invalid_pairing_code"); return false
    end
    -- A listen host already owns the authoritative body and local HTTP app.
    -- Sending a client RPC to itself fails on offline/listen-host sessions.
    if TheWorld ~= nil and TheWorld.ismastersim then
        local friend = TheWorld._my_friend
        if friend == nil then Notify(ThePlayer, "failed", "companion_missing", attempt); return false end
        local dedicated = Dedicated()
        local player = ThePlayer or require("my_friend_policy").GetLeader(friend)
        if dedicated then
            local state = friend._my_friend_body
            player = state ~= nil and state.owner or DedicatedOwner(friend)
        end
        if operation == "connect" then
            local accepted, reason = M.Connect(friend, player, code, nil, attempt, dedicated)
            if dedicated then Report(accepted and "connecting" or "failed", reason)
            else Notify(player, accepted and "connecting" or "failed", reason, attempt) end
            return accepted, reason
        end
        if not API.CanConnect(friend, player) or friend._my_friend_body ~= nil and friend._my_friend_body.owner ~= player then Report("failed", "permission_denied"); return false end
        API.Close(friend, "user_disconnected"); Report("disconnected"); return true
    end
    rpc.SendModRPCToServer(rpc.GetModRPC("MyFriends", "BodyControl"), operation, json.encode({code = code, attempt = attempt}))
    Report("request_sent")
    return true
end
function M.AttachAuto(player, enabled, code)
    if not enabled or player._my_friend_auto_model_attached or player:HasTag("my_friend") then return end
    player._my_friend_auto_model_attached = true
    local world = TheWorld
    local activate
    activate = function()
        if player ~= ThePlayer or TheWorld ~= world or stopped_worlds[world] or not player:IsValid() then return end
        player:RemoveEventCallback("playeractivated", activate, world)
        if automatic ~= nil then automatic:Stop() end
        automatic = require("my_friend_body_autoconnect").New(player, code, function(value, attempt)
            if player ~= ThePlayer or TheWorld ~= world then return false end
            return M.Control("start", value, true, attempt)
        end, function(failures, delay)
            Log("自动连接失败" .. failures .. "次；" .. (delay ~= nil and (delay .. "秒后重试。") or "本次世界不再自动重试。"))
        end)
        player:ListenForEvent("onremove", function()
            if automatic ~= nil and automatic.player == player then automatic:Stop(); automatic = nil end
        end)
    end
    player:ListenForEvent("playeractivated", activate, world)
    player:DoStaticTaskInTime(1, activate)
end
function M.Install(api, enabled, options)
    dedicated_transport = options ~= nil and options.dedicated_transport or nil
    dedicated_pair_code = options ~= nil and options.pair_code or "321151"
    rpc = enabled ~= false and api or nil
    if enabled == false then
        -- DST assigns numeric IDs by registration order. Keep disabled model
        -- handlers in the same slots so other MyFriends RPCs still line up.
        local function Ignore() end
        local function Reserve(register)
            if register == nil then return end
            return function(namespace, name) register(namespace, name, Ignore) end
        end
        api = {
            AddModRPCHandler = Reserve(api.AddModRPCHandler),
            AddClientModRPCHandler = Reserve(api.AddClientModRPCHandler),
            AddShardModRPCHandler = Reserve(api.AddShardModRPCHandler),
        }
    end
    require("my_friend_body_world").Install(api)
    require("my_friend_body_chat").Install(api)
    api.AddClientModRPCHandler("MyFriends", "BodyPublicInput", function(payload)
        if type(payload) ~= "string" or #payload > 4096 then return end
        local ok, data = pcall(json.decode, payload)
        if ok then ClientPublicInput(data) end
    end)
    api.AddModRPCHandler("MyFriends", "BodyRelayReply", function(player, payload)
        if type(payload) ~= "string" or #payload > 32768 then return end
        local ok, data = pcall(json.decode, payload)
        if not ok or type(data) ~= "table" or type(data.id) ~= "string" then return end
        local record = pending[data.id]
        if record == nil or record.owner ~= player or not player:IsValid() or not record.inst:IsValid() then return end
        if not record.closing and (record.inst._my_friend_body ~= record.state or not API.CanConnect(record.inst, player)) then return end
        if not record.closing and not RelayAuthorized(record.inst, record.state) then return end
        record.callback(type(data.reply) == "table" and data.reply or nil, data.reason)
    end)
    api.AddClientModRPCHandler("MyFriends", "BodyRelay", function(payload)
        if type(payload) ~= "string" or #payload > 65536 then return end
        local ok, data = pcall(json.decode, payload)
        if not ok or type(data) ~= "table" or type(data.id) ~= "string" or #data.id > 160
            or not ({connect = true, exchange = true})[data.path] or type(data.payload) ~= "table" then return end
        local world = TheWorld
        local closing = data.payload.closing ~= nil
        local function Reply(value, reason)
            if TheWorld ~= world or world == nil or not world:IsValid() then return end
            api.SendModRPCToServer(api.GetModRPC("MyFriends", "BodyRelayReply"),
                json.encode({id = data.id, reply = value, reason = reason, closing = closing}))
        end
        local success = pcall(function()
            TheSim:QueryServer(ROOT .. data.path, function(body, successful, code)
                Reply(DecodeResponse(data.path, body, successful, code, 30000, "client_http_error"))
            end, "POST", json.encode(data.payload))
        end)
        if not success then Reply(nil, "client_http_api_error") end
    end)
    api.AddModRPCHandler("MyFriends", "BodyControl", function(player, operation, payload)
        if type(operation) ~= "string" or type(payload) ~= "string" or #payload > 4096 then return end
        local friend = TheWorld ~= nil and TheWorld._my_friend or nil
        local ok, args = pcall(json.decode, payload)
        if not ok or type(args) ~= "table" then return end
        if args.attempt ~= nil and (type(args.attempt) ~= "number" or args.attempt < 1 or args.attempt > 1000000 or args.attempt % 1 ~= 0) then return end
        if friend == nil or not API.CanConnect(friend, player) then
            if player ~= nil and player:IsValid() and type(player.userid) == "string" then
                api.SendModRPCToClient(api.GetClientModRPC("MyFriends", "BodyEvent"), {player.userid},
                    json.encode({status = "failed", reason = friend == nil and "companion_missing" or "permission_denied", attempt = args.attempt}))
            end
            return
        end
        local result
        if operation == "connect" then
            local accepted, reason = M.Connect(friend, player, args.code, true, args.attempt)
            result = {status = accepted and "connecting" or "failed", reason = reason, attempt = args.attempt}
        elseif operation == "disconnect" then
            local state = friend._my_friend_body
            if state ~= nil and (state.owner ~= player or state.dedicated) then return end
            API.Close(friend, "user_disconnected"); result = {status = "disconnected"}
        elseif operation == "call" then
            serial = serial + 1
            result = API.Call(friend, player, "console:" .. GetTime() .. ":" .. serial, args.skill, Clean(args.arguments or {}, 0))
        else return end
        api.SendModRPCToClient(api.GetClientModRPC("MyFriends", "BodyEvent"), {player.userid}, json.encode(result))
    end)
    api.AddClientModRPCHandler("MyFriends", "BodyEvent", function(payload)
        if type(payload) ~= "string" or #payload > 32768 then return end
        local ok, data = pcall(json.decode, payload)
        if ok and type(data) == "table" then
            if automatic ~= nil then automatic:Result(data.status, data.reason, data.attempt) end
            Report(data.status, data.reason)
        end
    end)
end
return M
