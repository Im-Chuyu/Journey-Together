-- Run from the mod root: lua tests/discovery_trigger_test.lua
package.path = "scripts/?.lua;" .. package.path
local now, scans, global_scans, next_guid = 0, 0, 0, 0
GetTime = function() return now end
EQUIPSLOTS = {HEAD = "head", BODY = "body", HANDS = "hands"}
ACTIONS = {CHOP = {}, MINE = {}, DIG = {}, HARVEST = {}, PICKUP = {}}
TUNING = {TOTAL_DAY_TIME = 480}
Vector3 = function(x, y, z) return {x = x, y = y, z = z} end
local rawpairs = pairs
pairs = function(value)
    if value == Ents then global_scans = global_scans + 1 end
    return rawpairs(value)
end
Ents = {}
TheWorld = {ismastersim = true, state = {}, Map = {
    IsPassableAtPoint = function() return true end, GetTileAtPoint = function() return 0 end,
}}
local function entity(prefab, x, tags)
    next_guid = next_guid + 1
    local e = {prefab = prefab, GUID = next_guid, components = {}, tags = tags or {},
        x = x or 0, z = 0, events = {}, tasks = {}}
    function e:IsValid() return not self.removed end
    function e:HasTag(tag) return self.tags[tag] == true end
    function e:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    function e:AddTag(tag) self.tags[tag] = true end
    function e:RemoveTag(tag) self.tags[tag] = nil end
    function e:IsInLimbo() return self:HasTag("INLIMBO") end
    function e:GetPosition() return Vector3(self.x, 0, self.z) end
    function e:GetCurrentPlatform() end
    function e:GetPhysicsRadius() return .5 end
    function e:GetDistanceSqToInst(other) return (self.x - other.x)^2 + (self.z - other.z)^2 end
    function e:GetDistanceSqToPoint(point) return (self.x - point.x)^2 + (self.z - point.z)^2 end
    function e:ListenForEvent(event, fn)
        self.events[event] = self.events[event] or {}
        self.events[event][#self.events[event] + 1] = fn
    end
    function e:PushEvent(event, data)
        for _, fn in ipairs(self.events[event] or {}) do fn(self, data) end
    end
    function e:DoTaskInTime(_, fn) self.tasks[#self.tasks + 1] = fn end
    function e:DoPeriodicTask() error("discovery must not start periodic tasks") end
    function e:Flush()
        local tasks = self.tasks; self.tasks = {}
        for _, fn in ipairs(tasks) do fn(self) end
    end
    function e:Remove()
        self:PushEvent("onremove"); self.removed = true; Ents[self.GUID] = nil
    end
    e.Transform = {GetWorldPosition = function() return e.x, 0, e.z end}
    Ents[e.GUID] = e
    return e
end
local function matches(e, tags, all)
    for _, tag in ipairs(tags or {}) do
        if all and not e:HasTag(tag) or not all and e:HasTag(tag) then return not all end
    end
    return all
end
TheSim = {FindEntities = function(_, x, y, z, range, must, cant, oneof)
    scans = scans + 1
    local result = {}
    for _, e in rawpairs(Ents) do
        if e:IsValid() and (e.x - x)^2 + (e.z - z)^2 <= range^2
            and matches(e, must, true) and not matches(e, cant, false)
            and (oneof == nil or matches(e, oneof, false)) then result[#result + 1] = e end
    end
    return result
end}
local function noop() end
package.loaded.my_friend_policy = {GetLeader = noop, IsBusy = function() return false end,
    InRange = function() return true end, GuardAction = function(_, action) return action end,
    IsBaseCacheItem = function() return false end,
    DistanceSq = function(a, b) return a:GetDistanceSqToInst(b) end}
package.loaded.my_friend_navigation = {IsBlocked = function() return false end, IsNearHole = function() return false end}
package.loaded.my_friend_food_ai = {IsUsableFood = function(_, item) return item.components.edible ~= nil end}
package.loaded.my_friend_resource_reserves = {FollowingKeep = function() return {cutgrass = 20} end}
package.loaded.my_friend_equipment_reserves = {GetKeep = function() return {} end}
package.loaded.my_friend_dialogue = {Say = noop}
package.loaded.my_friend_exploration = {Save = noop, Load = noop}
package.loaded.my_friend_home = {Load = noop, Save = noop, Mode = noop}
package.loaded.my_friend_crafting_tech = {}
local Discovery = require("my_friend_discovery")
local Memory = require("my_friend_resource_memory")
local AI = require("my_friend_behavior_ai")
AI.IsTargetUnsafe = function() return false end
local WorldResources = require("my_friend_world_resources")
local BaseAI = require("my_friend_base_ai")
local Garden = require("my_friend_garden")
local Bags = require("my_friend_backpacks")
local Tidy = require("my_friend_tidy")
local Gather = require("my_friend_command_special_gather")
BufferedAction = function(inst, target, action, item)
    local a = {doer = inst, target = target, action = action, invobject = item, success = {}, failure = {}}
    function a:AddSuccessAction(fn) self.success[#self.success + 1] = fn end
    function a:AddFailAction(fn) self.failure[#self.failure + 1] = fn end
    return a
end
local function companion(x)
    local inst = entity("wendy", x)
    inst.components.health = {IsDead = function() return false end}
    inst.components.hunger = {GetPercent = function() return 1 end}
    local inventory = {inst = inst, items = {}}
    function inventory:ReferenceAllItems() return self.items end
    function inventory:GetEquippedItem() end
    function inventory:GetOverflowContainer() end
    function inventory:GetNumSlots() return 15 end
    function inventory:NumItems() return #self.items end
    function inventory:CanAcceptCount() return 1 end
    inst.components.inventory = inventory
    return inst, inventory
end
local function item(prefab, x, owner)
    local e = entity(prefab, x, {_inventoryitem = true})
    e.components.inventoryitem = {owner = owner, canbepickedup = true,
        GetGrandOwner = function() return e.components.inventoryitem.owner end}
    return e
end
local function container(prefab, x, drying)
    local e = entity(prefab, x, {_container = true, structure = true})
    local c = {inst = e, slots = {}, type = "chest", canbeopened = true}
    c.IsRestricted, c.IsOpenedByOthers = function() return false end, function() return false end
    function c:CanAcceptCount() return 20 end
    function c:GetAllItems() return self.slots end
    e.components.container = c
    if drying then e.components.dryingrack = {} end
    Discovery.ConfigureEntity(e); e:Flush()
    return e
end

-- An empty local discovery remains empty across arbitrarily many ticks.
local inst = companion(0)
local function query() return Discovery.Query(inst, "chests", "containers", inst.x, 0, 0, 12,
    {"_container"}, {"INLIMBO"}, nil, true) end
assert(#query() == 0)
local before = scans
for i = 1, 30 do now = now + 30; assert(#query() == 0) end
assert(scans == before, "empty discoveries must not expire on a timer")
local far = container("treasurechest", 500)
assert(#query() == 0 and scans == before, "distant facility changes must not invalidate a local discovery")
local chest = container("treasurechest", 5)
assert(#query() == 1 and scans == before + 1, "new nearby facilities wake a negative discovery")
before = scans; chest:PushEvent("itemget")
assert(#query() == 1 and scans == before + 1)
chest:Remove(); assert(#query() == 0)
before = scans; inst.x = 2; query(); assert(scans == before, "small movement reuses the discovery fringe")
inst.x = 8; query(); assert(scans == before + 1, "entering a new search area triggers discovery")

-- Empty owned-backpack lookup has one legacy bootstrap, never a timed retry.
local bag_inst = companion(800)
Bags.FindOwned(bag_inst); before = global_scans
for i = 1, 20 do now = now + 20; assert(Bags.FindOwned(bag_inst) == nil) end
assert(global_scans == before)
local bag = item("backpack", 810)
bag.tags.backpack = true
bag.components.equippable = {equipslot = "body", IsRestricted = function() return false end}
Bags.WrapBackpack(bag)
bag:OnLoad({my_friend_owned_backpack = true})
assert(Bags.FindOwned(bag_inst) == bag and global_scans == before, "loaded ownership enters the index directly")
Bags.ClearOwned(bag); assert(Bags.FindOwned(bag_inst) == nil)
Bags.MarkOwned(bag_inst, bag)
assert(Bags.FindOwned(bag_inst) == bag and global_scans == before)
bag:Remove(); assert(Bags.FindOwned(bag_inst) == nil)

-- Missing resources stay negative; new relevant resources, inventory, area
-- and explicit retry expiry each trigger a new search episode.
local seeker = companion(1000)
assert(WorldResources.Find(seeker, {log = 1}) == nil)
before = global_scans
for i = 1, 20 do now = now + 20; assert(WorldResources.Find(seeker, {log = 1}) == nil) end
assert(global_scans == before, "missing resources do not start eight-second full-world loops")
local unrelated = item("rocks", 1040); Discovery.ConfigureEntity(unrelated)
WorldResources.Find(seeker, {log = 1}); assert(global_scans == before)
local log = item("log", 1050); Discovery.ConfigureEntity(log)
assert(WorldResources.Find(seeker, {log = 1}) == log and global_scans == before + 1)
before = global_scans
now = now + 100; assert(WorldResources.Find(seeker, {log = 1}) == log and global_scans == before)
local deadline = now + 10
seeker._my_friend_base_blocked = {[log.GUID] = deadline}
local function blocked(target) return target == log and now < deadline end
assert(WorldResources.Find(seeker, {log = 1}, blocked) == nil)
before = global_scans
now = now + 5; assert(WorldResources.Find(seeker, {log = 1}, blocked) == nil and global_scans == before)
now = deadline; assert(WorldResources.Find(seeker, {log = 1}, blocked) == log and global_scans == before + 1)
Discovery.InventoryChanged(seeker); WorldResources.Find(seeker, {log = 1}); assert(global_scans == before + 2)
seeker.x = seeker.x + 9; WorldResources.Find(seeker, {log = 1}); assert(global_scans == before + 3)

-- Existing resource memory resolves locally, without another full traversal.
Memory.Observe(seeker, {log}, log.x, log.z, 4, now)
seeker._my_friend_world_resource_query = nil
before = global_scans
assert(WorldResources.Find(seeker, {log = 1}) == log and global_scans == before)
local unsafe = true
AI.IsTargetUnsafe = function(_, target) return target == log and unsafe end
assert(WorldResources.Find(seeker, {log = 1}) == nil and global_scans == before)
unsafe, now = false, now + 3
assert(WorldResources.Find(seeker, {log = 1}) == log and global_scans == before,
    "moving threats are rechecked without full-world rediscovery")
AI.IsTargetUnsafe = function() return false end

-- Static base facilities share one snapshot, including negative results.
local resident = companion(2000)
resident._my_friend_base = {x = 2000, z = 0}
assert(BaseAI.FindBaseStructure(resident, "researchlab") == nil)
before = scans
for i = 1, 15 do BaseAI.FindBaseStructure(resident, "researchlab"); BaseAI.FindBaseStructure(resident, "firepit") end
assert(scans == before)
local lab = entity("researchlab", 2002, {structure = true})
BaseAI.OnBuildStructure(resident, lab); lab:Flush()
assert(BaseAI.FindBaseStructure(resident, "researchlab") == lab)
lab:Remove(); assert(BaseAI.FindBaseStructure(resident, "researchlab") == nil)

-- Plant regrowth has no native event. The wrapped native method invalidates
-- discoveries, runs once, preserves nil return values and is installed once.
local plant = entity("grass", 2004)
local calls = 0
plant.components.pickable = {inst = plant, product = "cutgrass", transplanted = true,
    CanBePicked = function(self) return self.ready end,
    CanBeFertilized = function(self) return not self.ready end,
    Regen = function(self) calls = calls + 1; self.ready = true; return nil, "regrown" end}
Discovery.ConfigureEntity(plant); plant:Flush()
local plants, barren = Garden.Plants(resident, resident:GetPosition(), 34, function() return true end)
assert(#plants == 1 and barren == 1)
before = scans; Garden.Plants(resident, resident:GetPosition(), 34, function() return true end); assert(scans == before)
Discovery.ConfigureEntity(plant)
local first, second = plant.components.pickable:Regen()
assert(first == nil and second == "regrown" and calls == 1)
plants, barren = Garden.Plants(resident, resident:GetPosition(), 34, function() return true end)
assert(#plants == 1 and barren == 0 and scans == before + 1)

-- An empty automatic rack search sleeps until a rack changes or we move.
local collector = companion(3000)
assert(Gather.GetNearbyDryingRackAction(collector) == nil)
before = scans
for i = 1, 20 do now = now + 20; Gather.GetNearbyDryingRackAction(collector) end
assert(scans == before)
local rack = entity("meatrack", 3002, {structure = true})
local completed = 0
rack.components.dryer = {ondonedrying = function(self) completed = completed + 1; self:AddTag("dried"); return "done" end}
Discovery.ConfigureEntity(rack); rack:Flush()
Gather.GetNearbyDryingRackAction(collector)
before = scans
assert(rack.components.dryer.ondonedrying(rack) == "done" and completed == 1)
local harvest = Gather.GetNearbyDryingRackAction(collector)
assert(harvest ~= nil and harvest.target == rack and scans == before + 1)
local new_collector = companion(3200)
local new_rack = container("meatrack", 3202, true)
local raw = item("meat", 3202, new_rack)
raw.components.dryable = {}
new_rack.components.container.slots[1] = raw
assert(Gather.GetNearbyDryingRackAction(new_collector) == nil)
before = scans
for i = 1, 10 do Gather.GetNearbyDryingRackAction(new_collector) end
assert(scans == before)
local dried = item("meat_dried", 3202, new_rack)
new_rack.components.container.slots[1] = dried
new_rack:PushEvent("itemlose", {prev_item = raw})
new_rack:PushEvent("itemget", {item = dried})
harvest = Gather.GetNearbyDryingRackAction(new_collector)
assert(harvest ~= nil and harvest.invobject == dried and scans == before + 1,
    "native container drying completion wakes the automatic harvest")
local edge_collector = companion(3400)
local edge_rack = entity("meatrack", 3414, {structure = true, dried = true})
edge_rack.components.dryer = {}
Discovery.ConfigureEntity(edge_rack); edge_rack:Flush()
assert(Gather.GetNearbyDryingRackAction(edge_collector) == nil, "discovery fringe must not extend action range")
before = scans; edge_collector.x = 3402
assert(Gather.GetNearbyDryingRackAction(edge_collector).target == edge_rack and scans == before,
    "small movement rechecks known fringe candidates without rediscovery")

-- Tidying retries when an item arrives, storage changes, gift protection
-- expires or a failed-container deadline passes; idle ticks do no work.
local tidier, inventory = companion(4000)
local store = container("treasurechest", 4002)
assert(Tidy.GetNearbyRelaxedAction(tidier) == nil)
before = scans
for i = 1, 20 do now = now + 20; Tidy.GetNearbyRelaxedAction(tidier) end
assert(scans == before)
local cargo = item("cutgrass", 4000, tidier)
cargo.components.stackable = {StackSize = function() return 30 end}
inventory.items = {cargo}; Discovery.InventoryChanged(tidier)
assert(Tidy.GetNearbyRelaxedAction(tidier).target == store and scans == before)
cargo._my_friend_player_organize_until = now + 10
Discovery.InventoryChanged(tidier)
assert(Tidy.GetNearbyRelaxedAction(tidier) == nil)
now = now + 10; assert(Tidy.GetNearbyRelaxedAction(tidier) ~= nil)
tidier._my_friend_storage_retry = {[store] = now + 10}
store:PushEvent("onclose")
assert(Tidy.GetNearbyRelaxedAction(tidier) == nil)
before = scans; now = now + 10
assert(Tidy.GetNearbyRelaxedAction(tidier) ~= nil and scans == before)

-- Saves carry coordinates/counts only; a restored companion rediscovers
-- local facilities on its current shard rather than inheriting live caches.
local saved = {}
seeker._my_friend_base = {x = seeker.x, z = 0}
BaseAI.OnSave(seeker, saved)
assert(#saved.my_friend_resource_memory > 0 and saved.my_friend_resource_memory[1].entity == nil)
seeker._my_friend_discoveries = {old = true}
BaseAI.OnLoad(seeker, saved)
assert(seeker._my_friend_discoveries == nil and seeker._my_friend_world_resource_query == nil)
assert(next(seeker._my_friend_resource_memory) ~= nil)
-- Manual bases keep the player's exact centre and record facilities in the
-- same cached, event-invalidated registry. Recording does not claim ownership.
local home_stub = package.loaded.my_friend_home
package.loaded.my_friend_home = nil
local Home = require("my_friend_home")
home_stub.Mode, home_stub.Facilities, home_stub.WANDER_RADIUS = Home.Mode, Home.Facilities, Home.WANDER_RADIUS
resident = companion(8000)
local facility_list = {}
for index, prefab in ipairs({"cookpot", "researchlab", "researchlab2", "saltbox", "icebox", "treasurechest"}) do
    facility_list[#facility_list + 1] = container(prefab, 8000 + index * 4)
end
local edge = container("treasurechest", 8032)
local outside = container("icebox", 8032.1)
before = scans
Home.Set(resident, Vector3(8000, 0, 0), "base")
assert(Home.Get(resident).x == 8000 and scans == before + 1)
assert(#Home.Facilities(resident) == 7 and Home.TravelLimit(resident) == 32)
assert(Home.IsPointInRange(resident, Vector3(8032, 0, 0))
    and not Home.IsPointInRange(resident, Vector3(8032.1, 0, 0)))
for _, facility in ipairs(facility_list) do assert(facility._my_friend_base_structure == nil) end
before = scans
for i = 1, 10 do Home.Facilities(resident); BaseAI.FindBaseStructure(resident, "researchlab") end
assert(scans == before, "facility lookup must not restart periodic base scans")
edge:Remove()
assert(#Home.Facilities(resident) == 6 and scans == before + 1)
local new_facility = container("cookpot", 8028)
assert(#Home.Facilities(resident) == 7)
new_facility:PushEvent("onignite"); new_facility.tags.fire = true
assert(#Home.Facilities(resident) == 6, "burning facilities cannot remain usable")
local house_save = {}; Home.Save(resident, house_save)
assert(house_save.my_friend_home.x == 8000 and house_save.my_friend_home.mode == "base")
assert(house_save.my_friend_home.entity == nil and house_save.my_friend_home.facilities == nil)
local restored = companion(9000); Home.Load(restored, house_save)
assert(Home.Get(restored).x == 8000 and #Home.Facilities(restored) == 6)
Home.Set(resident, Vector3(9000, 0, 0), "base")
assert(#Home.Facilities(resident) == 0, "replacing a base drops the old facility catalogue")
Home.Set(resident, Vector3(9000, 0, 0), "hold")
assert(Home.TravelLimit(resident) == 40, "wait-here retains its existing travel margin")
print("PASS: event-triggered discovery, persistent negative results, scoped changes, ownership index, resource memory/retries, native regrowth/drying, tidy wakeups and save reset")
