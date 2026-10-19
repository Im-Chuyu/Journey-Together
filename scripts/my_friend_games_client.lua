local json = require("json")
local L = require("my_friend_games_strings")
local Catalog = require("my_friend_games_catalog")
local Chat = require("my_friend_games_chat")
local M = {players = {}, game = "gomoku"}
function M.Send(action, data)
    local friend = M.friend
    if friend ~= nil and not friend:IsValid() then friend = nil end
    if ThePlayer == nil or not ThePlayer:IsValid() then return false end
    SendModRPCToServer(GetModRPC("MyFriends", "GameRequest"), action, json.encode(data or {}), friend)
    return true
end
function M.UpdateNotice()
    if M.notice ~= nil and M.notice.inst:IsValid() then M.notice:Refresh(M) end
    if M.screen ~= nil and M.screen.inst:IsValid() and M.screen.invitation_notice ~= nil then
        M.screen.invitation_notice:Refresh(M)
    end
end
function M.Show(mode)
    if TheFrontEnd == nil or ThePlayer == nil or ThePlayer.HUD == nil then M.pending_mode = mode; return end
    local old = M.screen
    if old ~= nil and old.inst:IsValid() then old:Close() end
    local Screen = require("screens/my_friend_games_screen")
    M.screen = Screen(M, mode)
    M.pending_mode = nil
    TheFrontEnd:PushScreen(M.screen)
    M.UpdateNotice()
end
function M.Open(friend)
    M.friend, M.message = friend, nil
    M.Send("menu", {})
    -- Only the initial request needs the panel's entity identity. Later
    -- requests use server-side membership/current-companion checks.
    M.friend = nil
end
function M.OpenGame(id)
    if Catalog.Get(id) == nil then return end
    if M.match ~= nil and M.match.game ~= id and (M.match.status == "playing" or M.match.status == "scoring") then
        M.game, M.message = M.match.game, L.Get("busy")
        M.Show("board"); return
    end
    M.game, M.message = id, nil
    if M.match ~= nil and M.match.game ~= id then M.match = nil end
    M.Show("board")
end
function M.Move(x, y)
    local match = M.match
    if match ~= nil and match.game == "go" and match.status == "scoring" then
        if M.pending_move ~= nil or match.board[(y - 1) * 19 + x] == 0 then return end
        M.pending_move = match.revision
        if not M.Send("mark", {id = match.id, revision = match.revision, x = x, y = y}) then M.pending_move = nil end
        return
    end
    if match == nil or match.status ~= "playing" or M.pending_move ~= nil
        or match.side ~= 0 and match.side ~= match.turn then return end
    local size = Catalog.Get(match.game).rules.SIZE
    if match.board[(y - 1) * size + x] ~= 0 then return end
    M.pending_move = match.revision
    if not M.Send("move", {id = match.id, revision = match.revision, x = x, y = y}) then M.pending_move = nil end
end
function M.Chat(kind, value)
    local match = M.match
    if match == nil or Chat.Normalize(kind, value) == nil then return false end
    local now = GetTime()
    if now < (M.chat_after or 0) then return false end
    if not M.Send("chat", {id = match.id, kind = kind, value = value}) then return false end
    M.chat_after = now + .9
    return true
end
local function ValidMatch(data)
    local def = Catalog.Get(data.game)
    if def == nil or type(data.id) ~= "string" or type(data.board) ~= "table"
        or type(data.participants) ~= "table" or type(data.revision) ~= "number"
        or data.revision % 1 ~= 0 or data.revision < 0
        or (data.side ~= 0 and data.side ~= 1 and data.side ~= 2)
        or (data.turn ~= 1 and data.turn ~= 2)
        or not ({playing = true, scoring = true, won = true, draw = true, ended = true})[data.status] then return false end
    for i = 1, 2 do
        if type(data.participants[i]) ~= "table" or type(data.participants[i].name) ~= "string" then return false end
    end
    if data.chat ~= nil then
        if type(data.chat) ~= "table" or #data.chat > Chat.MAX_MESSAGES then return false end
        for _, entry in ipairs(data.chat) do if not Chat.Valid(entry) then return false end end
    end
    if data.version ~= nil and (type(data.version) ~= "number" or data.version % 1 ~= 0 or data.version < 0) then return false end
    if data.count ~= nil and (type(data.count) ~= "number" or data.count % 1 ~= 0 or data.count < 0
        or data.count > def.rules.SIZE^2) then return false end
    if data.black_offer ~= nil and (type(data.black_offer) ~= "table" or type(data.black_offer.id) ~= "string"
        or type(data.black_offer.from) ~= "string" or type(data.black_offer.name) ~= "string") then return false end
    if data.offer ~= nil and (type(data.offer) ~= "table" or type(data.offer.id) ~= "string"
        or type(data.offer.to) ~= "string" or (data.offer.kind ~= "count" and data.offer.kind ~= "draw_offer")) then return false end
    if data.undo_offer ~= nil and (type(data.undo_offer) ~= "table" or type(data.undo_offer.id) ~= "string"
        or type(data.undo_offer.to) ~= "string" or type(data.undo_offer.from) ~= "string"
        or type(data.undo_offer.name) ~= "string") then return false end
    if data.status == "scoring" then
        if data.game ~= "go" or type(data.dead) ~= "table" or type(data.confirmed) ~= "table"
            or type(data.confirmed[1]) ~= "boolean" or type(data.confirmed[2]) ~= "boolean" then return false end
        for key, value in pairs(data.dead) do
            local i = tonumber(key)
            if i == nil or i % 1 ~= 0 or i < 1 or i > 361 or value ~= true then return false end
        end
    end
    if data.score ~= nil and (type(data.score) ~= "table" or type(data.score[1]) ~= "number"
        or type(data.score[2]) ~= "number" or data.score[1] < 0 or data.score[1] > 361
        or data.score[2] < 0 or data.score[2] > 368.5) then return false end
    for i = 1, def.rules.SIZE^2 do
        if data.board[i] ~= 0 and data.board[i] ~= 1 and data.board[i] ~= 2 then return false end
    end
    return data.winner == nil or data.winner == 1 or data.winner == 2
end
function M.Receive(kind, payload)
    -- Escaping 40 valid chat messages plus Go dead-group marks can exceed
    -- 32 KiB; retain a bounded allowance for legitimate complete snapshots.
    if type(kind) ~= "string" or type(payload) ~= "string" or #payload > 65536 then return end
    local ok, data = pcall(json.decode, payload)
    if not ok or type(data) ~= "table" then return end
    if kind == "menu" then
        M.catalog = {}
        for _, id in ipairs(type(data.games) == "table" and data.games or {}) do
            if Catalog.Get(id) ~= nil then M.catalog[#M.catalog + 1] = id end
        end
        if data.current == nil then M.match, M.pending_move = nil, nil end
        M.Show("menu")
    elseif kind == "history" then
        if type(data.rows) ~= "table" or #data.rows > 20 or type(data.page) ~= "number"
            or data.page % 1 ~= 0 or data.page < 1 or type(data.pages) ~= "number" or data.pages < data.page then return end
        for _, row in ipairs(data.rows) do
            if type(row) ~= "table" or Catalog.Get(row.game) == nil or type(row.names) ~= "table"
                or type(row.names[1]) ~= "string" or type(row.names[2]) ~= "string"
                or row.winner ~= nil and row.winner ~= 1 and row.winner ~= 2 then return end
        end
        M.history = data
        if M.screen == nil or M.screen.mode ~= "history" then M.Show("history") end
    elseif kind == "roster" then
        M.players = {}
        for _, player in ipairs(type(data.players) == "table" and data.players or {}) do
            if type(player) == "table" and type(player.id) == "string" and type(player.name) == "string" then
                M.players[#M.players + 1] = player
            end
        end
        if M.screen ~= nil and M.screen.mode == "players" then M.screen:Refresh() else M.Show("players") end
    elseif kind == "invite" then
        if type(data.id) ~= "string" or type(data.name) ~= "string" or Catalog.Get(data.game) == nil then return end
        M.invite = data
    elseif kind == "sent" then
        M.sent_invite, M.message = data.id, L.Get("sent")
    elseif kind == "invite_closed" then
        if M.invite ~= nil and M.invite.id == data.id then M.invite = nil end
        if M.sent_invite == data.id then M.sent_invite = nil end
        if data.key ~= "accepted" then M.message = L.Get(data.key or "cancelled") end
        if M.screen ~= nil and M.screen.mode == "invitation" and data.key ~= "accepted" then M.Show("menu") end
    elseif kind == "state" then
        if not ValidMatch(data) then return end
        if M.match ~= nil and M.match.id == data.id and M.match.revision > data.revision then return end
        if M.match ~= nil and M.match.id == data.id and (M.match.version or 0) > (data.version or 0) then return end
        local pending = M.match ~= nil and M.match.id == data.id and M.pending_move or nil
        if pending ~= nil and (data.revision > pending or data.status ~= "playing" and data.status ~= "scoring") then pending = nil end
        M.match, M.game, M.pending_move, M.message = data, data.game, pending, nil
        if data.open then M.Show("board") end
    elseif kind == "left" then
        if M.match ~= nil and M.match.id == data.id then
            M.match, M.pending_move = nil, nil
            if M.screen ~= nil then M.screen:Close() end
        end
    elseif kind == "message" then
        M.pending_move, M.message = nil, L.Get(data.key or "forbidden")
        if data.key == "finished" and data.current == nil then M.match = nil end
        if M.screen == nil then M.Show("menu") end
    else return end
    if M.screen ~= nil and M.screen.inst:IsValid() then M.screen:Refresh() end
    M.UpdateNotice()
end
function M.Attach(controls)
    if controls.my_friend_games_notice ~= nil and controls.my_friend_games_notice.inst:IsValid() then
        M.notice = controls.my_friend_games_notice
        M.UpdateNotice()
        return
    end
    local Notice = require("widgets/my_friend_games_notice")
    M.notice = controls:AddChild(Notice(M))
    controls.my_friend_games_notice = M.notice
    local notice = M.notice
    controls.inst:ListenForEvent("onremove", function()
        if M.notice == notice then M.notice = nil end
    end)
    M.UpdateNotice()
    if M.pending_mode ~= nil then M.Show(M.pending_mode) end
end
return M
