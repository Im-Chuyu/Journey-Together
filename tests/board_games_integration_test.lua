-- Real game service, RPC, client, JSON, rules, renderer and screen; stub only engine/UI primitives.
-- lua tests/board_games_integration_test.lua [native scripts path]
local native = arg[1] or "../yuanma/scripts"
package.path = "./scripts/?.lua;" .. native .. "/?.lua;" .. package.path
require("class")
local json = require("json")
local now, packets, archives, handlers = 0, {}, {}, {}
function GetTime() return now end
FRAMES = 1 / 30
DEFAULTFONT, ANCHOR_MIDDLE, SCALEMODE_PROPORTIONAL = "font", 0, 0
CHATFONT = "chatfont"
CONTROL_CANCEL, CONTROL_PAUSE = 1, 2
local Widget = Class(function(self, name)
    self.name, self.children, self.visible, self.valid = name, {}, true, true
    self.inst = {IsValid = function() return self.valid end}
end)
function Widget:AddChild(child) self.children[#self.children + 1] = child; return child end
function Widget:SetPosition(x, y) self.x, self.y = x, y end
function Widget:SetSize(w, h) self.w, self.h = w, h end
Widget.ForceImageSize = Widget.SetSize
function Widget:SetString(value) self.text = value end
function Widget:SetFont(font) self.font = font end
Widget.SetTruncatedString = Widget.SetString
function Widget:SetOnClick(fn) self.click = fn end
function Widget:Show() self.visible = true end
function Widget:Hide() self.visible = false end
function Widget:Enable() self.enabled = true end
function Widget:Disable() self.enabled = false end
function Widget:Kill() self.valid = false; for _, c in ipairs(self.children) do c:Kill() end end
function Widget:OnDestroy() self:Kill() end
function Widget:OnControl() return false end
for _, name in ipairs({"SetHAnchor", "SetVAnchor", "SetScaleMode", "SetScale", "SetClickable", "SetTint",
    "SetColour", "SetRegionSize", "SetHAlign", "SetRotation", "Set", "SetImageNormalColour",
    "SetImageFocusColour", "SetImageDisabledColour", "Refresh"}) do Widget[name] = function() end end
package.loaded["widgets/widget"] = Widget
for _, name in ipairs({"screen", "image", "imagebutton", "text", "playerbadge", "my_friend_games_chat", "my_friend_games_notice"}) do
    package.loaded["widgets/" .. name] = Class(Widget, function(self) Widget._ctor(self, name) end)
end
package.loaded.my_friend_games_history = {ForWorld = function()
    return {Append = function(_, record) archives[#archives + 1] = record end}
end}
local Games = require("my_friend_games")
local Catalog = require("my_friend_games_catalog")
require("my_friend_games_rpc").Install({
    AddModRPCHandler = function(_, name, fn) handlers[name] = fn end,
    AddClientModRPCHandler = function() end,
})
function GetModRPC(_, name) return name end
function SendModRPCToServer(name, ...) handlers[name](ThePlayer, ...) end
TheFrontEnd = {PushScreen = function() end, PopScreen = function(_, screen) screen:OnDestroy() end}

local function Entity(userid)
    local e = {userid = userid, prefab = "wilson", components = {}, valid = true, tags = {}}
    e.Transform = {GetWorldPosition = function() return 0, 0, 0 end}
    function e:IsValid() return self.valid end
    function e:HasTag(t) return self.tags[t] == true end
    function e:GetDisplayName() return self.userid or "Companion" end
    function e:ListenForEvent() end
    function e:RemoveEventCallback() end
    function e:DoTaskInTime(delay, fn)
        local task = {at = now + delay, fn = fn}
        function task:Cancel() self.cancelled = true end
        return task
    end
    return e
end
local function Setup()
    now, packets, archives = 0, {}, {}
    local world, first, second, friend = Entity(), Entity("first"), Entity("second"), Entity()
    first.HUD, second.HUD = {}, {}
    friend.GUID, friend.isplayer, friend.tags.my_friend = 9, true, true
    friend.components.my_friend_affinity = {Get = function() return 50 end}
    world.GUID, world.ismastersim, world.state, world._my_friend = 1, true, {cycles = 0}, friend
    TheWorld, ThePlayer, AllPlayers = world, first, {first, second}
    world._my_friend_games = Games.New(world, function(userid, kind, data)
        packets[#packets + 1] = {userid = userid, kind = kind, payload = json.encode(data)}
    end)
    package.loaded.my_friend_games_client = nil
    local client = require("my_friend_games_client")
    return world._my_friend_games, first, second, friend, client
end
local function Request(player, action, data)
    now = now + .1
    handlers.GameRequest(player, action, json.encode(data or {}))
end
local function Flush(client)
    local current = packets; packets = {}
    for _, p in ipairs(current) do if p.userid == ThePlayer.userid then client.Receive(p.kind, p.payload) end end
end
local function Bot(game)
    local steps = 0
    while game.ai_task ~= nil do
        local task = game.ai_task
        assert(not task.cancelled); now = task.at; task.fn()
        steps = steps + 1; assert(steps < 3000)
    end
    return steps
end
local passed = 0
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end

Test("Xiangqi is advertised and four languages have matching game keys/placeholders", function()
    local service, p = Setup()
    Request(p, "menu")
    local menu = json.decode(packets[#packets].payload)
    assert(menu.games[3] == "xiangqi")
    local base = require("languages/zh/games")
    for _, language in ipairs({"zh_tw", "en", "ru"}) do
        local translated = require("languages/" .. language .. "/games")
        for key, value in pairs(base) do
            assert(type(translated[key]) == "string", language .. ":" .. key)
            local _, expected = value:gsub("%%s", "")
            local _, actual = translated[key]:gsub("%%s", "")
            assert(expected == actual, key)
        end
        for key in pairs(translated) do assert(base[key] ~= nil, key) end
    end
end)
Test("self-play client selects a piece, sends source and target through RPC and renders 90 reusable cells", function()
    local service, p, _, _, client = Setup()
    Request(p, "invite", {game = "xiangqi", target = p.userid})
    Flush(client)
    assert(client.match.game == "xiangqi" and client.match.side == 0)
    assert(#client.screen.board.cells == 90 and client.screen.black_name.text:find("红方", 1, true))
    local cells = client.screen.board.cells
    client.Move(1, 7); assert(client.selected_from == 55)
    client.Move(1, 6); Flush(client)
    assert(client.match.board[46] == 7 and client.match.board[55] == 0 and client.match.revision == 1)
    assert(client.pending_move == nil and client.selected_from == nil and client.screen.board.cells == cells)
    assert(client.match.last_from == 55 and client.match.last == 46)
end)
Test("server refuses forged, missing-source, noninteger, wrong-turn and stale moves", function()
    local service, p, q = Setup()
    local game = service:Start("xiangqi", p, q, false)
    local red = game.participants[1].id == p.userid and p or q
    local black = red == p and q or p
    local function Move(who, data) data.id, data.revision = game.id, data.revision or game.state.revision; Request(who, "move", data) end
    Move(black, {x = 1, y = 6, from_x = 1, from_y = 7})
    Move(red, {x = 1, y = 6})
    Move(red, {x = 1, y = 6, from_x = .5, from_y = 7})
    Move(red, {x = 1, y = 6, from_x = 1, from_y = 4})
    assert(game.state.count == 0)
    Move(red, {x = 1, y = 6, from_x = 1, from_y = 7})
    assert(game.state.count == 1)
    Move(black, {x = 1, y = 5, from_x = 1, from_y = 4, revision = 0})
    assert(game.state.count == 1)
end)
Test("player invitation, approved takeback and request for Red reuse existing protocols", function()
    local service, p, q = Setup()
    Request(p, "invite", {game = "xiangqi", target = q.userid})
    local invitation
    for _, packet in ipairs(packets) do if packet.kind == "invite" then invitation = json.decode(packet.payload) end end
    assert(invitation)
    Request(q, "reply", {id = invitation.id, accept = true})
    local game = service:Current(p.userid)
    assert(game ~= nil and service:Current(q.userid) == game)
    local red = game.participants[1].id == p.userid and p or q
    local black = red == p and q or p
    Request(red, "move", {id = game.id, revision = 0, from_x = 1, from_y = 7, x = 1, y = 6})
    Request(red, "undo", {id = game.id, revision = 1})
    assert(game.undo_offer.to == black.userid and game.state.count == 1)
    Request(black, "undo_reply", {id = game.id, offer = game.undo_offer.id, accept = true})
    assert(game.state.count == 0)
    Request(black, "black", {id = game.id})
    assert(game.black_offer.from == black.userid)
    Request(red, "black_reply", {id = game.id, offer = game.black_offer.id, accept = true})
    assert(game.participants[1].id == black.userid and game.state.count == 0)
end)
Test("bot uses cooperative source-aware play and does not retain search state afterwards", function()
    local service, p, _, friend = Setup()
    local game = service:Start("xiangqi", p, friend, true)
    if game.participants[1].bot then
        assert(Bot(game) > 1)
    else
        Request(p, "move", {id = game.id, revision = 0, from_x = 1, from_y = 7, x = 1, y = 6})
        assert(Bot(game) > 1)
    end
    assert(game.state.turn == (game.participants[1].bot and 2 or 1))
    assert(game.ai_search == nil and game.state.last_from ~= nil)
end)
Test("undo/restart invalidate old asynchronous turns; leave cleans searches and archives once", function()
    local service, p, _, friend = Setup()
    local game = service:Start("xiangqi", p, friend, true)
    if not game.participants[1].bot then
        game.participants[1], game.participants[2] = game.participants[2], game.participants[1]
        service:ScheduleAI(game)
    end
    local oldtask = game.ai_task
    now = oldtask.at; oldtask.fn()
    local pending = game.ai_task
    assert(game.ai_search ~= nil)
    service:MakeBlack(game, p.userid)
    assert(pending.cancelled and game.ai_search == nil)
    pending.fn()
    assert(game.state.count == 0)
    Request(p, "move", {id = game.id, revision = game.state.revision, from_x = 1, from_y = 7, x = 1, y = 6})
    local task = game.ai_task
    Request(p, "undo", {id = game.id, revision = game.state.revision})
    assert(task.cancelled and game.state.count == 0 and game.ai_search == nil)
    Request(p, "leave", {id = game.id})
    assert(game.finished and game.ai_search == nil and #archives == 1 and archives[1].game == "xiangqi")
    service:Finish(game)
    assert(#archives == 1)
end)
Test("draw offers work for Xiangqi while pass and scoring commands are refused", function()
    local service, p = Setup(); local game = service:Start("xiangqi", p, p, false)
    Request(p, "pass", {id = game.id, revision = 0}); assert(game.state.count == 0 and game.state.status == "playing")
    Request(p, "count", {id = game.id, revision = 0}); assert(game.state.status == "playing")
    Request(p, "draw_offer", {id = game.id, revision = 0})
    assert(game.state.status == "draw" and #archives == 1)
end)
Test("client accepts more than 81 Xiangqi plies and 361 Go moves but rejects malformed pieces", function()
    local service, p, _, _, client = Setup(); local game = service:Start("xiangqi", p, p, false)
    game.state.count = 100
    local snapshot = service:Snapshot(game, p.userid, false)
    client.Receive("state", json.encode(snapshot)); assert(client.match.count == 100)
    snapshot.revision = snapshot.revision + 1; snapshot.board[90] = 15
    client.Receive("state", json.encode(snapshot)); assert(client.match.revision == 0)
    game = service:Start("go", p, p, false); game.state.count = 400
    client.Receive("state", json.encode(service:Snapshot(game, p.userid, false)))
    assert(client.match.game == "go" and client.match.count == 400)
end)
Test("Xiangqi rotates Black's view while keeping server coordinates and cell instances", function()
    Setup()
    local client = {Move = function() end}
    local board = require("widgets/my_friend_xiangqi_board")(client)
    local state = require("my_friend_xiangqi").New()
    local match = {board = state.board, side = 2, turn = 1, status = "playing"}
    local cell = board.cells[55]
    board:Refresh(match)
    assert(cell.x == 184 and cell.y == 69 and not cell.enabled)
    match.side, client.selected_from = 1, 55
    board:Refresh(match)
    assert(board.cells[55] == cell and cell.x == -184 and cell.y == -69 and cell.mark.visible)
    assert(board.cells[46].hint.visible)
    board:Kill(); assert(not cell.inst:IsValid())
end)
Test("Gomoku and Go still play through the same service", function()
    for _, id in ipairs({"gomoku", "go"}) do
        local service, p = Setup(); local game = service:Start(id, p, p, false)
        Request(p, "move", {id = game.id, revision = 0, x = 4, y = 4})
        assert(game.state.board[3 * Catalog.Get(id).rules.SIZE + 4] == 1)
        Request(p, "undo", {id = game.id, revision = 1})
        assert(game.state.count == 0 and game.state.turn == 1)
        service:Shutdown(); assert(next(service.games) == nil)
    end
end)
Test("concurrent searches share a frame budget and resume when the next frame starts", function()
    local service, p, _, friend = Setup()
    local game = service:Start("xiangqi", p, friend, true)
    if not game.participants[1].bot then
        Request(p, "move", {id = game.id, revision = 0, from_x = 1, from_y = 7, x = 1, y = 6})
    end
    local task = game.ai_task; now = task.at
    service.ai_tick, service.ai_used = now, .006
    task.fn()
    assert(game.ai_search == nil and game.ai_task ~= task)
    task = game.ai_task; now = task.at; task.fn()
    assert(game.ai_search ~= nil)
    task = game.ai_task
    service:CancelAI(game); service:ScheduleAI(game)
    local replacement = game.ai_task
    task.fn()
    assert(game.ai_task == replacement and game.ai_token ~= nil)
    service:Shutdown()
    task.fn()
    assert(game.ai_search == nil and game.ai_task == nil and game.ai_token == nil)
end)
print(string.format("%d board game integration tests passed", passed))
