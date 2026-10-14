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
local discoveries, resolutions = 0, 0
TheSim = {FindEntities = function(_, x, _, z, radius, must)
    if must ~= nil and must[1] == "_inventoryitem" then return {} end
    if must ~= nil and must[1] == "structure" then
        if radius == 3 then resolutions = resolutions + 1
        else discoveries = discoveries + 1 end
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
command = {special = "read", target = "book_birds"}
inst._my_friend_command = command
for _ = 1, 5 do assert(Books.GetReadAction(inst, command) == nil) end
assert(discoveries == before + 1, "an empty read request discovers once and then stops")
inst._my_friend_command, inventory_books = nil, {old}
now = now + 6
assert(Books.GetStoreAction(inst) == nil and discoveries == before + 1,
    "automatic storage must not repeatedly scan for new shelves when memory is empty")
local other = entity("wendy", 0)
Memory.RememberBase(other, Vector3(0, 0, 0))
Memory.Scan(other)
Memory.Prune(other)
assert(#Memory.Stations(other) == 0 and Books.GetReadAction(other, {}) == nil
    and Books.GetStoreAction(other) == nil)
assert(discoveries == before + 1 and resolutions == 1, "other characters must not enter the shelf workflow")
print("PASS: distant remembered shelves, no periodic scans, one scan per empty read request, coordinate resolution and Wickerbottom-only behavior")
