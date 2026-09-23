local M = {}
local EquipSlots = require("my_friend_equip_slots")

function M.Removed(inst, slot, item)
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
    local equip = inventory.Equip
    inventory.Equip = function(self, item, ...)
        local component = item ~= nil and item.components.equippable or nil
        if self.inst:HasTag("my_friend") and component ~= nil and not self.isloading
            and not self.inst._my_friend_player_equipping then
            local current = self:GetEquippedItem(component.equipslot)
            if current ~= nil and current ~= item and current:HasTag("heavy") then return false end
        end
        if self.inst:HasTag("my_friend") and component ~= nil and not self.isloading
            and not self.inst._my_friend_player_equipping
            and not self.inst._my_friend_light_equip_override then
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

-- Rain gear that is doing its job holds moisture at zero, so "am I wet" is the
-- wrong question while it is still raining. Ask the sky as well, and let the
-- answer linger, so a brief gap in the weather does not start a swap.
local function WantsRain(inst)
    local moisture = inst.components.moisture
    if moisture == nil then return false end
    local state = TheWorld ~= nil and TheWorld.state or nil
    if state ~= nil and (state.israining == true or state.issnowing == true) then
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

local function HasFullRain(inst)
    local inventory = inst.components.inventory
    if inventory == nil then return false end
    for _, slot in ipairs(EquipSlots.All()) do
        local item = inventory:GetEquippedItem(slot)
        local waterproofer = item ~= nil and item.components ~= nil
            and item.components.waterproofer or nil
        if waterproofer ~= nil and Clamp01(waterproofer:GetEffectiveness()) >= 1 then
            return true
        end
    end
    return false
end

local function Score(inst, item, needs)
    if item == nil or not item:IsValid() then return 0 end
    local components = item.components
    local equippable = components ~= nil and components.equippable or nil
    if equippable == nil then return 0 end
    local score = 0
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
        local waterproof = Clamp01(components.waterproofer:GetEffectiveness())
        local current = inst.components.inventory:GetEquippedItem(
            item.components.equippable.equipslot)
        if HasFullRain(inst) and current ~= item then
            waterproof = 0
        end
        -- Once a currently worn item already gives full protection, another
        -- rain item cannot improve the loadout and must not be selected.
        if current ~= nil and current ~= item and current.components.waterproofer ~= nil
            and Clamp01(current.components.waterproofer:GetEffectiveness()) >= 1 then
            return score
        end
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

-- Slots the companion is not free to rearrange this tick.
local function IsSlotLocked(inst, slot, current)
    if not M.Allowed(inst, slot) then return true end
    if current ~= nil then
        if current.components.equippable:ShouldPreventUnequipping() then return true end
        -- The light AI owns whatever is lighting the way.
        if Light().IsLightEquipment(current) then return true end
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
                and (item:HasTag("needssewing") or item.components.sewing ~= nil
                    or item.prefab == "heatstone" or item.prefab == "heatrock")
            or armor ~= nil and not armor.indestructible and (armor.condition or 0) <= 0)
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

function M.GetDroppedCombatItemAction(inst)
    local wanted = inst ~= nil and inst._my_friend_combat_hand_item or nil
    if wanted == nil or wanted:IsValid() and wanted.components.inventoryitem ~= nil
        and wanted.components.inventoryitem:GetGrandOwner() == inst then return end
    local p = inst:GetPosition()
    local entities = TheSim:FindEntities(p.x, p.y, p.z, 5, {"_inventoryitem"}, {"INLIMBO"})
    for _, item in ipairs(entities) do
        local ii = item.components ~= nil and item.components.inventoryitem or nil
        if item:IsValid() and ii ~= nil and ii.owner == nil and ii.canbepickedup
            and IsCombatHandItem(item)
            and (wanted == nil or item.prefab == wanted.prefab) then
            local action = BufferedAction(inst, item, ACTIONS.PICKUP)
            action:AddSuccessAction(function()
                if inst:IsValid() then
                    inst._my_friend_combat_hand_item = item
                    inst._my_friend_combat_hand_until = _G.GetTime() + 4
                end
            end)
            return action
        end
    end
end

local function FindRepairKit(inst, item)
    local inventory = inst.components.inventory
    if inventory == nil then return end
    local forge = item.components ~= nil and item.components.forgerepairable or nil
    local material = forge ~= nil and forge.repairmaterial or nil
    if material == nil then
        for _, candidate in ipairs({"lunarplant", "voidcloth", "wagpunk_bits", "dreadstone"}) do
            if item:HasTag("forgerepairable_" .. candidate) then
                material = candidate
                break
            end
        end
    end
    for _, kit in ipairs(inventory:ReferenceAllItems()) do
        local kitforge = kit.components ~= nil and kit.components.forgerepair or nil
        if material ~= nil and kitforge ~= nil
            and kitforge.repairmaterial == material then
            return kit, ACTIONS.REPAIR
        end
        -- The vanilla forge components mirror their material as tags. Keep
        -- the tag fallback because broken Brightshade/Void items can rebuild
        -- their repair component after reaching zero durability.
        if material ~= nil and kitforge == nil
            and kit:HasTag("forgerepair_" .. material)
            and item:HasTag("forgerepairable_" .. material) then
            return kit, ACTIONS.REPAIR
        end
        if material == nil and kit.components ~= nil and kit.components.sewing ~= nil
            and (item:HasTag("needssewing")
                or item.prefab == "heatstone" or item.prefab == "heatrock") then
            return kit, ACTIONS.SEW
        end
    end
end

function M.GetRepairAction(inst)
    if inst == nil or inst.components == nil or inst.components.inventory == nil
        or require("my_friend_policy").IsBusy(inst)
        or GetTime() < (inst._my_friend_repair_after or 0) then return end
    local ordinary
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if IsBroken(item) and item.components ~= nil
            and (item.components.equippable ~= nil or item.components.armor ~= nil
                or item.components.insulator ~= nil or item.components.forgerepairable ~= nil
                or item:HasTag("forgerepairable_lunarplant")
                or item:HasTag("forgerepairable_wagpunk_bits")
                or item:HasTag("forgerepairable_dreadstone")
                or item:HasTag("forgerepairable_voidcloth")
                or item:HasTag("needssewing")
                or item.prefab == "heatstone" or item.prefab == "heatrock") then
            local kit, action_id = FindRepairKit(inst, item)
            if kit ~= nil and action_id ~= nil then
                local action = BufferedAction(inst, item, action_id, kit)
                action:AddSuccessAction(function()
                    if inst:IsValid() then inst._my_friend_repair_after = GetTime() + 2 end
                end)
                if IsUrgentRepairItem(item) then return action end
                ordinary = ordinary or action
            end
        end
    end
    return ordinary
end

function M.HasRepairAction(inst)
    return M.GetRepairAction(inst) ~= nil
end

function M.HasUrgentRepairAction(inst)
    if inst == nil or inst.components == nil or inst.components.inventory == nil
        or require("my_friend_policy").IsBusy(inst) then return false end
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if IsUrgentRepairItem(item) and IsBroken(item)
            and FindRepairKit(inst, item) ~= nil then return true end
    end
    return false
end

function M.UpdateLoadout(inst)
    if inst == nil or not inst:IsValid() or inst.components == nil then return end
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
    local now = GetTime()
    -- Built once: this runs on every brain tick, and ReferenceAllItems walks
    -- both grids plus the backpack and allocates a fresh table each call.
    local items = inventory:ReferenceAllItems()
    local hold, idle = Timers(inst, "_my_friend_loadout_hold"),
        Timers(inst, "_my_friend_loadout_idle")
    -- Deliberately left false, which is what the pass this replaced always set
    -- it to: its loop only ever covered HEAD and HANDS, so the guard reading it
    -- in Backpacks.StartOwnedRecovery has never once fired. Setting it honestly
    -- would silently switch that guard on and stop the companion fetching its
    -- backpack for most of winter -- a behaviour change that has nothing to do
    -- with fixing the swap loop.
    inst._my_friend_temperature_body_equipped = false

    for _, slot in ipairs(EquipSlots.All()) do
        local current = inventory:GetEquippedItem(slot)
        if not IsSlotLocked(inst, slot, current) then
            local currentscore = Score(inst, current, needs)
            local best, bestscore = current, currentscore
            for _, item in ipairs(items) do
                local equippable = item.components.equippable
                if item ~= current and equippable ~= nil and equippable.equipslot == slot
                    and not equippable:IsRestricted(inst)
                    and not Light().IsLightEquipment(item) then
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
