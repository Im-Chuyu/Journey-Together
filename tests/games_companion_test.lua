package.path = "scripts/?.lua;" .. package.path
local now = 10
GetTime = function() return now end
READY, RUNNING, SUCCESS, FAILED = 0, 1, 2, 3
Class = function(base, ctor)
    local c = {_ctor = ctor, _base = base}; c.__index = c
    return setmetatable(c, {__index = base, __call = function(_, ...)
        local value = setmetatable({}, c); ctor(value, ...); return value
    end})
end
BehaviourNode = {}
function BehaviourNode._ctor(self) self.status = READY end
function BehaviourNode:Reset() self.status = READY end
function BehaviourNode:Stop() if self.OnStop ~= nil then self:OnStop() end end
function BehaviourNode:Sleep(delay) self.nextupdatetime = now + delay end
local player = {userid = "A", x = 0, IsValid = function() return true end}
local other = {userid = "B", x = 0, IsValid = function() return true end}
local leader, available, allowed, urgent, route_action, stops = player, true, true, false, nil, 0
local inst = {GUID = 9, x = 1, components = {}, tags = {my_friend = true}}
function inst:IsValid() return true end
function inst:HasTag(tag) return self.tags[tag] == true end
function inst:GetBufferedAction() return self.action end
function inst:ClearBufferedAction() self.action = nil end
inst.components.locomotor = {Stop = function() stops = stops + 1 end}
inst.sg = {currentstate = {name = "idle"}, statemem = {}}
function inst.sg:HasStateTag(tag)
    return tag == "busy" and (self.currentstate.name == "eat"
        or self.currentstate.name == "emote" and now < (self.entered or 0) + .5)
end
local emote_starts = 0
function inst.sg:GoToState(name, data)
    assert(self.currentstate.name ~= "eat", "the game must never interrupt a genuine busy action")
    self.currentstate, self.statemem, self.entered = {name = name}, {}, now
    if name == "emote" then assert(data.loop and data.anim == "native_sit"); emote_starts = emote_starts + 1 end
end
local Policy = {GetLeader = function() return leader end, IsRoaming = function() return false end,
    IsFollowGatheringPaused = function() return false end,
    IsBusy = function(actor) return actor.sg:HasStateTag("busy") end,
    DistanceSq = function(a, b) return (a.x - b.x)^2 end,
    GuardAction = function(_, action) return action end}
package.loaded.my_friend_policy = Policy
package.loaded.my_friend_sitting = {Available = function(_, c)
    return available and not (c ~= nil and (c.threat or c.hurt or c.dark or c.thermal))
end}
package.loaded.my_friend_base_ai = {SetTask = function(actor, task) actor.task = task end}
package.loaded.my_friend_progress = {Check = function() end}
package.loaded.my_friend_behavior_ai = {ObservePlayerAttack = function() end}
package.loaded.my_friend_dialogue = {OnDecision = function() end}
package.loaded["behaviours/my_friend_route_action"] = function(actor, getter)
    local route = setmetatable({status = READY, getactionfn = getter}, {__index = BehaviourNode})
    function route:Visit() self.action = getter(actor); route_action = self.action; self.status = self.action ~= nil and RUNNING or FAILED end
    function route:OnStop() self.stopped = true end
    return route
end
ACTIONS = {WALKTO = {}}
BufferedAction = function(actor, target, kind)
    return {doer = actor, target = target, action = kind, Fail = function(self) self.failed = true end}
end
GetCommonEmotes = function() return {sit = {data = {anim = "native_sit", loop = true, fx = false}}} end
local game = {id = "g1", state = {status = "playing"}, participants = {{id = "A"}, {id = "companion:9", bot = true}}}
TheWorld = {_my_friend = inst, _my_friend_games = {Current = function(_, id) return id == "A" and game or nil end,
    CanPlay = function() return allowed end, Companion = function(_, match)
        for _, p in ipairs(match.participants) do if p.bot and p.id == "companion:9" then return inst end end
    end}}
local Companion = require("my_friend_games_companion")
assert(Companion.Score(inst) == 13)
game.participants[1], game.participants[2] = game.participants[2], game.participants[1]
assert(Companion.Score(inst) == 13, "the companion may sit while playing Black or White")
leader = nil; assert(Companion.Score(inst) == 0, "independent companions do not sit beside a game participant")
leader = other; assert(Companion.Score(inst) == 0, "only the actual followed opponent can request the pose")
leader = player; allowed = false; assert(Companion.Score(inst) == 0); allowed = true
assert(Companion.Score(inst, {threat = {}}) == 0)
inst.tags.wereplayer = true; assert(Companion.Score(inst) == 0); inst.tags.wereplayer = nil
inst.sg.HasState = function() return false end
assert(Companion.Score(inst) == 0, "modded state graphs without emotes must safely skip sitting")
inst.sg.HasState = nil
available = false; assert(Companion.Score(inst) == 0); available = true
local sit = Companion.Behaviour(inst)
local urgent_node = setmetatable({}, {__index = BehaviourNode})
function urgent_node:Visit() self.status = RUNNING end
local fallback = setmetatable({}, {__index = BehaviourNode})
function fallback:Visit() self.status = RUNNING end
local entries = {
    {id = "game_sit", score = function(c) return Companion.Score(inst, c) end, node = sit, passive = true},
    {id = "emergency", score = function() return urgent and 170 or 0 end, node = urgent_node},
    {id = "follow", score = function() return 10 end, node = fallback, passive = true},
}
local Utility = require("behaviours/my_friend_utility")
local root = Utility(inst, entries, function() return {leader = leader} end)
root:Visit()
assert(root.active.id == "game_sit" and inst.sg.currentstate.name == "emote" and emote_starts == 1)
now = now + .6
root:Visit()
assert(emote_starts == 1, "the native looping sit must not restart every AI tick")
urgent = true; now = now + .6; root:Visit()
assert(root.active.id == "emergency" and inst.sg.currentstate.name == "idle", "higher-priority behavior preempts the cosmetic sit")
urgent = false; now = now + .6; root:Visit()
assert(root.active.id == "game_sit" and emote_starts == 2, "the companion returns to sitting after the emergency")
now = now + .6
inst.x = 9; root:Visit()
assert(route_action ~= nil and route_action.target == player and route_action.arrivedist == 2.5)
assert(inst.sg.currentstate.name == "idle")
inst.x = 2.5
sit.route.pendingstatus, sit.route.status = SUCCESS, SUCCESS
now = now + .6; root:Visit()
assert(inst.sg.currentstate.name == "emote" and emote_starts == 3, "returning close enough resumes /sit")
now = now + .6
inst.sg.currentstate, inst.sg.statemem = {name = "hit"}, {}
urgent = true; root:Visit()
assert(inst.sg.currentstate.name == "hit", "interruption must not force another action back to idle")
urgent = false; inst.sg.currentstate = {name = "eat"}
local old_active = root.active
root:Visit(); assert(root.active == old_active, "busy actions retain ownership")
inst.sg.currentstate = {name = "idle"}; now = now + .6; root:Visit()
assert(root.active.id == "game_sit")
now = now + .6; game.state.status = "ended"; root:Visit()
assert(root.active.id == "follow" and inst.sg.currentstate.name == "idle", "game completion releases the loop")
print("PASS: followed-opponent-only /sit, affinity and survival guards, native loop reuse, real utility preemption/resumption, approach and busy ownership")
