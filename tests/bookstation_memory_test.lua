-- Run from the mod root: lua tests/bookstation_memory_test.lua
package.path = "scripts/?.lua;" .. package.path
local now = 10
GetTime = function() return now end
Vector3 = function(x, y, z) return {x = x, y = y, z = z} end
ACTIONS = {MY_FRIEND_OPEN = {}, MY_FRIEND_STORE = {}, READ = {}, PICKUP = {}, WALKTO = {}}
BufferedAction = function(inst, target, action, item, pos)
    local value = {doer = inst, target = target, action = action, invobject = item, pos = pos}
    function value:GetActionPoint() return self.pos or self.target and self.target:GetPosition() end
    function value:AddSuccessAction(fn) self.success = fn end
    function value:AddFailAction(fn) self.failure = fn end
    return value
end
package.loaded.my_friend_inventory = {ContainerReach = function() return 2 end}
package.loaded.my_friend_dialogue = {Reply = function() end}
package.loaded.my_friend_base_ai = {GetBasePoint = function() return nil end}
package.loaded.my_friend_commands = {Clear = function(inst) inst._my_friend_command = nil end}
local function entity(prefab, x)
    local e = {prefab = prefab, pos = {x = x, y = 0, z = 0}, components = {}, removed = false}
    function e:IsValid() return not self.removed end
    function e:HasTag(tag) return tag == "structure" and self.prefab == "bookstation" end
    function e:HasAnyTag(...) for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end return false end
    function e:GetPosition() return self.pos end
    function e:GetDistanceSqToPoint(p) return (self.pos.x - p.x)^2 + (self.pos.z - p.z)^2 end
    function e:GetDistanceSqToInst(other) return self:GetDistanceSqToPoint(other.pos) end
    function e:GetCurrentPlatform() return nil end
    function e:PushEvent() end
    e.Transform = {GetWorldPosition = function() return e.pos.x, 0, e.pos.z end}
    return e
end
local inst, shelf = entity("wickerbottom", -30), entity("bookstation", 31)
local leader
inst.components.follower = {GetLeader = function() return leader end}
local book = entity("book_birds", 31)
book.components = {book = {}, finiteuses = {GetUses = function() return 5 end},
    inventoryitem = {owner = shelf, GetGrandOwner = function() return shelf end}}
local opened, inventory_books = false, {}
shelf.components.container = {slots = {book}, readonlycontainer = false,
    IsRestricted = function() return false end, IsOpenedByOthers = function() return false end,
    IsOpenedBy = function() return opened end, CanTakeItemInSlot = function() return true end,
    CanAcceptCount = function() return 1 end}
inst.components.inventory = {ReferenceAllItems = function() return inventory_books end,
    CanAcceptCount = function() return 1 end}
inst.sg = {currentstate = {name = "idle"}, HasStateTag = function() return false end}
local stations = {shelf}
local discoveries, resolutions, nearby_discoveries = 0, 0, 0
TheSim = {FindEntities = function(_, x, _, z, radius, must)
    if must ~= nil and must[1] == "_inventoryitem" then return {} end
    if must ~= nil and must[1] == "structure" then
        if radius == 3 then resolutions = resolutions + 1
        else discoveries = discoveries + 1 end
        if radius == 20 then nearby_discoveries = nearby_discoveries + 1 end
    end
    local result = {}
    for _, station in ipairs(stations) do
        if station:IsValid() and (station.pos.x - x)^2 + (station.pos.z - z)^2 <= radius^2 then
            result[#result + 1] = station
        end
    end
    return result
end}
local Home = require("my_friend_home")
local Memory = require("my_friend_wickerbottom")
local Books = require("my_friend_books")
local Navigation = require("my_friend_navigation")
Home.Set(inst, Vector3(0, 0, 0), "base")
assert(Memory.IsRemembered(inst, shelf))
assert(discoveries == 1)
for _ = 1, 10 do
    now = now + 6
    Memory.Stations(inst)
end
assert(discoveries == 1 and resolutions == 0, "idle memory lookup must never refresh shelf positions")
local command = {special = "read", target = "book_birds"}
inst._my_friend_command = command
local action = Books.GetReadAction(inst, command)
assert(action ~= nil and action.action == ACTIONS.MY_FRIEND_OPEN and action.target == shelf,
    "61 units away, walk to the remembered shelf instead of reporting a missing book")
inst._my_friend_navigation_action = action
assert(Navigation.InTravelRange(inst, shelf.pos) and action:validfn())
inst.pos.x, opened = 30, true
action = Books.GetReadAction(inst, command)
assert(action.action == ACTIONS.READ and action.invobject == book and action:validfn())
-- An exhausted carried book is stored at the same remembered shelf from afar.
inst.pos.x, inst._my_friend_command, opened = -30, nil, false
local old = entity("book_birds", -30)
old.components = {book = {}, finiteuses = {GetUses = function() return 1 end},
    inventoryitem = {GetGrandOwner = function() return inst end}}
inventory_books = {old}
action = Books.GetStoreAction(inst)
assert(action.action == ACTIONS.MY_FRIEND_STORE and action.target == shelf and action:validfn())
assert(discoveries == 1 and resolutions == 0, "reading/storing uses existing records without discovery scans")
local saved = {}; Memory.Save(inst, saved)
assert(saved.my_friend_bookstations.stations[1].entity == nil, "save coordinates without live entity references")
stations, inventory_books = {}, {}
Memory.Load(inst, saved)
command = {special = "read", target = "book_birds"}
inst._my_friend_command = command
local visit = Books.GetReadAction(inst, command)
assert(visit ~= nil and visit.action == ACTIONS.WALKTO and visit.pos.x == 31,
    "an unresolved saved shelf must be visited, not treated as a missing book")
inst._my_friend_command, stations = nil, {shelf}
Memory.Load(inst, saved)
assert(#Memory.Stations(inst) == 0, "loading/looking up coordinates does not scan")
inst._my_friend_command = {special = "read", target = "book_birds"}
visit = Books.GetReadAction(inst, inst._my_friend_command)
inst.pos.x = 30
visit.success()
inst._my_friend_command = nil
assert(Memory.Stations(inst)[1] == shelf)
assert(discoveries == 1 and resolutions == 1, "arrival resolves only the saved coordinate once")
-- Changing the base retires old shelves and binds the new local catalogue.
local replacement = entity("bookstation", 105)
replacement.components.container = shelf.components.container
stations = {shelf, replacement}
Home.Set(inst, Vector3(100, 0, 0), "base")
assert(not Memory.IsRemembered(inst, shelf) and Memory.IsRemembered(inst, replacement))
replacement.removed = true
now = now + 6; assert(#Memory.Stations(inst) == 0)
local before = discoveries
stations = {}
inst.pos.x = 100
command = {special = "read", target = "book_birds"}
inst._my_friend_command = command
for _ = 1, 5 do assert(Books.GetReadAction(inst, command) == nil) end
assert(discoveries == before + 2, "an empty read request searches the base and nearby area once each")
inst._my_friend_command, inventory_books = nil, {old}
now = now + 6
assert(Books.GetStoreAction(inst) == nil and discoveries == before + 2,
    "automatic storage must not repeatedly scan for new shelves when memory is empty")
local other = entity("wendy", 0)
Memory.RememberBase(other, Vector3(0, 0, 0))
Memory.Scan(other)
Memory.Prune(other)
assert(#Memory.Stations(other) == 0 and Books.GetReadAction(other, {}) == nil
    and Books.GetStoreAction(other) == nil)
assert(discoveries == before + 2 and resolutions == 1, "other characters must not enter the shelf workflow")
local function reader(x)
    local value = entity("wickerbottom", x)
    value.components.inventory = {ReferenceAllItems = function() return {} end,
        CanAcceptCount = function() return 1 end}
    value.components.follower = {GetLeader = function() return leader end}
    value.sg = inst.sg
    return value
end
local function bookshelf(x, prefab)
    local value, volume = entity("bookstation", x), entity(prefab or "book_birds", x)
    volume.components = {book = {}, finiteuses = {GetUses = function() return 5 end},
        inventoryitem = {owner = value, GetGrandOwner = function() return value end}}
    value.components.container = {slots = {volume},
        IsRestricted = function() return value.restricted end,
        IsOpenedByOthers = function() return value.opened_by_other end,
        IsOpenedBy = function() return value.opened end,
        Close = function() value.opened = false end,
        CanTakeItemInSlot = function() return true end, CanAcceptCount = function() return 1 end}
    return value, volume
end
local function request(value)
    local result = {special = "read", target = "book_birds"}
    value._my_friend_command = result
    return result
end

-- No base at all: a public read request still discovers nearby shelves,
-- independently of a far-away leader and the ordinary activity circle.
inst = reader(1000)
local local_shelf, local_book = bookshelf(1008)
stations = {local_shelf}
leader = entity("wilson", 2000); AllPlayers = {leader}
command = request(inst)
before = discoveries
action = assert(Books.GetReadAction(inst, command))
assert(action.target == local_shelf and action.action == ACTIONS.MY_FRIEND_OPEN and action:validfn())
inst._my_friend_navigation_action = action
assert(Navigation.InTravelRange(inst, Vector3(1002, 0, 0)))
assert(not Navigation.InTravelRange(inst, Vector3(900, 0, 0)), "shelf access must not grant unlimited travel")
for _ = 1, 8 do Books.GetReadAction(inst, command) end
assert(discoveries == before + 1, "one nearby scan per request, even with no base")
local transient = {}; Memory.Save(inst, transient)
assert(transient.my_friend_bookstations == nil)
inst.pos.x, local_shelf.opened = 1007, true
action = assert(Books.GetReadAction(inst, command))
assert(action.action == ACTIONS.READ and action.invobject == local_book and action:validfn())
action.success()
assert(inst._my_friend_command == nil and not action:validfn() and #Memory.Stations(inst) == 0,
    "request-local shelves must retire with their command")
leader, AllPlayers = nil, {}

-- Existing but empty/wrong-book records must not hide a newly built shelf.
inst = reader(2010)
local empty_shelf = bookshelf(2000, "book_fire")
stations = {empty_shelf}
Home.Set(inst, Vector3(2000, 0, 0), "base")
local fresh = bookshelf(2020)
stations = {empty_shelf, fresh}
command = request(inst); before = discoveries
action = assert(Books.GetReadAction(inst, command))
assert(action.target == fresh and discoveries == before + 1,
    "a missing requested book permits one base refresh despite existing records")

-- Inside the base, the requested volume can live on a nearby shelf outside
-- the 32-unit circle. Its access is temporary; the base centre stays fixed.
inst = reader(3025)
empty_shelf = bookshelf(3000, "book_fire")
stations = {empty_shelf}
Home.Set(inst, Vector3(3000, 0, 0), "base")
local_shelf = bookshelf(3040)
stations = {empty_shelf, local_shelf}
command = request(inst); before = discoveries
action = assert(Books.GetReadAction(inst, command))
assert(action.target == local_shelf and discoveries == before + 2)
inst._my_friend_navigation_action = action
assert(Navigation.InTravelRange(inst, local_shelf.pos) and action:validfn())
local only_base = {}; Memory.Save(inst, only_base)
assert(#only_base.my_friend_bookstations.stations == 1
    and only_base.my_friend_bookstations.stations[1].x == 3000)
inst._my_friend_command = nil
assert(not action:validfn() and Home.Get(inst).x == 3000)

-- Far outside the base, first steps back to a remembered shelf remain valid.
inst = reader(3800)
shelf = bookshelf(4010); stations = {shelf}
Home.Set(inst, Vector3(4000, 0, 0), "base")
command = request(inst)
action = assert(Books.GetReadAction(inst, command))
inst._my_friend_navigation_action = action
assert(action.target == shelf and Navigation.InTravelRange(inst, Vector3(3801, 0, 0)))
assert(not Navigation.InTravelRange(inst, Vector3(3801, 0, 20)))
local_shelf = bookshelf(3808)
stations = {shelf, local_shelf}
command = request(inst)
action = assert(Books.GetReadAction(inst, command))
assert(action.target == local_shelf, "equal-durability books prefer the nearby shelf over a distant base")

-- A failed saved-coordinate visit must allow the command to find another
-- shelf, rather than repeatedly returning the identical failed WALKTO.
inst = reader(5000)
Memory.Load(inst, {my_friend_bookstations = {base = {x = 5000, z = 0},
    stations = {{x = 5010, z = 0}}}})
fresh = bookshelf(5018); stations = {fresh}
command = request(inst)
action = assert(Books.GetReadAction(inst, command))
assert(action.action == ACTIONS.WALKTO and action.pos.x == 5010)
action.failure()
action = assert(Books.GetReadAction(inst, command))
assert(action.target == fresh and action.action == ACTIONS.MY_FRIEND_OPEN)

-- Nearby discovery keeps container restrictions and the exact 20-unit
-- search boundary. A new request can retry, the same request cannot rescan.
for _, field in ipairs({"restricted", "opened_by_other", "readonlycontainer"}) do
    inst = reader(6000); local_shelf = bookshelf(6005)
    if field == "readonlycontainer" then local_shelf.components.container[field] = true
    else local_shelf[field] = true end
    stations = {local_shelf}; command = request(inst)
    assert(Books.GetReadAction(inst, command) == nil, field)
end
inst = reader(7000); local_shelf = bookshelf(7020.1)
stations = {local_shelf}; command = request(inst); before = discoveries
assert(Books.GetReadAction(inst, command) == nil and discoveries == before + 1)
local_shelf.pos.x = 7020
assert(Books.GetReadAction(inst, command) == nil and discoveries == before + 1)
command = request(inst)
assert(Books.GetReadAction(inst, command).target == local_shelf and discoveries == before + 2)
print("PASS: base and nearby shelf discovery, empty-record fallback, bounded retries/routes, coordinate-only saves, container permissions and Wickerbottom-only behaviour")
