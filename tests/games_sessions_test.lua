package.path = "scripts/?.lua;" .. package.path
local now, guid, tasks, messages = 0, 0, {}, {}
GetTime = function() return now end
EMOJI_ITEMS = {emoji_pig = {input_name = "pig", data = {utf8_str = "<pig>"}}}
local original_random = math.random
math.random = function(n) return n ~= nil and 1 or .5 end
local function clone(t)
    if type(t) ~= "table" then return t end
    local out = {}; for k, v in pairs(t) do out[k] = clone(v) end; return out
end
local function entity(userid, x, companion)
    guid = guid + 1
    local e = {userid = userid, GUID = guid, x = x or 0, prefab = companion and "wendy" or "wilson",
        listeners = {}, isplayer = true, tags = {my_friend = companion}}
    function e:IsValid() return not self.removed end
    function e:HasTag(tag) return self.tags[tag] == true end
    function e:GetDisplayName() return self.userid or "伙伴" end
    e.Transform = {GetWorldPosition = function() return e.x, 0, 0 end}
    function e:DoTaskInTime(delay, fn)
        local task = {at = now + delay, fn = fn}; function task:Cancel() self.cancelled = true end
        tasks[#tasks + 1] = task; return task
    end
    function e:ListenForEvent(event, fn, source)
        source = source or self; source.listeners[event] = source.listeners[event] or {}; source.listeners[event][fn] = true
    end
    function e:RemoveEventCallback(event, fn, source)
        source = source or self; if source.listeners[event] ~= nil then source.listeners[event][fn] = nil end
    end
    function e:PushEvent(event)
        local copy = {}; for fn in pairs(self.listeners[event] or {}) do copy[#copy + 1] = fn end
        for _, fn in ipairs(copy) do fn(self) end
    end
    function e:DoPeriodicTask() error("board games must not add periodic scans") end
    return e
end
local world, a, b, c = entity(nil), entity("A"), entity("B", 1), entity("C", 2)
world.ismastersim, TheWorld = true, world
local friend = entity(nil, 3, true); world._my_friend = friend
friend.components = {my_friend_affinity = {Get = function(_, p) return p.affinity or 20 end}}
AllPlayers = {a, b, c}
local Games = require("my_friend_games")
local service = Games.New(world, function(userid, kind, data)
    messages[#messages + 1] = {userid = userid, kind = kind, data = clone(data)}
end)
local function request(p, action, data, f) now = now + .12; service:Request(p, action, data or {}, f) end
local function advance(dt)
    local target = now + dt
    while true do
        local next_task
        for _, task in ipairs(tasks) do
            if not task.cancelled and not task.done and task.at <= target and (next_task == nil or task.at < next_task.at) then next_task = task end
        end
        if next_task == nil then break end
        now, next_task.done = next_task.at, true; next_task.fn()
    end
    now = target
end
local function last(kind, userid)
    for i = #messages, 1, -1 do
        if messages[i].kind == kind and (userid == nil or messages[i].userid == userid) then return messages[i].data end
    end
end
request(a, "menu", {}, friend); assert(last("menu", "A").games[1] == "gomoku")
a.affinity = 19
request(a, "menu", {}, friend); assert(last("message", "A").key == "affinity")
request(a, "bot", {game = "gomoku"}, friend); assert(service:Current("A") == nil)
a.affinity = 20
c.x = 100; request(c, "menu", {}, friend); assert(last("message", "C").key == "unavailable"); c.x = 2
request(a, "menu", {}, entity(nil, 1, true)); assert(last("message", "A").key == "unavailable")
request(a, "roster"); local roster = last("roster", "A").players
assert(#roster == 3 and roster[1].id == "A" and roster[1].self)
local stranger = entity("unlisted")
local before = #messages
request(stranger, "menu"); assert(#messages == before, "unregistered senders must not receive game data")

request(a, "invite", {game = "gomoku", target = "B"})
local invite = last("invite", "B")
assert(invite ~= nil and service.incoming.B == invite.id)
request(c, "reply", {id = invite.id, accept = true})
assert(service.invites[invite.id] ~= nil and service:Current("A") == nil, "only the recipient can accept")
request(b, "reply", {id = invite.id, accept = false})
assert(service.invites[invite.id] == nil and service.incoming.B == nil)
advance(2)
request(a, "invite", {game = "gomoku", target = "B"})
invite = last("invite", "B")
request(b, "reply", {id = invite.id, accept = true})
local game = assert(service:Current("A"))
assert(service:Current("B") == game and last("state", "B").side == 2 and last("state", "B").open)
request(c, "move", {id = game.id, revision = 0, x = 8, y = 8})
assert(game.state.count == 0, "a third player cannot place stones by guessing a session id")
request(b, "move", {id = game.id, revision = 0, x = 8, y = 8})
assert(game.state.count == 0 and last("message", "B").key == "wrong_turn")
request(a, "move", {id = game.id, revision = 0, x = 0/0, y = 8})
assert(game.state.count == 0)
request(a, "move", {id = game.id, revision = 0, x = 8, y = 8})
assert(game.state.count == 1 and game.state.turn == 2)
request(a, "move", {id = game.id, revision = 0, x = 9, y = 8})
assert(game.state.count == 1 and last("message", "A").key == "stale")
b.tags.playerghost = true; b:PushEvent("death"); b:PushEvent("attacked")
request(b, "move", {id = game.id, revision = 1, x = 9, y = 8})
assert(game.state.count == 2 and game.state.status == "playing", "death/attacks do not terminate board play")
request(a, "resign", {id = game.id})
assert(game.state.status == "ended" and game.state.winner == 2 and game.state.revision == 3)
assert(last("state", "B").board[113] == 1 and last("state", "B").reason == "resigned")

-- Self selection opens immediately and alternates both colors.
advance(2)
request(a, "invite", {game = "gomoku", target = "A"})
game = service:Current("A")
assert(service.incoming.A == nil and service.outgoing.A == nil, "self-play never creates an invitation")
assert(last("state", "A").side == 0 and game.participants[1].id == game.participants[2].id)
for i = 1, 4 do request(a, "move", {id = game.id, revision = i - 1, x = i, y = 1}) end
assert(game.state.count == 4 and game.state.turn == 1)
request(a, "resign", {id = game.id})

request(c, "invite", {game = "gomoku", target = "A"})
invite = last("invite", "A"); advance(46)
assert(service.invites[invite.id] == nil and last("invite_closed", "C").key == "expired")
request(c, "invite", {game = "gomoku", target = "A"})
invite = last("invite", "A")
request(c, "cancel", {id = invite.id})
assert(service.invites[invite.id] == nil)

-- Companion AI uses one deferred move, checks current session validity, and
-- never changes inventory, the behaviour tree or the companion's world task.
request(a, "bot", {game = "gomoku"}, friend)
game = service:Current("A")
request(a, "move", {id = game.id, revision = 0, x = 8, y = 8})
assert(game.ai_task ~= nil and game.state.count == 1)
advance(.36)
assert(game.ai_task == nil and game.state.count == 2 and game.state.turn == 1)
request(a, "move", {id = game.id, revision = 2, x = 1, y = 1})
friend.removed = true; friend:PushEvent("onremove"); advance(.5)
assert(game.state.count == 3 and game.state.status == "ended" and game.reason == "left")
friend.removed = nil

-- Disconnect before acceptance and during play, timeout and bounded cleanup.
request(c, "invite", {game = "gomoku", target = "B"}); invite = last("invite", "B")
b.removed = true; b:PushEvent("onremove")
assert(service.invites[invite.id] == nil); b.removed = nil
request(a, "bot", {game = "gomoku"}, friend)
game = service:Current("A"); advance(1801)
assert(game.state.status == "ended" and game.reason == "timeout")
advance(601)
assert(service:Current("A") == nil)

-- Random colors, explicit first-player requests, private chat and exit.
math.random = function(n) return n == 2 and 2 or n ~= nil and 1 or 0 end
request(a, "invite", {game = "gomoku", target = "B"})
invite = last("invite", "B"); request(b, "reply", {id = invite.id, accept = true})
game = service:Current("A")
assert(game.participants[1].id == "B" and last("state", "A").side == 2, "the inviter can randomly receive White")
Networking_Say = function() error("private chat must never use public chat") end
TheNet = {Say = function() error("private chat must never use public chat") end}
local function chat(p, kind, value)
    advance(.9); request(p, "chat", {id = game.id, kind = kind, value = value, name = "forged"})
end
before = #messages
chat(a, "text", "  hello :pig:\n  ")
assert(game.chat[1].value == "hello :pig:" and game.chat[1].name == "A")
for i = before + 1, #messages do assert(messages[i].userid == "A" or messages[i].userid == "B") end
local seq = game.chat_seq
chat(a, "text", string.char(255)); chat(a, "text", string.rep("x", 321))
chat(a, "emoji", "not_an_emoji"); chat(a, "bot", 1)
assert(game.chat_seq == seq, "malformed/oversized/spoofed messages must not enter the private log")
chat(b, "quick", 2); chat(b, "emoji", "pig")
assert(game.chat[2].kind == "quick" and game.chat[3].value == "pig")
request(c, "chat", {id = game.id, kind = "text", value = "intrusion"})
assert(game.chat_seq == seq + 2, "outsiders cannot inject private chat")
request(a, "black", {id = game.id})
local offer = assert(game.black_offer)
request(a, "black_reply", {id = game.id, offer = offer.id, accept = true})
assert(game.black_offer == offer, "the requester cannot approve their own player-opponent request")
request(b, "black_reply", {id = game.id, offer = offer.id, accept = false})
assert(game.participants[1].id == "B" and game.black_offer == nil)
advance(5.1); request(a, "black", {id = game.id}); offer = game.black_offer
request(b, "move", {id = game.id, revision = 0, x = 8, y = 8})
request(b, "black_reply", {id = game.id, offer = offer.id, accept = true})
assert(game.participants[1].id == "A" and game.state.count == 0 and game.state.revision == 2
    and game.chat_seq == 3, "approved first-player changes restart the board, retain chat, and advance revision")
request(b, "move", {id = game.id, revision = 1, x = 9, y = 9})
assert(game.state.count == 0)
for i = 1, 55 do chat(a, "text", "private " .. i) end
assert(#game.chat == 40 and game.chat[#game.chat].seq == game.chat_seq)
request(a, "leave", {id = game.id})
assert(service:Current("A") == nil and service:Current("B").reason == "left_game"
    and last("left", "A").id == game.id)
before = #messages
chat(b, "text", "after exit")
for i = before + 1, #messages do assert(messages[i].userid ~= "A", "exited players must not receive old snapshots or private messages") end
request(b, "leave", {id = game.id}); assert(service.games[game.id] == nil)

request(a, "bot", {game = "gomoku"}, friend)
game = service:Current("A")
assert(game.participants[1].bot and game.ai_task ~= nil and #game.chat == 1, "a Black companion starts automatically and greets privately")
advance(.4)
assert(game.state.count == 1 and game.state.turn == 2, "a Black companion must actually make the opening move")
request(a, "leave", {id = game.id})
request(a, "bot", {game = "gomoku"}, friend)
game = service:Current("A")
request(a, "black", {id = game.id})
assert(game.participants[1].id == "A" and game.state.count == 0 and game.ai_task == nil)
advance(.5); assert(game.state.count == 0, "a cancelled Black AI callback cannot place a stale opening")
request(a, "move", {id = game.id, revision = game.state.revision, x = 8, y = 8})
advance(9)
request(a, "move", {id = game.id, revision = game.state.revision, x = 1, y = 1})
advance(.5)
assert(game.state.count == 4 and #game.chat >= 2, "random companion dialogue is triggered by play rather than periodic tasks")
request(a, "leave", {id = game.id})
math.random = function(n) return n ~= nil and 1 or .5 end

-- Outcome dialogue is emitted once, for the human's result, in either color.
local rules = require("my_friend_gomoku")
local function Four(side, y)
    local state = rules.New()
    for x = 1, 4 do state.board[(y - 1) * 15 + x] = side end
    state.count, state.turn = 4, side
    return state
end
request(a, "bot", {game = "gomoku"}, friend)
game = service:Current("A"); game.state = Four(1, 4)
request(a, "move", {id = game.id, revision = 0, x = 5, y = 4})
assert(game.state.winner == 1 and game.chat[#game.chat].kind == "player_win" and game.chat[#game.chat].target == "A")
local result_seq = game.chat_seq
service:Finish(game, nil, 1)
assert(game.chat_seq == result_seq, "duplicate completion callbacks must not repeat an outcome line")
request(a, "bot", {game = "gomoku"}, friend)
game = service:Current("A"); game.state = Four(2, 4)
service:ScheduleAI(game); advance(.4)
assert(game.state.winner == 2 and game.chat[#game.chat].kind == "player_loss" and game.chat[#game.chat].target == "A")
math.random = function(n) return n == 2 and 2 or n ~= nil and 1 or 0 end
request(a, "bot", {game = "gomoku"}, friend)
game = service:Current("A"); game.state = Four(1, 4); advance(.4)
assert(game.participants[1].bot and game.chat[#game.chat].kind == "player_loss")
request(a, "bot", {game = "gomoku"}, friend)
game = service:Current("A"); game.state = Four(2, 4)
request(a, "move", {id = game.id, revision = 0, x = 5, y = 4})
assert(game.participants[1].bot and game.chat[#game.chat].kind == "player_win")
advance(.4); assert(game.state.count == 5, "the finished game's pending AI opener must be cancelled")

-- In PvP, only the current followed participant receives support; these
-- lines remain private, and switching the leader changes who is supported.
math.random = function(n) return n ~= nil and 1 or 0 end
local followed = a
friend.components.follower = {GetLeader = function() return followed end}
request(a, "invite", {game = "gomoku", target = "B"})
invite = last("invite", "B"); request(b, "reply", {id = invite.id, accept = true})
game = service:Current("A")
assert(game.chat[1].kind == "cheer" and game.chat[1].target == "A")
request(a, "move", {id = game.id, revision = 0, x = 8, y = 8})
advance(13)
request(b, "move", {id = game.id, revision = 1, x = 9, y = 8})
assert(game.chat_seq == 1, "the other participant's move must not trigger support")
request(a, "move", {id = game.id, revision = 2, x = 1, y = 1})
assert(game.chat_seq == 2 and game.chat[2].target == "A")
followed = b
request(b, "move", {id = game.id, revision = 3, x = 2, y = 1})
assert(game.chat_seq == 3 and game.chat[3].target == "B")
followed = nil; advance(13)
request(a, "move", {id = game.id, revision = 4, x = 3, y = 1})
assert(game.chat_seq == 3, "a companion following nobody must not root for an arbitrary player")
followed = b
game.state = Four(2, 15)
request(b, "move", {id = game.id, revision = 0, x = 5, y = 15})
assert(game.chat[#game.chat].kind == "player_win" and game.chat[#game.chat].target == "B")
request(a, "invite", {game = "gomoku", target = "B"})
invite = last("invite", "B"); request(b, "reply", {id = invite.id, accept = true})
game = service:Current("A"); game.state = Four(1, 15)
request(a, "move", {id = game.id, revision = 0, x = 5, y = 15})
assert(game.chat[#game.chat].kind == "player_loss" and game.chat[#game.chat].target == "B")
request(a, "leave", {id = game.id}); request(b, "leave", {id = game.id})
friend.components.follower = nil
for _ = 1, 20 do
    request(a, "bot", {game = "gomoku"}, friend)
    game = service:Current("A"); request(a, "resign", {id = game.id})
end
local count = 0; for _ in pairs(service.games) do count = count + 1 end
assert(count == 1, "repeated finished games without viewers must not accumulate boards")
-- Go reuses membership/private delivery, but scoring remains an active match.
local records = {}
world._my_friend_games_history = {Append = function(_, row) records[#records + 1] = clone(row) end,
    Page = function(_, page, cb) cb({page=1,pages=1,total=#records,rows=clone(records)}) end}
game = service:Start("go", a, b, false)
request(b,"pass",{id=game.id,revision=0}); assert(game.state.passes==0 and last("message","B").key=="wrong_turn")
request(c,"pass",{id=game.id,revision=0}); assert(game.state.passes==0)
request(a,"move",{id=game.id,revision=0,x=4,y=4})
request(a,"count",{id=game.id,revision=1}); local offer=assert(game.offer)
request(a,"offer_reply",{id=game.id,offer=offer.id,accept=true}); assert(game.state.status=="playing")
request(b,"offer_reply",{id=game.id,offer=offer.id,accept=false}); assert(game.offer==nil)
advance(6)
request(a,"count",{id=game.id,revision=1}); offer=game.offer
request(b,"offer_reply",{id=game.id,offer=offer.id,accept=true})
assert(game.state.status=="scoring" and service:Busy("A") and not game.finished)
request(a,"bot",{game="gomoku"},friend); assert(service:Current("A")==game and last("message","A").key=="busy")
request(a,"confirm",{id=game.id,revision=game.state.revision}); assert(not game.finished)
local oldrevision=game.state.revision
request(b,"mark",{id=game.id,revision=oldrevision,x=4,y=4})
assert(not game.state.confirmed[1] and game.state.dead["61"])
request(a,"confirm",{id=game.id,revision=oldrevision}); assert(not game.state.confirmed[1],"stale confirmations cannot approve new dead marks")
request(b,"play_on",{id=game.id,revision=game.state.revision})
assert(game.state.status=="playing" and game.state.turn==2 and game.state.dead==nil)
request(b,"pass",{id=game.id,revision=game.state.revision})
request(a,"pass",{id=game.id,revision=game.state.revision}); assert(game.state.status=="scoring")
request(a,"confirm",{id=game.id,revision=game.state.revision})
request(b,"confirm",{id=game.id,revision=game.state.revision})
assert(game.finished and game.state.winner==1 and game.state.score[1]==361 and game.state.seen==nil)
assert(#records==1 and records[1].names[1]=="A" and records[1].winner==1 and records[1].game=="go")
service:Finish(game); assert(#records==1,"a match must be archived exactly once")
request(a,"history",{page=1}); assert(last("history","A").rows[1].names[2]=="B")
game = service:Start("go",a,b,false)
advance(6); request(a,"draw_offer",{id=game.id,revision=0}); offer=game.offer
advance(31); assert(game.offer==nil)
request(b,"offer_reply",{id=game.id,offer=offer.id,accept=true}); assert(not game.finished)
request(a,"draw_offer",{id=game.id,revision=0}); offer=game.offer
request(b,"move",{id=game.id,revision=0,x=10,y=10}); assert(game.offer==offer,"wrong-turn moves do not clear a request")
request(a,"move",{id=game.id,revision=0,x=10,y=10}); assert(game.offer==nil,"a changed position invalidates pending requests")
advance(6); request(b,"draw_offer",{id=game.id,revision=1}); offer=game.offer
request(a,"offer_reply",{id=game.id,offer=offer.id,accept=true})
assert(game.finished and game.state.status=="draw" and records[2].draw and records[2].winner==nil)
-- The bot responds once per turn; scoring has no AI polling.
game = service:Start("go",a,friend,true)
request(a,"pass",{id=game.id,revision=0}); advance(.4)
assert(game.state.status=="scoring" and game.state.confirmed[2] and game.ai_task==nil)
request(a,"confirm",{id=game.id,revision=game.state.revision}); assert(game.finished and records[3].winner==2)
game = service:Start("go",a,a,false)
request(a,"count",{id=game.id,revision=0}); assert(game.state.status=="scoring")
request(a,"confirm",{id=game.id,revision=game.state.revision}); assert(not game.finished)
request(a,"confirm",{id=game.id,revision=game.state.revision}); assert(game.finished)
game=service:Start("go",a,b,false)
advance(6); request(a,"count",{id=game.id,revision=0}); offer=game.offer
request(b,"offer_reply",{id=game.id,offer=offer.id,accept=true})
advance(1801); assert(game.finished and records[#records].reason=="timeout", "scoring also has an idle limit")
service:Shutdown()
assert(next(service.games) == nil and next(service.invites) == nil and next(service.byuser) == nil)
for _, e in ipairs({a, b, c, friend}) do assert(next(e.listeners.onremove or {}) == nil) end
for _, task in ipairs(tasks) do assert(task.cancelled or task.done) end

-- Exercise the real RPC entry, with a token codec replacing only native JSON.
local encoded = {}
package.loaded.json = {encode = function(data) encoded[#encoded + 1] = clone(data); return tostring(#encoded) end,
    decode = function(text) assert(encoded[tonumber(text)] ~= nil, "malformed json"); return clone(encoded[tonumber(text)]) end}
if arg[1] ~= nil then dofile(arg[1]); package.loaded.json = _G.json end
local handler, client_handler
require("my_friend_games_rpc").Install({
    AddModRPCHandler = function(ns, name, fn) assert(ns == "MyFriends" and name == "GameRequest"); handler = fn end,
    AddClientModRPCHandler = function(ns, name, fn) assert(ns == "MyFriends" and name == "GameEvent"); client_handler = fn end,
    GetClientModRPC = function() return {} end, SendModRPCToClient = function() end,
})
handler(a, {}, "{}", friend); handler(a, "menu", string.rep("x", 1025), friend)
handler(a, "menu", "malformed", friend); handler(a, "menu", "1", false)
assert(world._my_friend_games == nil)
local payload = package.loaded.json.encode({})
now = now + 1; handler(a, "menu", payload, friend)
assert(world._my_friend_games ~= nil and type(client_handler) == "function")
world._my_friend_games:Shutdown()
math.random = original_random
print("PASS: authorized RPC, invitations/self-play, two-player turns, death/attack continuity, AI cancellation, disconnect/timeouts and bounded cleanup")
