-- Run from the mod root: lua tests/wortox_healing_test.lua
package.path = "scripts/?.lua;" .. package.path
local now, scans = 0, 0
GetTime = function() return now end
Vector3 = function(x, y, z) return {x = x, y = y, z = z} end
TUNING = {WORTOX_SOUL_HEAL_DELAY = 2, TOTAL_DAY_TIME = 480}
ACTIONS = {WALKTO = {}, DROP = {}, FEEDPLAYER = {}}
package.loaded.my_friend_dialogue = {Say = function() end}
package.loaded.my_friend_food_storage = {IsReserved = function() return false end,
    ReferenceItems = function(inst) return inst.components.inventory:ReferenceAllItems() end}
AllPlayers = {}

-- Minimal engine event/timer interfaces. Tests use the real role module,
-- shared health eligibility, food estimates and feeding action validation.
local function event_entity()
    local value = {listeners = {}, subscriptions = {}, tasks = {}}
    function value:ListenForEvent(event, callback, source)
        source = source or self
        source.listeners[event] = source.listeners[event] or {}
        local row = {listener = self, callback = callback}
        table.insert(source.listeners[event], row)
        table.insert(self.subscriptions, {event = event, source = source, row = row})
    end
    function value:RemoveEventCallback(event, callback, source)
        source = source or self
        local rows = source.listeners[event] or {}
        for i = #rows, 1, -1 do
            if rows[i].listener == self and rows[i].callback == callback then table.remove(rows, i) end
        end
    end
    function value:PushEvent(event, data)
        local copy = {}
        for _, row in ipairs(self.listeners[event] or {}) do copy[#copy + 1] = row end
        for _, row in ipairs(copy) do row.callback(self, data) end
    end
    function value:DoPeriodicTask(period, fn)
        local task = {period = period, fn = fn, nexttime = now + period}
        function task:Cancel() self.cancelled = true end
        self.tasks[#self.tasks + 1] = task
        return task
    end
    function value:DoTaskInTime(_, fn) return {fn = fn, Cancel = function() end} end
    return value
end
TheWorld = event_entity()
TheWorld.ismastersim = true
local function character(prefab, x, percent, companion)
    local inst = event_entity()
    inst.prefab, inst.components, inst.tags = prefab, {}, {player = true}
    inst.tags.my_friend = companion or nil
    inst.pos, inst.percent, inst.reads = Vector3(x or 0, 0, 0), percent or 1, 0
    function inst:IsValid() return not self.removed end
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    function inst:GetPosition() return Vector3(self.pos.x, 0, self.pos.z) end
    function inst:GetDistanceSqToInst(other)
        return (self.pos.x - other.pos.x)^2 + (self.pos.z - other.pos.z)^2
    end
    function inst:GetDistanceSqToPoint(point)
        return (self.pos.x - point.x)^2 + (self.pos.z - point.z)^2
    end
    function inst:ChangeHealth(percent)
        local old = self.percent
        self.percent, self.components.health.currenthealth = percent, percent * 100
        self:PushEvent("healthdelta", {oldpercent = old, newpercent = percent, amount = (percent - old) * 100})
    end
    function inst:Remove() self:PushEvent("onremove"); self.removed = true end
    inst.Transform = {GetWorldPosition = function() return inst.pos.x, 0, inst.pos.z end}
    inst.entity = {IsVisible = function() return not inst.invisible end}
    inst.components.health = {currenthealth = inst.percent * 100, maxhealth = 100, canheal = true,
        IsDead = function() return inst.dead == true end,
        IsHurt = function() return inst.percent < (inst.health_cap or 1) end,
        GetPercent = function() inst.reads = inst.reads + 1; return inst.percent end}
    inst.components.hunger = {current = 100, max = 100,
        GetPercent = function(self) return self.current / self.max end}
    inst.components.sanity = {current = 100, max = 100}
    inst.components.eater = {healthabsorption = 1, hungerabsorption = 1, sanityabsorption = 1,
        CanEat = function() return true end, PrefersToEat = function() return true end,
        DoFoodEffects = function() return true end}
    inst.state_tags = {idle = true}
    inst.sg = {currentstate = {name = "idle"},
        HasStateTag = function(_, tag) return inst.state_tags[tag] == true end,
        HasAnyStateTag = function(_, ...)
            for _, tag in ipairs({...}) do if inst.state_tags[tag] then return true end end
            return false
        end}
    return inst
end
BufferedAction = function(inst, target, action, item, point)
    local result = {doer = inst, target = target, action = action, invobject = item,
        pos = point, options = {}, successes = {}, failures = {}}
    function result:AddSuccessAction(fn) table.insert(self.successes, fn) end
    function result:AddFailAction(fn) table.insert(self.failures, fn) end
    function result:IsValid() return self.validfn == nil or self.validfn(self) end
    function result:Success() for _, fn in ipairs(self.successes) do fn() end end
    function result:Fail() for _, fn in ipairs(self.failures) do fn() end end
    return result
end
TheSim = {FindEntities = function(_, x, _, z, radius, must)
    scans = scans + 1
    assert(radius == 10 and must[1] == "player", "only the local ten-unit player query is allowed")
    local found = {}
    for _, player in ipairs(AllPlayers) do
        if player:IsValid() and (player.pos.x - x)^2 + (player.pos.z - z)^2 <= radius^2 then
            found[#found + 1] = player
        end
    end
    return found
end}
local Wortox = require("my_friend_wortox")
local Health = require("my_friend_health")
local Food = require("my_friend_food_ai")
local Feed = require("my_friend_feed_player")
local function companion()
    local inst = character("wortox", 0, 1, true)
    local soul = {prefab = "wortox_soul", components = {}, IsValid = function() return true end}
    soul.components.inventoryitem = {GetGrandOwner = function() return inst end}
    inst.items = {soul}
    inst.components.inventory = {maxslots = 1, itemslots = {soul}, GiveItem = function() return true end,
        ReferenceAllItems = function() return inst.items end}
    inst.components.follower = {GetLeader = function() return inst.leader end}
    Wortox.Configure(inst)
    return inst
end
local function periodic(inst)
    local task = inst._my_friend_soul_healing.task
    assert(task.period == 30 and not task.cancelled)
    now = task.nexttime
    task.nexttime = now + task.period
    task.fn(inst)
end

local near = character("wilson", 10, .7)
local far = character("wilson", 1000, .1)
AllPlayers = {near, far}
local inst = companion()
assert(scans == 0 and near.reads == 0 and far.reads == 0, "subscribing must not poll health")
for i = 1, 100 do
    assert(Wortox.GetHealPlayerScore(inst) == 0 and Wortox.GetHealPlayerAction(inst) == nil)
end
assert(scans == 0 and near.reads == 0 and far.reads == 0, "idle decisions must not rediscover players")
far:ChangeHealth(.05)
assert(far.reads == 0 and Wortox.GetHealPlayerScore(inst) == 0, "distant damage must not read health or trigger healing")
near:ChangeHealth(.7)
assert(near.reads == 0, "an unchanged healthdelta must not trigger discovery")
near:ChangeHealth(.69)
assert(Wortox.GetHealPlayerScore(inst) == 108 and scans == 0, "nearby changes trigger treatment without scans")
local action = assert(Wortox.GetHealPlayerAction(inst))
assert(action.action == ACTIONS.WALKTO and action.target == near and action.arrivedist == 4)
inst.pos.x = 8
action = assert(Wortox.GetHealPlayerAction(inst))
assert(action.action == ACTIONS.DROP and action.options.wholestack == false and action.pos.x == 8)
assert(action:IsValid(), "drop at the companion's feet, not on the player")
inst.state_tags.busy = true
assert(action:IsValid() and Wortox.GetHealPlayerAction(inst) == nil,
    "a selected drop must remain valid in its own busy animation without starting a second action")
inst.state_tags.busy = nil
action:Success()
assert(Wortox.GetHealPlayerAction(inst) == nil, "wait for native delayed healing before spending another soul")
now = now + TUNING.WORTOX_SOUL_HEAL_DELAY + .5
assert(Wortox.GetHealPlayerAction(inst) ~= nil, "below 80%, continue after native heal delay")
near:ChangeHealth(.8)
assert(Wortox.GetHealPlayerScore(inst) == 0 and Wortox.GetHealPlayerAction(inst) == nil)
assert(far.reads == 0 and scans == 0)
inst:Remove()

-- An injured player entering the area without a health event is found on the
-- 30s fallback, using the companion's current position rather than the leader.
near.pos.x, near.percent, near.components.health.currenthealth = 120, .79, 79
inst = companion(); inst.pos.x = 115
assert(Wortox.GetHealPlayerScore(inst) == 0)
local before = scans
periodic(inst)
assert(scans == before + 1 and Wortox.GetHealPlayerScore(inst) == 108)
for i = 1, 40 do Wortox.GetHealPlayerScore(inst); Wortox.GetHealPlayerAction(inst) end
assert(scans == before + 1 and far.reads == 0, "actions revalidate only known candidates")
near.pos.x = 125.1
assert(Wortox.GetHealPlayerScore(inst) == 0, "leaving the detection radius also ends treatment")
inst:Remove()

-- Keep leader preference, then choose the lowest health among triggered
-- candidates. Busy, threatened and occupied bodies cannot spend souls.
local leader = character("wilson", 4, 1)
local other = character("willow", 3, 1)
AllPlayers = {leader, other, far}
inst = companion(); inst.leader = leader
leader:ChangeHealth(.7); other:ChangeHealth(.2)
assert(Wortox.GetHealPlayerAction(inst).invobject ~= nil and inst._my_friend_soul_patient == leader)
inst.state_tags.busy = true
assert(Wortox.GetHealPlayerAction(inst) == nil)
inst.state_tags.busy = nil; inst._my_friend_under_threat = true
assert(Wortox.GetHealPlayerAction(inst) == nil)
inst._my_friend_under_threat = nil; inst._my_friend_possess_parked = true
before = scans; periodic(inst)
assert(scans == before and Wortox.GetHealPlayerScore(inst) == 0)
inst._my_friend_possess_parked = nil
leader:ChangeHealth(1); other:ChangeHealth(.19)
assert(Wortox.GetHealPlayerAction(inst).invobject ~= nil and inst._my_friend_soul_patient == other)
other.invisible = true
assert(Wortox.GetHealPlayerScore(inst) == 0)
other.invisible, other.dead = nil, true
assert(Wortox.GetHealPlayerScore(inst) == 0)
inst:Remove()

-- Native markers, age components and ordinary-healing flags apply equally
-- to souls and food. No character prefab blacklist is required.
local variants = {
    function(p) p.tags.health_as_oldage = true end,
    function(p) p.components.oldager = {} end,
    function(p) p.components.health.canheal = false end,
    function(p) p._no_healing = true end,
    function(p) p.tags.cannotheal = true end,
}
for _, setup in ipairs(variants) do
    local player = character("mod_time_character", 2, 1)
    setup(player)
    AllPlayers = {player}
    inst = companion(); inst.leader = player
    player:ChangeHealth(.2)
    assert(not Health.CanReceiveHealing(player) and not Food.CanHealWithFood(player))
    periodic(inst)
    assert(Wortox.GetHealPlayerScore(inst) == 0 and Wortox.GetHealPlayerAction(inst) == nil)
    assert(Feed.Score(inst, player) == 0, "a time meter must not cause feeding for health")
    inst:Remove()
end
assert(not Health.CanReceiveHealing({components = {}}))
local capped = character("wilson", 2, 1)
capped.health_cap = .4
AllPlayers = {capped}; inst = companion(); inst.leader = capped
capped:ChangeHealth(.4)
periodic(inst)
assert(Wortox.GetHealPlayerScore(inst) == 0 and Feed.Score(inst, capped) == 0,
    "health penalties must not cause endless healing above the recoverable maximum")
inst:Remove()
local player = character("mod_character", 2, 1)
AllPlayers = {player}; inst = companion(); inst.leader = player
player:ChangeHealth(.2)
action = assert(Wortox.GetHealPlayerAction(inst))
player.components.oldager = {}
assert(not action:IsValid(), "revalidate after a mod changes health semantics during travel")
local food = {prefab = "healing_food", components = {}, IsValid = function() return true end,
    HasAnyTag = function() return false end, HasTag = function() return false end}
food.components.inventoryitem = {GetGrandOwner = function() return inst end}
food.components.edible = {healthvalue = 40, sanityvalue = 0,
    GetHealth = function() return 40 end, GetHunger = function() return 30 end, GetSanity = function() return 0 end}
inst.items = {food}
assert(Food.GetFoodDeltas(player, food) == 0 and Feed.GetAction(inst) == nil)
player.components.hunger.current = 30
local feeding = assert(Feed.GetAction(inst))
assert(Feed.Score(inst, player) == 34 and feeding:IsValid(), "time-based characters can still be fed for hunger")
player.components.oldager = nil; player.components.hunger.current = 100
feeding = assert(Feed.GetAction(inst))
player.components.health.canheal = false
assert(not feeding:IsValid(), "queued feeding must revalidate ordinary healing eligibility")
inst:Remove()

-- Existing players bind once, late arrivals bind through world events, and
-- both departing players and the companion release callbacks and timers.
AllPlayers = {}; inst = companion()
local state = inst._my_friend_soul_healing
Wortox.Configure(inst); Wortox.ConfigureHealing(inst)
assert(inst._my_friend_soul_healing == state and #inst.tasks == 1)
player = character("wilson", 2, 1)
AllPlayers[1] = player
TheWorld:PushEvent("ms_playerjoined", player)
assert(#player.listeners.healthdelta == 1)
player:ChangeHealth(.7)
assert(Wortox.GetHealPlayerScore(inst) == 108)
TheWorld:PushEvent("ms_playerleft", player)
assert(#player.listeners.healthdelta == 0 and inst._my_friend_soul_patient == nil)
TheWorld:PushEvent("ms_playerjoined", player)
player:Remove()
assert(state.players[player] == nil and state.pending[player] == nil)
local replacement = character("wilson", 2, 1)
AllPlayers[1] = replacement; TheWorld:PushEvent("ms_playerjoined", replacement)
local task = state.task
inst:Remove()
assert(task.cancelled and #replacement.listeners.healthdelta == 0)
assert(#TheWorld.listeners.ms_playerjoined == 0 and #TheWorld.listeners.ms_playerleft == 0)
local non_wortox = character("wendy", 0, 1, true)
Wortox.Configure(non_wortox)
assert(non_wortox._my_friend_soul_healing == nil and #non_wortox.tasks == 0)
print("PASS: local health events, 30s ten-unit checks, native soul actions, time-based health exclusions, feeding for hunger, late joins and listener/task cleanup")
