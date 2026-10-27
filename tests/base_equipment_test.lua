-- lua tests/base_equipment_test.lua [path-to-extracted-DST-scripts]
package.path = "./scripts/?.lua;" .. package.path
local passed, failed, now, scans, serial = 0, 0, 100, 0, 0
local entities, crafted = {}, {}
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
function GetTime() return now end
function RoundBiasedUp(x) return math.ceil(x - .00001) end
function Vector3(x, y, z) return {x = x, y = y, z = z} end
EQUIPSLOTS = {HANDS = "hands", HEAD = "head", BODY = "body"}
TUNING = {SPEAR_DAMAGE = 34, TOTAL_DAY_TIME = 480}
TECH = {SCIENCE_ONE = {SCIENCE = 1}, SCIENCE_TWO = {SCIENCE = 2}}
local recipes = {}
function Ingredient(name, amount) return {type = name, amount = amount} end
function Recipe2(name, ingredients, level) recipes[name] = {name = name, ingredients = ingredients, level = level} end
function GetValidRecipe(name) return recipes[name] end
function CanPrototypeRecipe(level, trees) return (trees.SCIENCE or 0) >= (level.SCIENCE or 0) end
local native = arg[1] or "../yuanma/scripts"
local file = assert(io.open(native .. "/recipes.lua", "rb"))
for line in file:lines() do
    local name = line:match('Recipe2%("([%w_]+)"')
    if name == "rope" or name == "spear" or name == "armorwood" or name == "footballhat"
        or name == "hambat" or name == "umbrella" or name == "sewing_kit" then
        assert(loadstring(line))()
    end
end
file:close()
ACTIONS = {PICKUP = "pickup", MY_FRIEND_WITHDRAW = "withdraw", BUILD = "build", WALKTO = "walk", ATTACK = "attack"}
function BufferedAction(doer, target, action, invobject, pos, recipe)
    local a = {doer = doer, target = target, action = action, invobject = invobject, pos = pos,
        recipe = recipe, success = {}, fail = {}}
    function a:AddSuccessAction(fn) self.success[#self.success + 1] = fn end
    function a:AddFailAction(fn) self.fail[#self.fail + 1] = fn end
    function a:GetActionPoint() return self.pos end
    return a
end
function Class(base, ctor)
    if ctor == nil then ctor, base = base, nil end
    local c = {}; c.__index = c
    return setmetatable(c, {__index = base, __call = function(_, ...)
        local o = setmetatable({}, c); ctor(o, ...); return o
    end})
end
READY, RUNNING, FAILED, SUCCESS = 0, 1, 2, 3
BehaviourNode = {_ctor = function(self, name) self.name = name end, Sleep = function() end}
local function Entity(name, x)
    serial = serial + 1
    local e = {GUID = serial, prefab = name, x = x or 0, z = 0, tags = {}, components = {}}
    function e:IsValid() return not self.removed end
    function e:IsInLimbo() return self:HasTag("INLIMBO") end
    function e:HasTag(t) return self.tags[t] == true end
    function e:HasAnyTag(...)
        local tags = {...}; if type(tags[1]) == "table" then tags = tags[1] end
        for _, t in ipairs(tags) do if self:HasTag(t) then return true end end
        return false
    end
    function e:GetPosition() return Vector3(self.x, 0, self.z) end
    function e:GetDistanceSqToPoint(p) return (self.x - p.x)^2 + (self.z - p.z)^2 end
    function e:GetDistanceSqToInst(other) return self:GetDistanceSqToPoint(other:GetPosition()) end
    function e:GetCurrentPlatform() return self.platform end
    e.Transform = {GetWorldPosition = function() return e.x, 0, e.z end}
    e.entity = {GetParent = function() end}
    Ents[e.GUID] = e
    return e
end
local function Reset()
    Ents, AllPlayers, entities, crafted, scans = {}, {}, {}, {}, 0
    TheWorld = {ismastersim = true, state = {cycles = 1}}
end
Reset()
TheSim = {FindEntities = function(_, x, y, z, r, must, cant)
    scans = scans + 1; local found = {}
    for _, e in ipairs(entities) do
        local match = e:IsValid() and e:GetDistanceSqToPoint(Vector3(x, y, z)) <= r*r
        for _, t in ipairs(must or {}) do match = match and e:HasTag(t) end
        for _, t in ipairs(cant or {}) do match = match and not e:HasTag(t) end
        if match then found[#found + 1] = e end
    end
    return found
end}
package.loaded.techtree = {BONUS_TECH = {"SCIENCE"}}
package.loaded.my_friend_light_ai = {IsDark = function() return false end}
package.loaded.my_friend_navigation = {}
package.loaded.my_friend_dodge = {Reset = function() end}
package.loaded.my_friend_equipment = {FindDroppedCombatItem = function() end,
    PreferredHead = function() end, GetCombatUtilityScore = function() return 0 end}
package.loaded.my_friend_survival_ai = {GetThermalNeed = function() end}
package.loaded.my_friend_equip_slots = {All = function() return {"hands", "head", "body"} end}
local Discovery = require("my_friend_discovery")
local Policy = require("my_friend_policy")
local Home = require("my_friend_home")
local Materials = require("my_friend_crafting_materials")
local Tech = require("my_friend_crafting_tech")
local Base = {GetStoragePressure = function() return false end, SetTask = function() end}
package.loaded.my_friend_base_ai = Base
local function Item(owner, name, count, x)
    local e = Entity(name, x); e.count = count or 1
    local ii = {owner = owner, canbepickedup = true}
    function ii:GetGrandOwner() return self.owner end
    e.components.inventoryitem = ii
    e.components.stackable = {StackSize = function() return e.count end}
    entities[#entities + 1] = e
    return e
end
local function Gear(owner, name, slot, damage, armor)
    local e = Item(owner, name)
    e.components.equippable = {equipslot = slot, IsRestricted = function() return e.restricted == true end}
    if damage ~= nil then
        e.components.weapon = {damage = damage, GetDamage = function() return damage end}
        e.components.finiteuses = {GetUses = function() return e.uses or 100 end}
    end
    if armor ~= nil then e.components.armor = {absorb_percent = .8, condition = armor} end
    return e
end
local function Actor(manual, hp)
    local i = Entity("wendy"); i.tags.my_friend = true; i.items, i.equipped = {}, {}
    if manual ~= false then i._my_friend_home = {mode = "base", x = 0, z = 0} end
    local health = {currenthealth = hp or 100, maxhealth = 100}
    function health:IsDead() return self.currenthealth <= 0 end
    function health:GetPercent() return self.currenthealth / self.maxhealth end
    i.components.health = health
    i.components.hunger = {GetPercent = function() return i.hunger or .8 end}
    i.components.follower = {GetLeader = function() return i.leader end}
    i.sg = {currentstate = {name = "idle"}, HasStateTag = function(_, t) return i.state_tags and i.state_tags[t] end,
        HasAnyStateTag = function(_, ...)
            for _, t in ipairs({...}) do if i.state_tags and i.state_tags[t] then return true end end; return false
        end}
    function i:GetBufferedAction() return self.buffered end
    function i:ClearBufferedAction() self.buffered = nil end
    local inv = {inst = i}
    function inv:ReferenceAllItems()
        i.inventory_reads = (i.inventory_reads or 0) + 1
        local a = {}; for _, e in ipairs(i.items) do if e:IsValid() and e.count > 0 then a[#a + 1] = e end end
        if i.sewing_default ~= nil and i.sewing_default:IsValid() then a[#a + 1] = i.sewing_default end
        return a
    end
    function inv:GetActiveItem() return i.active end
    function inv:GetEquippedItem(slot) return i.equipped[slot] end
    function inv:CanAcceptCount(_, count) return i.full and 0 or count end
    function inv:Equip(e) i.equipped[e.components.equippable.equipslot] = e; return true end
    i.sewing_default = Item(i, "sewing_kit")
    i.sewing_default.components.sewing = {}
    i.components.inventory = inv
    local combat = {inst = i, defaultdamage = 10, min_attack_period = .4}
    function combat:CalcDamage(_, e) return e ~= nil and e.components.weapon:GetDamage(i, self.target) or 10 end
    function combat:CanTarget() return true end
    function combat:SetTarget(t) self.target = t end
    function combat:GetWeapon() return inv:GetEquippedItem("hands") end
    i.components.combat = combat
    i.components.locomotor = {Stop = function() i.stopped = true end}
    local builder = {ingredientmod = 1, accessible_tech_trees = {}, accessible_tech_trees_no_temp = {}}
    function builder:KnowsRecipe(recipe) return not i.unknown end
    function builder:CanLearn() return true end
    function builder:EvaluateTechTrees() end
    function builder:UsePrototyper(s) self.accessible_tech_trees = s.components.prototyper:GetTechTrees(); return true end
    i.components.builder = builder
    return i
end
local function Add(i, name, n) local e = Item(i, name, n); i.items[#i.items + 1] = e; return e end
local function Chest(x, contents)
    local e = Entity("treasurechest", x); e.tags.chest, e.tags.structure = true, true
    local c = {canbeopened = true, slots = {}}
    function c:IsRestricted() return e.restricted == true end
    function c:IsOpenedByOthers() return e.busy == true end
    function c:IsOpenedBy(p) return p == e.opened_by end
    function c:GetAllItems() return self.slots end
    e.components.container = c; entities[#entities + 1] = e
    for name, n in pairs(contents or {}) do c.slots[#c.slots + 1] = Item(e, name, n, x) end
    return e
end
local function Consume(i, recipe)
    for _, ing in ipairs(recipe.ingredients) do
        local n = math.max(1, RoundBiasedUp(ing.amount * i.components.builder.ingredientmod))
        for _, e in ipairs(i.items) do
            if e.prefab == ing.type then local take = math.min(n, e.count); e.count = e.count - take; n = n - take end
        end
        assert(n == 0, "build consumed unavailable " .. ing.type)
    end
end
function Base.GetRecipeAction(i, name)
    return BufferedAction(i, nil, ACTIONS.BUILD, nil, i:GetPosition(), name)
end
local Survival = dofile("scripts/my_friend_survival_ai.lua")
package.loaded.my_friend_survival_ai.IsWornOut = Survival.IsWornOut
local Equipment = dofile("scripts/my_friend_equipment.lua")
package.loaded.my_friend_equipment = Equipment
local Basic = require("my_friend_basic_equipment")
local Behavior = require("my_friend_behavior_ai")
local Rules = require("my_friend_combat_rules")
local CombatNode = require("behaviours/my_friend_combat")
local function Execute(i, a)
    assert(a.validfn == nil or a.validfn(a), "action validation failed: " .. tostring(a.recipe or a.action))
    if a.action == ACTIONS.WALKTO then
        i.x = a.target.x - 1; i.z = a.target.z
    elseif a.action == ACTIONS.PICKUP or a.action == ACTIONS.MY_FRIEND_WITHDRAW then
        local source = a.invobject or a.target; local count = math.min(source.count, a._my_friend_withdraw_count)
        Add(i, source.prefab, count); source.count = source.count - count
        if source.count == 0 then source.removed = true end
        Discovery.Touch(a.target)
    elseif a.action == ACTIONS.BUILD then
        Consume(i, recipes[a.recipe]); crafted[#crafted + 1] = a.recipe
        if a.recipe == "rope" then Add(i, "rope", recipes.rope.numtogive or 1)
        elseif a.recipe == "sewing_kit" then
            local e = Item(i, "sewing_kit"); e.components.sewing = {}
            e.components.finiteuses = {GetUses = function() return e.uses or 5 end}
            i.items[#i.items + 1] = e
        elseif a.recipe == "umbrella" then
            local e = Gear(i, "umbrella", "hands")
            e.components.waterproofer = {GetEffectiveness = function() return .9 end}
            i.items[#i.items + 1] = e
        else
            local armor = a.recipe == "footballhat" or a.recipe == "armorwood"
            local e = Gear(i, a.recipe, armor and (a.recipe == "footballhat" and "head" or "body") or "hands",
                not armor and (a.recipe == "hambat" and 59.5 or 34) or nil, armor and 100 or nil)
            i.items[#i.items + 1] = e
        end
    else error("unexpected action") end
    Discovery.InventoryChanged(i)
    for _, fn in ipairs(a.success) do fn() end
end
local function Complete(i)
    for n = 1, 40 do local a = Basic.GetAction(i); if a == nil then return end; Execute(i, a) end
    error("crafting did not terminate")
end
local function Crafted(name) for _, n in ipairs(crafted) do if n == name then return true end end; return false end
test("preferred pair uses native recipes, chest and ground supplies across the manual base", function()
    Reset(); local i = Actor(); i.x = -25; i.leader = Entity("wilson", -25)
    Chest(25, {pigskin = 2, meat = 2, twigs = 2}); Item(nil, "cutgrass", 3, 29)
    assert(Basic.Score(i, {leader = i.leader}) > 0)
    Complete(i)
    assert(Crafted("footballhat") and Crafted("hambat") and Crafted("rope"))
    assert(not Crafted("armorwood") and not Crafted("spear"))
end)
test("fallback accounts for three shared ropes and stops after one log suit and spear", function()
    Reset(); local i = Actor(); Chest(5, {log = 8, cutgrass = 9, flint = 1, twigs = 2})
    Complete(i); assert(Crafted("armorwood") and Crafted("spear"))
    local ropes = 0; for _, name in ipairs(crafted) do if name == "rope" then ropes = ropes + 1 end end
    assert(ropes == 3 and #crafted == 5)
    local before = scans; assert(Basic.GetAction(i) == nil); assert(scans == before)
end)
test("partial preferred materials do not consume resources before fallback selection", function()
    Reset(); local i = Actor(); Chest(3, {pigskin = 1, log = 8, cutgrass = 9, flint = 1, twigs = 2})
    Complete(i); assert(Crafted("armorwood") and Crafted("spear") and not Crafted("footballhat"))
end)
test("empty supply scan sleeps exactly 240 seconds despite newly added materials", function()
    Reset(); local i = Actor(); assert(Basic.GetAction(i) == nil)
    local before = scans; local added = Chest(4, {pigskin = 2, rope = 1, twigs = 2, meat = 2})
    Discovery.Touch(added); now = now + 239.99
    assert(Basic.Score(i, {}) == 0 and Basic.GetAction(i) == nil and scans == before)
    now = now + .01; Complete(i); assert(Crafted("footballhat") and Crafted("hambat"))
end)
test("existing carried armor or weapon is preserved and only the missing role is crafted", function()
    Reset(); local i = Actor(); i.items = {Gear(i, "armorwood", "body", nil, 100)}
    Chest(4, {pigskin = 1, meat = 2, twigs = 2}); Complete(i)
    assert(#crafted == 1 and crafted[1] == "hambat")
    Reset(); i = Actor(); i.items = {Gear(i, "spear", "hands", 34)}
    Chest(4, {pigskin = 1, rope = 1}); Complete(i)
    assert(#crafted == 1 and crafted[1] == "footballhat")
end)
test("fully equipped in backpack or active slot does not scan, even with broken gear elsewhere", function()
    Reset(); local i = Actor(); i.items = {Gear(i, "armorwood", "body", nil, 100)}
    i.active = Gear(i, "spear", "hands", 34)
    i.components.moisture = {inherentWaterproofness = .8}
    local before = scans; assert(Basic.GetAction(i) == nil and scans == before)
end)
test("base boundary, other platforms, and inaccessible containers cannot supply gear", function()
    Reset(); local i = Actor(); Chest(32.01, {pigskin = 2, rope = 1, meat = 2, twigs = 2})
    local busy = Chest(3, {log = 8, rope = 3, flint = 1, twigs = 2}); busy.busy = true
    local boat = Chest(4, {pigskin = 2, rope = 1, meat = 2, twigs = 2}); boat.platform = "boat"
    assert(Basic.GetAction(i) == nil and #crafted == 0)
    Reset(); i = Actor(); i.x = 32.01; local before = scans
    assert(Basic.Score(i, {}) == 0 and Basic.GetAction(i) == nil and scans == before)
end)
test("queued withdrawal rechecks ownership, base identity, source position, and new commands", function()
    Reset(); local i = Actor(); local c = Chest(4, {pigskin = 2, rope = 1, meat = 2, twigs = 2})
    local a = assert(Basic.GetAction(i)); assert(a.validfn(a))
    c.x = 33; assert(not a.validfn(a)); c.x = 4
    i._my_friend_command = {id = "sit"}; assert(not a.validfn(a)); i._my_friend_command = nil
    i._my_friend_home = {mode = "base", x = 0, z = 0}; assert(not a.validfn(a))
end)
test("native tech requirements approach only a station inside the base", function()
    Reset(); local i = Actor(); i.unknown = true
    Add(i, "pigskin", 2); Add(i, "rope", 1); Add(i, "meat", 2); Add(i, "twigs", 2)
    local station = Entity("researchlab2", 25); station.tags.structure = true
    station.components.prototyper = {GetTechTrees = function() return {SCIENCE = 2} end,
        CanUsePrototyper = function() return i:GetDistanceSqToInst(station) <= 4 end}
    entities[#entities + 1] = station; Complete(i)
    assert(Crafted("footballhat") and Crafted("hambat") and i.x == 24)
end)
test("missing tech blocks crafting but partial ingredients now make a single suit", function()
    Reset(); local i = Actor(); i.unknown = true
    Chest(3, {pigskin = 2, rope = 1, meat = 2, twigs = 2}); assert(Basic.GetAction(i) == nil)
    Reset(); i = Actor(); Chest(3, {log = 8, rope = 2, flint = 1, twigs = 2})
    Complete(i); assert(Crafted("armorwood") and not Crafted("spear"))
end)
test("busy and starvation leave gear crafting to survival; canceled actions can resume", function()
    Reset(); local i = Actor(); Add(i, "pigskin", 2); Add(i, "rope", 1); Add(i, "meat", 2); Add(i, "twigs", 2)
    i.state_tags = {busy = true}; assert(Basic.GetAction(i) == nil)
    i.state_tags = {}; i.hunger = .2; assert(Basic.GetAction(i) == nil)
    i.hunger = .8; local a = assert(Basic.GetAction(i)); a._my_friend_cancelled = true
    for _, fn in ipairs(a.fail) do fn() end
    assert(Basic.GetAction(i) ~= nil)
end)
test("default crafting material planner retains 20-unit range and carried-first subtraction", function()
    Reset(); local i = Actor(false); Add(i, "pigskin", 1); Add(i, "rope", 1)
    Chest(21, {pigskin = 10, rope = 10})
    local p = assert(Materials.Plan(i, recipes.footballhat)); assert(#p == 0)
    i.items = {}; assert(Materials.Plan(i, recipes.footballhat) == nil)
end)
test("real navigation allows finite base-wide material and science trips while following", function()
    Reset(); local i = Actor(); i.x = -25; i.leader = Entity("wilson", -25)
    local chest = Chest(25, {pigskin = 2, rope = 1, meat = 2, twigs = 2})
    local a = assert(Basic.GetAction(i)); i._my_friend_navigation_action = a
    local Navigation = dofile("scripts/my_friend_navigation.lua")
    assert(Navigation.InTravelRange(i, i:GetPosition()))
    assert(Navigation.InTravelRange(i, chest:GetPosition()))
    assert(Basic.IsBaseEquipmentTravel(i))
    i.leader.x = 33; assert(not Basic.IsBaseEquipmentTravel(i)); i.leader.x = -25
    i._my_friend_follow_requested_until = now + 5; assert(not Basic.IsBaseEquipmentTravel(i))
    i._my_friend_follow_requested_until = nil
    assert(not Navigation.InTravelRange(i, Vector3(32.01, 0, 0)))
    i._my_friend_navigation_action = nil
    assert(not Navigation.InTravelRange(i, chest:GetPosition()), "ordinary follow range was widened")
    i._my_friend_navigation_action = a; i._my_friend_home = {mode = "base", x = 0, z = 0}
    assert(not Navigation.InTravelRange(i, chest:GetPosition()))
end)
local function Enemy(i, name)
    local t = Entity(name or "hound", 2); t.tags._combat = true
    t.components.health = {currenthealth = 100, IsDead = function() return false end}
    t.components.combat = {target = i, GetWeapon = function() end}
    entities[#entities + 1] = t; return t
end
test("80 percent HP and 25 damage boundaries cannot be bypassed by early-world priority", function()
    Reset(); local i = Actor(false, 79.99); local t = Enemy(i)
    assert(Behavior.IsPriorityEngaged(i, t))
    assert(not Behavior.CanCounterAttack(i, t) and not Behavior.CanContinueCombat(i, t))
    assert(Behavior.FindEscapeThreat(i) == t)
    i.components.health.currenthealth = 80; assert(not Behavior.ShouldRetreatUnequipped(i, t))
    i.components.health.currenthealth = 79
    local e = Gear(i, "tool", "hands", 25); i.items = {e}; Discovery.InventoryChanged(i)
    assert(not Behavior.ShouldRetreatUnequipped(i, t))
    e.components.weapon.damage = 24.99; e.components.weapon.GetDamage = function() return 24.99 end
    Discovery.InventoryChanged(i); assert(Behavior.ShouldRetreatUnequipped(i, t))
end)
test("carried usable armor prevents forced retreat; exhausted, locked and foreign armor do not", function()
    Reset(); local i = Actor(false, 79); local t = Enemy(i)
    local armor = Gear(i, "footballhat", "head", nil, 100); i.items = {armor}
    assert(not Behavior.ShouldRetreatUnequipped(i, t))
    armor.components.armor.condition = 0
    assert(Behavior.ShouldRetreatUnequipped(i, t))
    armor.components.armor.condition = 100; armor.components.inventoryitem.islockedinslot = true
    Discovery.InventoryChanged(i); assert(Behavior.ShouldRetreatUnequipped(i, t))
    armor.components.inventoryitem.islockedinslot = nil; armor.components.inventoryitem.owner = Entity("wilson")
    Discovery.InventoryChanged(i); assert(Behavior.ShouldRetreatUnequipped(i, t))
end)
test("strong carried, active and target-dependent weapons work; restricted and exhausted weapons do not", function()
    Reset(); local i = Actor(false, 79); local t = Enemy(i)
    local e = Gear(i, "hambat", "hands", 59); i.active = e
    assert(not Behavior.ShouldRetreatUnequipped(i, t))
    assert(Behavior.FindBestCombatWeapon(i, t) == e)
    e.uses = 0; assert(Behavior.ShouldRetreatUnequipped(i, t))
    e.uses = 100; e.restricted = true; Discovery.InventoryChanged(i)
    assert(Behavior.ShouldRetreatUnequipped(i, t))
end)
test("native targeting and queued attacks reject a newly unequipped low-health actor", function()
    Reset(); local i = Actor(false, 100); local t = Enemy(i); Rules.Configure(i)
    assert(i.components.combat:CanTarget(t)); i.components.health.currenthealth = 79
    assert(not i.components.combat:CanTarget(t)); assert(not Rules.CanAttack(t, i))
end)
test("combat node cancels only its attack and retreats from its current leader-assistance target", function()
    Reset(); local i = Actor(false, 79); local leader = Entity("wilson"); i.leader = leader; AllPlayers = {leader}
    local t = Enemy(i); t.components.combat.target = leader
    i.components.combat.target = t; i._my_friend_assist_target = t
    i.state_tags = {attack = true}; i.buffered = BufferedAction(i, t, ACTIONS.ATTACK)
    local node = CombatNode(i); node.target = t; node:Visit()
    assert(node.status == FAILED and i.buffered == nil and i.components.combat.target == nil)
    assert(Behavior.FindEscapeThreat(i) == t)
    i.components.health.currenthealth = 80; assert(Behavior.FindEscapeThreat(i) == nil)
end)
test("busy eating is preserved and unrelated player fights do not cause fleeing", function()
    Reset(); local i = Actor(false, 79); local leader = Entity("wilson"); i.leader = leader; AllPlayers = {leader}
    local t = Enemy(i); t.components.combat.target = leader
    assert(Behavior.FindEscapeThreat(i) == nil)
    i.components.combat.target = t; i._my_friend_assist_target = t
    i.state_tags = {busy = true}; i.buffered = {action = "eat"}
    local node = CombatNode(i); node.target = t; node:Visit()
    assert(i.buffered ~= nil and i.buffered.action == "eat")
end)
test("combat eligibility caches inventory inspection and immediately rechecks threshold or loss", function()
    Reset(); local i = Actor(false, 79); local t = Enemy(i)
    assert(Behavior.ShouldRetreatUnequipped(i, t)); local reads = i.inventory_reads; local before = scans
    for n = 1, 20 do assert(Behavior.ShouldRetreatUnequipped(i, t)) end
    assert(i.inventory_reads == reads and scans == before)
    local e = Gear(i, "spear", "hands", 34); i.items = {e}; Discovery.InventoryChanged(i)
    assert(not Behavior.ShouldRetreatUnequipped(i, t)); e.removed = true
    assert(Behavior.ShouldRetreatUnequipped(i, t))
end)
local function Waterproof(item, value)
    item.components.waterproofer = {GetEffectiveness = function() return value end}
    return item
end
local function EquippedActor()
    local i = Actor()
    i.items = {Waterproof(Gear(i, "footballhat", "head", nil, 100), .2), Gear(i, "spear", "hands", 34)}
    return i
end
test("20-percent defensive helmet does not prevent crafting one 90-percent umbrella", function()
    Reset(); local i = EquippedActor(); Chest(5, {pigskin = 1, twigs = 6, silk = 2})
    assert(math.abs(Equipment.GetAvailableRainProtection(i) - .2) < .00001)
    Complete(i); assert(#crafted == 1 and crafted[1] == "umbrella")
    assert(Equipment.GetAvailableRainProtection(i) == 1)
    local before = scans; assert(Basic.Score(i, {}) == 0 and Basic.GetAction(i) == nil and scans == before)
end)
test("rain protection combines slots and intrinsic modifiers, with an exact 80-percent boundary", function()
    Reset(); local i = EquippedActor()
    i.items[#i.items + 1] = Waterproof(Gear(i, "raincoat", "body"), .6)
    assert(math.abs(Equipment.GetAvailableRainProtection(i) - .8) < .00001)
    assert(Basic.GetAction(i) == nil and scans == 0)
    i.items[3].components.waterproofer.GetEffectiveness = function() return .5999 end
    Chest(3, {pigskin = 1, twigs = 6, silk = 2}); Complete(i); assert(Crafted("umbrella"))
    Reset(); i = EquippedActor(); i.components.moisture = {inherentWaterproofness = .3,
        waterproofnessmodifiers = {Get = function() return .3 end}}
    assert(math.abs(Equipment.GetAvailableRainProtection(i) - .8) < .00001)
    assert(Basic.Score(i, {}) == 0 and Basic.GetAction(i) == nil and scans == 0)
end)
test("two partial hats cannot be added as if both were worn", function()
    Reset(); local i = EquippedActor()
    i.items[1] = Waterproof(Gear(i, "hat_one", "head", nil, 100), .4)
    i.items[#i.items + 1] = Waterproof(Gear(i, "hat_two", "head", nil, 100), .5)
    assert(Equipment.GetAvailableRainProtection(i) == .5)
    Chest(3, {pigskin = 1, twigs = 6, silk = 2}); Complete(i); assert(Crafted("umbrella"))
end)
test("usable active or backpack umbrella prevents duplicates; exhausted or restricted gear does not", function()
    Reset(); local i = EquippedActor()
    local e = Waterproof(Gear(i, "umbrella", "hands"), .9); i.active = e
    assert(Equipment.GetAvailableRainProtection(i) == 1 and Basic.GetAction(i) == nil and scans == 0)
    e.components.finiteuses = {GetUses = function() return 0 end}
    assert(Equipment.GetAvailableRainProtection(i) == .2)
    e.components.finiteuses = nil; e.restricted = true
    assert(Equipment.GetAvailableRainProtection(i) == .2)
    e.restricted = nil; e.components.inventoryitem.islockedinslot = true
    assert(Equipment.GetAvailableRainProtection(i) == .2)
    e.components.inventoryitem.islockedinslot = nil; e.components.inventoryitem.owner = Entity("wilson")
    assert(Equipment.GetAvailableRainProtection(i) == .2)
end)
test("broken or worn-out multifunctional rain gear is excluded", function()
    Reset(); local i = EquippedActor(); local e = i.items[1]
    e.components.armor.condition = 0; assert(Equipment.GetAvailableRainProtection(i) == 0)
    e.components.armor.condition = 100; e.components.armor.GetPercent = function() return .01 end
    assert(Equipment.GetAvailableRainProtection(i) == 0)
end)
test("umbrella missing-material retry is exactly four minutes without repeated discovery", function()
    Reset(); local i = EquippedActor(); assert(Basic.GetAction(i) == nil)
    local before = scans; local start = now
    local c = Chest(5, {pigskin = 1, twigs = 6, silk = 2}); Discovery.Touch(c)
    now = start + 239.99
    assert(Basic.Score(i, {}) == 0 and Basic.GetAction(i) == nil and scans == before)
    now = start + 240; Complete(i); assert(Crafted("umbrella"))
end)
test("combat material failure does not block an affordable umbrella", function()
    Reset(); local i = Actor(); Chest(5, {pigskin = 1, twigs = 6, silk = 2})
    Complete(i); assert(#crafted == 1 and crafted[1] == "umbrella")
    assert(i._my_friend_base_equipment.next_scan == now + 240)
end)
test("rain material failure does not block a newly affordable weapon", function()
    Reset(); local i = EquippedActor(); assert(Basic.GetAction(i) == nil)
    assert(i._my_friend_base_equipment.rain_next_scan == now + 240)
    i.items[2].removed = true; Add(i, "pigskin", 1); Add(i, "twigs", 2); Add(i, "meat", 2)
    Discovery.InventoryChanged(i); Complete(i)
    assert(#crafted == 1 and crafted[1] == "hambat")
end)
test("rain build rechecks gifted protection and real failure sets only its own cooldown", function()
    Reset(); local i = EquippedActor(); Add(i, "pigskin", 1); Add(i, "twigs", 6); Add(i, "silk", 2)
    local a = assert(Basic.GetAction(i)); assert(a.recipe == "umbrella" and a.validfn(a))
    i.items[#i.items + 1] = Waterproof(Gear(i, "raincoat", "body"), .9)
    assert(not a.validfn(a)); a._my_friend_cancelled = true
    for _, fn in ipairs(a.fail) do fn() end
    assert(i._my_friend_base_equipment.rain_next_scan == nil)
    i.items[#i.items].removed = true
    a = assert(Basic.GetAction(i)); for _, fn in ipairs(a.fail) do fn() end
    assert(i._my_friend_base_equipment.rain_next_scan == now + 240)
    assert(i._my_friend_base_equipment.next_scan == nil)
end)
for name, supplies in pairs({footballhat = {pigskin = 1, rope = 1}, hambat = {pigskin = 1, twigs = 2, meat = 2},
    armorwood = {log = 8, rope = 2}, spear = {twigs = 2, rope = 1, flint = 1}}) do
    test("partial supplies craft a single " .. name, function()
        Reset(); local i = Actor(); Chest(5, supplies); Complete(i)
        assert(#crafted == 1 and crafted[1] == name, "single item was rejected or wrong item crafted")
    end)
end
test("gear and umbrella have the same score and yield to every safety gate", function()
    Reset(); local i = EquippedActor(); assert(Basic.Score(i, {}) == 73)
    for _, key in ipairs({"ghost", "threat", "dark", "thermal", "hurt", "hurt_evade"}) do
        local context = {}; context[key] = true; assert(Basic.Score(i, context) == 0)
    end
    i._my_friend_command = {id = "sit"}; assert(Basic.Score(i, {}) == 0); i._my_friend_command = nil
    i.hunger = .2; assert(Basic.Score(i, {}) == 0); i.hunger = .8
    i.state_tags = {busy = true}; assert(Basic.Score(i, {}) == 0)
end)
test("real Utility preempts umbrella preparation for rescue without applying failure cooldown", function()
    Reset(); local i = EquippedActor(); Add(i, "pigskin", 1); Add(i, "twigs", 6); Add(i, "silk", 2)
    i.components.locomotor.Clear = function() end
    package.loaded.my_friend_progress = {Check = function() end}
    package.loaded.my_friend_dialogue = {OnDecision = function() end}
    local Utility = require("behaviours/my_friend_utility")
    local function Node(getter)
        local n = {status = READY, getactionfn = getter}
        function n:Reset() self.status = READY end
        function n:Stop() self.stopped = true end
        function n:Visit()
            if self.getactionfn ~= nil and self.action == nil then
                self.action = assert(self.getactionfn())
                function self.action:Fail() for _, fn in ipairs(self.fail) do fn() end end
            end
            self.status = RUNNING
        end
        return n
    end
    local gear, rescue, rescue_score = Node(function() return Basic.GetAction(i) end), Node(), 0
    local u = Utility(i, {{id = "basic_equipment", node = gear, score = function(c) return Basic.Score(i, c) end},
        {id = "rescue", node = rescue, score = function() return rescue_score end}}, function() return {} end)
    u:Visit(); assert(u.active.id == "basic_equipment"); local a = gear.action
    rescue_score = 144; u:Visit()
    assert(u.active.id == "rescue" and a._my_friend_cancelled and gear.stopped)
    assert(i._my_friend_base_equipment.rain_next_scan == nil)
end)
local function SewingActor()
    local i = EquippedActor(); i.sewing_default = nil
    i.components.moisture = {inherentWaterproofness = .8}
    return i
end
test("missing sewing supplies craft exactly one native sewing kit from base ground and chest materials", function()
    Reset(); local i = SewingActor(); Chest(5, {log = 1, houndstooth = 2}); Item(nil, "silk", 8, 28)
    assert(Basic.Score(i, {}) == 73); Complete(i)
    assert(#crafted == 1 and crafted[1] == "sewing_kit")
    local before = scans; assert(Basic.Score(i, {}) == 0 and Basic.GetAction(i) == nil and scans == before)
end)
test("usable active sewing tape prevents duplicate kit preparation", function()
    Reset(); local i = SewingActor(); i.active = Item(i, "sewing_tape"); i.active.components.sewing = {}
    assert(Basic.Score(i, {}) == 0 and Basic.GetAction(i) == nil and scans == 0)
end)
test("exhausted sewing kit does not count as a usable sewing supply", function()
    Reset(); local i = SewingActor(); local old = Add(i, "sewing_kit", 1)
    old.components.sewing = {}; old.components.finiteuses = {GetUses = function() return 0 end}
    Chest(4, {log = 1, silk = 8, houndstooth = 2}); Complete(i)
    assert(#crafted == 1 and crafted[1] == "sewing_kit")
end)
test("locked sewing supply does not suppress kit preparation", function()
    Reset(); local i = SewingActor(); local old = Add(i, "sewing_tape", 1)
    old.components.sewing = {}; old.components.inventoryitem.islockedinslot = true
    Chest(4, {log = 1, silk = 8, houndstooth = 2}); Complete(i)
    assert(#crafted == 1 and crafted[1] == "sewing_kit")
end)
test("sewing kit failure cools down for exactly 240 seconds without repeated discovery", function()
    Reset(); local i = SewingActor(); assert(Basic.GetAction(i) == nil)
    local before, start = scans, now
    local c = Chest(4, {log = 1, silk = 8, houndstooth = 2}); Discovery.Touch(c)
    now = start + 239.99; assert(Basic.Score(i, {}) == 0 and Basic.GetAction(i) == nil and scans == before)
    now = start + 240; Complete(i); assert(Crafted("sewing_kit"))
end)
test("sewing failure does not block a new armour job", function()
    Reset(); local i = SewingActor(); assert(Basic.GetAction(i) == nil)
    local retry = i._my_friend_base_equipment.sewing_next_scan; assert(retry == now + 240)
    i.items[1].removed = true; Add(i, "pigskin", 1); Add(i, "rope", 1); Discovery.InventoryChanged(i)
    Complete(i); assert(#crafted == 1 and crafted[1] == "footballhat")
    assert(i._my_friend_base_equipment.sewing_next_scan == retry)
end)
test("combat and rain failure do not block an affordable sewing kit", function()
    Reset(); local i = Actor(); i.sewing_default = nil
    Chest(4, {log = 1, silk = 8, houndstooth = 2}); Complete(i)
    assert(#crafted == 1 and crafted[1] == "sewing_kit")
    assert(i._my_friend_base_equipment.next_scan == now + 240 and i._my_friend_base_equipment.rain_next_scan == now + 240)
end)
test("gifted sewing supplies invalidate a queued kit and cancellation does not consume cooldown", function()
    Reset(); local i = SewingActor(); Add(i, "log", 1); Add(i, "silk", 8); Add(i, "houndstooth", 2)
    local a = assert(Basic.GetAction(i)); assert(a.recipe == "sewing_kit" and a.validfn(a))
    local gift = Add(i, "sewing_kit", 1); gift.components.sewing = {}
    assert(not a.validfn(a)); a._my_friend_cancelled = true
    for _, fn in ipairs(a.fail) do fn() end
    assert(i._my_friend_base_equipment.sewing_next_scan == nil and Basic.GetAction(i) == nil)
end)
test("sewing kit respects science requirements, busy state and explicit commands", function()
    Reset(); local i = SewingActor(); i.unknown = true
    Chest(4, {log = 1, silk = 8, houndstooth = 2}); assert(Basic.GetAction(i) == nil)
    i.unknown = nil; i._my_friend_base_equipment = nil
    i.state_tags = {busy = true}; assert(Basic.GetAction(i) == nil)
    i.state_tags = {}; i._my_friend_command = {id = "sit"}; assert(Basic.Score(i, {}) == 0 and Basic.GetAction(i) == nil)
end)
print(string.format("RESULT: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
