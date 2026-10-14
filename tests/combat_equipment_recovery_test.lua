-- Run from the mod root: lua tests/combat_equipment_recovery_test.lua
package.path = "scripts/?.lua;" .. package.path
local now = 10
GetTime = function() return now end
Vector3 = function(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
EQUIPSLOTS = {HANDS = "hands", HEAD = "head", BODY = "body"}
ACTIONS = {PICKUP = {}, ATTACK = {}}
package.loaded.my_friend_food_ai = {}
package.loaded.my_friend_resource_safety = {IsBlocked = function() return false end}
BufferedAction = function(inst, target, action)
    local a = {doer = inst, target = target, action = action}
    function a:AddSuccessAction(fn) self.success = fn end
    function a:AddFailAction(fn) self.failure = fn end
    function a:GetActionPoint() return self.target:GetPosition() end
    return a
end
local function entity(prefab, x)
    local e = {prefab = prefab, components = {}, pos = {x = x or 0, y = 0, z = 0}, events = {}, tags = {}}
    function e:IsValid() return not self.removed end
    function e:HasTag(tag) return self.tags[tag] == true end
    function e:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    function e:GetPosition() return self.pos end
    function e:GetDistanceSqToInst(other) return (self.pos.x - other.pos.x)^2 end
    function e:GetCurrentPlatform() return nil end
    function e:ListenForEvent(event, fn) self.events[event] = fn end
    e.Transform = {GetWorldPosition = function() return e.pos.x, 0, 0 end}
    return e
end
local inst, enemy, leader = entity("wendy"), entity("hound", 2), entity("wilson", -30)
inst.tags.my_friend, enemy.tags.hound = true, true
inst.components.health = {IsDead = function() return false end, GetPercent = function() return 1 end}
enemy.components.health = {IsDead = function() return false end}
enemy.components.combat = {target = inst}
inst.components.combat = {}
inst.components.follower = {GetLeader = function() return leader end}
local function weapon(name, damage)
    local item = entity(name, 6)
    item.owner = inst
    item.components = {inventoryitem = {canbepickedup = true, GetGrandOwner = function() return item.owner end},
        equippable = {equipslot = "hands"}, weapon = {GetDamage = function() return damage end}}
    return item
end
local sword, tool = weapon("spear", 50), weapon("axe", 20)
sword.components.inventoryitem.owner, tool.components.inventoryitem.owner = inst, inst
local hand, room, equips = sword, true, 0
local inv = {inst = inst, GetEquippedItem = function(_, slot) return slot == "hands" and hand or nil end,
    ReferenceAllItems = function() return hand and {hand} or {} end,
    CanAcceptCount = function() return room and 1 or 0 end}
function inv:Equip(item)
    -- Mirror the native same-item trap: RemoveFromOwner unequips it, then
    -- olditem == item skips reassignment. The recovery callback must not call it.
    if hand == item then
        hand, item.owner, item.components.inventoryitem.owner = nil, nil, nil
        item.tags.INLIMBO = true
        return
    end
    hand = item; equips = equips + 1
    inst.events.equip(inst, {item = item, eslot = "hands"})
    return true
end
inst.components.inventory = inv
local Equipment = require("my_friend_equipment")
local AI = require("my_friend_behavior_ai")
local Navigation = require("my_friend_navigation")
local Policy = require("my_friend_policy")
Equipment.Configure(inst)
inst._my_friend_combat_hand_item = sword
inst.events.unequip(inst, {item = sword, eslot = "hands"})
hand, sword.owner, sword.components.inventoryitem.owner = nil, nil, nil
inst.events.dropitem(inst, {item = sword})
inv:Equip(tool)
inst._my_friend_combat_hand_item = tool -- even an older fallback must not erase the dropped sword
assert(Equipment.FindDroppedCombatItem(inst) == sword)
assert(not AI.CanCounterAttack(inst, enemy), "picking up the real weapon must win over tools/bare hands")
assert(Equipment.COMBAT_RECOVERY_SCORE > 128 + 10, "recovery must interrupt active assistance")
local action = Equipment.GetDroppedCombatItemAction(inst)
Policy.GuardAction(inst, action)
assert(action:validfn(), "recovery is not blocked by the leader's ordinary activity range")
inst._my_friend_navigation_action = action
assert(Navigation.InTravelRange(inst, sword.pos))
sword.owner, sword.components.inventoryitem.owner = inst, inst
action.success()
assert(hand == sword and inst._my_friend_combat_recovery_item == nil and inst._my_friend_combat_hand_item == sword)
assert(equips == 2, "picked-up weapon should be re-equipped")
-- Empty hands: native PICKUP has already equipped the spear before Succeed.
hand, sword.owner, sword.components.inventoryitem.owner = nil, nil, nil
inst._my_friend_combat_recovery_item = sword
action = Equipment.GetDroppedCombatItemAction(inst)
sword.owner, sword.components.inventoryitem.owner = inst, inst
inv:Equip(sword)
local before_equips = equips
action.success()
assert(hand == sword and sword.components.inventoryitem.owner == inst and not sword.tags.INLIMBO)
assert(equips == before_equips, "auto-equipped pickup must not equip the same weapon twice")
-- The companion inventory hook also protects other callers and installs once.
Equipment.Wrap(inv)
local wrapped = inv.Equip
Equipment.Wrap(inv)
assert(inv.Equip == wrapped and inv:Equip(sword) == true and hand == sword)
assert(equips == before_equips)
-- A stolen weapon must not be substituted with someone else's identical prefab.
inst._my_friend_combat_recovery_item = sword
sword.owner, sword.components.inventoryitem.owner = leader, leader
assert(Equipment.FindDroppedCombatItem(inst) == nil)
sword.owner, sword.components.inventoryitem.owner, hand = nil, nil, tool
inst._my_friend_combat_recovery_item = sword
room = false; assert(Equipment.CombatRecoveryScore(inst) == 0); room = true
action = Equipment.GetDroppedCombatItemAction(inst)
action.failure()
assert(Equipment.FindDroppedCombatItem(inst) == nil, "failed pickup uses a retry delay")
now = now + 5; assert(Equipment.FindDroppedCombatItem(inst) == sword)
action = Equipment.GetDroppedCombatItemAction(inst)
now = now + Equipment.COMBAT_RECOVERY_TIMEOUT
assert(not Equipment.IsCombatRecoveryActionValid(inst, action), "the whole pickup attempt has a bounded deadline")
action.failure()
assert(Equipment.FindDroppedCombatItem(inst) == nil)
now = now + Equipment.COMBAT_RECOVERY_RETRY
action = Equipment.GetDroppedCombatItemAction(inst)
action._my_friend_cancelled = true
action.failure()
assert(Equipment.FindDroppedCombatItem(inst) == nil, "interrupted recovery cannot churn each frame")
now = now + 1
assert(Equipment.FindDroppedCombatItem(inst) == sword)
Equipment.Removed(inst, "hands", sword)
assert(Equipment.FindDroppedCombatItem(inst) == nil, "explicit player removal must not be undone")
-- Active combat checks share loadout scoring without delaying a fresh disarm.
hand, sword.owner, sword.components.inventoryitem.owner = sword, inst, inst
local full_checks = 0
local old_counter = AI.CanCounterAttack
AI.CanCounterAttack = function() full_checks = full_checks + 1; return true end
local started = now
for frame = 0, 29 do
    now = started + frame / 30
    assert(AI.CanContinueCombat(inst, enemy))
end
assert(full_checks <= 4, "combat frames must not rescore the full loadout each tick")
sword.owner, sword.components.inventoryitem.owner, hand = nil, nil, tool
inst._my_friend_combat_recovery_item = sword
assert(not AI.CanContinueCombat(inst, enemy), "new disarms invalidate the cache immediately")
AI.CanCounterAttack = old_counter
print("PASS: disarmed weapon recovery, native auto-equip idempotence, ownership/full slots, bounded deadlines and cancellation/retry delays")
