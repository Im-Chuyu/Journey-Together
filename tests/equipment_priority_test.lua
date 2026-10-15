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
    inst.components.moisture = {}
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
-- A non-armour crown must not override usable armour in either slot.
local combat_head = inventory.slots.head
crown = gear(inst, "alterguardianhat", "head")
inventory.items[#inventory.items + 1] = crown
AI.EquipBestCombatArmor(inst, enemy)
assert(inventory.slots.head == combat_head and inventory.slots.body == insulated,
    "combat armour takes priority over the daily crown preference")
before = equips; AI.EquipBestCombatArmor(inst, enemy)
assert(equips == before)

-- Real and unknown multifunctional gear follows component capabilities,
-- regardless of inventory order or whether the crown is already equipped.
need, TheWorld.state.israining = nil, false
for _, slot in ipairs({"head", "body"}) do
    for _, name in ipairs({"lunarplanthat", "ruinshat", "mod_weather_armor"}) do
        for _, crown_first in ipairs({true, false}) do
            inst, inventory = companion()
            inst._my_friend_under_threat = true
            crown = gear(inst, "alterguardianhat", "head")
            local armor = gear(inst, name, slot, .9, {hot = 240}, .35)
            armor.tags.light = true
            inventory.items = crown_first and {crown, armor} or {armor, crown}
            if slot == "head" then inventory:Equip(crown) end
            AI.EquipBestCombatArmor(inst, enemy)
            assert(inventory.slots[slot] == armor, name .. ": capabilities must not exclude armour")
            local before_scans, before_equips = scans, equips
            for i = 1, 5 do
                AI.EquipBestCombatArmor(inst, enemy)
                now = now + 2
                Equipment.UpdateLoadout(inst)
                Light.UpdateEquipment(inst)
                Light.GetLightAction(inst)
            end
            assert(scans == before_scans + 5, "one carried-item snapshot per armour evaluation")
            assert(equips == before_equips, "multifunctional armour must not churn")
        end
    end
end

-- Stronger absorption wins even against weak armour with thermal/rain/speed
-- bonuses. Among equally protective armour, active needs break the tie.
for _, slot in ipairs({"head", "body"}) do
    for _, thermal in ipairs({"cold", "hot", "rain"}) do
        inst, inventory = companion()
        need = thermal ~= "rain" and thermal or nil
        TheWorld.state.israining = thermal == "rain"
        local plain = gear(inst, "plain_armor", slot, .9)
        local useful = gear(inst, "mod_multifunction_armor", slot, .8, {[thermal] = 240}, 1)
        inventory.items = {useful, plain}
        inventory:Equip(useful)
        AI.EquipBestCombatArmor(inst, enemy)
        assert(inventory.slots[slot] == plain, "utility must not outweigh stronger absorption")
        useful.components.armor.GetAbsorption = function() return .9 end
        useful.components.armor.condition = 50
        AI.EquipBestCombatArmor(inst, enemy)
        assert(inventory.slots[slot] == useful, thermal .. ": equal protection prefers active utility")
        before = equips
        AI.EquipBestCombatArmor(inst, enemy)
        assert(equips == before, "fully waterproof armour must remain stable")
    end
end

-- Durability breaks remaining ties; an exact tie keeps the current item.
inst, inventory = companion()
need, TheWorld.state.israining = nil, false
local low = gear(inst, "armor_low", "head", .9)
local high = gear(inst, "armor_high", "head", .9)
low.components.armor.condition = 10
inventory.items = {low, high}; inventory:Equip(low)
AI.EquipBestCombatArmor(inst, enemy)
assert(inventory.slots.head == high)
low.components.armor.condition = 100
before = equips; AI.EquipBestCombatArmor(inst, enemy)
assert(equips == before)

-- Compare absorption against the actual attacker and weapon, not a prefab
-- list or unconditional base value. Unsupported armour falls back safely.
local enemyweapon = entity("enemy_weapon")
low.components.armor.GetAbsorption = function(_, attacker, weapon)
    assert(attacker == enemy and weapon == enemyweapon)
    return nil
end
high.components.armor.GetAbsorption = low.components.armor.GetAbsorption
crown = gear(inst, "alterguardianhat", "head")
inventory.items[#inventory.items + 1] = crown
AI.EquipBestCombatArmor(inst, enemy, enemyweapon)
assert(inventory.slots.head == crown, "no applicable armour allows the daily fallback")

-- Unneeded rain protection and insulation for the wrong season do not
-- displace equal armour; speed is useful while manoeuvring in combat.
inst, inventory = companion()
need = "hot"
local plain = gear(inst, "plain_armor", "head", .9)
local wrong_season = gear(inst, "winter_armor", "head", .9, {cold = 240}, 1)
inventory.items = {wrong_season, plain}; inventory:Equip(plain)
before = equips; AI.EquipBestCombatArmor(inst, enemy)
assert(equips == before, "only active environmental needs affect utility")
wrong_season.components.equippable.GetWalkSpeedMult = function() return 1.25 end
AI.EquipBestCombatArmor(inst, enemy)
assert(inventory.slots.head == wrong_season, "speed can break an equal-protection tie")
need = nil

-- Invalid, depleted, restricted, locked or foreign armour cannot suppress
-- the fallback. Empty light fuel alone must not invalidate working armour.
for _, state in ipairs({"broken", "depleted", "restricted", "locked", "foreign", "removed"}) do
    inst, inventory = companion()
    crown = gear(inst, "alterguardianhat", "head")
    local armor = gear(inst, "mod_armor", "head", .95)
    if state == "broken" then armor.tags.broken = true
    elseif state == "depleted" then armor.components.armor.condition = 0
    elseif state == "restricted" then armor.restricted = true
    elseif state == "locked" then armor.components.inventoryitem.islockedinslot = true
    elseif state == "foreign" then armor.owner = enemy
    elseif state == "removed" then armor.removed = true end
    inventory.items = {armor, crown}
    AI.EquipBestCombatArmor(inst, enemy)
    assert(inventory.slots.head == crown, state .. ": ignore unusable armour")
end
inst, inventory = companion()
crown = gear(inst, "alterguardianhat", "head")
local helmet = gear(inst, "mod_lit_armor", "head", .9)
helmet.components.fueled = {IsEmpty = function() return true end}
inventory.items = {crown, helmet}; inventory:Equip(crown)
AI.EquipBestCombatArmor(inst, enemy)
assert(inventory.slots.head == helmet, "depleted lighting does not remove armour protection")

-- The action-based lighting path must also stand down while fighting, even
-- in darkness, and resume once the threat/target/short weapon lock expires.
Light.IsDark = function() return true end
for _, lock in ipairs({"threat", "target", "hand"}) do
    inst._my_friend_under_threat = lock == "threat"
    inst.components.combat.target = lock == "target" and enemy or nil
    inst._my_friend_combat_hand_until = lock == "hand" and now + 4 or nil
    before = equips
    Light.UpdateEquipment(inst)
    Light.GetLightAction(inst)
    assert(inventory.slots.head == helmet and equips == before,
        lock .. ": lighting must not override combat armour")
end
now = now + 5
Light.GetLightAction(inst)
assert(inventory.slots.head == crown, "lighting resumes after combat locks expire")
Light.IsDark = function() return false end

inst._my_friend_under_threat = true
AI.EquipBestCombatArmor(inst, enemy)
assert(inventory.slots.head == helmet)
inst._my_friend_under_threat, inst._my_friend_combat_hand_until = false, nil
now = now + 15
Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == crown, "daytime crown preference resumes after combat")

-- With no armour candidate, ordinary clothing remains equipped.
inst, inventory = companion()
local coat = gear(inst, "weathercoat", "body", nil, {cold = 240}, 1)
inventory.items = {coat}; inventory:Equip(coat)
AI.EquipBestCombatArmor(inst, enemy)
assert(inventory.slots.body == coat)

-- Rain utility is the remaining protection of the whole loadout. A full
-- source is tried first, and redundant worn pieces are released without a
-- wear/remove loop or discarding the single fully protective piece instead.
for _, pre_equipped in ipairs({false, true}) do
    inst, inventory = companion()
    need, TheWorld.state.israining = nil, true
    local rainhat = gear(inst, "rainhat", "head", nil, nil, .5)
    local raincoat = gear(inst, "raincoat", "body", nil, nil, .5)
    local umbrella = gear(inst, "umbrella", "hands", nil, nil, 1)
    inventory.items = {rainhat, raincoat, umbrella}
    if pre_equipped then
        inventory:Equip(rainhat); inventory:Equip(raincoat); inventory:Equip(umbrella)
    end
    Equipment.UpdateLoadout(inst)
    now = now + 45; Equipment.UpdateLoadout(inst)
    assert(inventory.slots.hands == umbrella and inventory.slots.head == nil
        and inventory.slots.body == nil, "one full item replaces redundant partial rain gear")
    before = equips
    for i = 1, 8 do now = now + 45; Equipment.UpdateLoadout(inst) end
    assert(equips == before, "fully protected loadout must remain stable")
end
-- Several partial items may be required, but a third pure rain item adds no
-- utility after their combined protection reaches 100%.
inst, inventory = companion()
local head_rain = gear(inst, "rainhat", "head", nil, nil, .5)
local body_rain = gear(inst, "raincoat", "body", nil, nil, .5)
local hand_rain = gear(inst, "partial_umbrella", "hands", nil, nil, .35)
inventory.items = {head_rain, body_rain, hand_rain}
Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == head_rain and inventory.slots.body == body_rain
    and inventory.slots.hands == nil, "combined full protection prevents a third rain item")
-- Extra rain protection is allowed when another active capability needs the
-- same piece; inherent waterproofness also counts towards the shared limit.
inst, inventory = companion()
need = "cold"
local warm_rain = gear(inst, "warm_rainhat", "head", nil, {cold = 240}, .5)
local full_rain = gear(inst, "raincoat", "body", nil, nil, 1)
inventory.items = {warm_rain, full_rain}
Equipment.UpdateLoadout(inst)
assert(inventory.slots.head == warm_rain and inventory.slots.body == full_rain)
inst, inventory = companion()
need = nil
inst.components.moisture.inherentWaterproofness = 1
inventory.items = {gear(inst, "umbrella", "hands", nil, nil, 1)}
Equipment.UpdateLoadout(inst)
assert(inventory.slots.hands == nil, "intrinsic protection removes the need for pure rain gear")
print("PASS: combat/daily equipment priorities, aggregate rain protection, redundant gear release, multifunctional retention and stable loadouts")
