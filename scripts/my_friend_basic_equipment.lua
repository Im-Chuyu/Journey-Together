local Policy = require("my_friend_policy")
local Base = require("my_friend_base_ai")
local Home = require("my_friend_home")
local Materials = require("my_friend_crafting_materials")
local Tech = require("my_friend_crafting_tech")
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
}

local function ManualArea(inst)
    local origin = Home.Mode(inst) == "base" and Home.Get(inst) or nil
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
    if state ~= nil and state.home ~= inst._my_friend_home then
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
            or NeedsGoal(inst, "umbrella") and GetTime() >= (state ~= nil and state.rain_next_scan or 0)) then return 0 end
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
                and (type(c.weapon.damage) == "function"
                    or type(c.weapon.damage) == "number"
                        and c.weapon.damage >= TUNING.SPEAR_DAMAGE) then
                return true
            end
        end
    end
    return false
end

local function Station(inst, recipe)
    for _, station in ipairs(Home.Facilities(inst)) do
        if station:GetCurrentPlatform() == inst:GetCurrentPlatform()
            and Tech.StationCanTeach(inst, station, recipe) then return station end
    end
end

local function PlanSet(inst, snapshot, rain)
    local choices = rain and {{"umbrella"}}
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
            if recipe == nil or not Tech.CanBuild(inst, recipe) and Station(inst, recipe) == nil then return false end
            for _, ingredient in ipairs(recipe.ingredients or {}) do
                local need = math.max(1, RoundBiasedUp(ingredient.amount * (inst.components.builder.ingredientmod or 1)))
                local prefab = ingredient.type
                while (counts[prefab] or 0) < need do
                    -- These equipment sets only refine rope. Never gather
                    -- plants or recursively plan unrelated construction.
                    if prefab ~= "rope" or name == "rope" or not AddRecipe("rope", goal) then return false end
                    local rope = GetValidRecipe("rope")
                    counts.rope = (counts.rope or 0) + math.max(1, rope.numtogive or 1)
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

local function GetManualAction(inst, area)
    local state = inst._my_friend_base_equipment
    if state == nil or state.home ~= inst._my_friend_home then
        state = {home = inst._my_friend_home}
        inst._my_friend_base_equipment = state
    end
    local step = state.steps ~= nil and state.steps[1] or nil
    while step ~= nil and not NeedsGoal(inst, step.goal) do
        table.remove(state.steps, 1)
        step = state.steps[1]
    end
    local function Retry()
        if step.goal == "umbrella" then state.rain_next_scan = GetTime() + M.BASE_RETRY
        else state.next_scan = GetTime() + M.BASE_RETRY end
        state.steps, state.goal = nil, nil
        inst._my_friend_equipment_recipe = nil
    end
    local snapshot
    if step == nil then
        state.steps, state.goal, inst._my_friend_equipment_recipe = nil, nil, nil
        local combat = (NeedsGoal(inst, "spear") or NeedsGoal(inst, "armorwood"))
            and GetTime() >= (state.next_scan or 0)
        local rain = NeedsGoal(inst, "umbrella") and GetTime() >= (state.rain_next_scan or 0)
        if not combat and not rain then return end
        snapshot = Materials.Snapshot(inst, area)
        if combat then
            state.steps = PlanSet(inst, snapshot)
            if state.steps == nil then state.next_scan = GetTime() + M.BASE_RETRY end
        end
        if state.steps == nil and rain then
            state.steps = PlanSet(inst, snapshot, true)
            if state.steps == nil then state.rain_next_scan = GetTime() + M.BASE_RETRY end
        end
        step = state.steps ~= nil and state.steps[1] or nil
        if step == nil then return end
    end
    snapshot = snapshot or Materials.Snapshot(inst, area)
    local recipe = GetValidRecipe(step.recipe)
    local plan = recipe ~= nil and Materials.Plan(inst, recipe, area, snapshot) or nil
    if plan == nil then Retry() return end
    local action = Materials.GetAction(inst, plan, area)
    if action == nil and #plan == 0 then
        if not Tech.CanBuild(inst, recipe) then
            local station = Station(inst, recipe)
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
    action._my_friend_base_equipment = state.home
    state.goal = step.goal
    inst._my_friend_equipment_recipe = step.goal
    local valid = action.validfn
    action.validfn = function(act)
        return inst:IsValid() and state.home == inst._my_friend_home and ManualArea(inst) ~= nil
            and not inst:HasTag("playerghost") and not inst.components.health:IsDead()
            and inst._my_friend_command == nil and not inst._my_friend_under_threat
            and NeedsGoal(inst, step.goal)
            and (act.target == nil or Home.IsPointInRange(inst, act.target:GetPosition()))
            and (valid == nil or valid(act))
    end
    action:AddSuccessAction(function()
        if inst:IsValid() and inst._my_friend_base_equipment == state
            and state.steps ~= nil and state.steps[1] == step and action.recipe == step.recipe then
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
    if Home.Mode(inst) == "base" then return GetManualAction(inst, ManualArea(inst)) end
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
