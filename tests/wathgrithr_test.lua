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
local carrying, hand, active, contents, inventory_scans = true, weapon, nil, {}, 0
weapon.components.inventoryitem = {GetGrandOwner = function() return inst end}
inst.components.inventory = {GetEquippedItem = function() return hand end,
    GetActiveItem = function() return active end,
    ReferenceAllItems = function()
        inventory_scans = inventory_scans + 1
        return carrying and {weapon} or contents
    end}
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
carrying, hand, leader = false, nil, entity("wilson", 1)
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

local function inventory_changed()
    inst._my_friend_discovery_inventory = (inst._my_friend_discovery_inventory or 0) + 1
end
for _, prefab in ipairs({"spear_wathgrithr_lightning", "spear_wathgrithr_lightning_charged"}) do
    local spear, owner = entity(prefab), inst
    spear.components.inventoryitem = {GetGrandOwner = function() return owner end}
    for _, location in ipairs({"hand", "active", "inventory", "backpack"}) do
        hand, active, contents = nil, nil, {}
        if location == "hand" then hand = spear
        elseif location == "active" then active = spear
        else contents = {spear} end
        inventory_changed()
        now = inst._my_friend_spear_ask_after
        local replies, deadline = #said, inst._my_friend_spear_ask_after
        Wigfrid.UpdateRequest(inst)
        assert(#said == replies and inst._my_friend_spear_ask_after == deadline,
            prefab .. " in " .. location .. " suppresses requests without moving the five-day deadline")
        local before = inventory_scans
        for iteration = 1, 20 do now = now + 5; Wigfrid.UpdateRequest(inst) end
        assert(#said == replies and inventory_scans == before,
            "unchanged possession must not repeatedly traverse carried inventory")
        hand, active, contents, owner = nil, nil, {spear}, nil
        inventory_changed()
        Wigfrid.UpdateRequest(inst)
        assert(#said == replies + 1 and said[#said][1] == "spear_request",
            "a transferred spear must no longer suppress an overdue request")
        owner = inst
    end
end

local replies = #said
active = weapon
inventory_changed()
Wigfrid.UpdateRequest(inst)
assert(inst._my_friend_spear_question == nil and #said == replies,
    "receiving a spear during the reply window clears the pending question")
inst._my_friend_spear_question = {player = leader, deadline = now + 30}
assert(not Wigfrid.Answer(inst, leader, "不给") and inst._my_friend_spear_question == nil)
assert(#said == replies, "a fulfilled request must not produce a refusal response")
active, contents = nil, {}
inventory_changed()
Wigfrid.UpdateRequest(inst)
assert(#said == replies, "losing a spear must not bypass the existing five-day cooldown")
print("PASS: native lunge cycle, target-only ignition checks, durability, timed requests, carried spear suppression, cached possession and fulfilled question cleanup")
