-- Offline exchange ownership. Only records in possessions hold the companion
-- slot. Claims belong to individual users and never point at the live AI.
local Wire = require("my_friend_possession_transport")
local M = {grace = 15 * 60}
local hooks

local function Shard()
    return tostring(TheShard:GetShardId())
end

local function State()
    local world = TheWorld
    if world._my_friend_returns == nil then
        world._my_friend_returns = {claims = {}, away = {}, receipts = {}}
    end
    return world._my_friend_returns
end

local function Session(userid)
    return (TheWorld._my_friend_possessions or {})[userid]
end

local function Cancel(userid)
    local tasks = TheWorld._my_friend_return_tasks
    if tasks ~= nil and tasks[userid] ~= nil then
        tasks[userid]:Cancel()
        tasks[userid] = nil
    end
end

local Check, RemoteVisit
local function Schedule(userid, delay)
    local world = TheWorld
    Cancel(userid)
    world._my_friend_return_tasks = world._my_friend_return_tasks or {}
    local tasks = world._my_friend_return_tasks
    tasks[userid] = world:DoStaticTaskInTime(math.max(0, delay), function()
        tasks[userid] = nil
        Check(userid)
    end)
end

function M.Token(sess)
    if sess.exchange_token == nil then
        sess.exchange_token = table.concat({sess.userid, Shard(), sess.companion_id or "",
            tostring(os.time()), tostring(GetTime())}, ":")
    end
    return sess.exchange_token
end

local function Deadline(record)
    record.offline_until = record.offline_until or os.time() + (record.grace or M.grace)
    return record.offline_until
end

local function Available(player)
    return player ~= nil and player:IsValid() and not player._despawning
        and not player.is_snapshot_user_session and not player:HasTag("my_friend")
end

-- The two shards save independently. Retain an acknowledgement until the
-- producer confirms it, including across a disconnect or world restart.
local function SendReceipt(token)
    local world = TheWorld
    local receipt = State().receipts[token]
    if not receipt then return end
    world._my_friend_receipt_tasks = world._my_friend_receipt_tasks or {}
    local tasks = world._my_friend_receipt_tasks
    if tasks[token] then return end
    tasks[token] = world:DoStaticTaskInTime(20, function()
        tasks[token] = nil
        SendReceipt(token)
    end)
    Wire.Send(receipt.home, "claimed", receipt.userid, token)
end

local function Complete(userid, token, home)
    local state = State()
    state.claims[userid], state.away[userid] = nil, nil
    if home then
        state.receipts[token] = {userid = userid, home = home}
        SendReceipt(token)
    end
end

local function FinishClaim(player, claim)
    local traveller = player.components.my_friend_traveller
    if traveller == nil then return false end
    if traveller.return_receipt ~= claim.token then
        local ok, applied = pcall(hooks.apply, player, claim)
        if not ok then
            if not player._my_friend_return_error then print("[MyFriends] Body return deferred: " .. tostring(applied)) end
            player._my_friend_return_error = true
        end
        if not ok or not applied then return false end
        player._my_friend_return_error = nil
        traveller.exchange_route = nil
        traveller.return_receipt = claim.token
    end
    -- If serialization throws, retry the save without applying the body twice.
    if not pcall(SerializeUserSession, player) then return false end
    Complete(player.userid, claim.token, claim.home)
    if player._my_friend_return_waiting and player.components.playercontroller ~= nil then
        player.components.playercontroller:Enable(true)
    end
    player._my_friend_return_waiting = nil
    return true
end

local function Hold(player)
    player._my_friend_return_waiting = true
    if player.components.playercontroller ~= nil and player.player_classified ~= nil then
        player.components.playercontroller:Enable(false)
    end
end

local function LegacyBody(prefab, d, original, borrowed)
    local main = d and d.seamlessplayerswapper and d.seamlessplayerswapper.main_data
    if not main or main.prefab ~= original or prefab ~= borrowed
        or d.migration or d.my_friend_companion or type(d.health) ~= "table" then return end
    return {inv = d.inventory, skill_data = d.skilltreeupdater,
        meters = {ghost = d.is_ghost or d.health.health == 0,
            native_health = d.health, native_hunger = d.hunger, native_sanity = d.sanity},
        wx78 = d.upgrademoduleowner and {modules = d.upgrademoduleowner, sockets = d.socketholder},
        abigail = d.ghostlybond and {bond = d.ghostlybond}}
end

local function ReadLegacyBody(userid, original, borrowed, callback)
    local world = TheWorld
    local file = TheNet:GetUserSessionFile(world.meta.session_identifier, userid)
    if not file then return end
    TheNet:DeserializeUserSession(file, function(success, text)
        if not success or type(text) ~= "string" or world ~= TheWorld or hooks.online(userid) then return end
        local ok, saved = RunInSandboxSafe(text)
        if not ok or type(saved) ~= "table" or type(saved.data) ~= "table" then return end
        local body = LegacyBody(saved.prefab, saved.data, original, borrowed)
        if body then callback(body, saved.prefab, saved.data.skinner) end
    end)
end

local function LocatePreviousOwner(userid, sess)
    local peers = {}
    for id in pairs(TheWorld._my_friend_known_shards or {}) do peers[tostring(id)] = true end
    for id in pairs(Shard_GetConnectedShards()) do peers[tostring(id)] = true end
    peers[Shard()] = nil
    local first = next(peers)
    local single = first ~= nil and next(peers, first) == nil
    sess.legacy_deadline = sess.legacy_deadline or os.time() + M.grace
    for id in pairs(peers) do
        Wire.Send(id, "locate", userid, M.Token(sess), {single = single, deadline = sess.legacy_deadline,
            original = sess.player_prefab, borrowed = sess.active_prefab or sess.companion_prefab})
    end
end

Check = function(userid)
    local state = State()
    local player = hooks.online(userid)
    local claim = state.claims[userid]
    if claim ~= nil then
        if claim.destination == nil and Available(player) then
            Hold(player)
            if not FinishClaim(player, claim) then Schedule(userid, 1) end
        end
        return
    end
    local away = state.away[userid]
    local sess = Session(userid)
    if sess and sess.player_migrated and not sess.remote_shard then
        LocatePreviousOwner(userid, sess)
        Schedule(userid, 30)
        return
    end
    local record = away or sess
    if record == nil then return end
    if record.selecting then
        if Available(player) or TheNet:GetClientTableForUser(userid) then
            Schedule(userid, 5)
            return
        end
        record.selecting = nil
        Deadline(record)
    end
    if record.offline_until == nil then return end
    local remaining = record.offline_until - os.time()
    if remaining > 0 then Schedule(userid, remaining) return end
    if not away and sess and not sess.active_body and not sess.player_migrated then
        ReadLegacyBody(userid, sess.player_prefab, sess.companion_prefab, function(body, prefab, skin)
            if Session(userid) == sess and not sess.active_body then
                sess.active_body, sess.active_prefab, sess.active_skin_data = body, prefab, skin
                Schedule(userid, 0)
            end
        end)
        if not sess.active_body then Schedule(userid, 30) return end
    end
    if Available(player) then Hold(player) end
    if away ~= nil then
        away.committed = true
        away.borrowed.first_shard = away.first_shard
        Wire.Send(away.home, "expired", userid, away.token, away.borrowed)
        Schedule(userid, 12)
    elseif not sess.player_migrated and hooks.settle(sess) then
        if Available(player) then Schedule(userid, 0) end
    else
        Schedule(userid, 2)
    end
end

function M.Save(world, data)
    local state = State()
    -- Save an up-to-date remote body if the server stops while its owner is
    -- still online. A loaded online snapshot gets a fresh grace period.
    for userid, away in pairs(state.away) do
        local player = hooks.online(userid)
        if Available(player) and not away.committed and not away.offline_until and not player._my_friend_return_waiting then
            away.borrowed = hooks.capture(player)
        end
    end
    if next(state.away) or next(state.claims) or next(state.receipts) then data.my_friend_body_returns = state end
end

function M.Load(world, data)
    local saved = data and data.my_friend_body_returns or {}
    world._my_friend_returns = {claims = saved.claims or {}, away = saved.away or {}, receipts = saved.receipts or {}}
end

function M.Start(world)
    for token in pairs(State().receipts) do SendReceipt(token) end
    for userid, sess in pairs(world._my_friend_possessions or {}) do
        -- Old saves recorded a solo migration without a destination or final
        -- inventory. Attach the next real owner on the other shard; never
        -- release from the obsolete pre-migration inventory.
        if sess.player_migrated and not sess.remote_shard then
            Schedule(userid, 0)
        end
        if not sess.player_migrated and (sess.active_body or sess.player_body) and not hooks.online(userid) then
            Schedule(userid, sess.selecting and 0 or Deadline(sess) - os.time())
        end
    end
    for userid, away in pairs(State().away) do
        if away.borrowed ~= nil and (away.committed or not hooks.online(userid)) then
            Schedule(userid, away.selecting and 0 or Deadline(away) - os.time())
        end
    end
end

function M.Leave(player, sess)
    local userid = player.userid
    if userid == nil or player._my_friend_migrating then return end
    RemoteVisit(player)
    local away = State().away[userid]
    if sess ~= nil and not sess.player_migrated and sess.active_body ~= nil then
        sess.selecting = player._my_friend_rerolling or nil
        Schedule(userid, sess.selecting and 5 or Deadline(sess) - os.time())
    elseif away ~= nil and not away.committed and not player._my_friend_return_waiting then
        away.borrowed = hooks.capture(player)
        away.selecting = player._my_friend_rerolling or nil
        Schedule(userid, away.selecting and 5 or Deadline(away) - os.time())
    end
end

function M.Migrate(player, sess, destination)
    local traveller = player.components.my_friend_traveller
    if traveller == nil or player.userid == nil then return end
    if sess ~= nil then
        -- The AI did not travel with its owner. The native migration record
        -- carries a routing ticket, not a second copy of either inventory.
        traveller.exchange_route = {userid = player.userid, home = Shard(), token = M.Token(sess),
            first_shard = tostring(destination), grace = M.grace}
        sess.remote_shard = tostring(destination)
        sess.player_migrated = true
        sess.offline_until = nil
    elseif traveller.possession ~= nil then
        traveller.exchange_route = nil
    end
    local away = State().away[player.userid]
    if away ~= nil and not away.committed then State().away[player.userid] = nil end
    Cancel(player.userid)
end

RemoteVisit = function(player)
    local traveller = player.components.my_friend_traveller
    if traveller == nil then return end
    local away = State().away[player.userid]
    if traveller.exchange_route == nil and away ~= nil and not away.committed then
        traveller.exchange_route = {userid = player.userid, home = away.home, token = away.token,
            first_shard = away.first_shard, grace = away.grace}
    end
    local route = traveller.exchange_route
    if type(route) ~= "table" or route.userid ~= player.userid or type(route.home) ~= "string"
        or type(route.token) ~= "string" or route.token == "" then return end
    if route.home == Shard() then
        traveller.exchange_route = nil
    elseif not State().away[player.userid] then
        State().away[player.userid] = {token = route.token, home = route.home,
            first_shard = route.first_shard, grace = type(route.grace) == "number" and route.grace or nil}
    end
end

function M.Join(player)
    if not Available(player) or not player.userid or player.userid == "" then return false end
    local userid = player.userid
    RemoteVisit(player)
    local state = State()
    local claim = state.claims[userid]
    local away = state.away[userid]
    local sess = Session(userid)
    local record = away or sess
    if claim and not claim.destination or away and away.committed
        or record and record.offline_until and record.offline_until <= os.time() then
        Hold(player)
        Schedule(userid, 0)
        return true
    end
    if record then record.offline_until, record.selecting = nil, nil end
    Cancel(userid)
    return false
end

function M.PrepareLogin(player, data)
    if data == nil or not player.userid then return data end
    local userid = player.userid
    local state = State()
    local claim = state.claims[userid]
    local away = state.away[userid]
    local travel = data.my_friend_traveller
    local expected = claim or away
    if expected and travel and travel.return_receipt == expected.token then
        -- Player save reached disk before the matching world snapshot.
        if not player.is_snapshot_user_session then Complete(userid, expected.token, expected.home) end
        return data
    end
    local sess = Session(userid)
    if sess and not sess.active_body and not sess.player_migrated and not player.is_snapshot_user_session
        and sess.offline_until then
        local body = LegacyBody(player.prefab, data, sess.player_prefab, sess.companion_prefab)
        if body then
            sess.active_body, sess.active_prefab, sess.active_skin_data = body, player.prefab, data.skinner
        else
            -- This is the first authoritative login for an ambiguous old
            -- save. Let native loading complete before taking its snapshot.
            sess.offline_until = nil
        end
    end
    if sess and not sess.player_migrated and sess.exchange_token and travel
        and travel.return_receipt == sess.exchange_token then
        -- The player file may even be newer than a world snapshot taken
        -- before settlement. Finish the world half, preserving this inventory.
        if not player.is_snapshot_user_session then
            sess.offline_until = os.time()
            Hold(player)
            Schedule(userid, 0)
        end
        return data
    end
    if player.is_snapshot_user_session then
        -- Snapshot replay spawns/despawns a fake player. Never load a second
        -- set of items here or let that player cancel a deadline/collect a claim.
        if not (claim and not claim.destination or away and away.committed) then return data end
    elseif not M.Join(player) then
        return data
    end
    -- Never instantiate the stale borrowed inventory (or its bell's beefalo)
    -- even for one frame. Carry the account's progress through native swap.
    return {age = data.age, builder = data.builder, petleash = data.petleash,
        maprecorder = data.maprecorder, seamlessplayerswapper = data.seamlessplayerswapper,
        migration = data.migration}
end

function M.Pending(player)
    local state = State()
    local claim = state.claims[player.userid]
    local away = state.away[player.userid]
    return player._my_friend_return_waiting or claim ~= nil or away ~= nil and away.committed
end

function M.StoreClaim(sess, claim)
    claim.token = M.Token(sess)
    State().claims[sess.userid] = claim
end

function M.Expects(source, kind, userid, token)
    local state = State()
    local claim = state.claims[userid]
    if kind == "locate" then return not claim and not Session(userid) end
    if kind == "located" then
        local sess = Session(userid)
        return sess and sess.player_migrated and sess.exchange_token == token
    end
    if kind == "done" then
        local receipt = state.receipts[token]
        return receipt and receipt.home == source and receipt.userid == userid
    end
    if kind == "claimed" then return true end -- duplicates receive a terminal reply
    if kind == "body" then
        local away = state.away[userid]
        return away and away.committed and away.home == source and away.token == token
    end
    if kind == "expired" then
        if claim then return claim.destination == source and claim.token == token end
        local sess = Session(userid)
        return sess and sess.player_migrated and sess.exchange_token == token and not hooks.online(userid)
    end
    return false
end

local function Locate(source, userid, token, request)
    if type(request.original) ~= "string" or type(request.borrowed) ~= "string"
        or type(request.deadline) ~= "number" then return end
    local state = State()
    local existing = state.away[userid]
    if existing then
        if existing.home == source and existing.token == token then Wire.Send(source, "located", userid, token) end
        return
    end
    local player = hooks.online(userid)
    if player then
        local traveller = player.components.my_friend_traveller
        local swapper = player.components.seamlessplayerswapper
        if not traveller or not swapper or swapper.main_data.prefab ~= request.original then return end
        traveller.exchange_route = {userid = userid, home = source, token = token}
        RemoteVisit(player)
        Wire.Send(source, "located", userid, token)
        return
    end
    -- Before routing tickets existed, only a single possible destination
    -- plus a matching, non-departing native user session identifies the body.
    if not request.single then return end
    ReadLegacyBody(userid, request.original, request.borrowed, function(body, prefab, skin)
        if state ~= State() or state.away[userid] or state.claims[userid] or Session(userid) then return end
        state.away[userid] = {token = token, home = source, offline_until = request.deadline,
            borrowed = {body = body, prefab = prefab, skin = skin}}
        Schedule(userid, request.deadline - os.time())
        Wire.Send(source, "located", userid, token)
    end)
end

function M.Message(source, kind, userid, token, data)
    local state = State()
    if kind == "locate" then
        Locate(source, userid, token, data)
    elseif kind == "located" then
        Session(userid).remote_shard = source
    elseif kind == "claimed" then
        local claim = state.claims[userid]
        if claim and claim.destination == source and claim.token == token then state.claims[userid] = nil end
        Wire.Send(source, "done", userid, token)
    elseif kind == "done" then
        state.receipts[token] = nil
        local tasks = TheWorld._my_friend_receipt_tasks
        if tasks and tasks[token] then tasks[token]:Cancel(); tasks[token] = nil end
    elseif kind == "body" then
        if type(data.body) ~= "table" or type(data.body.meters) ~= "table"
            or type(data.prefab) ~= "string" or data.token ~= token then return end
        data.destination, data.home = nil, source
        state.claims[userid], state.away[userid] = data, nil
        Schedule(userid, 0)
    elseif kind == "expired" then
        local claim = state.claims[userid]
        if not claim then
            local sess = Session(userid)
            if not sess or type(data.body) ~= "table" or type(data.body.meters) ~= "table"
                or type(data.prefab) ~= "string" then return end
            if sess.remote_shard and sess.remote_shard ~= source and sess.remote_shard ~= data.first_shard then return end
            if not hooks.settle(sess, data, source) then return end
            claim = state.claims[userid]
        end
        Wire.Send(source, "body", userid, token, claim)
    end
end

function M.Bind(callbacks) hooks = callbacks end
return M
