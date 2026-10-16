package.path = "scripts/?.lua;" .. package.path
local now, scans, guid, affinity, charges = 10, 0, 0, 60, 0
GetTime = function() return now end
TUNING = {TOTAL_DAY_TIME = 480}
STRINGS = {CHARACTER_TITLES = {}}
EQUIPSLOTS = {HANDS = "hands", BODY = "body", HEAD = "head"}
ACTIONS = {}
for _, name in ipairs({"DEPLOY", "CHOP", "MINE", "DIG", "PICK", "PICKUP", "HARVEST", "HAMMER",
    "ATTACK", "FISH", "TILL", "POUR_WATER_GROUNDTILE", "MY_FRIEND_LEVELSOIL", "WALKTO"}) do
    ACTIONS[name] = {id = name}
end
local vector_methods = {}
function vector_methods:Get() return self.x, self.y, self.z end
function vector_methods:LengthSq() return self.x^2 + self.z^2 end
Vector3 = function(x, y, z)
    return setmetatable({x = x, y = y or 0, z = z}, {__index = vector_methods,
        __sub = function(first, second) return Vector3(first.x - second.x, 0, first.z - second.z) end})
end
local replies, trees = {}, {}
package.loaded.my_friend_dialogue = {Reply = function(_, key) replies[#replies + 1] = key end}
package.loaded.my_friend_backpacks = {}
package.loaded.my_friend_home = {IsAskPending = function() return false end,
    IsPointInRange = function() return false end}
package.loaded.my_friend_beefalo = {Riding = {}}
package.loaded.my_friend_special_commands = {Parse = function() end, IsPublic = function() return false end}
package.loaded.my_friend_characters = {List = function() return {"wendy"} end}
package.loaded.my_friend_carry_backpack = {Answer = function() return false end, Cancel = function() end}
package.loaded.my_friend_pets = {Parse = function() end}
package.loaded.my_friend_wathgrithr = {Answer = function() return false end}
package.loaded.my_friend_recipe_cooking = {Cancel = function() end}
package.loaded.my_friend_crafting_tech = {}
package.loaded.my_friend_behavior_ai = {IsHazardousPath = function() return false end}
local function entity(prefab, x, z)
    guid = guid + 1
    local value = {prefab = prefab, GUID = guid, components = {}, tags = {}, pos = Vector3(x or 0, 0, z or 0)}
    function value:IsValid() return not self.removed end
    function value:HasTag(tag) return self.tags[tag] == true end
    function value:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    function value:GetPosition() return Vector3(self.pos.x, 0, self.pos.z) end
    function value:GetDisplayName() return "Wendy" end
    function value:GetDistanceSqToPoint(point) return (self.pos - point):LengthSq() end
    function value:GetDistanceSqToInst(other) return self:GetDistanceSqToPoint(other.pos) end
    value.Transform = {GetWorldPosition = function() return value.pos:Get() end}
    return value
end
local player, inst = entity("wilson", 100), entity("wendy")
player.userid = "tree_planter"
inst.tags.my_friend = true
local leader = player
inst.sg = {currentstate = {name = "idle"}, HasStateTag = function() return inst.busy == true end}
inst.components.health = {IsDead = function() return inst.dead == true end}
inst.components.follower = {GetLeader = function() return leader end}
inst.components.builder = {}
inst.components.my_friend_affinity = {
    CanCommandWork = function() return affinity > 50 end,
    DoDelta = function(_, _, amount) charges = charges + 1; assert(amount == -.01) end,
}
local items, active = {}, nil
inst.components.inventory = {ReferenceAllItems = function() return items end,
    GetActiveItem = function() return active end}
AllPlayers = {player}
local blocked
TheWorld = {ismastersim = true, state = {cycles = 500}, Map = {
    IsPassableAtPoint = function() return true end, IsOceanTileAtPoint = function() return false end,
    IsPointNearHole = function(_, point) return blocked ~= nil and blocked(point) end,
}}
TheSim = {FindEntities = function(_, x, _, z, radius)
    scans = scans + 1
    assert(x == 0 and z == 0 and radius <= math.sqrt(2) * 10 + 2,
        "only the fixed square's circumscribed area and its spacing clearance may be queried")
    local found = {}
    for _, tree in ipairs(trees) do
        if (tree.pos.x - x)^2 + (tree.pos.z - z)^2 <= radius^2 then found[#found + 1] = tree end
    end
    return found
end}
BufferedAction = function(doer, target, kind, item, point)
    local action = {doer = doer, target = target, action = kind, invobject = item,
        point = point, success = {}, failure = {}, options = {}}
    function action:AddSuccessAction(callback) self.success[#self.success + 1] = callback end
    function action:AddFailAction(callback) self.failure[#self.failure + 1] = callback end
    function action:GetActionPoint() return self.point end
    function action:Fail() for _, callback in ipairs(self.failure) do callback() end end
    return action
end
local Policy = require("my_friend_policy")
local Commands = require("my_friend_commands")
local Base = require("my_friend_base_ai")
local Forestry = require("my_friend_forestry")
local Navigation = require("my_friend_navigation")
local Plant = require("my_friend_command_plant")
Base.EnsureBase = function() error("planting must not initialise or relocate a base") end
Forestry.EnsurePlot = function() error("planting must not clear or relocate a forest") end
local random = math.random
math.random = function() return 1 end
local function request(message)
    assert(Commands.Dispatch(inst, player, message or "温蒂，种树"))
    local command = Commands.Get(inst)
    assert(command.id == "plant_trees" and command.origin.x == inst.pos.x and command.origin.z == inst.pos.z)
    return command
end
local function seed(prefab, count)
    local value = entity(prefab)
    value.count, value.owner = count, inst
    value.components.inventoryitem = {GetGrandOwner = function() return value.owner end}
    value.components.deployable = {CanDeploy = function(_, point)
        if value.unplantable then return false end
        for _, tree in ipairs(trees) do if (tree.pos - point):LengthSq() < .5^2 then return false end end
        return true
    end}
    items[#items + 1] = value
    return value
end
local function next_action()
    return Commands.Commit(inst, Base.GetCommandAction(inst))
end
local function perform(action)
    assert(action.action == ACTIONS.DEPLOY and action:validfn())
    assert(action.invobject.count > 0 and math.abs(action.point.x) <= Plant.RANGE
        and math.abs(action.point.z) <= Plant.RANGE)
    local sapling = entity(action.invobject.prefab .. "_sapling", action.point.x, action.point.z)
    trees[#trees + 1] = sapling
    action.invobject.count = action.invobject.count - 1
    if action.invobject.count == 0 then action.invobject.removed = true; action.invobject.owner = nil end
    for _, callback in ipairs(action.success) do callback() end
    now = now + 1
end

leader = nil
assert(not Commands.Dispatch(inst, player, "温蒂，种树"))
leader, affinity = player, 50
assert(not Commands.Dispatch(inst, player, "温蒂，种下去") and replies[#replies] == "affinity_work")
affinity = 60
for _, keyword in ipairs({"种树", "种下去", "种吧"}) do request("温蒂，" .. keyword) end
assert(Commands.DispatchWheel(inst, player, "plant_trees"))
assert(Commands.Get(inst).origin.x == 0, "the wheel uses companion position too")

local base = {forest = {x = 1000, z = 1000}, tree_plant_index = 8}
inst._my_friend_base = base
local cones = seed("pinecone", 2)
local nuts = seed("acorn", 2)
active = seed("twiggy_nut", 2)
local command = request()
local first = assert(next_action())
assert(first.invobject == active and charges == 1)
assert(Plant.RANGE == 10 and first.point:LengthSq() > Plant.RANGE^2,
    "square corners beyond the inscribed circle must be planted too")
assert(not Policy.InRange(inst, inst), "the leader is deliberately far from the planting origin")
inst._my_friend_navigation_action = first
assert(Navigation.InTravelRange(inst, first.point), "fixed planting points are not rejected by the leader/home boundary")
assert(not Navigation.InTravelRange(inst, Vector3(50, 0, 0)), "planting routes remain bounded")
perform(first)
inst.pos, player.pos = Vector3(40, 0, 0), Vector3(120, 0, 0)
local second = assert(next_action())
assert(math.abs(second.point.x) <= Plant.RANGE and math.abs(second.point.z) <= Plant.RANGE and command.origin.x == 0)
inst.busy = true
assert(second:validfn(), "the selected deployment stays valid during its own busy animation")
inst.tags.playerghost = true
assert(not second:validfn(), "a queued deployment cannot survive becoming a ghost")
inst.tags.playerghost, inst.busy = nil, false
perform(second)
for index = 1, 4 do perform(assert(next_action())) end
assert(charges == 1 and command.planted_count == 6)
assert(cones.count == 0 and nuts.count == 0)
assert(next_action() == nil and Commands.Get(inst) == nil and replies[#replies] == "plant_trees_done")
assert(inst._my_friend_base == base and base.forest.x == 1000 and base.tree_plant_index == 8,
    "explicit planting must leave the base forestry job untouched")

inst.pos, player.pos, trees, items, active = Vector3(0, 0, 0), Vector3(100, 0, 0), {}, {}, nil
command = request()
local before = scans
assert(next_action() == nil and replies[#replies] == "plant_trees_no_seeds" and scans == before)
seed("pinecone", 50)
command = request()
local points8 = Forestry.Points({x = 0, z = 0, half_size = 8})
local points10 = Forestry.Points({x = 0, z = 0, half_size = 10})
local points12 = Forestry.Points({x = 0, z = 0, half_size = 12})
assert(#points8 < #points10 and #points10 < #points12 and #points10 > Forestry.TREE_LIMIT,
    "capacity must follow square size at the base planting spacing, not the base's fixed tree target")
assert(#Forestry.Points({x = 0, z = 0, half_size = 10}, Forestry.SPACING * .75) > #points10
    and #Forestry.Points({x = 0, z = 0, half_size = 10}, Forestry.SPACING * 1.5) < #points10,
    "capacity must also follow spacing without a separate tree count limit")
assert(#points10 == 64)
local rows, columns = {}, {}
for first_index, point in ipairs(points10) do
    assert(math.abs(point.x) <= Plant.RANGE and math.abs(point.z) <= Plant.RANGE)
    rows[point.z], columns[point.x] = (rows[point.z] or 0) + 1, (columns[point.x] or 0) + 1
    for second_index = first_index + 1, #points10 do
        assert((point - points10[second_index]):LengthSq() >= Forestry.SPACING^2 - .000001,
            "expanding the area must retain the base planting spacing")
    end
end
for _, count in pairs(rows) do assert(count == 8, "every square row must be complete, including its middle") end
for _, count in pairs(columns) do assert(count == 8, "every square column must be complete, including its middle") end
for index = 1, 50 do perform(assert(next_action())) end
assert(next_action() == nil and command.planted_count == 50 and items[1].count == 0,
    "the reported 50-seed case must use all 50 seeds instead of stopping at 40")
trees, items = {}, {}
seed("pinecone", 100)
command = request()
for index = 1, #points10 do perform(assert(next_action())) end
before = scans
assert(next_action() == nil and replies[#replies] == "plant_trees_done" and scans == before)
assert(command.planted_count == #points10 and items[1].count == 100 - #points10)
assert(#trees == #points10, "sufficient seeds must fill every square grid point")
local corner = trees[1]
assert(corner.pos:LengthSq() > 12^2)
assert(#Forestry.Trees(inst, {x = 0, z = 0, half_size = 10}) == #points10,
    "tree discovery must include square corners, not just the old circular query")

trees, items = {}, {}
local locked = seed("pinecone", 2)
locked.components.inventoryitem.islockedinslot = true
request()
assert(next_action() == nil and replies[#replies] == "plant_trees_no_seeds")
locked.components.inventoryitem.islockedinslot = false
command = request()
local failed = assert(next_action())
failed:Fail()
local replacement = assert(next_action())
assert((replacement.point - failed.point):LengthSq() > .1)
locked.owner = player
assert(not replacement:validfn(), "a transferred seed cannot be consumed by a queued action")
locked.owner = inst
Commands.Clear(inst)
local planted = command.planted_count
for _, callback in ipairs(replacement.success) do callback() end
assert(not replacement:validfn() and command.planted_count == planted,
    "cancelled commands and their late callbacks must not affect later work")

blocked = function() return true end
request()
assert(next_action() == nil and replies[#replies] == "plant_trees_no_space")
before = scans
for iteration = 1, 20 do assert(next_action() == nil) end
assert(scans == before, "an exhausted planting command must not keep scanning")
blocked = nil
inst.busy = true
request()
before = scans
assert(next_action() == nil and scans == before)
inst.busy = false
assert(next_action() ~= nil)

local language = require("my_friend_strings")
for _, code in ipairs({"zh", "zh_tw", "en", "ru"}) do
    language.language = code
    package.loaded.my_friend_commands = nil
    local localized = require("my_friend_commands")
    assert(localized.DispatchWheel(inst, player, "plant_trees"), code)
    assert(localized.Get(inst).id == "plant_trees")
    local lines = require("my_friend_language").DialogueLines(code)
    assert(lines.replies.describe_plant_trees and lines.replies.plant_trees_no_seeds and lines.replies.plant_trees_no_space)
end
trees, inst._my_friend_base = {}, {forest = {x = 0, z = 0}}
local base_point = assert(Forestry.FindPlantPoint(inst, locked, Navigation.IsLand))
assert(base_point.x == -2 * Forestry.SPACING and base_point.z == -2 * Forestry.SPACING,
    "base planting retains its original spacing after extracting the shared selector")
blocked = function() return true end
assert(Forestry.FindPlantPoint(inst, locked, Navigation.IsLand) == nil)
now = now + 31
assert(Forestry.FindPlantPoint(inst, locked, Navigation.IsLand) == nil and inst._my_friend_base.forest == nil,
    "base planting still rejects a persistently unplantable plot after its original timeout")
math.random = random
print("PASS: planting chat/wheel permissions, fixed companion origin, native DEPLOY, carried seeds, base-independent layout, route bounds, one work charge, cancellation and bounded completion")
