-- Per-world, transient game sessions. Transport is injected; no UI or AI
-- behaviour tree owns this state, and death/attacks do not cancel a game.
local Catalog = require("my_friend_games_catalog")
local Policy = require("my_friend_policy")
local Chat = require("my_friend_games_chat")
local History = require("my_friend_games_history")
local M = {}
local Service = {}; Service.__index = Service
local ACTIONS = {menu = true, roster = true, bot = true, invite = true, reply = true,
    cancel = true, move = true, resume = true, resign = true, leave = true,
    chat = true, black = true, black_reply = true, history = true,
    pass = true, count = true, draw_offer = true, offer_reply = true,
    mark = true, confirm = true, play_on = true, undo = true, undo_reply = true}
local function Active(game) return game ~= nil and not game.finished end
local function Cancel(task) if task ~= nil then task:Cancel() end end
local function Name(entity)
    local name = entity.GetDisplayName ~= nil and entity:GetDisplayName() or entity.name or entity.userid
    name = tostring(name or "?"):gsub("[%c]", " ")
    -- Bound text without cutting the middle of a UTF-8 sequence.
    if #name > 96 then
        local n = 97
        while n > 1 and name:byte(n) >= 128 and name:byte(n) < 192 do n = n - 1 end
        name = name:sub(1, n - 1)
    end
    return name
end
function M.New(world, send)
    return setmetatable({world = world, send = send, games = {}, byuser = {}, invites = {},
        incoming = {}, outgoing = {}, serial = 0}, Service)
end
function Service:Player(userid)
    for _, p in ipairs(AllPlayers or {}) do
        if p.userid == userid and Policy.IsLocalPlayer(p) then return p end
    end
end
function Service:Emit(userid, kind, data)
    if not self.shutting_down and self.world:IsValid() and self:Player(userid) ~= nil then self.send(userid, kind, data) end
end
function Service:Error(player, key)
    self:Emit(player.userid, "message", {key = key, current = self.byuser[player.userid]})
end
function Service:ID(prefix)
    self.serial = self.serial + 1
    return prefix .. tostring(self.world.GUID) .. ":" .. tostring(self.serial)
end
function Service:Current(userid) return self.games[self.byuser[userid]] end
function Service:Busy(userid)
    local game = self:Current(userid)
    return Active(game)
end
function Service:CanPlay(player)
    local friend = self.world._my_friend
    local affinity = friend ~= nil and friend:IsValid() and friend.components ~= nil
        and friend.components.my_friend_affinity or nil
    return affinity ~= nil and affinity:Get(player) >= 20
end
function Service:Companion(game)
    local friend = self.world._my_friend
    if friend ~= nil and friend:IsValid() and friend:HasTag("my_friend") and friend.isplayer == true then
        for _, p in ipairs(game.participants) do
            if p.bot and p.id == "companion:" .. tostring(friend.GUID) then return friend end
        end
    end
end
function Service:NotifyCompanion(game)
    local friend = self:Companion(game)
    if friend ~= nil then
        friend._my_friend_replan_requested = true
        if friend.brain ~= nil and friend.brain.ForceUpdate ~= nil then friend.brain:ForceUpdate() end
    end
end
function Service:Access(player, friend)
    local game = self:Current(player.userid)
    if game ~= nil then return true end
    local active = self.world._my_friend
    local candidate = friend or active
    return active ~= nil and candidate == active and candidate:IsValid()
        and candidate:HasTag("my_friend") and candidate.isplayer == true
        and Policy.DistanceSq(player, candidate) <= 20^2
end
function Service:Snapshot(game, userid, open)
    local s, participants = game.state, game.participants
    for _, p in ipairs(participants) do
        local entity = p.bot and self:Companion(game) or self:Player(p.id)
        if entity ~= nil then
            p.prefab = entity.prefab
            local skinner = entity.components ~= nil and entity.components.skinner or nil
            p.skin = skinner ~= nil and skinner.skin_name or entity.GetSkinName ~= nil and entity:GetSkinName() or nil
        end
    end
    return {id = game.id, game = game.game, board = s.board, turn = s.turn, status = s.status,
        winner = s.winner, last = s.last, line = s.line, revision = s.revision, reason = game.reason,
        participants = participants, side = participants[1].id == userid
            and (participants[2].id == userid and 0 or 1) or 2, open = open == true,
        chat = game.chat, chat_seq = game.chat_seq, black_offer = game.black_offer, version = game.version or 0,
        offer = game.offer, dead = s.dead, confirmed = s.confirmed,
        undo_offer = game.undo_offer,
        score = s.score or s.preview,
        captures = s.captures, passes = s.passes, count = s.count}
end
function Service:AddChat(game, participant, kind, value, quiet)
    game.chat_seq = game.chat_seq + 1
    game.chat[#game.chat + 1] = {seq = game.chat_seq, name = participant.name,
        speaker = participant.id, kind = kind, value = value, target = participant.target}
    if #game.chat > Chat.MAX_MESSAGES then table.remove(game.chat, 1) end
    if not quiet then self:Publish(game) end
end
function Service:BotTalk(game, force, quiet)
    if game.state.status ~= "playing" then return end
    local bot
    for _, p in ipairs(game.participants) do if p.bot then bot = p end end
    if bot == nil or not force and (GetTime() < (game.bot_chat_after or 0) or math.random() >= .28) then return end
    game.bot_chat_after = GetTime() + 8
    self:AddChat(game, bot, "bot", math.random(Chat.BOT_COUNT), quiet)
end
function Service:Supporter(game)
    if game.participants[1].bot or game.participants[2].bot
        or game.participants[1].id == game.participants[2].id then return end
    local friend = self.world._my_friend
    if friend == nil or not friend:IsValid() or not friend:HasTag("my_friend") or friend.isplayer ~= true then return end
    local leader = Policy.GetLeader(friend)
    if leader == nil or not Policy.IsLocalPlayer(leader) or self.byuser[leader.userid] ~= game.id then return end
    return friend, leader
end
function Service:Cheer(game, mover, force, quiet)
    if game.state.status ~= "playing" then return end
    local friend, leader = self:Supporter(game)
    if friend == nil or mover ~= nil and mover ~= leader then return end
    if game.support_user ~= leader.userid then
        game.support_user, game.cheer_after, force = leader.userid, nil, true
    end
    if not force and (GetTime() < (game.cheer_after or 0) or math.random() >= .25) then return end
    game.cheer_after = GetTime() + 12
    self:AddChat(game, {id = "companion:" .. tostring(friend.GUID), name = Name(friend), target = Name(leader)},
        "cheer", math.random(Chat.MESSAGE_COUNTS.cheer), quiet)
end
function Service:OutcomeTalk(game)
    local winner = game.state.winner
    if winner == nil then return end
    local friend, target, target_side = self:Companion(game)
    if friend ~= nil then
        for side, p in ipairs(game.participants) do if not p.bot then target, target_side = p, side end end
    else
        local leader
        friend, leader = self:Supporter(game)
        if friend ~= nil then
            for side, p in ipairs(game.participants) do if p.id == leader.userid then target, target_side = p, side end end
        end
    end
    if friend == nil or target == nil then return end
    local kind = winner == target_side and "player_win" or "player_loss"
    self:AddChat(game, {id = "companion:" .. tostring(friend.GUID), name = Name(friend), target = target.name},
        kind, math.random(Chat.MESSAGE_COUNTS[kind]), true)
end
function Service:ClearBlackOffer(game)
    Cancel(game.black_task); game.black_task, game.black_offer = nil, nil
end
function Service:ClearUndo(game)
    Cancel(game.undo_task); game.undo_task, game.undo_offer = nil, nil
end
function Service:MakeBlack(game, userid)
    if game.participants[2].id ~= userid then return end
    Cancel(game.ai_task); game.ai_task = nil
    self:ClearBlackOffer(game)
    self:ClearOffer(game)
    self:ClearUndo(game)
    game.participants[1], game.participants[2] = game.participants[2], game.participants[1]
    local revision = game.state.revision + 1
    game.state = Catalog.Get(game.game).rules.New(); game.state.revision = revision
    self:Touch(game); self:Publish(game); self:NotifyCompanion(game); self:ScheduleAI(game)
end
function Service:Publish(game, open)
    game.version = (game.version or 0) + 1
    local seen = {}
    for _, p in ipairs(game.participants) do
        if not p.bot and not seen[p.id] and self.byuser[p.id] == game.id then
            seen[p.id] = true
            self:Emit(p.id, "state", self:Snapshot(game, p.id, open))
        end
    end
end
function Service:Unlisten(record)
    for _, listener in ipairs(record.listeners or {}) do
        self.world:RemoveEventCallback("onremove", listener.fn, listener.entity)
    end
    record.listeners = nil
end
function Service:Watch(record, entity, fn)
    record.listeners = record.listeners or {}
    record.listeners[#record.listeners + 1] = {entity = entity, fn = fn}
    self.world:ListenForEvent("onremove", fn, entity)
end
function Service:Drop(game)
    if self.games[game.id] ~= game then return end
    Cancel(game.ai_task); Cancel(game.idle_task); Cancel(game.expiry_task)
    self:ClearBlackOffer(game)
    self:ClearOffer(game)
    self:ClearUndo(game)
    self:Unlisten(game)
    for _, p in ipairs(game.participants) do
        if self.byuser[p.id] == game.id then self.byuser[p.id] = nil end
    end
    self.games[game.id] = nil
end
function Service:Release(userid)
    local old = self:Current(userid)
    self.byuser[userid] = nil
    if old ~= nil then
        for _, p in ipairs(old.participants) do
            if not p.bot and self.byuser[p.id] == old.id then return end
        end
        self:Drop(old)
    end
end
function Service:Finish(game, reason, winner)
    if self.games[game.id] ~= game or game.finished then return end
    game.finished = true
    game.state.seen = nil -- superko positions are never needed after completion
    if game.state.status == "playing" or game.state.status == "scoring" then
        game.state.status, game.state.revision = "ended", game.state.revision + 1
    end
    game.reason, game.state.winner = reason, winner or game.state.winner
    self:OutcomeTalk(game)
    self:ClearBlackOffer(game)
    self:ClearOffer(game)
    self:ClearUndo(game)
    -- Finished boards/chats are transient. Only this compact result is durable.
    local archive = History.ForWorld(self.world)
    if archive ~= nil then
        archive:Append({game = game.game, names = {game.participants[1].name, game.participants[2].name},
            winner = game.state.winner, draw = game.state.status == "draw", reason = game.reason,
            score = game.state.score, day = self.world.state ~= nil and self.world.state.cycles or nil})
    end
    Cancel(game.ai_task); Cancel(game.idle_task)
    game.ai_task, game.idle_task = nil, nil
    self:Unlisten(game)
    Cancel(game.expiry_task)
    game.expiry_task = self.world:DoTaskInTime(600, function()
        if self.games[game.id] == game then self:Drop(game) end
    end)
    self:Publish(game)
    self:NotifyCompanion(game)
end
function Service:Touch(game)
    Cancel(game.idle_task)
    game.idle_task = self.world:DoTaskInTime(1800, function()
        if self.games[game.id] == game and Active(game) then self:Finish(game, "timeout") end
    end)
end
function Service:Start(gameid, first, second, bot)
    self:Release(first.userid)
    if not bot and first.userid ~= second.userid then self:Release(second.userid) end
    local game = {id = self:ID("g"), game = gameid, state = Catalog.Get(gameid).rules.New(), chat = {}, chat_seq = 0,
        participants = {{id = first.userid, name = Name(first)},
            {id = bot and ("companion:" .. tostring(second.GUID)) or second.userid, name = Name(second), bot = bot == true}}}
    if math.random(2) == 2 then game.participants[1], game.participants[2] = game.participants[2], game.participants[1] end
    self.games[game.id], self.byuser[first.userid] = game, game.id
    if not bot then self.byuser[second.userid] = game.id end
    self:Watch(game, first, function() self:Finish(game, "left") end)
    if second ~= first then self:Watch(game, second, function() self:Finish(game, "left") end) end
    self:Touch(game)
    self:BotTalk(game, true, true)
    self:Cheer(game, nil, true, true)
    self:Publish(game, true)
    self:NotifyCompanion(game)
    self:ScheduleAI(game)
    return game
end
function Service:CloseInvite(invite, reason)
    if self.invites[invite.id] ~= invite then return end
    self.invites[invite.id] = nil
    self.incoming[invite.to], self.outgoing[invite.from] = nil, nil
    Cancel(invite.task); self:Unlisten(invite)
    self:Emit(invite.to, "invite_closed", {id = invite.id, key = reason})
    self:Emit(invite.from, "invite_closed", {id = invite.id, key = reason})
end
function Service:Roster(player)
    local list = {}
    for _, p in ipairs(AllPlayers or {}) do
        if type(p.userid) == "string" and Policy.IsLocalPlayer(p) then
            list[#list + 1] = {id = p.userid, name = Name(p), self = p == player,
                busy = not self:CanPlay(p) or self:Busy(p.userid)
                    or self.incoming[p.userid] ~= nil or self.outgoing[p.userid] ~= nil}
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    self:Emit(player.userid, "roster", {players = list})
end
function Service:ScheduleAI(game)
    local nextplayer = game.participants[game.state.turn]
    if game.state.status ~= "playing" or not nextplayer.bot then return end
    game.ai_task = self.world:DoTaskInTime(.35, function()
        game.ai_task = nil
        if not self.world:IsValid() or self.games[game.id] ~= game or game.state.status ~= "playing" then return end
        if self:Companion(game) == nil then self:Finish(game, "left") return end
        local rules = Catalog.Get(game.game).rules
        local x, y = rules.ChooseMove(game.state)
        if x == nil then
            if rules.Pass ~= nil then rules.Pass(game.state) else self:Finish(game, "stopped"); return end
        else rules.Play(game.state, x, y) end
        self:ClearOffer(game)
        self:BotTalk(game, false, true)
        if game.state.status == "scoring" then self:AfterGo(game)
        elseif game.state.status ~= "playing" then self:Finish(game)
        else self:Touch(game); self:Publish(game) end
    end)
end
function Service:ClearOffer(game)
    Cancel(game.offer_task); game.offer_task, game.offer = nil, nil
end
function Service:AfterGo(game)
    self:ClearOffer(game); self:ClearBlackOffer(game); self:ClearUndo(game)
    Cancel(game.ai_task); game.ai_task = nil
    if game.state.status == "scoring" then
        for side, p in ipairs(game.participants) do
            if p.bot and not game.state.confirmed[side] then Catalog.Get(game.game).rules.Confirm(game.state, side) end
        end
    end
    if game.state.status == "won" or game.state.status == "draw" then self:Finish(game)
    else self:Touch(game); self:Publish(game); self:ScheduleAI(game) end
end
function Service:UndoRequest(player, game, action, data)
    local rules = Catalog.Get(game.game).rules
    if rules.CanUndo == nil or rules.Undo == nil or game.state.status ~= "playing" then
        self:Error(player, "undo_unavailable"); return
    end
    if action == "undo_reply" then
        local offer = game.undo_offer
        if offer == nil or offer.id ~= data.offer or offer.to ~= player.userid
            or type(data.accept) ~= "boolean" then self:Error(player, "forbidden"); return end
        if data.accept then
            if not rules.Undo(game.state, 1) then self:Error(player, "undo_unavailable"); return end
            self:ClearUndo(game); self:Touch(game); self:Publish(game); self:ScheduleAI(game)
        else self:ClearUndo(game); self:Publish(game) end
        return
    end
    if data.revision ~= game.state.revision then
        self:Emit(player.userid, "state", self:Snapshot(game, player.userid)); self:Error(player, "stale"); return
    end
    if game.undo_offer ~= nil then self:Error(player, "undo_pending_error"); return end
    local first, second = game.participants[1], game.participants[2]
    local has_bot = first.bot or second.bot
    if has_bot or first.id == second.id then
        local plies = has_bot and math.min(2, #(game.state.history or {})) or 1
        Cancel(game.ai_task); game.ai_task = nil
        if not rules.Undo(game.state, plies) then self:Error(player, "undo_unavailable"); return end
        self:Touch(game); self:Publish(game); self:ScheduleAI(game)
        return
    end
    local opponent = first.id == player.userid and second or first
    local offer = {id = self:ID("u"), from = player.userid, to = opponent.id, name = Name(player)}
    game.undo_offer = offer
    game.undo_task = self.world:DoTaskInTime(30, function()
        if self.games[game.id] == game and game.undo_offer == offer then
            self:ClearUndo(game); self:Publish(game)
        end
    end)
    self:Publish(game)
end
function Service:AcceptOffer(game, kind)
    self:ClearOffer(game)
    if kind == "count" then
        Catalog.Get(game.game).rules.BeginScoring(game.state); self:AfterGo(game)
    else
        game.state.status, game.state.revision = "draw", game.state.revision + 1
        self:Finish(game, "agreed_draw")
    end
end
function Service:GoRequest(player, game, action, data)
    local s, rules = game.state, Catalog.Get(game.game).rules
    if (game.participants[1].bot or game.participants[2].bot) and self:Companion(game) == nil then
        self:Finish(game, "left"); return
    end
    if action == "offer_reply" then
        local offer = game.offer
        if offer == nil or offer.id ~= data.offer or type(data.accept) ~= "boolean"
            or offer.to ~= player.userid then self:Error(player, "forbidden"); return end
        if data.accept then self:AcceptOffer(game, offer.kind)
        else self:ClearOffer(game); self:Publish(game) end
        return
    end
    if game.game ~= "go" then self:Error(player, "forbidden"); return end
    if data.revision ~= s.revision then
        self:Emit(player.userid, "state", self:Snapshot(game, player.userid)); self:Error(player, "stale"); return
    end
    if action == "count" or action == "draw_offer" then
        if game.offer ~= nil then self:Error(player, "offer_pending"); return end
        if action == "count" and s.status ~= "playing" then self:Error(player, "forbidden"); return end
        local side = game.participants[1].id == player.userid and 1 or 2
        local other = game.participants[3 - side]
        local kind = action == "count" and "count" or "draw_offer"
        if other.bot or other.id == player.userid then self:AcceptOffer(game, kind); return end
        local offer = {id = self:ID("o"), kind = kind, to = other.id}
        game.offer = offer
        game.offer_task = self.world:DoTaskInTime(30, function()
            if self.games[game.id] == game and game.offer == offer then self:ClearOffer(game); self:Publish(game) end
        end)
        self:Publish(game); return
    end
    local ok, reason
    if action == "pass" then
        if game.participants[s.turn].id ~= player.userid then self:Error(player, "wrong_turn"); return end
        ok, reason = rules.Pass(s)
    elseif action == "mark" then ok, reason = rules.Mark(s, data.x, data.y)
    elseif action == "play_on" then ok, reason = rules.Resume(s)
    elseif action == "confirm" then
        local selfplay = game.participants[1].id == game.participants[2].id
        local side = game.participants[1].id == player.userid and 1 or 2
        if selfplay and s.confirmed ~= nil and s.confirmed[1] then side = 2 end
        ok, reason = rules.Confirm(s, side)
    end
    if not ok then self:Error(player, reason or "forbidden"); return end
    Cancel(game.ai_task); game.ai_task = nil
    self:AfterGo(game)
end
function Service:Request(player, action, data, friend)
    if self.shutting_down or not self.world:IsValid() or not self.world.ismastersim or not Policy.IsLocalPlayer(player)
        or type(player.userid) ~= "string" or type(action) ~= "string"
        or not ACTIONS[action] or type(data) ~= "table" then return end
    local now = GetTime()
    local limits = player._my_friend_games_limits or {}
    player._my_friend_games_limits = limits
    if now < (limits[action] or 0) then self:Error(player, "rate") return end
    limits[action] = now + (action == "invite" and 2 or action == "chat" and .8
        or (action == "black" or action == "count" or action == "draw_offer" or action == "undo") and 5
        or action == "history" and .5 or .08)
    if action == "history" then
        if not self:Access(player, friend) or not self:CanPlay(player) then self:Error(player, "forbidden"); return end
        if type(data.page) ~= "number" or data.page % 1 ~= 0 or data.page < 1 then return end
        local archive = History.ForWorld(self.world)
        if archive == nil then self:Error(player, "history_error"); return end
        archive:Page(data.page, function(result)
            if result ~= nil then self:Emit(player.userid, "history", result) else self:Error(player, "history_error") end
        end)
    elseif action == "menu" then
        if not self:Access(player, friend) then self:Error(player, "unavailable") return end
        if not self:CanPlay(player) then self:Error(player, "affinity") return end
        self:Emit(player.userid, "menu", {games = Catalog.ORDER, current = self.byuser[player.userid]})
    elseif action == "roster" then
        if not self:Access(player, friend) then self:Error(player, "unavailable") return end
        if not self:CanPlay(player) then self:Error(player, "affinity") return end
        self:Roster(player)
    elseif action == "bot" or action == "invite" then
        if Catalog.Get(data.game) == nil or not self:Access(player, friend) then self:Error(player, "unavailable") return end
        if not self:CanPlay(player) then self:Error(player, "affinity") return end
        if self:Busy(player.userid) or self.incoming[player.userid] or self.outgoing[player.userid] then self:Error(player, "busy") return end
        if action == "bot" then
            local companion = self.world._my_friend
            if companion == nil or not companion:IsValid() or not companion:HasTag("my_friend")
                or companion.isplayer ~= true or Policy.DistanceSq(player, companion) > 20^2 then
                self:Error(player, "unavailable") return
            end
            self:Start(data.game, player, companion, true)
        else
            local target = type(data.target) == "string" and self:Player(data.target) or nil
            if target == nil then self:Error(player, "offline") return end
            if not self:CanPlay(target) then self:Error(player, "affinity") return end
            if self:Busy(target.userid) or self.incoming[target.userid] or self.outgoing[target.userid] then self:Error(player, "busy") return end
            if target == player then self:Start(data.game, player, player, false); return end
            local invite = {id = self:ID("i"), from = player.userid, to = target.userid, game = data.game}
            self.invites[invite.id], self.incoming[invite.to], self.outgoing[invite.from] = invite, invite.id, invite.id
            self:Watch(invite, player, function() self:CloseInvite(invite, "offline") end)
            if target ~= player then self:Watch(invite, target, function() self:CloseInvite(invite, "offline") end) end
            invite.task = self.world:DoTaskInTime(45, function() self:CloseInvite(invite, "expired") end)
            self:Emit(invite.from, "sent", {id = invite.id})
            self:Emit(invite.to, "invite", {id = invite.id, game = invite.game, name = Name(player)})
        end
    elseif action == "reply" then
        local invite = type(data.id) == "string" and self.invites[data.id] or nil
        if invite == nil or invite.to ~= player.userid or type(data.accept) ~= "boolean" then self:Error(player, "expired") return end
        if not data.accept then self:CloseInvite(invite, "declined") return end
        local first = self:Player(invite.from)
        if first == nil then self:CloseInvite(invite, "offline") return end
        if not self:CanPlay(player) or not self:CanPlay(first) then self:CloseInvite(invite, "affinity") return end
        if self:Busy(first.userid) or self:Busy(player.userid) then self:CloseInvite(invite, "busy") return end
        self:CloseInvite(invite, "accepted")
        self:Start(invite.game, first, player, false)
    elseif action == "cancel" then
        local invite = self.invites[self.outgoing[player.userid]]
        if invite ~= nil and invite.id == data.id then self:CloseInvite(invite, "cancelled") end
    elseif action == "move" or action == "resign" or action == "resume" or action == "leave"
        or action == "chat" or action == "black" or action == "black_reply"
        or action == "pass" or action == "count" or action == "draw_offer" or action == "offer_reply"
        or action == "mark" or action == "confirm" or action == "play_on"
        or action == "undo" or action == "undo_reply" then
        local game = self:Current(player.userid)
        if game == nil or action ~= "resume" and game.id ~= data.id then self:Error(player, "finished") return end
        if action == "resume" then self:Emit(player.userid, "state", self:Snapshot(game, player.userid, true)) return end
        if action == "leave" then
            if Active(game) then
                local side = game.participants[1].id == player.userid and 1 or 2
                self:Finish(game, "left_game", 3 - side)
            end
            self:Release(player.userid); self:Emit(player.userid, "left", {id = game.id}); return
        end
        if action == "chat" then
            local value = Chat.Normalize(data.kind, data.value)
            if value == nil then self:Error(player, "invalid_chat") return end
            local p = game.participants[game.participants[1].id == player.userid and 1 or 2]
            self:AddChat(game, p, data.kind, value, true); self:BotTalk(game, false, true); self:Publish(game); return
        end
        if not Active(game) then self:Error(player, "finished") return end
        if action == "undo" or action == "undo_reply" then
            self:UndoRequest(player, game, action, data); return
        end
        if action == "pass" or action == "count" or action == "draw_offer" or action == "offer_reply"
            or action == "mark" or action == "confirm" or action == "play_on" then
            self:GoRequest(player, game, action, data); return
        end
        if action == "black" then
            if game.participants[1].id == player.userid then self:Error(player, "already_black") return end
            if (game.state.count or 0) > 2 then self:Error(player, "black_unavailable"); return end
            if game.black_offer ~= nil then self:Error(player, "black_pending") return end
            if game.participants[1].bot then self:MakeBlack(game, player.userid); return end
            local offer = {id = self:ID("b"), from = player.userid, name = Name(player)}
            game.black_offer = offer
            game.black_task = self.world:DoTaskInTime(30, function()
                if self.games[game.id] == game and game.black_offer == offer then
                    self:ClearBlackOffer(game); self:Publish(game)
                end
            end)
            self:Publish(game); return
        elseif action == "black_reply" then
            local offer = game.black_offer
            if offer == nil or offer.id ~= data.offer or game.participants[1].id ~= player.userid
                or type(data.accept) ~= "boolean" then self:Error(player, "forbidden") return end
            if data.accept then self:MakeBlack(game, offer.from)
            else self:ClearBlackOffer(game); self:Publish(game) end
            return
        end
        if action == "resign" then
            local side = game.participants[1].id == player.userid and 1 or 2
            self:Finish(game, "resigned", 3 - side); return
        end
        if game.state.status ~= "playing" then self:Error(player, "forbidden"); return end
        if (game.participants[1].bot or game.participants[2].bot) and self:Companion(game) == nil then self:Finish(game, "left") return end
        if data.revision ~= game.state.revision then
            self:Emit(player.userid, "state", self:Snapshot(game, player.userid))
            self:Error(player, "stale"); return
        end
        if game.participants[game.state.turn].id ~= player.userid then self:Error(player, "wrong_turn") return end
        local ok, reason = Catalog.Get(game.game).rules.Play(game.state, data.x, data.y)
        if not ok then self:Error(player, reason) return end
        self:ClearOffer(game)
        self:ClearUndo(game)
        self:Cheer(game, player, false, true)
        if game.state.status ~= "playing" then self:Finish(game)
        else self:Touch(game); self:Publish(game); self:ScheduleAI(game) end
    end
end
function Service:Shutdown()
    self.shutting_down = true
    local invites, games = {}, {}
    for _, invite in pairs(self.invites) do invites[#invites + 1] = invite end
    for _, game in pairs(self.games) do games[#games + 1] = game end
    for _, invite in ipairs(invites) do self:CloseInvite(invite, "cancelled") end
    for _, game in ipairs(games) do self:Drop(game) end
end
return M
