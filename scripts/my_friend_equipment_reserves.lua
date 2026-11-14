local Survival = require("my_friend_survival_ai")
local LightAI = require("my_friend_light_ai")
local M = {}
local EquipSlots = require("my_friend_equip_slots")
local SpDamage = require("components/spdamageutil")

local function Size(item)
    return item.components.stackable ~= nil and item.components.stackable:StackSize() or 1
end

local function Better(a, b)
    if b == nil then return true end
    if a.priority ~= b.priority then return a.priority end
    if a.usable ~= b.usable then return a.usable end
    if a.value ~= b.value then return a.value > b.value end
    if a.durability ~= b.durability then return a.durability > b.durability end
    if a.equipped ~= b.equipped then return a.equipped end
    return (a.item.GUID or 0) < (b.item.GUID or 0)
end

function M.IsCharacterEquipment(inst, item)
    if item == nil or not item:IsValid() then return false end
    if inst.prefab == "wathgrithr" then
        return require("my_friend_wathgrithr").IsSpear(item)
    end
    return inst.prefab == "wanda" and (item.components.pocketwatch ~= nil
        or item.prefab == "pocketwatch_weapon" or item.prefab == "nightmarefuel")
        or inst.prefab == "wortox" and item.prefab == "wortox_soul"
end

function M.WeaponValue(item)
    local weapon = item.components.weapon
    if weapon == nil then return 0 end
    local damage = weapon.damage
    if type(damage) == "function" then
        -- Read the advertised base value without invoking target callbacks.
        damage = item.scrapbook_weapondamage
        if type(damage) == "table" then damage = damage[1] end
        if type(damage) ~= "number" then damage = TUNING.SPEAR_DAMAGE end
    end
    return (type(damage) == "number" and damage or 0)
        + SpDamage.CalcTotalDamage(SpDamage.CollectSpDamage(item))
end

function M.GetKeep(inst)
    local inventory = inst.components.inventory
    local keep, roles = {}, {}
    if inventory == nil then return keep end
    local equipped = {}
    for _, slot in ipairs(EquipSlots.All()) do
        local item = inventory:GetEquippedItem(slot)
        if item ~= nil then equipped[item], keep[item] = true, Size(item) end
    end
    local items, usable_prefabs, player_prefabs, seen = inventory:ReferenceAllItems(), {}, {}, {}
    local active = inventory.GetActiveItem ~= nil and inventory:GetActiveItem() or nil
    for _, item in ipairs(items) do
        local c = item.components
        if item:IsValid() and c ~= nil and c.inventoryitem ~= nil
            and c.inventoryitem:GetGrandOwner() == inst then
            if (Survival.GetDurabilityPercent(item) or 1) > Survival.EQUIPMENT_WEAR_LIMIT
                and not item:HasTag("broken")
                and (c.equippable == nil or c.equippable.IsRestricted == nil
                    or not c.equippable:IsRestricted(inst)) then
                usable_prefabs[item.prefab] = true
            end
            if GetTime() < (item._my_friend_player_equipped_until or 0) then
                player_prefabs[item.prefab] = true
            end
        end
    end
    for _, item in ipairs(items) do
        local c = item.components
        local ii = c ~= nil and c.inventoryitem or nil
        if not seen[item] and item:IsValid() and ii ~= nil and ii:GetGrandOwner() == inst then
            seen[item] = true
            local durability = Survival.GetDurabilityPercent(item) or 1
            local eq = c.equippable
            local allowed = eq == nil or eq.IsRestricted == nil or not eq:IsRestricted(inst)
            -- Compare each purpose independently of current weather or activity.
            -- A single item can cover several purposes without extra copies.
            local function Reserve(role, value, combat)
                if not allowed or type(value) ~= "number" or value <= 0 then return end
                local candidate = {item = item, value = value, durability = durability,
                    usable = durability > Survival.EQUIPMENT_WEAR_LIMIT and not item:HasTag("broken"),
                    equipped = equipped[item] == true,
                    priority = combat == true and (equipped[item] == true or ii.islockedinslot == true)}
                local choices = roles[role] or {combat = combat}
                roles[role] = choices
                if Better(candidate, choices[1]) then
                    choices[2], choices[1] = choices[1], candidate
                elseif choices[1].item ~= item and Better(candidate, choices[2]) then
                    choices[2] = candidate
                end
            end
            if ii.islockedinslot or item:HasAnyTag("backpack", "heatrock", "irreplaceable") then
                keep[item] = Size(item)
            end
            if M.IsCharacterEquipment(inst, item) then
                keep[item] = Size(item)
            end
            if player_prefabs[item.prefab] then
                Reserve("player_choice:" .. item.prefab, 1)
            end
            if allowed and durability <= Survival.EQUIPMENT_WEAR_LIMIT
                and not usable_prefabs[item.prefab]
                and (c.forgerepairable ~= nil or item:HasTag("needssewing")) then
                Reserve("repairable:" .. item.prefab, 1)
            end
            if eq ~= nil then
                local slot = tostring(eq.equipslot)
                local weapon = c.weapon
                if weapon ~= nil and eq.equipslot == EQUIPSLOTS.HANDS
                    and not item:HasTag("torch") and item.prefab ~= "torch" then
                    local value = M.WeaponValue(item)
                    if c.tool == nil or value >= TUNING.SPEAR_DAMAGE then
                        local ranged = weapon.projectile ~= nil or c.projectile ~= nil
                            or item:HasTag("rangedweapon") or (weapon.attackrange or 0) > 3
                        Reserve(ranged and "ranged" or "melee", value, true)
                    end
                end
                local planar = SpDamage.GetSpDefenseForType(item, "planar")
                if c.armor ~= nil or planar > 0 then
                    local absorption = c.armor ~= nil and (c.armor.absorb_percent or .6) or 0
                    Reserve("armor:" .. slot, absorption * 100 + planar, true)
                end
                if c.waterproofer ~= nil then Reserve("rain:" .. slot, c.waterproofer:GetEffectiveness()) end
                Reserve("cold:" .. slot, Survival.GetInsulationValue(item, "cold"))
                Reserve("hot:" .. slot, Survival.GetInsulationValue(item, "hot"))
                local speed = eq.GetWalkSpeedMult ~= nil and eq:GetWalkSpeedMult() or eq.walkspeedmult or 1
                Reserve("speed:" .. slot, speed - 1)
                if LightAI.IsLightEquipment(item) or type(eq.dapperness) == "number"
                    and eq.dapperness > 0 then
                    Reserve("utility:" .. item.prefab, 1)
                end
            end
            if c.tool ~= nil then
                for action, effectiveness in pairs(c.tool.actions or {}) do
                    local id = type(action) == "table" and action.id or action
                    Reserve("tool:" .. tostring(id), effectiveness)
                    if c.tool.CanDoToughWork ~= nil and c.tool:CanDoToughWork() then
                        Reserve("tough_tool:" .. tostring(id), effectiveness)
                    end
                end
            end
            if c.sewing ~= nil or c.forgerepair ~= nil then Reserve("repair:" .. item.prefab, 1) end
            for _, name in ipairs({"fishingrod", "oceanfishingrod", "wateringcan"}) do
                if c[name] ~= nil then Reserve("tool:" .. name, 1) end
            end
        end
    end
    for _, choices in pairs(roles) do
        local best = choices[1]
        local amount = choices.combat and math.min(2, Size(best.item)) or Size(best.item)
        keep[best.item] = math.max(keep[best.item] or 0, amount)
        local next_choice = choices[2]
        if next_choice ~= nil then
            local item = next_choice.item
            local repairable = item.components.forgerepairable ~= nil or item:HasTag("needssewing")
            if choices.combat and amount < 2 and (next_choice.usable or repairable)
                or not choices.combat and best.durability < .15 and next_choice.usable then
                keep[item] = math.max(keep[item] or 0, choices.combat and 1 or Size(item))
            end
        end
    end
    if active ~= nil and active:IsValid() then keep[active] = Size(active) end
    return keep
end

return M
