-- Execute the actual panel button, game picker, board renderer and client
-- protocol. Only native widgets/JSON/network delivery are replaced.
package.path = "scripts/?.lua;" .. package.path
local function noop() end
local now = 10
GetTime = function() return now end
Class = function(base, ctor)
    local c = {_ctor = ctor, _base = base}; c.__index = c
    return setmetatable(c, {__index = base, __call = function(_, ...)
        local self = setmetatable({}, c); ctor(self, ...); return self
    end})
end
local Widget = Class({}, function(self, name)
    self.name, self.children, self.shown = name, {}, true
    self.inst = {IsValid = function() return not self.killed end, ListenForEvent = noop}
end)
function Widget:AddChild(child) self.children[#self.children + 1] = child; child.parent = self; return child end
function Widget:SetPosition(x, y) self.x, self.y = x, y end
function Widget:SetSize(w, h) self.w, self.h = w, h end
Widget.ForceImageSize = Widget.SetSize
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:Kill() self.killed = true; for _, c in ipairs(self.children) do c:Kill() end end
function Widget:Enable() self.disabled = false end
function Widget:Disable() self.disabled = true end
function Widget:SetOnClick(fn) self.onclick = fn end
function Widget:SetString(text) assert(type(text) == "string"); self.text = text end
function Widget:SetTruncatedString(text, width) self:SetString(text); self.text_width = width end
function Widget:SetTint(...) self.tint = {...} end
function Widget:SetHoverText(text) self.hover = text end
function Widget:ClearHoverText() self.hover = nil end
function Widget:ResetRegionSize() self.region_reset = true end
function Widget:GetLineEditString() return self.text end
function Widget:Set(_, _, _, _, skin) self.skin = skin end
function Widget:OnControl() return false end
function Widget:OnDestroy() self:Kill() end
for _, name in ipairs({"SetHAnchor", "SetVAnchor", "SetScaleMode", "SetScale", "StartUpdating", "SetClickable",
    "SetColour", "SetHAlign", "SetRegionSize", "SetImageNormalColour", "SetImageFocusColour", "SetImageDisabledColour",
    "SetTextLengthLimit", "SetAllowNewline", "SetIdleTextColour", "SetEditTextColour", "SetEditCursorColour", "SetTextPrompt", "SetFont"}) do Widget[name] = noop end
local Image = Class(Widget, function(self) Widget._ctor(self, "Image") end)
local Text = Class(Widget, function(self, _, _, text) Widget._ctor(self, "Text"); self.text = text end)
package.loaded["widgets/redux/templates"] = {ScrollingGrid = function(items, opts)
    local grid = Widget("scrolling_grid")
    grid.opts, grid.widgets, grid.current_scroll_pos, grid.target_scroll_pos = opts, {}, 1, 1
    for i = 1, (opts.num_visible_rows + 2) * opts.num_columns do
        grid.widgets[i] = grid:AddChild(opts.item_ctor_fn({}, i))
    end
    function grid:GetListWidgets() return self.widgets end
    function grid:RefreshView()
        local first = (math.floor(self.current_scroll_pos) - 1) * self.opts.num_columns
        for i, widget in ipairs(self.widgets) do self.opts.apply_fn({}, widget, self.items[first + i], first + i) end
    end
    function grid:SetItemsData(data)
        self.items = data
        self.end_pos = math.max(1, math.ceil(#data / self.opts.num_columns) - self.opts.num_visible_rows + self.opts.end_offset)
        self:RefreshView()
    end
    function grid:ScrollToScrollPos(position)
        self.current_scroll_pos = math.max(1, math.min(self.end_pos, position))
        self.target_scroll_pos = self.current_scroll_pos; self:RefreshView()
    end
    function grid:ScrollToDataIndex(index)
        self:ScrollToScrollPos(math.ceil(index / self.opts.num_columns) - self.opts.num_visible_rows + 1)
    end
    function grid:Scroll(delta) self:ScrollToScrollPos(self.target_scroll_pos + delta) end
    grid:SetItemsData(items)
    return grid
end}
package.loaded["widgets/widget"], package.loaded["widgets/screen"] = Widget, Widget
package.loaded["widgets/image"], package.loaded["widgets/imagebutton"], package.loaded["widgets/text"] = Image, Image, Text
package.loaded["widgets/playerbadge"], package.loaded["widgets/textedit"] = Image, Text
for _, name in ipairs({"invslot", "itemtile", "itemslot", "healthbadge", "hungerbadge", "sanitybadge", "moisturemeter"}) do package.loaded["widgets/" .. name] = Image end
package.loaded.my_friend_equip_slots = {Panel = function() return {} end}
DEFAULTFONT, ANCHOR_MIDDLE, ANCHOR_TOP, ANCHOR_LEFT, SCALEMODE_PROPORTIONAL = "font", 0, 1, 2, 1
CONTROL_CANCEL, CONTROL_PAUSE = 1, 2
SetAutopaused = function() error("games must not pause the world") end
local function clone(t)
    if type(t) ~= "table" then return t end
    local out = {}; for k, v in pairs(t) do out[k] = clone(v) end; return out
end
local tokens = {}
package.loaded.json = {encode = function(t) tokens[#tokens + 1] = clone(t); return tostring(#tokens) end,
    decode = function(text) assert(tokens[tonumber(text)] ~= nil); return clone(tokens[tonumber(text)]) end}
if arg[1] ~= nil then dofile(arg[1]); package.loaded.json = _G.json end
local json = require("json")
local requests = {}
GetModRPC = function(_, name) return name end
SendModRPCToServer = function(name, action, payload, friend)
    requests[#requests + 1] = {name = name, action = action, payload = payload, friend = friend}
end
local owner = {HUD = {}, IsValid = function() return true end}
ThePlayer = owner
TheFrontEnd = {screens = {}, PushScreen = function(self, screen) self.screens[#self.screens + 1] = screen end,
    PopScreen = function(self, screen)
        for i, value in ipairs(self.screens) do if value == screen then table.remove(self.screens, i) break end end
        screen:OnDestroy()
    end}
local Client = require("my_friend_games_client")
local controls = Widget("controls"); Client.Attach(controls)
assert(Client.notice.y + 19 < -80, "game invitations must sit below the companion HUD buttons")
local children = #controls.children
Client.Attach(controls)
assert(#controls.children == children, "HUD setup must not duplicate game notices")
local Panel = require("widgets/my_friend_panel")
local panel = Panel(owner)
local friend = {IsValid = function() return true end}
panel.friend = friend
panel.HideFriend = function(self) self.hidden, self.friend = true, nil end
local button, frame = panel.games, panel.info_frame
assert(button.x + button.w / 2 <= frame.x + frame.w / 2
    and button.x - button.w / 2 >= frame.x - frame.w / 2
    and button.y - button.h / 2 >= frame.y - frame.h / 2
    and button.y + button.h / 2 <= frame.y + frame.h / 2
    and button.scale_on_focus == false and button.move_on_click == false,
    "the whole games button, including hover/click behavior, must remain inside the info frame")
assert(button.x + button.w / 2 == frame.x + frame.w / 2
    and button.y - button.h / 2 == frame.y - frame.h / 2, "the game button must touch both frame edges exactly")
button.onclick()
assert(panel.hidden and requests[#requests].action == "menu" and requests[#requests].friend == friend
    and Client.friend == nil, "the client must not retain a removed companion body")
Client.Receive("menu", json.encode({games = {"gomoku"}}))
assert(Client.screen.mode == "menu")
local function find_button(root, label)
    for _, child in ipairs(root.children) do
        if child.onclick ~= nil and child.label ~= nil and child.label.text == label then return child end
        local nested = find_button(child, label); if nested ~= nil then return nested end
    end
end
local L = require("my_friend_games_strings")
find_button(Client.screen.root, L.Get("gomoku")).onclick()
assert(Client.screen.mode == "board" and #Client.screen.board.cells == 225)
Client.screen.player_button.onclick()
assert(requests[#requests].action == "roster")
local players = {}
for i = 1, 19 do players[i] = {id = tostring(i), name = "Player " .. i, self = i == 1} end
Client.Receive("roster", json.encode({players = players}))
local roster = Client.screen
assert(#roster.player_rows == 8 and roster.player_rows[1].record.self)
roster.player_rows[1].onclick()
assert(json.decode(requests[#requests].payload).target == "1", "self must be selectable")
find_button(roster.root, L.Get("next")).onclick()
assert(roster.page == 2 and roster.player_rows[1].record.id == "9")
find_button(roster.root, L.Get("next")).onclick()
assert(roster.page == 3 and not roster.player_rows[4].shown)
Client.Receive("sent", json.encode({id = "i1"}))
assert(roster.cancel_invite.shown)
Client.Receive("invite", json.encode({id = "i1", name = "Player 1", game = "gomoku"}))
assert(Client.notice.shown and Client.screen == roster, "incoming invitations do not force open a screen")
assert(roster.invitation_notice.shown, "an invitation remains clickable above an existing game screen")
Client.notice.button.onclick()
assert(Client.screen.mode == "invitation")
find_button(Client.screen.root, L.Get("accept")).onclick()
assert(requests[#requests].action == "reply" and json.decode(requests[#requests].payload).accept)

local state = require("my_friend_gomoku").New()
state.id, state.game, state.side, state.open = "g1", "gomoku", 0, true
state.participants = {{id = "1", name = "Player 1", prefab = "wilson", skin = "wilson_formal"},
    {id = "1", name = "Player 1", prefab = "wilson", skin = "wilson_formal"}}
state.chat, state.chat_seq, state.version = {}, 0, 1
Client.Receive("invite_closed", json.encode({id = "i1", key = "accepted"}))
Client.Receive("state", json.encode(state))
local board_screen, board = Client.screen, Client.screen.board
assert(Client.invite == nil and not Client.notice.shown and Client.match.side == 0)
assert(board_screen.avatars[1].skin == "wilson_formal" and board_screen.avatars[2].skin == "wilson_formal")
assert(find_button(board_screen.root, L.Get("hint")) == nil)
board.cells[113].onclick()
assert(requests[#requests].action == "move")
local move = json.decode(requests[#requests].payload)
assert(move.x == 8 and move.y == 8 and move.revision == 0)
local before = #requests
board.cells[114].onclick(); assert(#requests == before, "pending clicks cannot duplicate a move")
state.chat = {{seq = 1, name = "Player 1", kind = "text", value = "hello :pig:"}}
state.chat_seq, state.version, state.open = 1, 2, false
Client.Receive("state", json.encode(state))
assert(Client.pending_move == 0, "a chat-only snapshot must not acknowledge a pending board move")
state.board[113], state.revision, state.turn, state.open = 1, 1, 2, false
state.version = 3
Client.Receive("state", json.encode(state))
assert(board.cells[113].disabled and board.cells[113].stone.shown and Client.screen == board_screen)
board.cells[114].onclick()
assert(#requests == before + 1, "self-play permits the same client to play White")
Client.Receive("message", json.encode({key = "rate"}))
assert(Client.pending_move == nil)
owner.dead, owner.attacked = true, true
board_screen:Refresh()
assert(Client.screen == board_screen and not board_screen.closed, "health changes do not close the game")
local old = clone(state); old.revision = 0; old.board[113] = 0
Client.Receive("state", json.encode(old)); assert(Client.match.revision == 1)
local malformed = clone(state); malformed.board[2] = "wrong"
Client.Receive("state", json.encode(malformed)); assert(Client.match.board[2] == 0)
Client.Receive("state", "malformed"); Client.Receive("state", string.rep("x", 32769))
assert(Client.screen == board_screen)
local cells = board.cells
for _ = 1, 10 do board_screen:Refresh() end
assert(cells == board.cells and #cells == 225, "board refreshes reuse existing widgets")

-- Private input, quick messages and native emoji glyphs use only GameRequest.
EMOJI_ITEMS = {emoji_pig = {input_name = "pig", data = {utf8_str = "<pig>"}}}
for i = 1, 35 do EMOJI_ITEMS["different_key_" .. i] = {input_name = "extra_" .. i, data = {utf8_str = "<extra " .. i .. ">"}} end
local chat = board_screen.chat
chat.input:SetString("draft stays")
state.version, state.chat_seq = 4, 2
state.chat[2] = {seq = 2, name = "Player 2", kind = "emoji", value = "pig"}
Client.Receive("state", json.encode(state))
assert(chat.input:GetLineEditString() == "draft stays" and chat.rows[2].body.text == "<pig>")
chat.input.OnTextEntered("private :pig:")
assert(requests[#requests].name == "GameRequest" and requests[#requests].action == "chat"
    and json.decode(requests[#requests].payload).kind == "text" and chat.input:GetLineEditString() == "")
now = now + 1
chat:TogglePicker("quick"); find_button(chat.picker, L.Get("quick_1")).onclick()
assert(json.decode(requests[#requests].payload).kind == "quick" and json.decode(requests[#requests].payload).value == 1)
now = now + 1
chat:TogglePicker("emoji")
assert(#chat.emoji_grid.items == 36 and #chat.emoji_grid.widgets == 30,
    "emoji selection must include the whole registered catalog with bounded reusable widgets")
chat.emoji_grid:ScrollToDataIndex(#chat.emoji_grid.items)
find_button(chat.picker, "<pig>").onclick()
assert(json.decode(requests[#requests].payload).kind == "emoji" and json.decode(requests[#requests].payload).value == "pig")
state.side, state.version, state.participants[2].id = 2, 5, "2"
Client.Receive("state", json.encode(state))
assert(not board_screen.black_button.disabled)
board_screen.black_button.onclick(); assert(requests[#requests].action == "black")
state.black_offer, state.version = {id = "b1", from = "2", name = "Player 2"}, 6
Client.Receive("state", json.encode(state)); assert(board_screen.black_button.disabled)
state.side, state.version = 1, 7
Client.Receive("state", json.encode(state))
assert(board_screen.black_accept.shown and board_screen.black_prompt.shown)
board_screen.black_accept.onclick()
assert(requests[#requests].action == "black_reply" and json.decode(requests[#requests].payload).accept)
state.black_offer = nil
state.version = 8
Client.Receive("state", json.encode(state))
state.chat = {}
for i = 1, 40 do state.chat[i] = {seq = i, name = "Player 1", kind = "text", value = tostring(i)} end
state.version, state.chat_seq = 9, 40
Client.Receive("state", json.encode(state))
assert(chat.history.opts.num_visible_rows == 5 and chat.page_text == nil
    and chat.rows[1].body.text == "36" and chat.rows[5].body.text == "40", "chat shows five messages without page controls")
local rows = chat.rows
chat.history:Scroll(-1)
assert(chat.rows[1].body.text == "35" and chat.rows[5].body.text == "39", "scrolling moves one message instead of a whole page")
table.remove(state.chat, 1)
state.chat[#state.chat + 1] = {seq = 41, name = "Player 1", kind = "text", value = "41"}
state.version, state.chat_seq = 10, 41
Client.Receive("state", json.encode(state))
assert(chat.rows == rows and chat.rows[1].body.text == "35", "new capped-history messages preserve the message being read")
chat.history:ScrollToDataIndex(#state.chat)
assert(chat.rows[1].body.text == "37" and chat.rows[5].body.text == "41")
board_screen:OnControl(CONTROL_CANCEL, false)
assert(Client.screen == nil and Client.match ~= nil and Client.notice.shown, "minimizing must retain the game")
Client.notice.button.onclick(); assert(requests[#requests].action == "resume")
state.open = true; Client.Receive("state", json.encode(state))
assert(Client.screen.mode == "board")
Client.screen.exit_button.onclick()
before = #requests
Client.screen.exit_button.onclick()
assert(#requests == before + 1 and requests[#requests].action == "leave", "leaving needs explicit confirmation")
Client.Receive("message", json.encode({key = "finished"}))
assert(Client.match == nil and not Client.screen.bot_button.disabled, "expired/restarted sessions must release a stale client board")
state.id, state.open = "g2", true
Client.Receive("state", json.encode(state))
Client.Receive("left", json.encode({id = "g2"}))
assert(Client.match == nil and Client.screen == nil and not Client.notice.shown,
    "leaving must close the window and clear the resume entry")

-- Go uses a full 19x19 board, the same private chat and distinct scoring UI.
Client.OpenGame("go")
assert(#Client.screen.board.cells==361 and Client.screen.chat.history.opts.widget_height==20,
    "Go must have 361 points and compact, non-overlapping chat rows")
owner.userid="1"
local go={id="go1",game="go",board={},turn=1,status="playing",revision=0,version=1,side=1,open=true,
    participants={{id="1",name="甲"},{id="2",name="乙"}},chat={},chat_seq=0}
for i=1,361 do go.board[i]=0 end
Client.Receive("state",json.encode(go))
local go_screen=Client.screen
go.open=false
assert(go_screen.go_buttons.pass.shown and go_screen.go_buttons.count.shown and go_screen.black_button.y==-92)
go_screen.go_buttons.pass.onclick(); assert(requests[#requests].action=="pass")
go.offer={id="offer1",kind="count",to="1"}; go.version=2
Client.Receive("state",json.encode(go))
assert(go_screen.go_accept.shown and not go_screen.go_buttons.pass.shown)
go_screen.go_accept.onclick(); assert(requests[#requests].action=="offer_reply")
go.offer=nil; go.status="scoring"; go.revision=1; go.version=3
go.board[1]=1; go.dead={}; go.confirmed={false,false}; go.score={361,7.5}
Client.Receive("state",json.encode(go))
assert(not go_screen.bot_button.shown and go_screen.go_buttons.confirm.shown and not go_screen.board.cells[1].disabled)
go_screen.board.cells[1].onclick(); assert(requests[#requests].action=="mark")
assert(Client.pending_move==1)
-- A chat-only update must not acknowledge a pending dead mark.
go.version=4
Client.Receive("state",json.encode(go)); assert(Client.pending_move==1)
before=#requests; go_screen.board.cells[1].onclick(); assert(#requests==before)
go_screen.go_buttons.confirm.onclick(); assert(requests[#requests].action=="confirm")
go.confirmed[1]=true; go.dead["1"]=true; go.revision=2; go.version=5
Client.Receive("state",json.encode(go))
assert(Client.pending_move==nil and go_screen.go_buttons.confirm.disabled and go_screen.board.cells[1].dead.shown)
go_screen.go_buttons.play_on.onclick(); assert(requests[#requests].action=="play_on")
go_screen.history_button.onclick(); assert(requests[#requests].action=="history")
Client.Receive("history",json.encode({page=1,pages=2,total=22,rows={
    {game="go",names={"甲","乙"},winner=1},{game="gomoku",names={"丙","丁"},draw=true}}}))
assert(Client.screen.mode=="history" and #Client.screen.history_grid.items==2)
local result_rows=Client.screen.history_grid:GetListWidgets()
assert(result_rows[1].names.text=="甲  /  乙" and result_rows[1].result.text==L.Format("history_win","甲","乙")
    and result_rows[2].result.text==L.Get("draw"))
find_button(Client.screen.root,L.Get("next")).onclick()
assert(json.decode(requests[#requests].payload).page==2)
Client.Receive("history",json.encode({page=2,pages=2,total=22,rows={}}))
assert(Client.screen.history_empty.shown)
find_button(Client.screen.root,L.Get("back")).onclick()
assert(Client.screen.mode=="board" and #Client.screen.board.cells==361 and Client.match.id=="go1")
assert(Client.screen.close.h > Client.screen.close.w and Client.screen.close.x > 400,
    "the minimize control must be a vertical button on the board panel's right edge")
assert(Client.screen.close.label.text:find("\n", 1, true) ~= nil,
    "the minimize label should be arranged vertically")
assert(not Client.screen.title.shown and Client.screen.board.x == 125 and Client.screen.board.y == 75,
    "the board should move left and use the freed layout space")
Client.OpenGame("gomoku")
assert(Client.game=="go" and Client.match.id=="go1" and #Client.screen.board.cells==361,
    "selecting another game must not discard an active scoring session")
Client.screen:Close()
local large=clone(go)
large.id,large.revision,large.version,large.chat_seq="go_large",3,6,40
for i=1,361 do large.board[i]=1; large.dead[tostring(i)]=true end
large.chat={}
for i=1,40 do large.chat[i]={seq=i,name=string.rep('"',96),kind="text",value=string.rep('"',320)} end
local payload=json.encode(large)
if arg[1]~=nil then assert(#payload>32768 and #payload<65536) end
Client.Receive("state",payload)
assert(Client.match.id=="go_large","a complete valid Go snapshot must not be lost to JSON escaping")

-- Adding registered games adds exactly one selector button per game.
Client.match = nil
local catalog = require("my_friend_games_catalog")
catalog.GAMES.test2 = {id = "test2", name = "Game Two"}
catalog.GAMES.test3 = {id = "test3", name = "Game Three"}
Client.Receive("menu", json.encode({games = {"gomoku", "test2", "test3"}}))
assert(find_button(Client.screen.root, L.Get("gomoku")) ~= nil
    and find_button(Client.screen.root, "Game Two") ~= nil and find_button(Client.screen.root, "Game Three") ~= nil)
print("PASS: actual info-frame button/menu/invite/self-play/board flow, pagination, pending/stale packets, death continuity, minimize/resume and widget reuse")
