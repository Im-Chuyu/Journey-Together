local Screen = require("widgets/screen")
local Widget = require("widgets/widget")
local PlayerBadge = require("widgets/playerbadge")
local UI = require("widgets/my_friend_games_ui")
local L = require("my_friend_games_strings")
local Catalog = require("my_friend_games_catalog")
local GameScreen = Class(Screen, function(self, client, mode)
    Screen._ctor(self, "MyFriendGamesScreen")
    self.client, self.mode, self.page = client, mode, 1
    self.root = self:AddChild(Widget("games_root"))
    self.root:SetHAnchor(ANCHOR_MIDDLE); self.root:SetVAnchor(ANCHOR_MIDDLE)
    self.root:SetScaleMode(SCALEMODE_PROPORTIONAL)
    UI.Box(self.root, 0, 0, 4000, 4000, 0, 0, 0, .45)
    local width = mode == "board" and 940 or mode == "history" and 780 or 500
    local height = mode == "board" and 680 or mode == "history" and 600 or mode == "players" and 590 or 350
    UI.Box(self.root, 0, 0, width, height, .055, .075, .09, .98)
    UI.Box(self.root, 0, height / 2 - 3, width, 3, .8, .6, .25)
    self.title = UI.Text(self.root, L.Get(mode == "board" and Catalog.Get(client.game).name or mode == "players" and "roster"
        or mode == "invitation" and "invite" or mode == "history" and "history" or "select"), 0, height / 2 - 34, 27, width - 150)
    self.close = UI.Button(self.root, L.Get("close"), width / 2 - 53, height / 2 - 32, 90, 32,
        function() self:Close() end)
    if mode == "board" then
        self.title:Hide()
        local letters = {}
        for letter in L.Get("close"):gmatch("[%z\1-\127\194-\244][\128-\191]*") do letters[#letters + 1] = letter end
        self.close:ForceImageSize(36, math.max(100, #letters * 26 + 28))
        self.close:SetPosition(446, 82)
        self.close.label:SetString(table.concat(letters, "\n"))
        self.close.label:SetRegionSize(28, math.max(92, #letters * 26))
        self.close.label:SetHAlign(ANCHOR_MIDDLE)
        self.close.move_on_click = false
    end
    self.message = UI.Text(self.root, client.message or "", 0, -height / 2 + 25, 18, width - 30)
    if mode == "board" then self:BuildBoard()
    elseif mode == "players" then self:BuildPlayers()
    elseif mode == "invitation" then self:BuildInvitation()
    elseif mode == "history" then self:BuildHistory()
    else self:BuildMenu() end
    -- Also put invitations above our own modal screen, where the HUD notice
    -- behind the dark backdrop would otherwise be impossible to click.
    local Notice = require("widgets/my_friend_games_notice")
    self.invitation_notice = self:AddChild(Notice(client))
    self.invitation_notice:Refresh(client)
    self.default_focus = self.close
    -- This screen deliberately does not autopause, inspect health, subscribe
    -- to attacked/death events, or change the player's state graph.
end)
function GameScreen:Close()
    if self.closed then return end
    self.closed = true
    if self.client.screen == self then self.client.screen = nil end
    TheFrontEnd:PopScreen(self)
    self.client.UpdateNotice()
end
function GameScreen:BuildHistory()
    local TEMPLATES = require("widgets/redux/templates")
    self.history_grid = self.root:AddChild(TEMPLATES.ScrollingGrid({}, {
        scroll_context = {}, peek_height = 0, widget_width = 700, widget_height = 40,
        num_visible_rows = 10, num_columns = 1, end_offset = 1, scroll_per_click = 1,
        scrollbar_offset = 8, scrollbar_height_offset = -20,
        item_ctor_fn = function()
            local row = Widget("game_result_row")
            row.names = UI.Text(row, "", -85, 8, 18, 510)
            row.result = UI.Text(row, "", -85, -12, 16, 510)
            row.game = UI.Text(row, "", 285, 0, 18, 110)
            return row
        end,
        apply_fn = function(_, row, record)
            if record == nil then row:Hide(); return end
            row:Show()
            row.names:SetTruncatedString(record.names[1] .. "  /  " .. record.names[2], 510, nil, true)
            local result = record.winner ~= nil and L.Format("history_win", record.names[record.winner], record.names[3 - record.winner])
                or L.Get(record.draw and "draw" or "history_unfinished")
            row.result:SetTruncatedString(result, 510, nil, true)
            row.game:SetString(L.Get(Catalog.Get(record.game).name))
        end,
    }))
    self.history_grid:SetPosition(0, 15)
    self.history_empty = UI.Text(self.root, L.Get("history_empty"), 0, 20, 22, 650)
    self.history_page = UI.Text(self.root, "", 0, -205, 18, 500)
    local function Request(offset)
        local data = self.client.history
        local page = math.max(1, math.min(data ~= nil and data.pages or 1, (data ~= nil and data.page or 1) + offset))
        self.client.Send("history", {page = page})
    end
    UI.Button(self.root, L.Get("previous"), -150, -245, 130, 34, function() Request(-1) end)
    UI.Button(self.root, L.Get("next"), 0, -245, 130, 34, function() Request(1) end)
    UI.Button(self.root, L.Get("refresh"), 150, -245, 130, 34, function() Request(0) end)
    UI.Button(self.root, L.Get("back"), -300, -245, 130, 34, function() self.client.Show("board") end)
    self:RefreshHistory()
end
function GameScreen:RefreshHistory()
    local data = self.client.history or {rows = {}, page = 1, pages = 1}
    if self.history_data == data then return end
    self.history_data = data
    self.history_grid:SetItemsData(data.rows)
    self.history_grid:ScrollToScrollPos(1)
    if #data.rows == 0 then self.history_empty:Show() else self.history_empty:Hide() end
    self.history_page:SetString(L.Format("history_page", tostring(data.page), tostring(data.pages))
        .. (data.failed and (" · " .. L.Get("history_error")) or data.pending and (" · " .. L.Get("history_pending")) or ""))
end
function GameScreen:OnDestroy()
    if self.client.screen == self then self.client.screen = nil end
    self.closed = true
    GameScreen._base.OnDestroy(self)
end
function GameScreen:OnControl(control, down)
    if GameScreen._base.OnControl(self, control, down) then return true end
    if not down and (control == CONTROL_CANCEL or control == CONTROL_PAUSE) then self:Close(); return true end
end
function GameScreen:BuildMenu()
    local ids = self.client.catalog or Catalog.ORDER
    for i, id in ipairs(ids) do
        if Catalog.Get(id) ~= nil then
            UI.Button(self.root, L.Get(Catalog.Get(id).name), 0, 85 - (i - 1) * 48, 260, 38,
                function() self.client.OpenGame(id) end)
        end
    end
    if self.client.match ~= nil then
        UI.Button(self.root, L.Get("resume"), 0, -65, 260, 36, function() self.client.Send("resume", {}) end)
    end
end
function GameScreen:BuildInvitation()
    local invite = self.client.invite
    local text = invite ~= nil and L.Format("invitation", invite.name, L.Get(invite.game)) or L.Get("expired")
    local question = UI.Text(self.root, text, 0, 60, 22)
    question:SetRegionSize(440, 90)
    local function Reply(accept)
        if invite == nil or self.client.invite == nil or self.client.invite.id ~= invite.id then return end
        self.client.Send("reply", {id = invite.id, accept = accept})
    end
    UI.Button(self.root, L.Get("accept"), -110, -30, 170, 42, function() Reply(true) end)
    UI.Button(self.root, L.Get("decline"), 110, -30, 170, 42, function() Reply(false) end)
end
function GameScreen:BuildPlayers()
    self.player_rows = {}
    for i = 1, 8 do
        local row = UI.Button(self.root, "", 0, 205 - (i - 1) * 48, 420, 38, function()
            local record = self.player_rows[i].record
            if record ~= nil and not record.busy then
                self.client.Send("invite", {game = self.client.game or "gomoku", target = record.id})
            end
        end)
        self.player_rows[i] = row
    end
    UI.Button(self.root, L.Get("previous"), -160, -205, 125, 34, function() self.page = math.max(1, self.page - 1); self:RefreshPlayers() end)
    UI.Button(self.root, L.Get("refresh"), 0, -205, 125, 34, function() self.client.Send("roster", {}) end)
    UI.Button(self.root, L.Get("next"), 160, -205, 125, 34, function()
        self.page = math.min(math.max(1, math.ceil(#self.client.players / 8)), self.page + 1); self:RefreshPlayers()
    end)
    self.cancel_invite = UI.Button(self.root, L.Get("cancel"), 0, -250, 150, 30,
        function() if self.client.sent_invite ~= nil then self.client.Send("cancel", {id = self.client.sent_invite}) end end)
    self:RefreshPlayers()
end
function GameScreen:RefreshPlayers()
    local list = self.client.players or {}
    self.page = math.min(self.page, math.max(1, math.ceil(#list / 8)))
    for i, row in ipairs(self.player_rows) do
        local p = list[(self.page - 1) * 8 + i]
        row.record = p
        if p ~= nil then
            row:Show(); row.label:SetTruncatedString(p.name .. (p.self and (" (" .. L.Get("self") .. ")") or ""), 400, nil, true)
            if p.busy then row:Disable() else row:Enable() end
        else row:Hide() end
    end
    if self.client.sent_invite ~= nil then self.cancel_invite:Show() else self.cancel_invite:Hide() end
end
function GameScreen:BuildBoard()
    UI.Box(self.root, -305, 54, 260, 442, .085, .11, .13)
    self.history_button = UI.Button(self.root, L.Get("history"), -305, 282, 210, 32,
        function() self.client.Send("history", {page = 1}) end)
    local def = Catalog.Get(self.client.game)
    local Board = require(def.renderer)
    self.board = self.root:AddChild(Board(self.client))
    self.board:SetPosition(125, 75); self.board:SetScale(1.07)
    self.avatars = {}
    for i = 1, 2 do
        local avatar = self.root:AddChild(PlayerBadge("", {1, 1, 1, 1}, false, 0))
        avatar:SetScale(.55); avatar:SetPosition(-405, 235 - (i - 1) * 54)
        self.avatars[i] = avatar
    end
    self.black_name = UI.Text(self.root, L.Get("black"), -280, 235, 20, 190)
    self.white_name = UI.Text(self.root, L.Get("white"), -280, 181, 20, 190)
    self.status = UI.Text(self.root, L.Get("empty"), -305, 128, 22, 240)
    self.turn_hint = UI.Text(self.root, "", -305, 96, 19, 240)
    self.rules = UI.Text(self.root, L.Get(def.rules_text), -305, 50, 18, 240)
    self.rules:SetRegionSize(240, 78)
    self.bot_button = UI.Button(self.root, L.Get("companion"), -305, 0, 210, 36,
        function() self.client.Send("bot", {game = self.client.game or "gomoku"}) end)
    self.player_button = UI.Button(self.root, L.Get("players"), -305, -43, 210, 36,
        function() self.client.Send("roster", {}) end)
    self.black_button = UI.Button(self.root, L.Get("request_black"), -305, 0, 210, 36, function()
        if self.client.match ~= nil then self.client.Send("black", {id = self.client.match.id}) end
    end)
    self.black_prompt = UI.Text(self.root, L.Get("black_question"), -305, 50, 18)
    self.black_prompt:SetRegionSize(238, 65)
    local function BlackReply(accept)
        local match = self.client.match
        if match ~= nil and match.black_offer ~= nil then
            self.client.Send("black_reply", {id = match.id, offer = match.black_offer.id, accept = accept})
        end
    end
    self.black_accept = UI.Button(self.root, L.Get("accept"), -360, 0, 100, 34, function() BlackReply(true) end)
    self.black_decline = UI.Button(self.root, L.Get("decline"), -250, 0, 100, 34, function() BlackReply(false) end)
    self.exit_button = UI.Button(self.root, L.Get("leave"), -305, -138, 210, 32, function()
        if self.confirm_leave then
            local match = self.client.match
            if match ~= nil then self.client.Send("leave", {id = match.id}) end
            self.confirm_leave = nil
        else self.confirm_leave = true; self.exit_button.label:SetString(L.Get("confirm_leave")) end
    end)
    self.undo_button = UI.Button(self.root, L.Get("undo"), -305, -43, 210, 32, function()
        local match = self.client.match
        if match ~= nil then self.client.Send("undo", {id = match.id, revision = match.revision}) end
    end)
    self.undo_prompt = UI.Text(self.root, "", -305, -72, 18)
    self.undo_prompt:SetRegionSize(240, 45)
    local function UndoReply(accept)
        local match = self.client.match
        if match ~= nil and match.undo_offer ~= nil then
            self.client.Send("undo_reply", {id = match.id, offer = match.undo_offer.id, accept = accept})
        end
    end
    self.undo_accept = UI.Button(self.root, L.Get("yes"), -360, -105, 100, 30, function() UndoReply(true) end)
    self.undo_decline = UI.Button(self.root, L.Get("decline"), -250, -105, 100, 30, function() UndoReply(false) end)
    self.go_buttons = {}
    local function Action(action)
        local match = self.client.match
        if match ~= nil then self.client.Send(action, {id = match.id, revision = match.revision}) end
    end
    local function Button(key, action, x, y)
        local button = UI.Button(self.root, L.Get(key), x, y, 102, 30, function() Action(action) end)
        button.label:SetTruncatedString(L.Get(key), 92, nil, true)
        self.go_buttons[action] = button
    end
    Button("pass", "pass", -360, 2); Button("count", "count", -250, 2)
    Button("draw_offer", "draw_offer", -360, -34)
    Button("confirm_score", "confirm", -360, 2); Button("play_on", "play_on", -250, 2)
    self.go_resign = UI.Button(self.root, L.Get("resign"), -250, -34, 102, 30, function()
        if self.confirm_resign then Action("resign") else
            self.confirm_resign = true; self.go_resign.label:SetString(L.Get("yes"))
        end
    end)
    self.go_prompt = UI.Text(self.root, "", -305, 48, 18)
    self.go_prompt:SetRegionSize(240, 65)
    local function OfferReply(accept)
        local match = self.client.match
        if match ~= nil and match.offer ~= nil then
            self.client.Send("offer_reply", {id = match.id, offer = match.offer.id, accept = accept})
        end
    end
    self.go_accept = UI.Button(self.root, L.Get("yes"), -360, 2, 102, 30, function() OfferReply(true) end)
    self.go_decline = UI.Button(self.root, L.Get("decline"), -250, 2, 102, 30, function() OfferReply(false) end)
    local Chat = require("widgets/my_friend_games_chat")
    self.chat = self.root:AddChild(Chat(self.client)); self.chat:SetPosition(0, -255)
    self:RefreshBoard()
end
function GameScreen:RefreshAvatar(index, participant)
    local avatar = self.avatars[index]
    local prefab = participant ~= nil and type(participant.prefab) == "string" and participant.prefab or ""
    local skin = participant ~= nil and type(participant.skin) == "string" and participant.skin or nil
    local signature = prefab .. ":" .. (skin or "")
    if avatar.game_signature == signature then return end
    avatar.game_signature = signature
    -- Native/modded heads may not ship a skin build; keep the unknown head as
    -- a safe fallback without making missing art break the game screen.
    local ok = pcall(avatar.Set, avatar, prefab, {1, 1, 1, 1}, false, 0, skin)
    if not ok then avatar:Set("", {1, 1, 1, 1}, false, 0) end
end
function GameScreen:RefreshBoard()
    local match = self.client.match
    local playing = match ~= nil and match.status == "playing"
    local scoring = match ~= nil and match.status == "scoring"
    local ownturn = playing and (match.side == 0 or match.side == match.turn)
    local stones = match ~= nil and match.count or 0
    if match ~= nil and match.count == nil then
        for _, value in ipairs(match.board or {}) do if value ~= 0 then stones = stones + 1 end end
    end
    self.board:Refresh(match)
    if match ~= nil then
        self.black_name:SetTruncatedString(L.Get("black") .. ": " .. match.participants[1].name, 190, nil, true)
        self.white_name:SetTruncatedString(L.Get("white") .. ": " .. match.participants[2].name, 190, nil, true)
        local status = playing and L.Format("turn", L.Get(match.turn == 1 and "black" or "white"))
            or scoring and L.Get("scoring")
            or match.status == "draw" and L.Get("draw")
            or match.winner ~= nil and L.Format("won", L.Get(match.winner == 1 and "black" or "white")) or L.Get("ended")
        self.status:SetTruncatedString(status, 240, nil, true)
        self.turn_hint:SetTruncatedString(scoring and L.Get("mark_dead") or playing and L.Get(ownturn and "your_turn" or "waiting")
            or match.reason ~= nil and L.Get(match.reason) or "", 240, nil, true)
    else
        self.black_name:SetString(L.Get("black")); self.white_name:SetString(L.Get("white"))
        self.status:SetString(L.Get("empty")); self.turn_hint:SetString("")
    end
    for i = 1, 2 do self:RefreshAvatar(i, match ~= nil and match.participants[i] or nil) end
    self.black_button:Hide(); self.black_accept:Hide(); self.black_decline:Hide(); self.black_prompt:Hide(); self.rules:Show()
    self.undo_button:Hide(); self.undo_prompt:Hide(); self.undo_accept:Hide(); self.undo_decline:Hide()
    if playing or scoring then
        self.bot_button:Hide(); self.player_button:Hide()
        local offer = match.black_offer
        if offer ~= nil and match.side == 1 then
            self.black_accept:Show(); self.black_decline:Show(); self.black_prompt:Show(); self.rules:Hide()
        elseif playing and stones <= 2 then
            self.black_button:Show()
            if match.side == 2 and offer == nil then self.black_button:Enable() else self.black_button:Disable() end
            self.black_button.label:SetString(L.Get(offer ~= nil and "black_pending" or "request_black"))
        end
    else self.bot_button:Show(); self.bot_button:Enable(); self.player_button:Show(); self.player_button:Enable() end
    self:RefreshGo(match, playing, scoring)
    if match ~= nil then
        self.exit_button:Show()
        self.exit_button:SetPosition(-305, match.game == "go" and -140 or -105)
    else self.exit_button:Hide() end
    self:RefreshUndo(match, playing)
    self.confirm_leave = nil; self.exit_button.label:SetString(L.Get("leave"))
    self.chat:Refresh()
end
function GameScreen:RefreshUndo(match, playing)
    if match == nil or not playing then return end
    local has_stone = false
    for _, value in ipairs(match.board or {}) do if value ~= 0 then has_stone = true; break end end
    if not has_stone and match.undo_offer == nil then return end
    local y = match.game == "go" and -105 or -43
    if match.undo_offer == nil then
        self.undo_button:SetPosition(-305, y); self.undo_button:Show()
        return
    end
    local offer = match.undo_offer
    self.undo_prompt:SetPosition(-305, match.game == "go" and -72 or -43)
    self.undo_prompt:Show()
    if offer.to == ThePlayer.userid then
        self.undo_prompt:SetString(L.Format("undo_question", offer.name))
        self.undo_accept:SetPosition(-360, y); self.undo_decline:SetPosition(-250, y)
        self.undo_accept:Show(); self.undo_decline:Show()
    else
        self.undo_prompt:SetString(L.Get("undo_pending"))
    end
end
function GameScreen:RefreshGo(match, playing, scoring)
    for _, button in pairs(self.go_buttons) do button:Hide() end
    self.go_resign:Hide(); self.go_prompt:Hide(); self.go_accept:Hide(); self.go_decline:Hide()
    self.confirm_resign = nil; self.go_resign.label:SetString(L.Get("resign"))
    local def = Catalog.Get(self.client.game)
    self.rules:SetString(L.Get(def.rules_text))
    if match == nil or match.game ~= "go" then return end
    if match.score ~= nil then
        self.rules:SetString(L.Format("go_score", tostring(match.score[1]), tostring(match.score[2]))
            .. (scoring and ("\n" .. L.Get("score_help")) or ""))
    end
    if not playing and not scoring then return end
    self.go_buttons.draw_offer:Show(); self.go_resign:Show()
    if playing then
        self.black_button:SetPosition(-305, -66)
        self.go_buttons.pass:Show(); self.go_buttons.count:Show()
        if match.side == 0 or match.side == match.turn then self.go_buttons.pass:Enable() else self.go_buttons.pass:Disable() end
    else
        self.black_button:Hide(); self.black_accept:Hide(); self.black_decline:Hide(); self.black_prompt:Hide()
        self.go_buttons.confirm:Show(); self.go_buttons.play_on:Show()
        local confirmed = match.side ~= 0 and match.confirmed[match.side]
        self.go_buttons.confirm.label:SetTruncatedString(L.Get(confirmed and "score_wait" or "confirm_score"), 92, nil, true)
        if confirmed then self.go_buttons.confirm:Disable() else self.go_buttons.confirm:Enable() end
    end
    if match.offer ~= nil then
        self.go_buttons.pass:Hide(); self.go_buttons.count:Hide(); self.go_buttons.confirm:Hide(); self.go_buttons.play_on:Hide()
        self.rules:Hide(); self.go_prompt:Show()
        self.go_prompt:SetString(L.Get(match.offer.to == ThePlayer.userid
            and (match.offer.kind == "count" and "count_question" or "draw_question") or "offer_pending"))
        if match.offer.to == ThePlayer.userid then self.go_accept:Show(); self.go_decline:Show() end
    end
    if match.black_offer ~= nil and match.side == 1 then
        for _, button in pairs(self.go_buttons) do button:Hide() end
        self.go_prompt:Hide(); self.go_accept:Hide(); self.go_decline:Hide()
    end
end
function GameScreen:Refresh()
    self.message:SetTruncatedString(self.client.message or "", self.mode == "board" and 900 or 470, nil, true)
    if self.mode == "board" then self:RefreshBoard()
    elseif self.mode == "players" then self:RefreshPlayers()
    elseif self.mode == "history" then self:RefreshHistory() end
end
return GameScreen
