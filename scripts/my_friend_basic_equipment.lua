local Policy = require("my_friend_policy")
local Base = require("my_friend_base_ai")
local M = {}

local EQUIPMENT_RECIPES = {
    rope = true,
    spear = true,
    armorwood = true,
}

local function Available(inst)
    local c = inst.components
    return Policy.GetLeader(inst) == nil and not inst:HasTag("playerghost")
        and c.health ~= nil and not c.health:IsDead()
        and c.inventory ~= nil and c.builder ~= nil
        and c.hunger ~= nil and c.hunger:GetPercent() >= .4
        and not Policy.IsBusy(inst) and not inst._my_friend_under_threat
        and (c.combat == nil or c.combat.target == nil)
        and not inst._my_friend_command
        and (inst._my_friend_pending_recipe == nil
            or EQUIPMENT_RECIPES[inst._my_friend_pending_recipe])
        and not inst._my_friend_work_target and not inst._my_friend_work_cleanup
        and not inst._my_friend_storage_action and not inst._my_friend_chest_transfer
        and not inst._my_friend_container_action and not inst._my_friend_backpack_action
        and inst._my_friend_backpack_target == nil
        and not Base.GetStoragePressure(inst)
end

function M.Score(inst, context)
    if context.leader ~= nil or context.ghost or context.threat or context.dark
        or context.thermal or context.hurt or context.hurt_evade then return 0 end
    -- Food stocking has its own higher priority; a two-day stock deficit must
    -- not disable equipment when no food job can currently run.
    -- Finish preparing gear before surplus storage can put its rope away.
    -- Construction (78), food and emergencies still take precedence.
    return Available(inst) and 73 or 0
end

local function HasEquipment(inst, kind)
    local inventory = inst.components.inventory
    local items = inventory:ReferenceAllItems()
    local active = inventory:GetActiveItem()
    if active ~= nil then items[#items + 1] = active end
    -- ReferenceAllItems includes worn equipment and backpack contents. Retain
    -- worn-out items for the repair system instead of crafting duplicates.
    for _, item in ipairs(items) do
        local c = item.components
        if item:IsValid() and c ~= nil and c.equippable ~= nil
            and (c.equippable.IsRestricted == nil or not c.equippable:IsRestricted(inst)) then
            if kind == "armorwood" and c.armor ~= nil then return true end
            -- Torches and canes also have a weapon component. Only a combat
            -- weapon at least as strong as a spear replaces the basic weapon.
            -- Keep target-dependent weapons without calling damage on a fake target.
            if kind == "spear" and c.equippable.equipslot == EQUIPSLOTS.HANDS
                and c.weapon ~= nil and c.tool == nil
                and (type(c.weapon.damage) == "function"
                    or type(c.weapon.damage) == "number"
                        and c.weapon.damage >= TUNING.SPEAR_DAMAGE) then
                return true
            end
        end
    end
    return false
end

function M.GetAction(inst)
    if not Available(inst) then return end
    for _, name in ipairs({"spear", "armorwood"}) do
        if inst._my_friend_equipment_recipe == name and HasEquipment(inst, name) then
            inst._my_friend_equipment_recipe = nil
        end
        local recipe = GetValidRecipe(name)
        if recipe ~= nil and not HasEquipment(inst, name) then
            -- This uses the same recipe planner as base construction: it can
            -- withdraw from owned chests, refine rope, and approach a science
            -- machine before issuing the actual build action.
            local action = Base.GetRecipeGoalAction(inst, name, false,
                {cutgrass = 20, twigs = 20, log = 20})
            if action == nil then
                -- The carried minimum is a storage rule. It must not make a
                -- missing weapon or armor impossible when its ingredients
                -- are already available within the carried reserve.
                action = Base.GetRecipeGoalAction(inst, name, false)
            end
            if action ~= nil then
                -- Keep the materials reserved between withdrawal/refining and
                -- the final build. Otherwise base sorting can immediately put
                -- a newly withdrawn rope back into the chest.
                inst._my_friend_equipment_recipe = name
                action:AddSuccessAction(function()
                    if inst:IsValid() and inst._my_friend_equipment_recipe == name
                        and action.recipe == name then
                        inst._my_friend_equipment_recipe = nil
                    end
                end)
                local valid = action.validfn
                action.validfn = function(act)
                    return Policy.GetLeader(inst) == nil and not HasEquipment(inst, name)
                        and (valid == nil or valid(act))
                end
                return action
            end
        end
    end
end

return M
