local Policy = require("my_friend_policy")
local Inventory = require("my_friend_inventory")
local Food = require("my_friend_food_ai")
local Planner = require("my_friend_recipe_planner")
local Pot = require("my_friend_cookpot")
local Cooking = require("cooking")
local Storage = require("my_friend_food_storage")
local Cleanup = require("my_friend_cookpot_cleanup")
local M = {}

local function CookCommand(inst)
    local command = inst._my_friend_command
    return command ~= nil and command.special == "cook" and command or nil
end

local function Accessible(inst, pot)
    local command = CookCommand(inst)
    return (command == nil or pot ~= nil and pot.prefab == "portablecookpot")
        and Pot.Accessible(inst, pot, command ~= nil and command.cooking_origin or nil)
end

local function HasReadyMeal(inst)
    for _, item in ipairs(Storage.ReferenceItems(inst)) do
        if item:HasTag("preparedfood") and item.components.edible ~= nil
            and inst.components.eater:CanEat(item)
            and inst.components.eater:PrefersToEat(item) then
            return true
        end
    end
    return false
end

local function CanPlan(inst)
    local c = inst.components
    local special = inst._my_friend_command ~= nil
        and inst._my_friend_command.special == "cook"
    return not inst:HasTag("playerghost") and not c.health:IsDead()
        and not inst._my_friend_under_threat
        and (inst._my_friend_command == nil or special)
        and not inst._my_friend_thermal_need
        and not inst._my_friend_container_action and not inst._my_friend_storage_action
        and not inst._my_friend_backpack_action and inst._my_friend_backpack_target == nil
        and inst._my_friend_pending_recipe == nil and inst._my_friend_work_target == nil
        and GetTime() >= (inst._my_friend_hurt_evade_until or 0)
        and GetTime() >= (inst._my_friend_recipe_retry or 0)
        and not Policy.IsFollowGatheringPaused(inst) and not Policy.IsLeaderDead(inst)
        and not Policy.IsBusy(inst) and (c.combat == nil or c.combat.target == nil)
        and (c.rider == nil or not c.rider:IsRiding())
        and c.hunger ~= nil and (c.hunger:GetPercent() >= .25 or special)
        and (c.health.GetPercent == nil or c.health:GetPercent() > .35)
        and not require("my_friend_light_ai").IsDark(inst)
end

local function FridgeAvailable(inst, fridge, origin)
    if fridge == nil or not fridge:IsValid()
        or not (fridge.prefab == "icebox" or fridge:HasTag("fridge")
            or fridge:HasTag("chest") or fridge.prefab == "treasurechest"
            or fridge.prefab == "saltbox" or fridge.prefab == "dragonflychest")
        or fridge:HasAnyTag("INLIMBO", "burnt", "fire") then return false end
    return Inventory.CanWithdrawFrom(inst, fridge)
        and Policy.InRange(inst, fridge) and (origin or inst):GetDistanceSqToInst(fridge) <= Pot.RANGE^2
        and inst:GetCurrentPlatform() == fridge:GetCurrentPlatform()
end

local function Owned(inst, pot)
    return pot ~= nil and pot:IsValid() and pot._my_friend_recipe_job ~= nil
        and pot._my_friend_recipe_job.owner == Pot.OwnerID(inst)
end

local function Forget(inst, pot)
    Pot.Close(inst, pot)
    if Owned(inst, pot) then pot._my_friend_recipe_job = nil end
    inst._my_friend_recipe_pot, inst._my_friend_recipe_cache = nil, nil
    inst._my_friend_recipe_search = nil
    if inst._my_friend_command == nil or inst._my_friend_command.special ~= "cook" then
        inst._my_friend_recipe_requested = nil
        inst._my_friend_recipe_cooker = nil
    end
end

function M.Cancel(inst)
    Pot.Close(inst, inst._my_friend_recipe_pot)
    local cleanup = inst._my_friend_recipe_cleanup
    if cleanup ~= nil then Pot.Close(inst, cleanup.pot) end
    inst._my_friend_recipe_cleanup = nil
    local inventory = inst.components.inventory
    local opened = {}
    for pot in pairs(inventory ~= nil and inventory.opencontainers or {}) do
        if Owned(inst, pot) then opened[#opened + 1] = pot end
    end
    for _, pot in ipairs(opened) do Pot.Close(inst, pot) end
    -- Jobs stay on the pots so cooked food and partially filled pots can be
    -- recovered later; the cancelled command must no longer hold the actor.
    inst._my_friend_recipe_pot, inst._my_friend_recipe_cache = nil, nil
    inst._my_friend_recipe_search, inst._my_friend_recipe_retry = nil, nil
    inst._my_friend_recipe_requested, inst._my_friend_recipe_cooker = nil, nil
end

function M.ConfigurePot(pot)
    if not TheWorld.ismastersim or not Pot.PREFABS[pot.prefab] then return end
    local harvest = pot.components.stewer.onharvest
    pot.components.stewer.onharvest = function(...)
        pot._my_friend_recipe_job = nil
        if harvest ~= nil then return harvest(...) end
    end
    pot:ListenForEvent("onopen", function(_, data)
        if data ~= nil and Policy.IsLocalPlayer(data.doer) then pot._my_friend_recipe_job = nil end
    end)
    local save, load = pot.OnSave, pot.OnLoad
    pot.OnSave = function(self, data)
        data.my_friend_recipe_job = self._my_friend_recipe_job
        if save ~= nil then return save(self, data) end
    end
    pot.OnLoad = function(self, data, ...)
        if load ~= nil then load(self, data, ...) end
        self._my_friend_recipe_job = data ~= nil and data.my_friend_recipe_job or nil
    end
end

local function GroundIngredient(inst, entity)
    local inventoryitem = entity.components ~= nil and entity.components.inventoryitem or nil
    return entity:IsValid() and inventoryitem ~= nil and inventoryitem.owner == nil
        and inventoryitem.canbepickedup and entity:HasTag("_inventoryitem")
        and Cooking.IsCookingIngredient(entity.prefab)
        and entity:GetCurrentPlatform() == inst:GetCurrentPlatform()
        and Policy.InRange(inst, entity)
end

local function Nearby(inst, origin)
    local x, y, z = (origin or inst).Transform:GetWorldPosition()
    local command = CookCommand(inst)
    if origin == nil and command ~= nil and command.cooking_origin ~= nil then
        local point = command.cooking_origin
        x, y, z = point.x, point.y, point.z
    end
    local pots, fridges, grounds = {}, {}, {}
    local requested_cooker = inst._my_friend_recipe_cooker
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, Pot.RANGE, nil, {"INLIMBO", "burnt", "fire"})) do
        if Accessible(inst, entity) and (requested_cooker == nil
            or entity.prefab == requested_cooker) then pots[#pots + 1] = entity
        elseif FridgeAvailable(inst, entity, origin) then
            fridges[#fridges + 1] = entity
        elseif GroundIngredient(inst, entity) then
            grounds[#grounds + 1] = entity
        end
    end
    table.sort(pots, function(a, b)
        local ap, bp = Pot.Priority(inst, a), Pot.Priority(inst, b)
        return ap == bp and inst:GetDistanceSqToInst(a) < inst:GetDistanceSqToInst(b) or ap < bp
    end)
    table.sort(fridges, function(a, b) return inst:GetDistanceSqToInst(a) < inst:GetDistanceSqToInst(b) end)
    table.sort(grounds, function(a, b) return inst:GetDistanceSqToInst(a) < inst:GetDistanceSqToInst(b) end)
    return pots, fridges, grounds
end

local function Remaining(pot, prefabs)
    local remaining = {}
    for _, prefab in ipairs(prefabs) do remaining[prefab] = (remaining[prefab] or 0) + 1 end
    for _, item in pairs(pot.components.container:GetAllItems()) do
        if Planner.Size(item) ~= 1 or (remaining[item.prefab] or 0) == 0 then return end
        remaining[item.prefab] = remaining[item.prefab] - 1
        if remaining[item.prefab] == 0 then remaining[item.prefab] = nil end
    end
    return remaining
end

local function SelectOwnedPot(inst, pots)
    local current = inst._my_friend_recipe_pot
    local multiple = CookCommand(inst) ~= nil
    local preparing, cooking
    for _, pot in ipairs(pots) do
        if Owned(inst, pot) then
            local stewer = pot.components.stewer
            if stewer:IsDone() then return pot end
            if stewer:IsCooking() then
                cooking = cooking or pot
            elseif preparing == nil or pot == current then
                preparing = pot
            end
        end
    end
    -- Only one pot is being filled at a time, so its remaining ingredients
    -- cannot also be promised to another pot. Cooking pots need no more inputs.
    if preparing ~= nil then return preparing end
    if not multiple then return cooking end
    return nil, cooking ~= nil
end

local function GetPlan(inst)
    if CookCommand(inst) == nil then
        local current = inst._my_friend_recipe_pot
        if Owned(inst, current) and Accessible(inst, current) then return current, current._my_friend_recipe_job end
        local cache = inst._my_friend_recipe_cache
        if cache ~= nil and GetTime() < cache.untiltime then return cache.pot, cache.plan end
    end
    local pots = Nearby(inst)
    local owned, cooking = SelectOwnedPot(inst, pots)
    if owned ~= nil then
        inst._my_friend_recipe_pot = owned
        local command = CookCommand(inst)
        if command ~= nil and owned._my_friend_recipe_job.recipe ~= command.recipe
            and Cleanup.CanClean(inst, owned) then return owned, {cleanup = true} end
        return owned, owned._my_friend_recipe_job
    end
    local wanted = inst._my_friend_recipe_requested
    -- Automatic cooking supplies the companion; once a usable meal already
    -- exists, do not consume every remaining ingredient just because a pot is
    -- nearby. Explicit cook commands still pass through.
    if wanted == nil and not Food.NeedsFoodSupply(inst) and HasReadyMeal(inst) then
        inst._my_friend_recipe_cache = {pot = nil, plan = nil, untiltime = GetTime() + 10}
        return
    end
    local chosen, plan = nil, nil
    for _, pot in ipairs(pots) do
        local c, s = pot.components.container, pot.components.stewer
        if pot._my_friend_recipe_job == nil and pot._my_friend_beefalo_chef == nil
            and not s:IsCooking() and not s:IsDone() and c:CanOpen() then
            if Cleanup.CanClean(inst, pot) then return pot, {cleanup = true} end
            if next(c:GetAllItems()) == nil then
                -- Keep the pantry centred on the pot while walking between sources.
                local _, fridges, grounds = Nearby(inst, pot)
                local pool = Planner.Pool(inst, fridges, grounds)
                local candidate, searching = Planner.Find(inst, pot.prefab, pool, wanted)
                if searching then return nil, nil, "waiting" end
                if candidate ~= nil then chosen, plan = pot, candidate break end
            end
        end
    end
    inst._my_friend_recipe_cache = {pot = chosen, plan = plan, untiltime = GetTime() + 5}
    return chosen, plan, chosen == nil and cooking and "waiting" or nil
end

local function FindIngredients(inst, pot, remaining)
    local _, fridges, grounds = Nearby(inst, pot)
    local requested = inst._my_friend_recipe_requested ~= nil
    local pool = Planner.Pool(inst, (Owned(inst, pot) or Food.NeedsFoodSupply(inst)
        or not HasReadyMeal(inst) or requested)
        and fridges or {}, grounds)
    local available, carried, stored, ground = {}, nil, nil, nil
    for _, group in ipairs(pool) do
        available[group.prefab] = group.count
        if (remaining[group.prefab] or 0) > 0 then
            for _, source in ipairs(group.sources) do
                local item = source.item
                local owner = item.components.inventoryitem:GetGrandOwner()
                if owner == inst then
                    carried = carried or item
                elseif item.components.inventoryitem.owner == nil then
                    ground = ground or item
                else
                    stored = stored or item
                end
            end
        end
    end
    for prefab, count in pairs(remaining) do
        if (available[prefab] or 0) < count then return end
    end
    return carried or stored or ground
end

function M.ShouldReserve(inst, food)
    if not CanPlan(inst) or food == nil or food:HasTag("preparedfood") then return false end
    local pot, plan = GetPlan(inst)
    if pot == nil or not Accessible(inst, pot) or plan.cleanup then return false end
    if not Owned(inst, pot) and (pot._my_friend_recipe_job ~= nil
        or pot._my_friend_beefalo_chef ~= nil) then return false end
    if pot.components.stewer:IsCooking() or pot.components.stewer:IsDone() then return false end
    local remaining = Remaining(pot, plan.prefabs)
    return remaining ~= nil and (remaining[food.prefab] or 0) > 0
        and FindIngredients(inst, pot, remaining) ~= nil
end

function M.Score(inst, context)
    if not CanPlan(inst) or context ~= nil and (context.threat or context.dark
        or context.thermal or context.hurt or context.hurt_evade) then return 0 end
    local pot = GetPlan(inst)
    if pot == nil or not Accessible(inst, pot) or pot.components.stewer:IsCooking() then return 0 end
    return Owned(inst, pot) and 102 or Food.NeedsFoodSupply(inst) and 99 or 68
end

local function Guard(inst, pot, action, valid)
    local stamp = {}
    local command = inst._my_friend_command
    pot._my_friend_recipe_step = stamp
    action._my_friend_dialogue_kind = action.action == ACTIONS.HARVEST and "recipe_ready" or "recipe_cook"
    action.validfn = function()
        return Accessible(inst, pot)
            and inst._my_friend_command == command
            and not inst._my_friend_under_threat and valid()
    end
    action:AddSuccessAction(function()
        inst._my_friend_recipe_cache, inst._my_friend_food_supply_cache = nil, nil
        if command ~= nil and inst._my_friend_command == command then
            command.deadline = GetTime() + 180
        end
        inst:DoTaskInTime(2, function()
            if pot:IsValid() and pot._my_friend_recipe_step == stamp then Pot.Close(inst, pot) end
            if action.target ~= pot then Pot.Close(inst, action.target) end
        end)
    end)
    action:AddFailAction(function()
        Pot.Close(inst, action.target)
        if not action._my_friend_cancelled then
            inst._my_friend_recipe_retry = GetTime() + 10
            inst._my_friend_recipe_cache = nil
        end
    end)
    return Policy.GuardAction(inst, action)
end

function M.AddIngredient(act)
    local inst, pot, item = act.doer, act.target, act.invobject
    if not Owned(inst, pot) or not Accessible(inst, pot)
        or not Inventory.CanReachContainer(inst, pot) or not Planner.Available(inst, item)
        or item.components.inventoryitem:GetGrandOwner() ~= inst then return false end
    local c, s = pot.components.container, pot.components.stewer
    local remaining = Remaining(pot, pot._my_friend_recipe_job.prefabs)
    if remaining == nil or (remaining[item.prefab] or 0) == 0
        or s:IsCooking() or s:IsDone() or not c:IsOpenedBy(inst)
        or not c:CanTakeItemInSlot(item) then return false end
    local allowed = false
    for _, group in ipairs(Planner.Pool(inst)) do
        if group.prefab == item.prefab and group.count > 0 then allowed = true break end
    end
    if not allowed then return false end
    local moved = item.components.inventoryitem:RemoveFromOwner(false)
    if moved == nil or not moved:IsValid() or moved.components.inventoryitem == nil then return false end
    moved.prevcontainer, moved.prevslot = nil, nil
    if c:GiveItem(moved, nil, pot:GetPosition(), false) then return true end
    if moved:IsValid() then Inventory.GiveCarried(inst, moved, inst:GetPosition()) end
    return false
end

local function CanHarvest(inst, pot)
    local inventory = inst.components.inventory
    if not inventory:IsFull() then return true end
    local product = pot.components.stewer.product
    local recipe = Cooking.GetRecipe(pot.prefab, product)
    local count = recipe ~= nil and recipe.stacksize or 1
    for _, item in ipairs(inventory:ReferenceAllItems()) do
        if item.prefab == product and inventory:CanAcceptCount(item, count) >= count then return true end
    end
    return false
end

function M.GetAction(inst)
    if not CanPlan(inst) then return nil, "paused" end
    local delivery = Cleanup.GetDeliveryAction(inst, Guard)
    if delivery ~= nil then return delivery end
    local pot, plan, status = GetPlan(inst)
    if pot == nil or not Accessible(inst, pot) then return nil, status or "unavailable" end
    if plan.cleanup then return Cleanup.GetAction(inst, pot, Guard) end
    local c, s = pot.components.container, pot.components.stewer
    if s:IsCooking() then return nil, "waiting" end
    if s:IsDone() then
        if not Owned(inst, pot) then return end
        local requested = plan.recipe
        local valid_product = requested ~= nil and s.product == requested
            and Planner.EvaluateSpecific(inst, pot.prefab, plan.prefabs, requested) ~= nil
            or requested == nil and Planner.RecipeValue(inst, Cooking.GetRecipe(pot.prefab, s.product)) ~= nil
        if not valid_product then
            Forget(inst, pot)
            return nil, "paused"
        end
        if not CanHarvest(inst, pot) then return nil, "full" end
        local command = inst._my_friend_command
        local action = BufferedAction(inst, pot, ACTIONS.HARVEST)
        action:AddSuccessAction(function()
            Forget(inst, pot)
            if command ~= nil and command == inst._my_friend_command
                and command.special == "cook" and requested == command.recipe then
                command.cooked = (command.cooked or 0) + 1
                command.waiting = nil
            end
        end)
        return Guard(inst, pot, action, function() return Owned(inst, pot) and s:IsDone() end)
    end
    if not Owned(inst, pot) and (pot._my_friend_recipe_job ~= nil or pot._my_friend_beefalo_chef ~= nil) then return end
    local remaining = Remaining(pot, plan.prefabs)
    if remaining == nil then Forget(inst, pot) return nil, "paused" end
    local item = FindIngredients(inst, pot, remaining)
    if next(remaining) ~= nil and item == nil then
        -- Keep partial ingredients, but stop reserving meals after a failed plan.
        inst._my_friend_recipe_retry = GetTime() + 10
        Forget(inst, pot)
        return nil, "paused"
    end
    local function Unchanged()
        return not s:IsCooking() and not s:IsDone() and Remaining(pot, plan.prefabs) ~= nil
            and (Owned(inst, pot) or pot._my_friend_recipe_job == nil
                and pot._my_friend_beefalo_chef == nil and next(c:GetAllItems()) == nil)
    end
    if not Owned(inst, pot) then
        local action = BufferedAction(inst, pot, ACTIONS.MY_FRIEND_OPEN)
        action.arrivedist = Inventory.ContainerReach(inst, pot)
        action:AddSuccessAction(function()
            pot._my_friend_recipe_job = {owner = Pot.OwnerID(inst), prefabs = plan.prefabs,
                recipe = inst._my_friend_recipe_requested}
            inst._my_friend_recipe_pot = pot
        end)
        return Guard(inst, pot, action, Unchanged)
    end
    if item ~= nil and item.components.inventoryitem:GetGrandOwner() ~= inst then
        local source = item.components.inventoryitem.owner
        if inst.components.inventory:CanAcceptCount(item, 1) < 1 then return nil, "full" end
        if source == nil then
            local action = BufferedAction(inst, item, ACTIONS.PICKUP)
            return Guard(inst, pot, action, function()
                return Unchanged() and Planner.Available(inst, item)
                    and item.components.inventoryitem.owner == nil
            end)
        end
        if not FridgeAvailable(inst, source, pot) then return end
        local action = BufferedAction(inst, source, ACTIONS.MY_FRIEND_WITHDRAW, item)
        action._my_friend_withdraw_count = math.min(remaining[item.prefab], Planner.Size(item),
            inst.components.inventory:CanAcceptCount(item, remaining[item.prefab]))
        return Guard(inst, pot, action, function()
            return Unchanged() and FridgeAvailable(inst, source, pot)
                and Planner.Available(inst, item) and item.components.inventoryitem.owner == source
        end)
    elseif not c:IsOpenedBy(inst) then
        local action = BufferedAction(inst, pot, ACTIONS.MY_FRIEND_OPEN)
        action.arrivedist = Inventory.ContainerReach(inst, pot)
        return Guard(inst, pot, action, Unchanged)
    elseif item ~= nil then
        return Guard(inst, pot, BufferedAction(inst, pot, ACTIONS.MY_FRIEND_RECIPE_ADD, item), Unchanged)
    end
    return Guard(inst, pot, BufferedAction(inst, pot, ACTIONS.COOK), function()
        local valid
        if plan.recipe ~= nil then
            valid = Planner.EvaluateSpecific(inst, pot.prefab, plan.prefabs,
                plan.recipe) ~= nil
        else
            valid = Planner.Evaluate(inst, pot.prefab, plan.prefabs) ~= nil
        end
        return Unchanged() and s:CanCook() and valid
    end)
end

function M.GetSpecificAction(inst, recipe_name)
    local command = inst._my_friend_command
    if command == nil or command.special ~= "cook" or command.recipe ~= recipe_name then return end
    command.cooking_origin = command.cooking_origin or inst:GetPosition()
    command.waiting, command.failure_reply = nil, nil
    inst._my_friend_recipe_requested = recipe_name
    inst._my_friend_recipe_cooker = "portablecookpot"
    inst._my_friend_recipe_cache = nil
    local action, status = M.GetAction(inst)
    if status == "waiting" or status == "paused" then
        command.waiting = true
        command.deadline = GetTime() + 180
    elseif status == "full" then
        command.failure_reply = "recipe_inventory_full"
    end
    return action
end

return M
