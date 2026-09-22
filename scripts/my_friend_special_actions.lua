local Policy = require("my_friend_policy")
local Inventory = require("my_friend_inventory")
local BaseAI = require("my_friend_base_ai")
local Dialogue = require("my_friend_dialogue")
local RecipeCooking = require("my_friend_recipe_cooking")
local Books = require("my_friend_books")
local BookStation = require("my_friend_bookstation")
local Materials = require("my_friend_crafting_materials")
local Devices = require("my_friend_device_deploy")
local CraftingTech = require("my_friend_crafting_tech")

local M = {}

local function OwnItems(inst)
    return inst.components.inventory ~= nil
        and inst.components.inventory:ReferenceAllItems() or {}
end

local function FindSpicer(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local best
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, 20, {"spicer"}, {"INLIMBO", "burnt"})) do
        if entity.components.container ~= nil and not entity.components.container:IsOpenedByOthers(inst)
            and not entity.components.container:IsRestricted(inst) then
            if best == nil or inst:GetDistanceSqToInst(entity) < inst:GetDistanceSqToInst(best) then best = entity end
        end
    end
    return best
end

local function FindFood(inst, prefab)
    for _, item in ipairs(OwnItems(inst)) do
        local owner = item.components.inventoryitem.owner
        if item.prefab == prefab and item:HasTag("preparedfood") and owner ~= nil
            and owner.prefab ~= "beargerfur_sack"
            and not item:HasTag("spicedfood") and item.components.inventoryitem:GetGrandOwner() == inst
            and item.components.inventoryitem.owner ~= inst.components.inventory:GetOverflowContainer() then
            return item
        end
    end
end

local function FindSpice(inst, prefab)
    for _, item in ipairs(OwnItems(inst)) do
        if item.prefab == prefab and item.components.inventoryitem:GetGrandOwner() == inst then return item end
    end
end

local function SpiceAction(inst, command)
    local station = FindSpicer(inst)
    if station == nil then return end
    local c = station.components.container
    local stewer = station.components.stewer
    if stewer ~= nil and stewer:IsCooking() then
        command.waiting = true
        return
    end
    if not c:IsOpenedBy(inst) then
        local action = BufferedAction(inst, station, ACTIONS.MY_FRIEND_OPEN)
        action.arrivedist = Inventory.ContainerReach(inst, station)
        return Policy.GuardAction(inst, action)
    end
    if stewer ~= nil and stewer:IsDone() then
        local action = BufferedAction(inst, station, ACTIONS.HARVEST)
        action.validfn = function() return stewer:IsDone() and c:IsOpenedBy(inst) end
        action:AddSuccessAction(function()
            command.waiting = nil
            c:Close(inst)
            inst:PushEvent("closecontainer", {container = station})
            if inst._my_friend_command == command then
                require("my_friend_commands").Clear(inst)
            end
        end)
        return Policy.GuardAction(inst, action)
    end
    if c:GetItemInSlot(1) == nil then
        local food = FindFood(inst, command.food)
        if food == nil then return end
        local action = BufferedAction(inst, station, ACTIONS.MY_FRIEND_SPICE_ADD, food)
        action._my_friend_spice_slot = 1
        return Policy.GuardAction(inst, action)
    end
    if c:GetItemInSlot(2) == nil then
        local spice = FindSpice(inst, command.spice)
        if spice == nil then return end
        local action = BufferedAction(inst, station, ACTIONS.MY_FRIEND_SPICE_ADD, spice)
        action._my_friend_spice_slot = 2
        return Policy.GuardAction(inst, action)
    end
    local action = BufferedAction(inst, station, ACTIONS.COOK)
    action.validfn = function() return c:IsOpenedBy(inst) and c:GetItemInSlot(1) ~= nil and c:GetItemInSlot(2) ~= nil end
    action:AddSuccessAction(function() command.waiting = true end)
    return Policy.GuardAction(inst, action)
end

local function BuildAction(inst, command)
    local recipe = GetValidRecipe(command.recipe)
    if recipe == nil then return end
    command.waiting, command.failure_reply = nil, nil
    if Devices.IsRecipe(command.recipe) then
        local item = Devices.FindItem(inst, command.recipe)
        if item ~= nil then
            local deploy = Devices.GetDeployAction(inst, item)
            if deploy ~= nil then return deploy end
            command.failure_reply = "special_device_place_failed"
            return
        elseif command.device_ready then
            command.waiting = true
            return
        end
    end
    if inst._my_friend_storage_action ~= nil then
        command.waiting = true
        return
    end
    -- The vanilla builder refreshes its active prototyper before checking
    -- recipe knowledge. Special commands bypass the crafting UI, so do the
    -- same refresh here or a book can be reported unavailable while all of
    -- its ingredients are already present.
    if inst.components.builder.EvaluateTechTrees ~= nil then
        inst.components.builder:EvaluateTechTrees()
    end
    local materials = Materials.Plan(inst, recipe)
    if materials == nil then return end
    if not CraftingTech.CanBuild(inst, recipe) then
        local station, distance = CraftingTech.FindStation(inst, recipe)
        if station == nil then return end
        -- Collect first so fetching materials does not send us back and forth
        -- between the chest and an as-yet unlearned recipe's station.
        if #materials > 0 then return Materials.GetAction(inst, materials) end
        if distance > 2^2 then
            local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, station:GetPosition())
            action.arrivedist = 1.5
            return Policy.GuardAction(inst, action)
        end
        if not CraftingTech.Activate(inst, station, recipe) then return end
    end
    if #materials > 0 then return Materials.GetAction(inst, materials) end
    if command.recipe == "bookstation" and inst.components.builder:HasIngredients(recipe) then
        local prepare, reason = BookStation.GetPrepareAction(inst, command, recipe)
        if prepare ~= nil then return prepare end
        if reason ~= nil then
            command.waiting = reason == "waiting"
            command.failure_reply = not command.waiting and reason or nil
            return
        end
    end
    local action = BaseAI.GetRecipeAction(inst, command.recipe, command.build_point)
    if action ~= nil and action.action == (ACTIONS.MY_FRIEND_BUILD or ACTIONS.BUILD)
        and action.recipe == command.recipe then
        local previous = action.validfn
        action.validfn = function(act)
            return inst._my_friend_command == command
                and (command.recipe ~= "bookstation" or BookStation.IsClear(command))
                and (previous == nil or previous(act))
        end
        action:AddSuccessAction(function()
            if Devices.IsRecipe(command.recipe) then
                command.device_ready = true
            else
                if command.recipe == "bookstation" then Dialogue.Reply(inst, "bookstation_done") end
                if inst._my_friend_command == command then require("my_friend_commands").Clear(inst) end
            end
        end)
    end
    return action
end

function M.GetAction(inst, command)
    if command.special == "wendy_recall" then
        require("my_friend_abigail").Recall(inst, 480)
        require("my_friend_commands").Clear(inst)
        return
    elseif command.special == "read" then
        local action = Books.GetReadAction(inst, command)
        if action == nil and inst._my_friend_command == command then
            if not command.reported then
                command.reported = true
                Dialogue.Reply(inst, "special_no_book")
                require("my_friend_commands").Clear(inst)
            end
        end
        return action
    elseif command.special == "spice" then
        local action = SpiceAction(inst, command)
        if action == nil and command.waiting then return end
        if action == nil and not command.reported then
            command.reported = true
            Dialogue.Reply(inst, "special_no_food")
            require("my_friend_commands").Clear(inst)
        end
        return action
    elseif command.special == "cook" then
        local action = RecipeCooking.GetSpecificAction(inst, command.recipe)
        if action == nil and command.waiting then return end
        if action == nil and not command.reported then
            command.reported = true
            Dialogue.Reply(inst, command.failure_reply
                or ((command.cooked or 0) > 0 and "recipe_batch_done" or "special_cannot_make"),
                tostring(command.cooked or 0))
            require("my_friend_commands").Clear(inst)
        end
        return action
    end
    local action = BuildAction(inst, command)
    if action == nil and command.waiting then return end
    if action == nil and not command.reported then
        command.reported = true
        Dialogue.Reply(inst, command.failure_reply
            or (command.recipe == "bookstation" and "bookstation_cannot_make" or "special_cannot_make"))
        require("my_friend_commands").Clear(inst)
    end
    return action
end

return M
