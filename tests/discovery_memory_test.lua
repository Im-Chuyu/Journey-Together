-- Run from the mod root: lua tests/discovery_memory_test.lua
package.path = "scripts/?.lua;" .. package.path
local now, scans, global_scans, registrations, guid = 0, 0, 0, 0, 0
GetTime = function() return now end
ACTIONS = {CHOP = {}, MINE = {}, DIG = {}}
Vector3 = function(x, y, z) return {x = x, y = y, z = z} end
TUNING = {FRUITDRAGON = {HIT_RANGE = 3, ATTACK_RANGE = 2}, ALTERGUARDIAN_PHASE1_AOERANGE = 6,
    ALTERGUARDIAN_PROJECTILE_SPEED = 10}
Ents = {}
local rawpairs = pairs
pairs = function(value)
    if value == Ents then global_scans = global_scans + 1 end
    return rawpairs(value)
end
local world_tasks = {}
TheWorld = {ismastersim = true, state = {}, Map = {
    IsPassableAtPoint = function() return true end, GetTileAtPoint = function() return 0 end,
}, DoTaskInTime = function(_, delay, fn)
    assert(delay == 0)
    world_tasks[#world_tasks + 1] = fn
end}
local function flush()
    local tasks = world_tasks; world_tasks = {}
    for _, fn in ipairs(tasks) do fn(TheWorld) end
end
local function gc()
    collectgarbage("collect"); collectgarbage("collect")
    return collectgarbage("count")
end
EntityScript = {}
function EntityScript:IsValid() return not self.removed end
function EntityScript:HasTag(tag) return self.tags[tag] == true end
function EntityScript:HasAnyTag(...)
    for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
    return false
end
function EntityScript:GetPosition() return Vector3(self.x, 0, self.z) end
function EntityScript:ListenForEvent() registrations = registrations + 1 end
function EntityScript:PushEvent_Internal()
    self.native_events = (self.native_events or 0) + 1
    return nil, "event", nil
end
function EntityScript:PushEvent(event, data) return self:PushEvent_Internal(event, data) end
function EntityScript:Remove()
    self:PushEvent("onremove"); self.removed = true; Ents[self.GUID] = nil
end
local Transform = {GetWorldPosition = function(self) return self.inst.x, 0, self.inst.z end}
local function entity(prefab, x, tags)
    guid = guid + 1
    local e = setmetatable({prefab = prefab, GUID = guid, x = x or 0, z = 0,
        components = {}, tags = tags or {}}, {__index = EntityScript})
    e.Transform = setmetatable({inst = e}, {__index = Transform})
    Ents[e.GUID] = e
    return e
end
local function item(x)
    local e = entity("log", x, {_inventoryitem = true})
    e.components.inventoryitem = {canbepickedup = true}
    return e
end
TheSim = {FindEntities = function(_, x, _, z, radius, must, cant)
    scans = scans + 1
    local result = {}
    for _, e in rawpairs(Ents) do
        local allowed = e:IsValid() and (e.x - x)^2 + (e.z - z)^2 <= radius^2
        for _, tag in ipairs(must or {}) do allowed = allowed and e:HasTag(tag) end
        for _, tag in ipairs(cant or {}) do allowed = allowed and not e:HasTag(tag) end
        if allowed then result[#result + 1] = e end
    end
    return result
end}
local leader
package.loaded.my_friend_policy = {GetLeader = function() return leader end,
    InRange = function(_, e) return not e.outside_policy end}
package.loaded.my_friend_behavior_ai = {IsTargetUnsafe = function(_, e) return e.unsafe == true end}
package.loaded.my_friend_food_ai = {}
package.loaded.my_friend_navigation = {IsBlocked = function() return false end, IsNearHole = function() return false end}
local Pickable = {Regen = function(self) self.ready = true; return nil, "regrown", nil end}
local Crop, Dryer = {}, {Resume = function() return "resumed" end}
local Discovery = require("my_friend_discovery")
Discovery.Install(EntityScript, {pickable = Pickable, crop = Crop, dryer = Dryer})
Discovery.Install(EntityScript, {pickable = Pickable, crop = Crop, dryer = Dryer})

-- Steady-state spawn bookkeeping is per cell, not per world entity. Use the
-- real module and GC counters, with a generous bound for 32/64-bit Lua 5.1.
for i = 1, 10000 do item(i % 100 * 4).z = math.floor(i / 100) * 4 end
local before = gc()
for _, e in rawpairs(Ents) do Discovery.OnSpawn(e) end
local extra = gc() - before
assert(registrations == 0 and #world_tasks == 0)
assert(extra < 1024, "10000 unobserved entities must not acquire megabytes of per-entity bookkeeping")
for _, e in rawpairs(Ents) do assert(e._my_friend_discovery_watch == nil) end
print(string.format("Discovery spawn bookkeeping, 10000 entities: %.3f MiB", extra / 1024))
Ents = {}; gc()

-- Event forwarding and class wrappers preserve all native return values,
-- install once and never replace an individual component's callback.
local source = item(0)
local revision = Discovery.ResourceVersion({log = 1})
assert(select("#", source:PushEvent("ondropped")) == 3 and source.native_events == 1)
assert(Discovery.ResourceVersion({log = 1}) == revision + 1)
source.components.pickable = setmetatable({inst = source, product = "twigs"}, {__index = Pickable})
assert(select("#", source.components.pickable:Regen()) == 3 and source.components.pickable.ready)
assert(rawget(source.components.pickable, "Regen") == nil)
source:Remove(); source = nil; gc()

-- New prefabs are often placed after postinit. Final positions are notified
-- once in a single weak, world-owned batch, including empty-query wakeups.
local observer = {}
local function query() return Discovery.Query(observer, "local", "resources", 1000, 0, 0, 12) end
assert(#query() == 0)
for i = 1, 100 do local e = item(0); Discovery.OnSpawn(e); e.x = 1000 + i / 100 end
assert(#world_tasks == 1 and registrations == 0)
flush()
assert(#query() == 100)
local old_scans = scans
for _, e in rawpairs(Ents) do e.x = 2000; e:PushEvent("ondropped") end
assert(#query() == 0 and scans == old_scans + 1, "moving queried objects invalidates their previous area")
Ents = {}; observer = nil; gc()

-- An idle local query stores GUIDs and must not retain removed Lua objects.
local weak = setmetatable({}, {__mode = "v"})
observer = {}
do
    local e = item(3000); weak[1] = e
    Discovery.OnSpawn(e); flush()
    assert(#Discovery.Query(observer, "saved", "resources", 3000, 0, 0, 12) == 1)
    e:Remove()
end
gc(); assert(weak[1] == nil, "query cache must not keep a removed entity alive")
assert(#Discovery.Query(observer, "saved", "resources", 3000, 0, 0, 12) == 0)

-- Preserve the entire resource order: the safe target can be beyond any
-- tempting top-N memory cutoff. Reusing the cache must not rescan Ents.
local WorldResources = require("my_friend_world_resources")
local actor = {components = {inventory = {CanAcceptCount = function() return 1 end}},
    Transform = {GetWorldPosition = function() return 0, 0, 0 end}}
local last_guid, first_guid
for i = 1, 80 do
    local e = item(4000 + i)
    e.unsafe = i < 80
    first_guid, last_guid = first_guid or e.GUID, e.GUID
    Discovery.OnSpawn(e)
end
flush()
assert(WorldResources.Find(actor, {log = 1}) == Ents[last_guid])
local before_queries = gc()
for i = 2, 16 do WorldResources.Find(actor, {log = 1, ["need" .. i] = 1}) end
assert(gc() - before_queries < 256, "candidate metadata must not allocate a record per object")
local before_global = global_scans
Ents[last_guid].unsafe, Ents[first_guid].unsafe = true, false
now = now + 3
assert(WorldResources.Find(actor, {log = 1}) == Ents[first_guid] and global_scans == before_global)
weak = setmetatable({}, {__mode = "v"})
for id, e in rawpairs(Ents) do weak[id] = e end
for _, e in rawpairs(Ents) do e:Remove() end
gc(); assert(next(weak) == nil, "resource-query candidates must not retain removed objects")

-- Old home/base/player references must also be weak. A collected old
-- reference must not accidentally compare equal to a new nil context.
do
    local e = item(8000)
    leader = entity("wilson", 0)
    actor._my_friend_home, actor._my_friend_base = {}, {target = leader}
    weak.home, weak.base, weak.leader = actor._my_friend_home, actor._my_friend_base, leader
    Discovery.OnSpawn(e); flush(); WorldResources.Find(actor, {log = 1})
    Ents[leader.GUID] = nil
    actor._my_friend_home, actor._my_friend_base, leader = nil, nil, nil
end
gc(); assert(weak.home == nil and weak.base == nil and weak.leader == nil)
before_global = global_scans
assert(WorldResources.Find(actor, {log = 1}) ~= nil and global_scans == before_global + 1)

-- Resetting the bounded cell directory must invalidate an old empty cache,
-- even if its old sum and the new area's sum happen to be identical.
Discovery.MAX_CELLS = 4
assert(#Discovery.Query(observer, "empty", "structures", 100000, 0, 0, 1) == 0)
for i = 1, 10 do Discovery.OnSpawn(item(200000 + i * 64)) end
old_scans = scans
Discovery.Query(observer, "empty", "structures", 100000, 0, 0, 1)
assert(scans == old_scans + 1)
Discovery.MAX_CELLS = 4096
flush()

-- The actual boss FX cache must tolerate holes in weak value arrays, release
-- removed targets and clear remaining query state when combat resets.
local Profiles, Dodge = require("my_friend_dodge_profiles"), require("my_friend_dodge")
local inst = {components = {}}
local library = Profiles.Create(inst)
inst._my_friend_dodge = {profiles = library}
local fx_query
for _, row in ipairs(library.targetanimtable.wagboss_robot) do if row.avoid_break then fx_query = row.avoid_break end end
local fx_scans, found = 0, {}
TheSim = {FindEntities = function() fx_scans = fx_scans + 1; return {unpack(found)} end}
local enemy, debris, missile = entity("wagboss_robot", 0), entity("debris", 0), entity("wagboss_missile", 0)
found = {enemy, debris, missile}
assert(fx_query(enemy) == missile)
weak = setmetatable({debris = debris, enemy = enemy, missile = missile}, {__mode = "v"})
debris:Remove(); debris = nil; found = {}
gc(); assert(weak.debris == nil and fx_query(enemy) == missile and fx_scans == 1,
    "a collected intermediate slot must not hide later FX or force a rescan")
found = {enemy, missile}
Dodge.Reset(inst)
assert(fx_query(enemy) == missile and fx_scans == 2)
enemy:Remove(); missile:Remove(); enemy, missile, found = nil, nil, {}
gc(); assert(weak.enemy == nil and weak.missile == nil, "boss FX cache must not retain its weak key through cached results")
print("PASS: bounded spawn bookkeeping, shared native notifications, placement/movement invalidation, GUID cache ordering and collection, weak contexts, cell reset and boss FX collection")
