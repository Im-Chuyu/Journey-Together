-- Run from the mod root: lua tests/equipment_priority_test.lua
package.path = "scripts/?.lua;" .. package.path
local now, need, scans, equips = 0, nil, 0, 0
GetTime = function() return now end
EQUIPSLOTS = {HEAD = "head", BODY = "body", HANDS = "hands"}
TheWorld = {ismastersim = true, state = {isday = true, israining = false}, HasTag = function() return false end}
TheSim = {FindEntities = function() error("equipment preference must not add world scans") end}
package.loaded.my_friend_policy = {IsBusy = function(inst) return inst.busy == true end,
    GetLeader = function() end}
package.loaded.my_friend_food_ai = {}
package.loaded.my_friend_navigation = {}
package.loaded.my_friend_home = {}
package.loaded.my_friend_inventory = {}
package.loaded.my_friend_resource_reserves = {}
package.loaded.my_friend_dialogue = {Say = function() end}
package.loaded.my_friend_survival_ai = {
    GetEquipmentThermalNeed = function() return need end,
    GetThermalNeed = function() return need end,
    GetInsulationValue = function(item, thermal)
        return item ~= nil and item.insulation ~= nil and item.insulation[thermal] or nil
    end,
    IsWornOut = function(item) return item ~= nil and item.worn == true end,
}
local function entity(prefab)
    local inst = {prefab = prefab, components = {}, tags = {my_friend = prefab == "wendy"}}
    function inst:IsValid() return not self.removed end
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    function inst:GetPosition() return {x = 0, y = 0, z = 0} end
    inst.components.health = {IsDead = function() return false end}
    return inst
end
local function companion()
    local inst = entity("wendy")
    local inventory = {inst = inst, slots = {}, items = {}}
    function inventory:GetEquippedItem(slot) return self.slots[slot] end
    function inventory:ReferenceAllItems() scans = scans + 1; return self.items end
    function inventory:CanAcceptCount() return 1 end
    function inventory:Equip(item)
        local slot = item.components.equippable.equipslot
        assert(self.slots[slot] ~= item, "never equip the same item twice")
        local current = self.slots[slot]
        if current ~= nil then current.equipped = false end
        self.slots[slot], item.equipped = item, true
        equips = equips + 1
        return true
    end
    function inventory:Unequip(slot)
        local current = self.slots[slot]
        self.slots[slot] = nil
        if current ~= nil then current.equipped = false end
        return current
    end
    function inventory:GiveItem() return true end
    inst.components.inventory, inst.components.combat = inventory, {}
    return inst, inventory
end
local function gear(inst, prefab, slot, armor, insulation, waterproof)
    local item = entity(prefab)
    item.owner, item.insulation = inst, insulation
    item.components.inventoryitem = {GetGrandOwner = function() return item.owner end}
    item.components.equippable = {equipslot = slot,
        IsRestricted = function() return item.restricted == true end,
        ShouldPreventUnequipping = function() return item.locked == true end,
        IsEquipped = function() return item.equipped == true end,
        GetWalkSpeedMult = function() return 1 end}
    if armor ~= nil then
        item.components.armor = {condition = 100, GetAbsorption = function() return armor end}
    end
    if waterproof ~= nil then
        item.components.waterproofer = {GetEffectiveness = function() return waterproof end}
    end
    return item
end
local Equipment = require("my_friend_equipment")
local Light = require("my_friend_light_ai")
Light.IsDark = function() return false end
local AI = require("my_friend_behavior_ai")
local inst, inventory = companion()
local crown = gear(inst, "alterguardianhat", "head")
inventory.items = {crown}
Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == crown, "carried crown should be worn even in daylight")
local before = equips
for i = 1, 8 do
    now = now + 15
    Equipment.UpdateLoadout(inst)
    Light.UpdateEquipment(inst)
end
assert(inventory.slots.head == crown and equips == before, "crown is neither stored nor re-equipped in daylight")
-- Ordinary headgear retains the old unused-gear removal behaviour.
inst, inventory = companion()
local hat = gear(inst, "footballhat", "head", .8)
inventory.items = {hat}; inventory:Equip(hat)
Equipment.UpdateLoadout(inst)
now = now + 31; Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == nil)
-- A miner's hat does not pin the slot against the preferred crown.
inst, inventory = companion()
hat, crown = gear(inst, "minerhat", "head"), gear(inst, "alterguardianhat", "head")
inventory.items = {hat, crown}; inventory:Equip(hat)
Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == crown)
-- Day-to-day thermal protection can still replace the crown when needed.
local warm = gear(inst, "winterhat", "head", nil, {cold = 240})
inventory.items[#inventory.items + 1] = warm
need, now = "cold", now + 11
Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == warm)
need, now = nil, now + 11
Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == crown)
-- Explicit removal cooldown, restrictions and ownership continue to apply.
inst, inventory = companion(); crown = gear(inst, "alterguardianhat", "head")
inventory.items = {crown}
Equipment.Removed(inst, "head", crown)
Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == nil)
now = now + 31; crown.restricted = true; Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == nil)
now = now + 2; crown.restricted, crown.owner = false, entity("wilson"); Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == nil)
now = now + 2; crown.owner, inst.busy = inst, true; Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == nil)
-- Combat replaces non-armour insulation and rain gear, for both slots.
local enemy = entity("hound")
for _, thermal in ipairs({"cold", "hot", "rain"}) do
    inst, inventory = companion()
    need = thermal ~= "rain" and thermal or nil
    TheWorld.state.israining = thermal == "rain"
    inst._my_friend_under_threat = true
    local head = gear(inst, "weatherhat", "head", nil, {[thermal] = 240}, 1)
    local body = gear(inst, "weathercoat", "body", nil, {[thermal] = 240}, 1)
    local helmet = gear(inst, "footballhat", "head", .8)
    local suit = gear(inst, "armorwood", "body", .8)
    inventory.items = {head, body, helmet, suit}
    inventory:Equip(head); inventory:Equip(body)
    local before_scans = scans
    AI.EquipBestCombatArmor(inst, enemy)
    assert(scans == before_scans + 1, "combat armour and crown selection reuse one inventory snapshot")
    assert(inventory.slots.head == helmet and inventory.slots.body == suit, thermal)
    now = now + 20
    Equipment.UpdateLoadout(inst)
    assert(inventory.slots.head == helmet and inventory.slots.body == suit, "survival loadout must stand down during combat")
end
-- Insulating armour remains a valid dual-purpose combat choice.
need = "cold"
local insulated = gear(inst, "insulatedarmor", "body", .8, {cold = 240})
inventory.items[#inventory.items + 1] = insulated
AI.EquipBestCombatArmor(inst, enemy)
assert(inventory.slots.body == insulated)
-- Crown is the explicit head exception; body armour is still selected.
crown = gear(inst, "alterguardianhat", "head")
inventory.items[#inventory.items + 1] = crown
AI.EquipBestCombatArmor(inst, enemy)
assert(inventory.slots.head == crown and inventory.slots.body == insulated)
before = equips; AI.EquipBestCombatArmor(inst, enemy)
assert(equips == before)
print("PASS: crown preference/daylight retention, normal headgear and thermal rules, ownership/removal guards, combat armour over clothing/rain gear, one shared inventory scan")
