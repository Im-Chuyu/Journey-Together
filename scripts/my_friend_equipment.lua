local M = {}
local LOADOUT_PERIOD = 1.25
local REPAIR_STATUS_PERIOD = 2
local EquipSlots = require("my_friend_equip_slots")
M.COMBAT_RECOVERY_RANGE = 8
M.COMBAT_RECOVERY_SCORE = 140
M.COMBAT_RECOVERY_TIMEOUT = 10
M.COMBAT_RECOVERY_RETRY = 5

function M.Removed(inst, slot, item)
    -- Explicit player removal is not an accidental disarm.
    if inst._my_friend_combat_recovery_item == item then inst._my_friend_combat_recovery_item = nil end
    if inst._my_friend_combat_hand_item == item then inst._my_friend_combat_hand_item = nil end
    if inst._my_friend_last_combat_unequip == item then inst._my_friend_last_combat_unequip = nil end
    if inst._my_friend_last_combat_equip == item then inst._my_friend_last_combat_equip = nil end
    if item ~= nil then item._my_friend_player_equipped_until = nil end
    inst._my_friend_equip_after = inst._my_friend_equip_after or {}
    inst._my_friend_equip_after[slot] = GetTime() + 30
    if item ~= nil and item:HasTag("backpack") then
        require("my_friend_backpacks").MarkOwned(inst, item)
        inst._my_friend_backpack_recover_after = GetTime() + 30
        inst._my_friend_backpack_retry = nil
    end
end

function M.MarkPlayerEquipped(inst, item)
    if item ~= nil and item:IsValid() then
        item._my_friend_player_equipped_until = GetTime() + 480
    end
end

function M.Allowed(inst, slot)
    local inventory = inst.components ~= nil and inst.components.inventory or nil
    local current = inventory ~= nil and inventory:GetEquippedItem(slot) or nil
    if current ~= nil and current:HasTag("heavy") then return false end
    return GetTime() >= ((inst._my_friend_equip_after or {})[slot] or 0)
end

function M.Hurt(inst)
    inst._my_friend_equip_after = nil
    inst._my_friend_backpack_recover_after = nil
    inst._my_friend_loadout_next = 0
end

function M.Save(inst, data)
    local saved = {}
    for slot, deadline in pairs(inst._my_friend_equip_after or {}) do
        if deadline > GetTime() then saved[slot] = deadline - GetTime() end
    end
    data.my_friend_equip_cooldowns = saved
    data.my_friend_backpack_cooldown = math.max(0, (inst._my_friend_backpack_recover_after or 0) - GetTime())
end

function M.Load(inst, data)
    inst._my_friend_equip_after = {}
    for slot, remaining in pairs(data ~= nil and data.my_friend_equip_cooldowns or {}) do
        if type(remaining) == "number" then
            inst._my_friend_equip_after[slot] = GetTime() + math.max(0, math.min(30, remaining))
        end
    end
    inst._my_friend_backpack_recover_after = GetTime()
        + math.max(0, math.min(30, data ~= nil and data.my_friend_backpack_cooldown or 0))
end

function M.Wrap(inventory)
    if inventory._my_friend_equipment_wrapped then return end
    inventory._my_friend_equipment_wrapped = true
    local equip = inventory.Equip
    inventory.Equip = function(self, item, ...)
        local component = item ~= nil and item.components.equippable or nil
        -- Native Equip removes an item's owner before testing olditem ~= item.
        -- Re-equipping the current item can therefore leave it in LIMBO.
        if self.inst:HasTag("my_friend") and component ~= nil and item:IsValid()
            and self:GetEquippedItem(component.equipslot) == item then return true end
        if self.inst:HasTag("my_friend") and component ~= nil and not self.isloading
            and not self.inst._my_friend_player_equipping
            and not self.inst._my_friend_wanda_dreadstone_pending then
            local current = self:GetEquippedItem(component.equipslot)
            if current ~= nil and current ~= item and current:HasTag("heavy") then return false end
        end
        if self.inst:HasTag("my_friend") and component ~= nil and not self.isloading
            and not self.inst._my_friend_player_equipping
            and not self.inst._my_friend_light_equip_override
            and not self.inst._my_friend_wanda_dreadstone_pending then
            local carry_heavy = self.inst._my_friend_command ~= nil
                and self.inst._my_friend_command.id == "carry_statue"
                and item ~= nil and item:HasTag("heavy")
            if not carry_heavy and not M.Allowed(self.inst, component.equipslot) then return false end
            local current = self:GetEquippedItem(component.equipslot)
            if component.equipslot == EQUIPSLOTS.HEAD and current ~= nil and current ~= item
                and GetTime() < (current._my_friend_player_equipped_until or 0) then
                local combat = self.inst.components.combat
                local survival = require("my_friend_survival_ai")
                -- Keeping a player chosen hat must never stop the companion
                -- from putting on warm or cooling gear, or from replacing a
                -- piece that is about to break.
                local emergency = self.inst._my_friend_under_threat
                    or combat ~= nil and combat.target ~= nil
                    or require("my_friend_light_ai").IsDark(self.inst)
                    or survival.NeedsTemperatureHelp(self.inst)
                    or survival.GetEquipmentThermalNeed(self.inst) ~= nil
                    or survival.IsWornOut(current)
                if not emergency then return false end
            end
        end
        return equip(self, item, ...)
    end
end

-- ---------------------------------------------------------------------------
-- Loadout arbiter for HEAD / BODY / HANDS.
--
-- These three slots used to be decided by four passes that all ran on every
-- brain tick, each aware of exactly one need: Rain wanted the waterproof
-- piece, UpdateMovementEquipment wanted the fast one, UpdateTemperatureEquipment
-- wanted the insulating one, and RemoveUnneeded stripped anything it did not
-- personally recognise as needed. Carrying an umbrella (rain + summer
-- insulation), a helmet (rain + armour) and a cane (speed) they could never
-- agree, and something was re-equipped almost every tick.
--
-- The worst offender was the take-off test: it asked moisture > 0, but good
-- rain gear drives moisture to zero, so the gear read as unnecessary the very
-- moment it started working, came off, moisture rose again, and it went back
-- on. Every flip is an unequip/equip pair with its own events, animation and
-- network traffic.
--
-- One pass now scores each candidate against every active need at once and
-- picks a single winner per slot. Need weights are two orders of magnitude
-- apart, so they act as a strict priority ladder (warmth/cooling > rain >
-- speed) while lower needs still break ties: given two equally waterproof hand
-- items, the one that also insulates wins.
--
-- Combat is deliberately not one of the needs. BehaviourAI.EquipBestCombatArmor
-- already owns HEAD and BODY while something is hostile, and it weighs armour
-- against the actual attacker and weapon rather than a raw absorb figure. All
-- four of the old passes stood down under threat for that reason, and so does
-- this one -- two systems dressing the companion mid-fight would just be the
-- same swap loop wearing a different hat.
-- ---------------------------------------------------------------------------

local NEED_WEIGHT = {
    thermal = 10000,
    rain = 100,
    speed = 1,
}

-- Nothing in a slot may change again for this long after it just did. The
-- single most effective guard against a swap loop: even if two needs disagree
-- forever, they can only trade the slot once every few seconds instead of
-- every frame.
M.SWAP_COOLDOWN = 10
-- A candidate has to be meaningfully better, not merely different, before the
-- companion pays the cost of changing.
M.SWAP_MARGIN = 1.1
-- How long a slot has to be useless before its contents are put away.
M.IDLE_RELEASE = 30
-- Dry weather has to hold for this long before rain gear comes off.
M.RAIN_RELEASE = 20
-- Insulation is expressed as extra seconds before freezing; INSULATION_LARGE
-- is the top of the vanilla range.
local INSULATION_SCALE = 240
-- A cane is 1.25, which is the practical ceiling for a hand item.
local SPEED_SCALE = .5

local survival_module, light_module
local function Survival()
    survival_module = survival_module or require("my_friend_survival_ai")
    return survival_module
end
local function Light()
    light_module = light_module or require("my_friend_light_ai")
    return light_module
end

function M.IsPreferredHead(inst, item)
    local c = item ~= nil and item:IsValid() and item.components or nil
    local equip = c ~= nil and c.equippable or nil
    return item ~= nil and item.prefab == "alterguardianhat" and equip ~= nil
        and equip.equipslot == EQUIPSLOTS.HEAD and not equip:IsRestricted(inst)
        and c.inventoryitem ~= nil and not c.inventoryitem.islockedinslot
        and c.inventoryitem:GetGrandOwner() == inst and not item:HasTag("broken")
        and (c.fueled == nil or not c.fueled:IsEmpty())
        and (c.finiteuses == nil or c.finiteuses:GetUses() > 0)
end

function M.PreferredHead(inst, items)
    local inventory = inst.components.inventory
    if inventory == nil then return end
    local current = inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
    if M.IsPreferredHead(inst, current) then return current end
    for _, item in ipairs(items or inventory:ReferenceAllItems()) do
        if M.IsPreferredHead(inst, item) then return item end
    end
end

-- Rain gear that is doing its job holds moisture at zero, so "am I wet" is the
-- wrong question while it is still raining. Ask the sky as well, and let the
-- answer linger, so a brief gap in the weather does not start a swap.
local function WantsRain(inst)
    local moisture = inst.components.moisture
    if moisture == nil then return false end
    local state = TheWorld ~= nil and TheWorld.state or nil
    if state ~= nil and state.israining == true then
        inst._my_friend_last_precipitation = GetTime()
        return true
    end
    -- Residual moisture needs drying, not an umbrella. Only actual rain starts
    -- the release window; spawning in clear weather must not start one.
    return inst._my_friend_last_precipitation ~= nil
        and GetTime() - inst._my_friend_last_precipitation < M.RAIN_RELEASE
end

local function IsTravelling(inst)
    local root = inst.brain ~= nil and inst.brain.bt ~= nil and inst.brain.bt.root or nil
    local node = root ~= nil and root.active ~= nil and root.active.node or nil
    if node ~= nil and node.routing then return true end
    return inst.sg ~= nil and (inst.sg:HasStateTag("moving")
        or inst.sg:HasStateTag("my_friend_walk"))
end

local function ActiveNeeds(inst)
    local thermal = Survival().GetEquipmentThermalNeed(inst)
    -- Hands follow the same temperature threshold as head/body. Combat owns
    -- the hand slot while attacking, then the cooling or warming item returns
    -- after the target is gone.
    local hand_thermal = thermal
    -- Published for the rest of the mod.
    inst._my_friend_temperature_equipment_need = thermal
    return {
        thermal = thermal,
        hand_thermal = hand_thermal,
        rain = WantsRain(inst),
        speed = IsTravelling(inst),
    }
end

local function Clamp01(value)
    if type(value) ~= "number" or value ~= value then return 0 end
    return value < 0 and 0 or value > 1 and 1 or value
end

local function RainProtection(item)
    local c = item ~= nil and item:IsValid() and item.components or nil
    return c ~= nil and c.waterproofer ~= nil
        and Clamp01(c.waterproofer:GetEffectiveness()) or 0
end

local function OtherRainProtection(inst, excluded_slot)
    local inventory = inst.components.inventory
    local moisture = inst.components.moisture
    local total = moisture ~= nil and (moisture.inherentWaterproofness or 0) or 0
    if moisture ~= nil and moisture.waterproofnessmodifiers ~= nil then
        total = total + (moisture.waterproofnessmodifiers:Get() or 0)
    end
    if inventory == nil then return total end
    for _, slot in ipairs(EquipSlots.All()) do
        if slot ~= excluded_slot then total = total + RainProtection(inventory:GetEquippedItem(slot)) end
    end
    return total
end

local function Score(inst, item, needs)
    if item == nil or not item:IsValid() then return 0 end
    local components = item.components
    local equippable = components ~= nil and components.equippable or nil
    if equippable == nil then return 0 end
    -- Crown utility remains useful in daylight/idle, below urgent thermal and
    -- rain protection but above the usual preference for an empty head slot.
    local score = not needs.combat and M.IsPreferredHead(inst, item) and 2 or 0
    local thermal = needs.thermal
    if equippable.equipslot == EQUIPSLOTS.HANDS then
        thermal = needs.hand_thermal
    end
    if thermal ~= nil then
        local insulation = Survival().GetInsulationValue(item, thermal)
        if insulation ~= nil then
            score = score + NEED_WEIGHT.thermal * Clamp01(insulation / INSULATION_SCALE)
        end
    end
    if needs.rain and components.waterproofer ~= nil then
        -- Score only the protection missing WITHOUT this slot. This applies
        -- equally to worn and stored items, and counts combined protection.
        local missing = math.max(0, 1 - OtherRainProtection(inst, equippable.equipslot))
        local waterproof = math.min(missing, RainProtection(item))
        score = score + NEED_WEIGHT.rain * waterproof
    end
    if needs.speed then
        local mult = equippable:GetWalkSpeedMult() or 1
        if mult > 1 then
            score = score + NEED_WEIGHT.speed * Clamp01((mult - 1) / SPEED_SCALE)
        end
    end
    -- Nearly destroyed gear is worth nothing here, so it is never chosen and,
    -- once it is the only thing in the slot, the stow branch below takes it off
    -- to be repaired rather than grinding the last of it away. Scoring it low
    -- but non-zero instead would have it stripped and immediately re-picked.
    if Survival().IsWornOut(item) then return 0 end
    return score
end

-- Combat first compares effective armour absorption. Reuse the ordinary
-- capability scoring only to break protection ties; a rain/thermal or headgear
-- preference must never disqualify armour or override stronger protection.
function M.GetCombatUtilityScore(inst, item, thermal_need)
    return Score(inst, item, {
        combat = true,
        thermal = thermal_need,
        rain = WantsRain(inst),
        speed = true,
    })
end

-- Slots the companion is not free to rearrange this tick.
local function IsSlotLocked(inst, slot, current, preferred_head)
    if not M.Allowed(inst, slot) then return true end
    if current ~= nil then
        if current.components.equippable:ShouldPreventUnequipping() then return true end
        -- The light AI owns whatever is lighting the way.
        if Light().IsLightEquipment(current)
            and not (slot == EQUIPSLOTS.HEAD
                and (preferred_head ~= nil or M.IsPreferredHead(inst, current))) then return true end
        if current:HasTag("backpack") then return true end
    end
    if slot == EQUIPSLOTS.HANDS then
        if inst._my_friend_tool_action ~= nil or inst._my_friend_work_target ~= nil
            or GetTime() < (inst._my_friend_hand_tool_lock_until or 0) then return true end
        local sg = inst.sg
        if sg ~= nil and (sg:HasStateTag("fishing") or sg:HasStateTag("catchfish")) then return true end
        if sg ~= nil and (sg:HasStateTag("prechop") or sg:HasStateTag("premine")
            or sg:HasStateTag("predig") or sg:HasStateTag("prehammer")
            or sg:HasStateTag("working")) then return true end
    end
    return false
end

local function LoadoutSlots(inst, items, needs, preferred_head)
    local slots = EquipSlots.All()
    if not needs.rain then return slots end
    -- Try the strongest rain source first: otherwise partial head/body gear
    -- can consume the entire need before a single 100% hand item is examined.
    local protection, order, full_slot = {}, {}, nil
    for index, slot in ipairs(slots) do
        order[slot] = index
        local current = inst.components.inventory:GetEquippedItem(slot)
        protection[slot] = RainProtection(current)
        if full_slot == nil and protection[slot] >= 1 and not Survival().IsWornOut(current) then
            full_slot = slot
        end
        if not IsSlotLocked(inst, slot, current, preferred_head) then
            for _, item in ipairs(items) do
                local equip = item:IsValid() and item.components.equippable or nil
                if equip ~= nil and equip.equipslot == slot and not equip:IsRestricted(inst)
                    and not Survival().IsWornOut(item)
                    and (not Light().IsLightEquipment(item) or item == preferred_head) then
                    protection[slot] = math.max(protection[slot], RainProtection(item))
                end
            end
        end
    end
    table.sort(slots, function(a, b)
        -- When already fully protected by one piece, release redundant pieces
        -- first. Otherwise simultaneous idle timers can discard the full piece
        -- and keep two partial ones merely because its slot was visited first.
        if a == full_slot then return false end
        if b == full_slot then return true end
        return protection[a] > protection[b]
            or protection[a] == protection[b] and order[a] < order[b]
    end)
    return slots
end

-- Only gear the companion put on for a reason is taken off again. A plain tool
-- or weapon in the hands is left alone, exactly as the old pass did.
local function IsDisposable(slot, item)
    local components = item ~= nil and item.components or nil
    if components == nil then return false end
    return slot == EQUIPSLOTS.HEAD or components.waterproofer ~= nil
        or components.armor ~= nil or components.insulator ~= nil
end

local function Timers(inst, key)
    inst[key] = inst[key] or {}
    return inst[key]
end

local function IsBroken(item)
    local finite = item ~= nil and item.components ~= nil and item.components.finiteuses
    local armor = item ~= nil and item.components ~= nil and item.components.armor
    local fueled = item ~= nil and item.components ~= nil and item.components.fueled
    return item ~= nil and item:IsValid()
        and (item:HasTag("broken")
            or finite ~= nil and finite:GetPercent() <= .15
            or fueled ~= nil and fueled:GetPercent() <= .15
            or armor ~= nil and not armor.indestructible and armor:GetPercent() <= .15)
end

local function IsCombatHandItem(item)
    return item ~= nil and item.components ~= nil
        and item.components.equippable ~= nil
        and item.components.equippable.equipslot == EQUIPSLOTS.HANDS
        and (item.components.weapon ~= nil or item.components.tool ~= nil)
end

local function IsUrgentRepairItem(item)
    if item == nil or item.components == nil then return false end
    local equippable = item.components.equippable
    local finite = item.components.finiteuses
    local forge = item.components.forgerepairable
    local broken = item:HasTag("broken")
    local depleted = finite ~= nil and finite:GetUses() <= 0
        or item.components.fueled ~= nil and item.components.fueled:IsEmpty()
    return (equippable ~= nil and (item.components.weapon ~= nil
                or item.components.tool ~= nil) and (broken or depleted))
        or forge ~= nil and broken
        or (item.prefab == "heatstone" or item.prefab == "heatrock")
            and equippable ~= nil
            and (broken or depleted)
end

function M.Configure(inst)
    if inst._my_friend_combat_recovery_configured then return end
    inst._my_friend_combat_recovery_configured = true
    inst._my_friend_last_combat_equip = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    inst:ListenForEvent("equip", function(_, data)
        if data ~= nil and data.eslot == EQUIPSLOTS.HANDS and IsCombatHandItem(data.item) then
            inst._my_friend_last_combat_equip = data.item
        end
    end)
    inst:ListenForEvent("unequip", function(_, data)
        if data ~= nil and data.eslot == EQUIPSLOTS.HANDS and IsCombatHandItem(data.item) then
            inst._my_friend_last_combat_unequip = data.item
        end
    end)
    inst:ListenForEvent("dropitem", function(_, data)
        local item = data ~= nil and data.item or nil
        if IsCombatHandItem(item) and (item == inst._my_friend_last_combat_equip
            or item == inst._my_friend_last_combat_unequip or item == inst._my_friend_combat_hand_item) then
            local previous = inst._my_friend_combat_recovery_item
            local ii = previous ~= nil and previous:IsValid() and previous.components.inventoryitem or nil
            if ii == nil or ii.owner ~= nil then inst._my_friend_combat_recovery_item = item end
            inst._my_friend_combat_recovery_retry = nil
            inst._my_friend_replan_requested = true
        end
    end)
end

function M.FindDroppedCombatItem(inst)
    if inst == nil or not inst:IsValid() or inst.components.inventory == nil
        or inst:HasTag("playerghost") or inst._my_friend_possess_parked or inst._my_friend_departing
        or inst.components.health ~= nil and inst.components.health:IsDead() then return end
    local item = inst._my_friend_combat_recovery_item or inst._my_friend_combat_hand_item
    if item == nil then return end
    local ii = item:IsValid() and item.components.inventoryitem or nil
    if ii == nil or ii.owner ~= nil or not IsCombatHandItem(item) then
        if inst._my_friend_combat_recovery_item == item then inst._my_friend_combat_recovery_item = nil end
        return
    end
    if GetTime() < (inst._my_friend_combat_recovery_retry or 0)
        or not ii.canbepickedup or item:HasAnyTag("INLIMBO", "fire", "outofreach", "broken")
        or item.components.finiteuses ~= nil and item.components.finiteuses:GetUses() <= 0
        or item.components.fueled ~= nil and item.components.fueled:IsEmpty()
        or inst:GetDistanceSqToInst(item) > M.COMBAT_RECOVERY_RANGE^2
        or inst:GetCurrentPlatform() ~= item:GetCurrentPlatform()
        or inst.components.inventory:CanAcceptCount(item, 1) < 1 then return end
    return item
end

function M.CombatRecoveryScore(inst)
    return M.FindDroppedCombatItem(inst) ~= nil and M.COMBAT_RECOVERY_SCORE or 0
end

function M.IsCombatRecoveryActionValid(inst, action, point)
    local item = action._my_friend_combat_recovery
    local ii = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    local origin = action._my_friend_combat_recovery_origin
    return inst:IsValid() and not inst:HasTag("playerghost") and not inst._my_friend_possess_parked
        and not inst._my_friend_departing
        and (inst.components.health == nil or not inst.components.health:IsDead())
        and GetTime() < (action._my_friend_combat_recovery_deadline or 0)
        and ii ~= nil and ii.owner == nil and ii.canbepickedup
        and not item:HasAnyTag("INLIMBO", "fire", "outofreach")
        and inst:GetCurrentPlatform() == item:GetCurrentPlatform()
        and inst.components.inventory:CanAcceptCount(item, 1) >= 1
        and (point == nil or origin ~= nil
            and (point.x - origin.x)^2 + (point.z - origin.z)^2 <= (M.COMBAT_RECOVERY_RANGE + 4)^2)
end

function M.GetDroppedCombatItemAction(inst)
    local item = M.FindDroppedCombatItem(inst)
    if item == nil then return end
    local action = BufferedAction(inst, item, ACTIONS.PICKUP)
    action._my_friend_combat_recovery = item
    action._my_friend_combat_recovery_origin = inst:GetPosition()
    action._my_friend_combat_recovery_deadline = GetTime() + M.COMBAT_RECOVERY_TIMEOUT
    action.validfn = function(act) return M.IsCombatRecoveryActionValid(inst, act) end
    action:AddSuccessAction(function()
        if not inst:IsValid() or not item:IsValid() then return end
        if inst._my_friend_combat_recovery_item == item then inst._my_friend_combat_recovery_item = nil end
        if item.components.inventoryitem:GetGrandOwner() == inst then
            local inventory = inst.components.inventory
            if inventory:GetEquippedItem(EQUIPSLOTS.HANDS) ~= item then inventory:Equip(item) end
            if inventory:GetEquippedItem(EQUIPSLOTS.HANDS) == item then
                inst._my_friend_combat_hand_item = item
                inst._my_friend_combat_hand_until = GetTime() + 4
            end
        end
    end)
    action:AddFailAction(function()
        if inst:IsValid() then
            inst._my_friend_combat_recovery_retry = GetTime()
                + (action._my_friend_cancelled and 1 or M.COMBAT_RECOVERY_RETRY)
        end
    end)
    return action
end

local function FindRepairKit(inst, item, items)
    local forge = item.components.forgerepairable
    for _, kit in ipairs(items) do
        local kitforge = kit.components ~= nil and kit.components.forgerepair or nil
        local ii = kit:IsValid() and kit.components.inventoryitem or nil
        if ii ~= nil and not ii.islockedinslot and ii:GetGrandOwner() == inst
            and (kit.components.finiteuses == nil or kit.components.finiteuses:GetUses() > 0) then
            if forge ~= nil and forge.repairable ~= false and kitforge ~= nil
                and kitforge.repairmaterial ~= nil and forge.repairmaterial == kitforge.repairmaterial then
                return kit, ACTIONS.REPAIR
            end
            if item.components.fueled ~= nil and item:HasTag("needssewing")
                and kit.components.sewing ~= nil then
                return kit, ACTIONS.SEW
            end
        end
    end
end

local function CarriedForRepair(inst, item)
    local ii = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    return ii ~= nil and not ii.islockedinslot and ii:GetGrandOwner() == inst
end

local function NightmareEquipment(item)
    local components = item.components
    local fueled = components.fueled
    return components.equippable ~= nil and components.pocketwatch == nil
        and fueled ~= nil and fueled.accepting and FUELTYPE ~= nil
        and (fueled.fueltype == FUELTYPE.NIGHTMARE or fueled.secondaryfueltype == FUELTYPE.NIGHTMARE)
end

local function NeedsNightmareFuel(inst, item)
    if not NightmareEquipment(item) then return false end
    local guid = inst._my_friend_equipment_refuel_guid
    return guid == nil and item.components.fueled:GetPercent() < .1
        or guid == item.GUID and item.components.fueled:GetPercent() <= .9
end

local function FindMaintenance(inst, item, items)
    if not CarriedForRepair(inst, item) then return end
    if IsBroken(item) then
        local kit, action = FindRepairKit(inst, item, items)
        if kit ~= nil then return kit, action, IsUrgentRepairItem(item) end
    end
    if NeedsNightmareFuel(inst, item) then
        for _, fuel in ipairs(items) do
            if CarriedForRepair(inst, fuel) and fuel.prefab == "nightmarefuel"
                and fuel.components.fuel ~= nil and item.components.fueled:CanAcceptFuelItem(fuel) then
                inst._my_friend_equipment_refuel_guid = item.GUID
                local slot = item.components.equippable.equipslot
                return fuel, ACTIONS.ADDFUEL, inst.components.inventory:GetEquippedItem(slot) == item
            end
        end
    end
end

local function CheckRefuelTarget(inst, items)
    local guid = inst._my_friend_equipment_refuel_guid
    if guid == nil then return end
    for _, item in ipairs(items) do
        if item.GUID == guid and CarriedForRepair(inst, item) and NeedsNightmareFuel(inst, item) then return end
    end
    inst._my_friend_equipment_refuel_guid = nil
end

function M.GetRepairStatus(inst)
    if inst == nil or inst.components == nil or inst.components.inventory == nil
        or require("my_friend_policy").IsBusy(inst) then return false, false end
    local now = GetTime()
    if now < (inst._my_friend_repair_after or 0) then
        return false, false
    end
    local revision = inst._my_friend_discovery_inventory or 0
    if inst._my_friend_repair_revision == revision
        or now < (inst._my_friend_repair_status_until or 0) then
        return inst._my_friend_repair_has == true, inst._my_friend_repair_urgent == true
    end
    local items = inst.components.inventory:ReferenceAllItems()
    CheckRefuelTarget(inst, items)
    local has, urgent = false, false
    for _, item in ipairs(items) do
        local kit, _, important = FindMaintenance(inst, item, items)
        if kit ~= nil then
            has = true
            urgent = urgent or important
        end
    end
    inst._my_friend_repair_revision = revision
    inst._my_friend_repair_status_until = now + REPAIR_STATUS_PERIOD
    inst._my_friend_repair_has, inst._my_friend_repair_urgent = has, urgent
    return has, urgent
end

function M.GetRepairAction(inst)
    if inst == nil or inst.components == nil or inst.components.inventory == nil
        or require("my_friend_policy").IsBusy(inst)
        or GetTime() < (inst._my_friend_repair_after or 0) then return end
    local target, material, kind
    local items = inst.components.inventory:ReferenceAllItems()
    CheckRefuelTarget(inst, items)
    for _, item in ipairs(items) do
        local kit, action_id, urgent = FindMaintenance(inst, item, items)
        if kit ~= nil and action_id ~= nil then
            if target == nil or urgent then target, material, kind = item, kit, action_id end
            if urgent then break end
        end
    end
    if target == nil then return end
    local action = BufferedAction(inst, target, kind, material)
    action.validfn = function()
        if not CarriedForRepair(inst, target) or not CarriedForRepair(inst, material) then return false end
        if kind == ACTIONS.ADDFUEL then
            return NeedsNightmareFuel(inst, target) and material.components.fuel ~= nil
                and target.components.fueled:CanAcceptFuelItem(material)
        end
        return IsBroken(target) and FindRepairKit(inst, target, {material}) == material
    end
    action:AddSuccessAction(function()
        if not inst:IsValid() then return end
        inst._my_friend_repair_after = GetTime() + (kind == ACTIONS.ADDFUEL and .15 or 2)
        inst._my_friend_repair_status_until, inst._my_friend_repair_revision = 0, nil
        if inst._my_friend_equipment_refuel_guid == target.GUID
            and (not CarriedForRepair(inst, target) or not NeedsNightmareFuel(inst, target)) then
            inst._my_friend_equipment_refuel_guid = nil
        end
    end)
    action:AddFailAction(function()
        if not inst:IsValid() then return end
        inst._my_friend_repair_after = GetTime() + 2
        inst._my_friend_repair_status_until, inst._my_friend_repair_revision = 0, nil
    end)
    return action
end

function M.HasRepairAction(inst)
    local has = M.GetRepairStatus(inst)
    return has
end

function M.HasUrgentRepairAction(inst)
    local _, urgent = M.GetRepairStatus(inst)
    return urgent
end

function M.UpdateLoadout(inst)
    if inst == nil or not inst:IsValid() or inst.components == nil then return end
    local now = GetTime()
    if now < (inst._my_friend_loadout_next or 0) then return end
    inst._my_friend_loadout_next = now + LOADOUT_PERIOD
    local inventory = inst.components.inventory
    if inventory == nil or inventory.ReferenceAllItems == nil then return end
    if require("my_friend_policy").IsBusy(inst) then return end
    -- Stand down while something is hostile and leave the slots to the combat
    -- armour code, exactly as all four of the passes this replaced did.
    local combat = inst.components.combat
    local combat_lock = inst._my_friend_combat_equipment_target
    if combat_lock ~= nil
        and (not combat_lock:IsValid()
            or combat == nil or combat.target ~= combat_lock
                and _G.GetTime() >= (inst._my_friend_combat_hand_until or 0)) then
        inst._my_friend_combat_equipment_target = nil
        combat_lock = nil
    end
    if inst._my_friend_under_threat
        or combat ~= nil and combat.target ~= nil
        or combat_lock ~= nil
        or _G.GetTime() < (inst._my_friend_combat_hand_until or 0) then return end

    local needs = ActiveNeeds(inst)
    -- Built once: this runs on every brain tick, and ReferenceAllItems walks
    -- both grids plus the backpack and allocates a fresh table each call.
    local items = inventory:ReferenceAllItems()
    local preferred_head = M.PreferredHead(inst, items)
    local hold, idle = Timers(inst, "_my_friend_loadout_hold"),
        Timers(inst, "_my_friend_loadout_idle")
    -- Deliberately left false, which is what the pass this replaced always set
    -- it to: its loop only ever covered HEAD and HANDS, so the guard reading it
    -- in Backpacks.StartOwnedRecovery has never once fired. Setting it honestly
    -- would silently switch that guard on and stop the companion fetching its
    -- backpack for most of winter -- a behaviour change that has nothing to do
    -- with fixing the swap loop.
    inst._my_friend_temperature_body_equipped = false

    for _, slot in ipairs(LoadoutSlots(inst, items, needs, preferred_head)) do
        local current = inventory:GetEquippedItem(slot)
        if not IsSlotLocked(inst, slot, current, preferred_head) then
            local currentscore = Score(inst, current, needs)
            local best, bestscore = current, currentscore
            for _, item in ipairs(items) do
                local equippable = item.components.equippable
                if item ~= current and equippable ~= nil and equippable.equipslot == slot
                    and not equippable:IsRestricted(inst)
                    and (not Light().IsLightEquipment(item) or item == preferred_head) then
                    local score = Score(inst, item, needs)
                    if score > bestscore then best, bestscore = item, score end
                end
            end

            if bestscore > 0 then idle[slot] = nil end
            -- An unmet temperature need is worth breaking the cooldown for; a
            -- slightly better umbrella is not.
            local urgent = currentscore == 0 and bestscore >= NEED_WEIGHT.thermal
            local settled = now >= (hold[slot] or 0)

            if best ~= current and bestscore > 0 and (settled or urgent)
                and (currentscore == 0 or bestscore > currentscore * M.SWAP_MARGIN) then
                -- Charge the cooldown for the attempt, not the success: Equip
                -- is also refused by the wrapper above when a player picked the
                -- current hat, and retrying that every tick is the same churn.
                hold[slot] = now + M.SWAP_COOLDOWN
                local worn = current ~= nil and Survival().IsWornOut(current)
                    and IsDisposable(slot, current)
                if inventory:Equip(best) == true then
                    if worn then require("my_friend_dialogue").Say(inst, "worn_out")
                    elseif needs.thermal ~= nil
                        and Survival().GetInsulationValue(best, needs.thermal) ~= nil then
                        require("my_friend_dialogue").Say(inst,
                            needs.thermal == "cold" and "cold" or "hot")
                    end
                end
            elseif current ~= nil and bestscore <= 0 and settled
                and IsDisposable(slot, current)
                and now >= (current._my_friend_player_equipped_until or 0)
                and (slot == EQUIPSLOTS.HEAD or inst._my_friend_command == nil) then
                -- Worn out gear comes off at once, so it survives to be sewn
                -- or refuelled. Anything else gets a while before being stowed,
                -- so a need that flickers on and off does not strip and
                -- re-dress the companion each time.
                local worn = Survival().IsWornOut(current)
                idle[slot] = idle[slot] or now
                if (worn or now - idle[slot] >= M.IDLE_RELEASE)
                    and inventory:CanAcceptCount(current, 1) > 0 then
                    local removed = inventory:Unequip(slot)
                    if removed ~= nil then
                        inventory:GiveItem(removed, nil, inst:GetPosition())
                        if worn then require("my_friend_dialogue").Say(inst, "worn_out") end
                    end
                    hold[slot] = now + M.SWAP_COOLDOWN
                    idle[slot] = nil
                end
            end
        end
    end
end

return M
