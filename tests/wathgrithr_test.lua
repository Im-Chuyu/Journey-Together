-- Run from the mod root: lua tests/wathgrithr_test.lua
package.path = "scripts/?.lua;" .. package.path
local now, leader, blocked = 0, nil, false
GetTime = function() return now end
TUNING = {TOTAL_DAY_TIME = 480}
EQUIPSLOTS = {HANDS = "hands"}
ACTIONS = {WALKTO = {}, MY_FRIEND_LIGHTNING_LUNGE = {}}
package.loaded.my_friend_policy = {
    GetLeader = function() return leader end, IsLocalPlayer = function(p) return p == leader and p ~= nil end,
    IsBusy = function(inst) return inst.busy end,
    DistanceSq = function(a, b) return (a.pos.x - b.pos.x)^2 + (a.pos.z - b.pos.z)^2 end,
}
local said = {}
package.loaded.my_friend_dialogue = {RandomReply = function(_, key, name)
    said[#said + 1] = {key, name}; return true
end}
local entities, scans = {}, 0
TheSim = {FindEntities = function() scans = scans + 1; return entities end}
TheWorld = {Map = {CanCastAtPoint = function() return not blocked end}}
BufferedAction = function(inst, target, action, weapon)
    return {doer = inst, target = target, action = action, invobject = weapon}
end
local function entity(prefab, x)
    local value = {prefab = prefab, components = {}, pos = {x = x or 0, y = 0, z = 0}, events = {}}
    function value:IsValid() return true end
    function value:HasTag(tag) return tag == "my_friend" and self.prefab == "wathgrithr" end
    function value:HasAnyTag() return false end
    function value:GetPosition() return self.pos end
    function value:ListenForEvent(event, fn) self.events[event] = fn end
    function value:DoPeriodicTask() end
    function value:GetDisplayName() return "Astra" end
    return value
end
local inst, target = entity("wathgrithr", 0), entity("hound", 3)
target.components.health, target.components.combat = {IsDead = function() return false end}, {}
local percent, charged, casts = 1, true, 0
local weapon = entity("spear_wathgrithr_lightning_charged")
weapon.components = {finiteuses = {GetPercent = function() return percent end},
    rechargeable = {IsCharged = function() return charged end}, aoeweapon_lunge = {},
    aoespell = {CastSpell = function() casts = casts + 1; return true end}}
local carrying = true
inst.components.inventory = {GetEquippedItem = function() return weapon end,
    ReferenceAllItems = function() return carrying and {weapon} or {} end}
inst.components.health = {IsDead = function() return false end}
local Wigfrid = require("my_friend_wathgrithr")
Wigfrid.Configure(inst)
for i = 1, 3 do
    inst.events.onattackother(inst, {target = target, weapon = weapon})
    assert(Wigfrid.GetCombatAction(inst, target) == nil)
end
inst.events.onattackother(inst, {target = target, weapon = weapon})
local action = Wigfrid.GetCombatAction(inst, target)
assert(action.action == ACTIONS.MY_FRIEND_LIGHTNING_LUNGE)
inst.busy, inst.sg = true, {currentstate = {name = "combat_lunge_start"}}
assert(Wigfrid.PerformLunge(action) and casts == 1 and inst._my_friend_spear_hits == 0)
inst.busy, inst.sg = false, nil
percent = .09; assert(Wigfrid.GetCombatAction(inst, target).action == ACTIONS.MY_FRIEND_LIGHTNING_LUNGE)
charged = false
local unavailable, wait = Wigfrid.GetCombatAction(inst, target)
assert(unavailable == nil and wait)
charged, percent = true, .2
assert(Wigfrid.GetCombatAction(inst, target) ~= nil, "20% still uses repair-only mode")
percent = .21
assert(Wigfrid.GetCombatAction(inst, target) == nil, "above 20% restores normal attacks")
percent = .09
local plant = entity("leif", 3)
plant.components = {health = {IsDead = function() return false end}, combat = {}, burnable = {}}
plant.sg = {mem = {burn_on_electrocute = true}}
assert(Wigfrid.GetCombatAction(inst, plant) == nil and not Wigfrid.CanLunge(inst, plant, weapon))
entities = {plant}
assert(Wigfrid.CanLunge(inst, target, weapon), "nearby plants are not the selected combat target")
for _, prefab in ipairs({"sapling", "farm_plant_carrot", "farm_plant_tomato", "evergreen"}) do
    entities = {entity(prefab, 2)}
    assert(Wigfrid.CanLunge(inst, target, weapon), prefab .. " must not block a lunge")
    assert(not Wigfrid.CanLunge(inst, entities[1], weapon), "non-combat vegetation is not a lunge target")
end
local Rules = require("my_friend_combat_rules")
for _, prefab in ipairs({"leif", "leif_sparse", "lordfruitfly", "lunarthrall_plant", "lunarthrall_plant_vine_end"}) do
    local enemy = entity(prefab, 3)
    enemy.components = {health = {IsDead = function() return false end}, combat = {}, burnable = {}}
    enemy.sg, enemy.tired = {mem = {burn_on_electrocute = true}}, true
    assert(Rules.BurnsWhenElectrocuted(enemy) and not Wigfrid.CanLunge(inst, enemy, weapon), prefab)
end
local fruitdragon = entity("fruitdragon", 3)
fruitdragon.components = {health = {IsDead = function() return false end}, combat = {}}
fruitdragon.sg = {mem = {burn_on_electrocute = true}}
assert(Wigfrid.CanLunge(inst, fruitdragon, weapon), "a short electrocuted stun without burnable is not ignition")
fruitdragon.components.burnable = {}
fruitdragon.sg.mem.noelectrocute = true
assert(Wigfrid.CanLunge(inst, fruitdragon, weapon), "permanently disabled electrocution cannot ignite")
fruitdragon.sg.mem.noelectrocute = nil
fruitdragon.HasTag = function(_, tag) return tag == "fireimmune" end
assert(Wigfrid.CanLunge(inst, fruitdragon, weapon), "fire-immune targets cannot be ignited")
assert(scans == 0, "lunge selection must not scan nearby vegetation")
entities = {}; blocked = true; assert(not Wigfrid.CanLunge(inst, target, weapon)); blocked = false
carrying, leader = false, entity("wilson", 1)
now = 5 * 480 - 1; Wigfrid.UpdateRequest(inst); assert(#said == 0)
now = 5 * 480; Wigfrid.UpdateRequest(inst)
assert(said[1][1] == "spear_request" and said[1][2] == "Astra")
assert(not Wigfrid.Answer(inst, entity("wilson"), "不行"))
assert(Wigfrid.Answer(inst, leader, "没材料"))
assert(said[2][1] == "spear_request_refused")
now = now + 5 * 480; Wigfrid.UpdateRequest(inst)
now = now + 31; assert(not Wigfrid.Answer(inst, leader, "不可以"))
local saved = {}; Wigfrid.Save(inst, saved)
local restored = entity("wathgrithr"); Wigfrid.Load(restored, saved)
assert(restored._my_friend_spear_ask_after == inst._my_friend_spear_ask_after)
print("PASS: native lunge cycle, target-only electrocution ignition checks, no vegetation scans, durability and timed requests")
