local Policy = require("my_friend_policy")
local Base = require("my_friend_base_ai")
local Home = require("my_friend_home")
local Materials = require("my_friend_crafting_materials")
local Tech = require("my_friend_crafting_tech")
local EquipmentReserves = require("my_friend_equipment_reserves")
local M = {}
M.BASE_RETRY = 4 * 60
M.RAIN_THRESHOLD = .8
local HasEquipment, NeedsGoal

local EQUIPMENT_RECIPES = {
    rope = true,
    spear = true,
    armorwood = true,
    footballhat = true,
    hambat = true,
    umbrella = true,
    sewing_kit = true,
    heatrock = true,
}

local function ManualArea(inst)
    local origin = Home.Mode(inst) == "base" and Home.Get(inst) or nil
    if origin ~= nil and inst:GetDistanceSqToPoint(origin) <= Home.MANUAL_BASE_RADIUS^2 then
        return {origin = origin, radius = Home.MANUAL_BASE_RADIUS}
    end
end

local function HeatRockArea(inst)
    if Home.Mode(inst) == "base" then return ManualArea(inst) end
    if Home.NoConstruction(inst) or not Base.IsComplete(inst) then return end
    local origin = Base.GetBasePoint(inst)
    if origin ~= nil and inst:GetDistanceSqToPoint(origin) <= Home.WANDER_RADIUS^2 then
        return {origin = origin, radius = Home.WANDER_RADIUS}
    end
end

function M.InTravelRange(inst, action, point)
    return action._my_friend_base_equipment == inst._my_friend_home
        and Home.Mode(inst) == "base" and inst._my_friend_command == nil
        and Home.IsPointInRange(inst, point)
end

function M.IsBaseEquipmentTravel(inst)
    local action = inst._my_friend_navigation_action
    local leader = Policy.GetLeader(inst)
    return action ~= nil and action._my_friend_base_equipment ~= nil and leader ~= nil
        and not Policy.IsFollowGatheringPaused(inst)
        and M.InTravelRange(inst, action, inst:GetPosition())
        and Home.IsPointInRange(inst, leader:GetPosition())
end

local function Available(inst)
    local c = inst.components
    local manual = Home.Mode(inst) == "base"
    return (manual and ManualArea(inst) ~= nil or not manual and Policy.GetLeader(inst) == nil)
        and not inst:HasTag("playerghost")
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
        and (manual or not Base.GetStoragePressure(inst))
end

function M.Score(inst, context)
    local state = inst._my_friend_base_equipment
    if state ~= nil and (state.home ~= inst._my_friend_home
        or state.base ~= (Home.Mode(inst) == "base" and inst._my_friend_home or inst._my_friend_base)) then
        if inst._my_friend_equipment_recipe == state.goal then inst._my_friend_equipment_recipe = nil end
        inst._my_friend_base_equipment = nil
        state = nil
    end
    if context.leader ~= nil and Home.Mode(inst) ~= "base" or context.ghost or context.threat or context.dark
        or context.thermal or context.hurt or context.hurt_evade then return 0 end
    if not Available(inst) then return 0 end
    if Home.Mode(inst) == "base" then
        local combat = NeedsGoal(inst, "spear") or NeedsGoal(inst, "armorwood")
        if not (combat and GetTime() >= (state ~= nil and state.next_scan or 0)
            or NeedsGoal(inst, "umbrella") and GetTime() >= (state ~= nil and state.rain_next_scan or 0)
            or NeedsGoal(inst, "sewing_kit") and GetTime() >= (state ~= nil and state.sewing_next_scan or 0)
            or NeedsGoal(inst, "heatrock") and GetTime() >= (state ~= nil and state.heatrock_next_scan or 0)) then return 0 end
    end
    -- Food stocking has its own higher priority; a two-day stock deficit must
    -- not disable equipment when no food job can currently run.
    -- Finish preparing gear before surplus storage can put its rope away.
    -- Construction (78), food and emergencies still take precedence.
    return 73
end

NeedsGoal = function(inst, name)
    if name == "umbrella" then
        return require("my_friend_equipment").GetAvailableRainProtection(inst) < M.RAIN_THRESHOLD
    end
    if name == "sewing_kit" or name == "heatrock" then
        if name == "heatrock" and GetValidRecipe(name) == nil then return false end
        local items = inst.components.inventory:ReferenceAllItems()
        local active = inst.components.inventory:GetActiveItem()
        if active ~= nil then items[#items + 1] = active end
        for _, item in ipairs(items) do
            local c = item:IsValid() and item.components or nil
            local ii = c ~= nil and c.inventoryitem or nil
            if c ~= nil and (name == "sewing_kit" and c.sewing ~= nil
                or name == "heatrock" and item.prefab == name and c.heater ~= nil)
                and ii ~= nil and ii:GetGrandOwner() == inst
                and not ii.islockedinslot and not item:HasTag("broken")
                and (name ~= "heatrock" or c.fueled == nil or not c.fueled:IsEmpty())
                and (c.finiteuses == nil or c.finiteuses:GetUses() > 0)
                and (c.stackable == nil or c.stackable:StackSize() > 0) then return false end
        end
        return true
    end
    return not HasEquipment(inst, name, true)
end

HasEquipment = function(inst, kind, usable)
    local inventory = inst.components.inventory
    local items = inventory:ReferenceAllItems()
    local active = inventory:GetActiveItem()
    if active ~= nil then items[#items + 1] = active end
    -- ReferenceAllItems includes worn equipment and backpack contents. Retain
    -- worn-out items for the repair system instead of crafting duplicates.
    for _, item in ipairs(items) do
        local c = item.components
        if item:IsValid() and c ~= nil and c.equippable ~= nil
            and (not usable or not item:HasTag("broken")
                and c.inventoryitem ~= nil and not c.inventoryitem.islockedinslot
                and c.inventoryitem:GetGrandOwner() == inst
                and (c.finiteuses == nil or c.finiteuses:GetUses() > 0)
                and (c.fueled == nil or not c.fueled:IsEmpty()))
            and (c.equippable.IsRestricted == nil or not c.equippable:IsRestricted(inst)) then
            if (kind == "armorwood" or kind == "footballhat") and c.armor ~= nil
                and (not usable or (c.armor.GetAbsorption ~= nil or (c.armor.absorb_percent or .6) > 0)
                    and (c.armor.indestructible or c.armor.condition == nil or c.armor.condition > 0)) then return true end
            -- Torches and canes also have a weapon component. Only a combat
            -- weapon at least as strong as a spear replaces the basic weapon.
            -- Keep target-dependent weapons without calling damage on a fake target.
            if (kind == "spear" or kind == "hambat") and item.prefab ~= "torch" and not item:HasTag("torch")
                and c.equippable.equipslot == EQUIPSLOTS.HANDS
                and c.weapon ~= nil and c.tool == nil
                and EquipmentReserves.WeaponValue(item) >= TUNING.SPEAR_DAMAGE then
                return true
            end
        end
    end
    return false
end

local function Station(inst, recipe, area)
    local facilities = Home.Mode(inst) == "base" and Home.Facilities(inst)
        or require("my_friend_discovery").Query(inst, "equipment_stations", "structures",
            area.origin.x, 0, area.origin.z, area.radius, {"prototyper"}, {"INLIMBO", "burnt", "fire"})
    for _, station in ipairs(facilities) do
        if station:GetCurrentPlatform() == inst:GetCurrentPlatform()
            and station:GetDistanceSqToPoint(area.origin) <= area.radius^2
            and Tech.StationCanTeach(inst, station, recipe) then return station end
    end
end

local function HeatRockMaterials(inst, snapshot)
    local tool = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if tool == nil or tool.prefab ~= "pickaxe" then return snapshot end
    local materials = {}
    for _, entry in ipairs(snapshot) do
        if entry.item ~= tool then
            materials[#materials + 1] = entry
        end
    end
    return materials
end

local function PlanSet(inst, snapshot, area, goal)
    local choices = goal ~= nil and {{goal}}
        or {{"footballhat", "hambat"}, {"armorwood", "spear"},
            {"footballhat"}, {"hambat"}, {"armorwood"}, {"spear"}}
    for _, set in ipairs(choices) do
        local counts, steps = {}, {}
        for _, entry in ipairs(snapshot) do
            local item = entry.item
            counts[item.prefab] = (counts[item.prefab] or 0)
                + (item.components.stackable ~= nil and item.components.stackable:StackSize() or 1)
        end
        local function AddRecipe(name, goal)
            local recipe = GetValidRecipe(name)
            if recipe == nil or not Tech.CanBuild(inst, recipe) and Station(inst, recipe, area) == nil then return false end
            for _, ingredient in ipairs(recipe.ingredients or {}) do
                local need = math.max(1, RoundBiasedUp(ingredient.amount * (inst.components.builder.ingredientmod or 1)))
                local prefab = ingredient.type
                while (counts[prefab] or 0) < need do
                    local craftable = prefab == "rope" or prefab == "pickaxe" and name == "heatrock"
                    if not craftable or name == prefab or not AddRecipe(prefab, goal) then return false end
                    counts[prefab] = (counts[prefab] or 0) + math.max(1, GetValidRecipe(prefab).numtogive or 1)
                end
                counts[prefab] = counts[prefab] - need
            end
            steps[#steps + 1] = {recipe = name, goal = goal}
            return true
        end
        local possible = true
        for _, name in ipairs(set) do
            if NeedsGoal(inst, name) and not AddRecipe(name, name) then possible = false break end
        end
        if possible and #steps > 0 then return steps end
    end
end

local function GetBaseAction(inst, area, manual)
    local base = manual and inst._my_friend_home or inst._my_friend_base
    local state = inst._my_friend_base_equipment
    if state == nil or state.base ~= base then
        state = {home = inst._my_friend_home, base = base}
        inst._my_friend_base_equipment = state
    end
    local step = state.steps ~= nil and state.steps[1] or nil
    while step ~= nil and not NeedsGoal(inst, step.goal) do
        table.remove(state.steps, 1)
        step = state.steps[1]
    end
    local function Retry()
        local goal = step.goal
        local key = goal == "umbrella" and "rain_next_scan" or goal == "sewing_kit" and "sewing_next_scan"
            or goal == "heatrock" and "heatrock_next_scan" or "next_scan"
        state[key] = GetTime() + M.BASE_RETRY
        state.steps, state.goal = nil, nil
        inst._my_friend_equipment_recipe = nil
    end
    local snapshot
    if step == nil then
        state.steps, state.goal, inst._my_friend_equipment_recipe = nil, nil, nil
        local combat = manual and (NeedsGoal(inst, "spear") or NeedsGoal(inst, "armorwood"))
            and GetTime() >= (state.next_scan or 0)
        local rain = manual and NeedsGoal(inst, "umbrella") and GetTime() >= (state.rain_next_scan or 0)
        local sewing = manual and NeedsGoal(inst, "sewing_kit") and GetTime() >= (state.sewing_next_scan or 0)
        local heatrock = NeedsGoal(inst, "heatrock") and GetTime() >= (state.heatrock_next_scan or 0)
        if not combat and not rain and not sewing and not heatrock then return end
        snapshot = Materials.Snapshot(inst, area)
        if combat then
            state.steps = PlanSet(inst, snapshot, area)
            if state.steps == nil then state.next_scan = GetTime() + M.BASE_RETRY end
        end
        if state.steps == nil and rain then
            state.steps = PlanSet(inst, snapshot, area, "umbrella")
            if state.steps == nil then state.rain_next_scan = GetTime() + M.BASE_RETRY end
        end
        if state.steps == nil and sewing then
            state.steps = PlanSet(inst, snapshot, area, "sewing_kit")
            if state.steps == nil then state.sewing_next_scan = GetTime() + M.BASE_RETRY end
        end
        if state.steps == nil and heatrock then
            state.steps = PlanSet(inst, HeatRockMaterials(inst, snapshot), area, "heatrock")
            if state.steps == nil then state.heatrock_next_scan = GetTime() + M.BASE_RETRY end
        end
        step = state.steps ~= nil and state.steps[1] or nil
        if step == nil then return end
    end
    snapshot = snapshot or Materials.Snapshot(inst, area)
    if step.goal == "heatrock" then snapshot = HeatRockMaterials(inst, snapshot) end
    local recipe = GetValidRecipe(step.recipe)
    local plan = recipe ~= nil and Materials.Plan(inst, recipe, area, snapshot) or nil
    if plan == nil then Retry() return end
    local action = Materials.GetAction(inst, plan, area)
    if action == nil and #plan == 0 then
        if not Tech.CanBuild(inst, recipe) then
            local station = Station(inst, recipe, area)
            if station ~= nil and inst:GetDistanceSqToInst(station) > 1.5^2 then
                action = BufferedAction(inst, station, ACTIONS.WALKTO)
                action.arrivedist = 1.5
                action.validfn = function() return Tech.StationCanTeach(inst, station, recipe) end
            elseif station ~= nil then
                Tech.Activate(inst, station, recipe)
            end
        end
        if action == nil and Tech.CanBuild(inst, recipe) then
            action = Base.GetRecipeAction(inst, step.recipe, nil, false)
        end
    end
    if action == nil then Retry() return end
    if manual then action._my_friend_base_equipment = state.home end
    state.goal = step.goal
    inst._my_friend_equipment_recipe = step.goal
    local inventory = inst.components.inventory
    local material = action.invobject or action.action == ACTIONS.PICKUP and action.target
    local acquiring_pickaxe = step.goal == "heatrock" and (action.recipe == "pickaxe"
        or material and material.prefab == "pickaxe")
    local hand_before_action
    local valid = action.validfn
    action.validfn = function(act)
        local allowed = inst:IsValid() and state.home == inst._my_friend_home
            and (manual and ManualArea(inst) ~= nil
                or not manual and state.base == inst._my_friend_base
                    and Policy.GetLeader(inst) == nil and HeatRockArea(inst) ~= nil)
            and not inst:HasTag("playerghost") and not inst.components.health:IsDead()
            and inst._my_friend_command == nil and not inst._my_friend_under_threat
            and NeedsGoal(inst, step.goal)
            and (act.target == nil or act.target:GetDistanceSqToPoint(area.origin) <= area.radius^2)
            and (valid == nil or valid(act))
        if not allowed then return false end
        if act.recipe == "heatrock" then
            -- The native builder can pick a different ingredient from the
            -- planner when several copies of a pickaxe are available.
            local builder = inst.components.builder
            local ingredients = builder:GetIngredients(act.recipe)
            for _, items in pairs(ingredients or {}) do
                for ingredient in pairs(items) do
                    local item = ingredient.components.inventoryitem
                    if item == nil or item.islockedinslot or item:GetGrandOwner() ~= inst then return false end
                end
            end
        end
        if acquiring_pickaxe then hand_before_action = inventory:GetEquippedItem(EQUIPSLOTS.HANDS) end
        return true
    end
    action:AddSuccessAction(function()
        if not inst:IsValid() or inst._my_friend_base_equipment ~= state
            or state.steps == nil or state.steps[1] ~= step then return end
        -- Native pickup and crafting can equip a new tool in empty hands.
        if acquiring_pickaxe and hand_before_action == nil and inst.components.inventory == inventory then
            local tool = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
            if tool ~= nil and tool.prefab == "pickaxe" and inventory:CanAcceptCount(tool, 1) > 0 then
                local removed = inventory:Unequip(EQUIPSLOTS.HANDS)
                if removed ~= nil then inventory:GiveItem(removed, nil, inst:GetPosition()) end
            end
        end
        if action.recipe == step.recipe then
            table.remove(state.steps, 1)
            if #state.steps == 0 then state.steps = nil end
            inst._my_friend_equipment_recipe = nil
        end
    end)
    action:AddFailAction(function()
        if inst:IsValid() and inst._my_friend_base_equipment == state and state.home == inst._my_friend_home
            and not action._my_friend_cancelled then Retry() end
    end)
    return Policy.GuardAction(inst, action)
end

function M.GetAction(inst)
    if not Available(inst) then return end
    if Home.Mode(inst) == "base" then return GetBaseAction(inst, ManualArea(inst), true) end
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
    local area = HeatRockArea(inst)
    if area ~= nil then return GetBaseAction(inst, area, false) end
end

return M
