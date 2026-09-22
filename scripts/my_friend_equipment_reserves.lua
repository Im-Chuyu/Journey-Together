local Survival = require("my_friend_survival_ai")
local LightAI = require("my_friend_light_ai")
local M = {}
local EquipSlots = require("my_friend_equip_slots")

local function Size(item)
    return item.components.stackable ~= nil and item.components.stackable:StackSize() or 1
end

local function Better(a, b)
    if b == nil then return true end
    if a.usable ~= b.usable then return a.usable end
    -- Healthy equipped gear already fills the reserve for identical gifts.
    if a.item.prefab == b.item.prefab and a.durability >= .15 and b.durability >= .15
        and a.equipped ~= b.equipped then return a.equipped end
    if a.value ~= b.value then return a.value > b.value end
    if a.durability ~= b.durability then return a.durability > b.durability end
    return a.equipped and not b.equipped
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
    local items, usable_prefabs, player_prefabs = inventory:ReferenceAllItems(), {}, {}
    for _, item in ipairs(items) do
        local c = item.components
        if item:IsValid() and c ~= nil and c.inventoryitem ~= nil
            and c.inventoryitem:GetGrandOwner() == inst then
            if (Survival.GetDurabilityPercent(item) or 1) > Survival.EQUIPMENT_WEAR_LIMIT
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
        if item:IsValid() and ii ~= nil and ii:GetGrandOwner() == inst then
            local durability = Survival.GetDurabilityPercent(item) or 1
            local eq = c.equippable
            local allowed = eq == nil or eq.IsRestricted == nil or not eq:IsRestricted(inst)
            -- Compare each purpose independently of current weather or activity.
            -- A single item can cover several purposes without extra copies.
            local function Reserve(role, value)
                if not allowed or type(value) ~= "number" or value <= 0 then return end
                local candidate = {item = item, value = value, durability = durability,
                    usable = durability > Survival.EQUIPMENT_WEAR_LIMIT, equipped = equipped[item] == true}
                local choices = roles[role] or {}
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
                if weapon ~= nil and eq.equipslot == EQUIPSLOTS.HANDS then
                    if type(weapon.damage) == "number" then
                        Reserve(weapon.projectile ~= nil and "ranged" or "melee", weapon.damage)
                    else
                        -- Keep one of each target-dependent weapon without
                        -- evaluating its damage function against a fake enemy.
                        Reserve("weapon:" .. item.prefab, 1)
                    end
                end
                if c.armor ~= nil then Reserve("armor:" .. slot, c.armor.absorb_percent or .6) end
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
        keep[best.item] = Size(best.item)
        if best.durability < .15 and choices[2] ~= nil and choices[2].usable then
            keep[choices[2].item] = Size(choices[2].item)
        end
    end
    return keep
end

return M
