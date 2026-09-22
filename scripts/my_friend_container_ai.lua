local FoodAI = require("my_friend_food_ai")
local LightAI = require("my_friend_light_ai")
local Policy = require("my_friend_policy")
local InventoryAI = require("my_friend_inventory")

local M = {}
M.SEARCH_RANGE = 15
local CANT_TAGS = {"INLIMBO", "burnt", "fire", "pickable", "playerghost"}

local function IsOwnSack(inst, target)
    return target ~= nil and target:IsValid() and target.prefab == "beargerfur_sack"
        and target.components.inventoryitem ~= nil
        and target.components.inventoryitem:GetGrandOwner() == inst
end

local function GetItems(target)
    local holder = target.components.inventoryitemholder
    if holder ~= nil then
        return holder.item ~= nil and holder.item:IsValid() and {holder.item} or {}
    end
    local container = target.components.container
    return container ~= nil and container:GetAllItems() or {}
end

local function IsAvailable(inst, target)
    if target == nil or not target:IsValid() or target:HasAnyTag("burnt", "fire") then return false end
    if IsOwnSack(inst, target) then
        local c = target.components.container
        return c ~= nil and not c.readonlycontainer and not c:IsRestricted(inst)
    end
    if target:HasTag("INLIMBO") or not Policy.InRange(inst, target) then return false end
    local holder = target.components.inventoryitemholder
    if target.prefab == "gelblob_storage" then return holder ~= nil and holder:CanTake(inst) end
    local c = target.components.container
    local leader = Policy.GetLeader(inst)
    return c ~= nil and (target:HasTag("fridge") or target.prefab == "icebox"
            or target.prefab == "saltbox" or target.prefab == "beargerfur_sack")
        and c.canbeopened and not c.readonlycontainer and not c:IsRestricted(inst)
        and (c:IsOpenedBy(inst) or c:CanOpen()
            or leader ~= nil and c:IsOpenedBy(leader))
end

local function CanAct(inst)
    return inst:IsValid() and not inst:HasTag("playerghost")
        and not inst.components.health:IsDead()
        and inst.components.inventory ~= nil and inst.components.eater ~= nil
        and not inst._my_friend_backpack_action and inst._my_friend_backpack_target == nil
        and not inst._my_friend_under_threat and not Policy.IsBusy(inst)
end

local function FindBestFood(inst, target, command)
    local best, bestscore, bestperish
    for _, item in ipairs(GetItems(target)) do
        local score, perish
        if command ~= nil then score = FoodAI.CommandScore(inst, item, true)
        else score, perish = FoodAI.Evaluate(inst, item) end
        if score ~= nil and (bestscore == nil or score > bestscore + .001
            or math.abs(score - bestscore) <= .001
                and (perish or math.huge) < (bestperish or math.huge)) then
            best, bestscore, bestperish = item, score, perish
        end
    end
    return best, bestscore
end

local function PreferCarriedFood(inst, command, score)
    if command ~= nil or score == nil then return false end
    local _, carriedscore = FoodAI.FindBestFood(inst)
    return carriedscore ~= nil and carriedscore > score + .001
end

local function FindOwnSack(inst, predicate)
    -- Portable sacks live in inventory slots or inside the equipped backpack.
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if IsOwnSack(inst, item) and IsAvailable(inst, item) and predicate(item) then return item end
    end
end

local function CarriedItems(inst)
    local inventory = inst.components.inventory
    local items = inventory:ReferenceAllItems()
    local active = inventory:GetActiveItem()
    if active ~= nil then items[#items + 1] = active end
    return items
end

local function SearchOrigin(inst)
    if Policy.GetLeader(inst) == nil then
        local Home = require("my_friend_home")
        local home = Home.Get(inst)
        if home ~= nil then return home.x, 0, home.z, Home.WANDER_RADIUS end
    end
    return Policy.SearchOrigin(inst, M.SEARCH_RANGE)
end

local function CloseContainer(inst, target)
    if target ~= nil and target:IsValid() and target.components.container ~= nil
        and target.components.container:IsOpenedBy(inst) then
        target.components.container:Close(inst)
        inst:PushEvent("closecontainer", {container = target})
    end
    inst._my_friend_container_action = nil
    inst._my_friend_container_target = nil
end

local function Count(item)
    return item ~= nil and item:IsValid()
        and (item.components.stackable ~= nil and item.components.stackable:StackSize() or 1) or 0
end

local function IsCarried(inst, item)
    return item ~= nil and item:IsValid() and item.components.inventoryitem ~= nil
        and item.components.inventoryitem:GetGrandOwner() == inst
end

local function DetachPortion(inst, record)
    if not IsCarried(inst, record.item) then return end
    local item = record.item
    local count = math.min(Count(item), record.count)
    if count <= 0 then return end
    return Count(item) > count and item.components.stackable:Get(count)
        or item.components.inventoryitem:RemoveFromOwner(true)
end

local function CanReturn(inst, record)
    local source = record.source
    local holder = source ~= nil and source:IsValid() and source.components.inventoryitemholder
    return record.count > 0 and IsCarried(inst, record.item)
        and holder ~= nil and holder:CanGive(record.item, inst)
end

local function StashInterrupted(inst, record)
    if record.count <= 0 or not IsCarried(inst, record.item) then return end
    local sack = FindOwnSack(inst, function(item)
        return item ~= record.item.components.inventoryitem.owner
            and item.components.container:CanAcceptCount(record.item, record.count) >= record.count
    end)
    if sack ~= nil then
        local container = sack.components.container
        local before = {}
        for _, item in ipairs(container:GetAllItems()) do before[item] = Count(item) end
        local moved = DetachPortion(inst, record)
        if moved ~= nil then
            moved.prevcontainer, moved.prevslot = nil, nil
            if container:GiveItem(moved, nil, inst:GetPosition(), false) then
                -- GiveItem can merge and remove the transferred entity.
                for _, item in ipairs(container:GetAllItems()) do
                    if Count(item) > (before[item] or 0) then
                        local n = Count(item) - (before[item] or 0)
                        inst._my_friend_food_returns[#inst._my_friend_food_returns + 1] =
                            {item = item, count = n, source = record.source}
                    end
                end
                return
            elseif moved:IsValid() then
                InventoryAI.GiveCarried(inst, moved, inst:GetPosition())
                record.item = moved
            end
        end
    end
    inst._my_friend_food_returns[#inst._my_friend_food_returns + 1] = record
end

function M.Cancel(inst)
    local meal = inst._my_friend_meal
    inst._my_friend_meal = nil
    inst._my_friend_food_returns = inst._my_friend_food_returns or {}
    if meal ~= nil then
        for _, record in ipairs(meal.portions or {}) do StashInterrupted(inst, record) end
    end
    CloseContainer(inst, inst._my_friend_container_target)
end

function M.ReturnFood(act)
    local record = act._my_friend_food_return
    if record == nil or not CanReturn(act.doer, record)
        or not InventoryAI.CanReachContainer(act.doer, record.source) then return false end
    local moved = DetachPortion(act.doer, record)
    if moved == nil then return false end
    if record.source.components.inventoryitemholder:GiveItem(moved, act.doer) then
        record.count = 0
        return true
    end
    if moved:IsValid() then
        InventoryAI.GiveCarried(act.doer, moved, act.doer:GetPosition())
        record.item = moved
    end
    return false
end

local function ReturnAction(inst, record)
    local action = BufferedAction(inst, record.source, ACTIONS.MY_FRIEND_RETURN_FOOD, record.item)
    action._my_friend_food_return = record
    action.validfn = function() return CanReturn(inst, record) end
    return action
end

local function FinishMeal(inst, meal)
    inst._my_friend_meal = nil
    CloseContainer(inst, meal.target)
    if meal.command ~= nil and inst._my_friend_command == meal.command and meal.ate then
        require("my_friend_commands").Clear(inst)
    end
end

local function NextMealAction(inst, meal)
    local target = meal.target
    if GetTime() > meal.deadline or meal.command ~= nil and inst._my_friend_command ~= meal.command
        or inst._my_friend_under_threat or LightAI.IsDark(inst) then M.Cancel(inst) return end
    local action
    if meal.portions ~= nil then
        local record
        for _, entry in ipairs(meal.portions) do
            if entry.count > 0 and IsCarried(inst, entry.item) then record = entry break end
        end
        if record == nil then FinishMeal(inst, meal) return end
        local shouldeat = not meal.ate or meal.command == nil and FoodAI.Evaluate(inst, record.item) ~= nil
        if shouldeat then
            action = BufferedAction(inst, nil, ACTIONS.EAT, record.item)
            action.validfn = function() return IsCarried(inst, record.item) end
            local before = Count(record.item)
            action:AddSuccessAction(function()
                record.count = math.max(0, record.count - (before - Count(record.item)))
                meal.ate = true
                inst._my_friend_food_supply_cache = nil
            end)
        elseif CanReturn(inst, record) then
            action = ReturnAction(inst, record)
        else
            -- A full or repurposed holder ends the obligation to return this food.
            record.count = 0
            return NextMealAction(inst, meal)
        end
    elseif not IsAvailable(inst, target) then
        M.Cancel(inst)
        return
    else
        local food, score = FindBestFood(inst, target, meal.command)
        if food == nil or PreferCarriedFood(inst, meal.command, score) then
            FinishMeal(inst, meal)
            return
        end
        local holder = target.components.inventoryitemholder
        local container = target.components.container
        if holder ~= nil then
            local capacity = inst.components.inventory:CanAcceptCount(food, Count(food))
            if capacity < 1 then FinishMeal(inst, meal) return end
            local amount = capacity >= Count(food) and Count(food) or 1
            local prefab, before = food.prefab, {}
            for _, item in ipairs(CarriedItems(inst)) do before[item] = Count(item) end
            action = BufferedAction(inst, target,
                capacity >= Count(food) and ACTIONS.TAKEITEM or ACTIONS.TAKESINGLEITEM)
            action.validfn = function()
                return IsAvailable(inst, target) and holder.item == food
                    and inst.components.inventory:CanAcceptCount(food, amount) >= amount
            end
            action:AddSuccessAction(function()
                meal.portions = {}
                for _, item in ipairs(CarriedItems(inst)) do
                    local added = Count(item) - (before[item] or 0)
                    if item.prefab == prefab and added > 0 then
                        meal.portions[#meal.portions + 1] = {item = item, count = added, source = target}
                    end
                end
            end)
        else
            local leader = Policy.GetLeader(inst)
            local open = container:IsOpenedBy(inst)
                or leader ~= nil and container:IsOpenedBy(leader)
            if not open or not IsOwnSack(inst, target) and not InventoryAI.CanReachContainer(inst, target) then
                action = IsOwnSack(inst, target)
                    and BufferedAction(inst, nil, ACTIONS.MY_FRIEND_POCKET_RUMMAGE, target)
                    or BufferedAction(inst, target, ACTIONS.MY_FRIEND_OPEN)
                if not IsOwnSack(inst, target) then
                    action.arrivedist = InventoryAI.ContainerReach(inst, target)
                end
                action.validfn = function() return IsAvailable(inst, target) end
            else
                action = BufferedAction(inst, nil, ACTIONS.EAT, food)
                action.validfn = function()
                    return IsAvailable(inst, target) and container:GetItemSlot(food) ~= nil
                        and (IsOwnSack(inst, target) or InventoryAI.CanReachContainer(inst, target))
                        and (container:IsOpenedBy(inst) or leader ~= nil and container:IsOpenedBy(leader))
                end
                action:AddSuccessAction(function()
                    meal.ate = true
                    inst._my_friend_food_supply_cache = nil
                    if meal.command ~= nil then FinishMeal(inst, meal) end
                end)
            end
        end
    end
    action:AddFailAction(function()
        if meal.command ~= nil and not action._my_friend_cancelled then
            meal.command.food_failed = meal.command.food_failed or {}
            meal.command.food_failed[target.GUID] = true
        end
        if inst._my_friend_meal == meal then M.Cancel(inst) end
    end)
    return Policy.GuardAction(inst, action)
end

local function GetMealAction(inst, command, own_only)
    if not CanAct(inst) then return end
    local meal = inst._my_friend_meal
    if meal ~= nil then
        -- The inventory-eat node must not preempt an in-flight world-container
        -- action with another step of that same meal. Command meals have one owner.
        if own_only and command == nil and not IsOwnSack(inst, meal.target) then return end
        return NextMealAction(inst, meal)
    end
    if inst._my_friend_container_action or LightAI.IsDark(inst) then return end
    local function Wanted(target)
        if command ~= nil and command.food_failed ~= nil and command.food_failed[target.GUID] then
            return false
        end
        local food, score = FindBestFood(inst, target, command)
        return food ~= nil and not PreferCarriedFood(inst, command, score)
    end
    local target = FindOwnSack(inst, Wanted)
    if target == nil and not own_only then
        local x, y, z, range = SearchOrigin(inst)
        local distance
        for _, entity in ipairs(TheSim:FindEntities(x, y, z, range, nil, CANT_TAGS)) do
            if IsAvailable(inst, entity) and Wanted(entity) then
                local d = inst:GetDistanceSqToInst(entity)
                if distance == nil or d < distance then target, distance = entity, d end
            end
        end
    end
    if target == nil then return end
    meal = {target = target, command = command, deadline = GetTime() + 40}
    inst._my_friend_meal = meal
    inst._my_friend_container_action = true
    inst._my_friend_container_target = target
    if command ~= nil then command.food_container = target end
    return NextMealAction(inst, meal)
end

function M.GetCarriedFoodAction(inst, command)
    return GetMealAction(inst, command, true)
end

function M.GetCommandFoodAction(inst, command)
    return GetMealAction(inst, command, false)
end

function M.GetFoodAction(inst)
    if inst._my_friend_command ~= nil and inst._my_friend_command.id == "food" then return end
    if inst._my_friend_meal == nil and inst.components.hunger ~= nil
        and inst.components.hunger:GetPercent() >= .25 then
        local cooking = require("my_friend_recipe_cooking")
        if cooking.Score(inst) > 0 then
            local action = cooking.GetAction(inst)
            if action ~= nil then return action end
        end
    end
    return GetMealAction(inst, nil, false)
end

function M.GetReturnFoodAction(inst)
    if not CanAct(inst) or inst._my_friend_container_action or LightAI.IsDark(inst) then return end
    local records = inst._my_friend_food_returns or {}
    for index = #records, 1, -1 do
        local record = records[index]
        if not CanReturn(inst, record) then
            table.remove(records, index)
        elseif Policy.InRange(inst, record.source) and InventoryAI.CanReachContainer(inst, record.source) then
            local action = ReturnAction(inst, record)
            action:AddSuccessAction(function()
                for i, entry in ipairs(records) do
                    if entry == record then table.remove(records, i) break end
                end
            end)
            return Policy.GuardAction(inst, action)
        end
    end
end

local function HasInventoryRoom(inst, item)
    return inst.components.inventory:CanAcceptCount(item, 1) > 0
end

local function FindLightSupply(inst, container)
    local best, bestscore
    for _, item in ipairs(container:GetAllItems()) do
        if item.components.edible == nil and LightAI.CanEquipLight(inst, item) then
            local slot = item.components.equippable.equipslot
            local equipped = inst.components.inventory:GetEquippedItem(slot)
            if not (equipped ~= nil and equipped:HasTag("backpack"))
                and (equipped == nil or HasInventoryRoom(inst, equipped)) then
                local score = equipped == nil and 2 or 1
                if bestscore == nil or score > bestscore then
                    best, bestscore = item, score
                end
            end
        end
    end
    if best ~= nil then return best, "equipment" end

    local missing = LightAI.GetMissingTorchMaterials(inst)
    if missing == nil then return end
    for _, item in ipairs(container:GetAllItems()) do
        if item.components.edible == nil and missing[item.prefab] ~= nil
            and HasInventoryRoom(inst, item) then
            return item, "material", missing
        end
    end
end

local function TakeContainerLightSupply(inst, container)
    if not InventoryAI.CanReachContainer(inst, container.inst) then return false end
    local item, kind, missing = FindLightSupply(inst, container)
    if item == nil or container:GetItemSlot(item) == nil then return false end
    if kind == "equipment" then
        return LightAI.EquipLight(inst, item)
    end

    local moved = false
    for _, material in ipairs(container:GetAllItems()) do
        local needed = missing[material.prefab] or 0
        while needed > 0 and material:IsValid()
            and container:GetItemSlot(material) ~= nil
            and HasInventoryRoom(inst, material) do
            local removed = container:RemoveItem(material, false)
            if removed == nil then break end
            require("my_friend_inventory").GiveCarried(inst, removed, inst:GetPosition())
            needed = needed - 1
            missing[material.prefab] = needed
            moved = true
        end
    end
    return moved
end


local function GetLightContainerAction(inst)
    if not CanAct(inst) or inst._my_friend_container_action then return end
    if GetTime() < (inst._my_friend_container_next_light or 0) then return end
    inst._my_friend_container_next_light = GetTime() + 1
    local x, y, z, range = SearchOrigin(inst)
    local target, distance
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, range, nil, CANT_TAGS)) do
        if IsAvailable(inst, entity) and entity.components.container ~= nil
            and FindLightSupply(inst, entity.components.container) ~= nil then
            local d = inst:GetDistanceSqToInst(entity)
            if distance == nil or d < distance then target, distance = entity, d end
        end
    end
    if target == nil then return end
    inst._my_friend_container_action = true
    inst._my_friend_container_target = target
    local action = BufferedAction(inst, target, ACTIONS.MY_FRIEND_OPEN)
    action.arrivedist = InventoryAI.ContainerReach(inst, target)
    action.validfn = function() return IsAvailable(inst, target) end
    action:AddSuccessAction(function()
        TakeContainerLightSupply(inst, target.components.container)
        inst:DoTaskInTime(.6, function() CloseContainer(inst, target) end)
    end)
    action:AddFailAction(function() CloseContainer(inst, target) end)
    return Policy.GuardAction(inst, action)
end

function M.GetEmergencyLightAction(inst)
    if not LightAI.IsDark(inst) or LightAI.HasUsableEquippedLight(inst)
        or LightAI.FindBestStoredLight(inst) ~= nil or LightAI.CanCraftTorch(inst) then return end
    return GetLightContainerAction(inst)
end

function M.GetLightSupplyAction(inst)
    if LightAI.IsDark(inst) or LightAI.CanSeeInDark(inst) or LightAI.HasLightReserve(inst) then return end
    return GetLightContainerAction(inst)
end

M.IsOwnFoodContainer = IsOwnSack
return M
