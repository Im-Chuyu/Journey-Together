-- Dedicated gather commands with native actions and command-specific follow-up.
local M = {}
local Policy = require("my_friend_policy")
local Dialogue = require("my_friend_dialogue")

local function DistSq(a, b) return a:GetDistanceSqToInst(b) end
local function Reachable(inst, target)
    return target ~= nil and target:IsValid()
        and not target:HasAnyTag("INLIMBO", "burnt")
        and not require("my_friend_navigation").IsBlocked(inst, target:GetPosition())
end
local function Targets(inst, command, radius, predicate)
    local p = command.origin or command.player:GetPosition()
    local x, _, z = p:Get()
    local result = {}
    for _, entity in ipairs(TheSim:FindEntities(x, 0, z, radius, nil,
        {"INLIMBO", "burnt", "fire"})) do
        if predicate(entity) and entity:GetDistanceSqToPoint(p) <= radius * radius then
            result[#result + 1] = entity
        end
    end
    table.sort(result, function(a, b) return DistSq(inst, a) < DistSq(inst, b) end)
    return result
end
local function Action(inst, target, action, item, dialogue_kind)
    if not Reachable(inst, target) then return end
    local result = BufferedAction(inst, target, action, item)
    result.arrivedist = 2
    result._my_friend_dialogue_kind = dialogue_kind
    return Policy.GuardAction(inst, result, 32)
end
local function MineTool(inst, command)
    local tool, preparation = require("my_friend_command_work").Tool(
        inst, command, ACTIONS.MINE, "pickaxe")
    if preparation ~= nil then return nil, preparation end
    if tool ~= nil and inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS) ~= tool then
        if not inst.components.inventory:Equip(tool) then return nil end
        return nil
    end
    return tool
end

local function DropCollectedRockFruit(inst, command)
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if item:IsValid() and item.prefab == "rock_avocado_fruit"
            and item.components ~= nil and item.components.inventoryitem ~= nil
            and item.components.inventoryitem:GetGrandOwner() == inst then
            local action = BufferedAction(inst, nil, ACTIONS.DROP, item, inst:GetPosition())
            action.options.wholestack = true
            action.validfn = function()
                return item:IsValid()
                    and item.components.inventoryitem:GetGrandOwner() == inst
            end
            action:AddSuccessAction(function()
                -- The inventory entity may be replaced when a whole stack is
                -- dropped.  Do not keep that stale reference as the mining
                -- target; let the normal ground-fruit search below find the
                -- actual dropped entity and reuse the regular MINE branch.
                command.phase = "crack_mine"
                command.crack_target = nil
                command.origin = inst:GetPosition()
                -- The drop action is owned by the command node.  Request an
                -- immediate utility replan so the next tick can issue MINE;
                -- otherwise the brain may keep the completed DROP action
                -- until its normal timeout expires.
                inst._my_friend_replan_requested = true
            end)
            return Policy.GuardAction(inst, action, 8)
        end
    end
    command.phase = "crack_mine"
end

local function RockFruit(inst, command)
    command.phase = command.phase or "mine"
    if command.phase == "crack" or command.phase == "crack_drop" then
        command.phase = "crack_drop"
        local action = DropCollectedRockFruit(inst, command)
        if action ~= nil then return action end
    end
    if command.phase == "crack_mine" then
        -- Fall through to the ordinary ground-fruit mining branch below.
        -- That branch already handles target selection, tool preparation and
        -- the native repeated MINE state.
        command.phase = "mine"
        command.cracking = true
    end
    if command.phase == "ask" then
        local question = inst._my_friend_rockfruit_question
        if question ~= nil and GetTime() < question.deadline then return end
        -- No answer within the promised window: preserve the gathered fruit
        -- instead of leaving the command in a permanent waiting state.
        inst._my_friend_rockfruit_question = nil
        command.phase = "store"
    end
    if command.phase == "store" then
        local Tidy = require("my_friend_tidy")
        local x, _, z = inst.Transform:GetWorldPosition()
        local best, distance
        for _, chest in ipairs(TheSim:FindEntities(x, 0, z, 32, {"_container"},
            {"INLIMBO", "burnt", "fire", "fridge", "saltbox"})) do
            if chest.components.container ~= nil and chest.components.container.type == "chest"
                and not chest:HasTag("backpack") then
                local d = DistSq(inst, chest)
                if distance == nil or d < distance then best, distance = chest, d end
            end
        end
        local action = best ~= nil and Tidy.StoreItemsInto(inst, best, function(_, item)
            return item.prefab == "rock_avocado_fruit"
                or item.prefab == "rock_avocado_fruit_ripe"
                or item.prefab == "rock_avocado_fruit_sprout"
        end, 32) or nil
        if action ~= nil then return action end
        require("my_friend_commands").Clear(inst)
        return
    end
    local mined = Targets(inst, command, 24, function(entity)
        local w = entity.components.workable
        return entity.prefab == "rock_avocado_fruit" and w ~= nil
            and w:CanBeWorked() and w:GetWorkAction() == ACTIONS.MINE
    end)
    if #mined > 0 then
        local tool, preparation = MineTool(inst, command)
        if preparation ~= nil then return preparation end
        if tool ~= nil then
            local target = mined[1]
            local action
            if command.cracking then
                -- Continue through the work-target path used by the regular
                -- mining command so repeated swings remain attached to this
                -- target after the confirmation drop.
                inst._my_friend_work_target = target
                inst._my_friend_work_action = ACTIONS.MINE
                inst._my_friend_work_left = target.components.workable:GetWorkLeft()
                inst._my_friend_work_stall_deadline = GetTime() + 45
                action = require("my_friend_base_ai").GetRepeatWorkAction(
                    inst, target, ACTIONS.MINE)
            else
                action = Action(inst, target, ACTIONS.MINE, tool, "rockfruit")
            end
            if action ~= nil then command.gathered = true return action end
        end
    end
    if command.cracking then
        -- There is no longer a ground fruit to mine.  Do not go back to the
        -- gathering/question path after the player has already answered.
        require("my_friend_commands").Clear(inst)
        return
    end
    local bushes = Targets(inst, command, 24, function(entity)
        local p = entity.components.pickable
        return entity.prefab == "rock_avocado_bush" and p ~= nil and p:CanBePicked()
    end)
    if #bushes > 0 then
        local action = Action(inst, bushes[1], ACTIONS.PICK, nil, "rockfruit")
        if action ~= nil then command.gathered = true return action end
    end
    if command.gathered and not command.question_asked then
        command.phase, command.question_asked = "ask", true
        inst._my_friend_rockfruit_question = {player = command.player, deadline = GetTime() + 30}
        Dialogue.Reply(inst, "rockfruit_ask")
        return
    end
    require("my_friend_commands").Clear(inst)
end
local function BullKelp(inst, command)
    command.phase = command.phase or "gather"
    if command.phase == "store" then
        local Tidy = require("my_friend_tidy")
        local x, _, z = inst.Transform:GetWorldPosition()
        local best, distance
        for _, fridge in ipairs(TheSim:FindEntities(x, 0, z, 32, {"_container"},
            {"INLIMBO", "burnt", "fire"})) do
            if fridge:HasTag("fridge") and fridge.components.container ~= nil then
                local d = DistSq(inst, fridge)
                if distance == nil or d < distance then best, distance = fridge, d end
            end
        end
        local action = best ~= nil and Tidy.StoreItemsInto(inst, best, function(_, item)
            return item.prefab == "kelp"
        end, 32) or nil
        if action ~= nil then return action end
        require("my_friend_commands").Clear(inst)
        return
    end
    command.failed = command.failed or {}
    local targets = Targets(inst, command, 20, function(entity)
        local p = entity.components.pickable
        return entity.prefab == "bullkelp_plant" and p ~= nil and p:CanBePicked()
            and not command.failed[entity.GUID]
    end)
    if #targets == 0 then
        command.phase = "store"
        if command.gathered then return BullKelp(inst, command) end
        require("my_friend_commands").Clear(inst)
        return
    end
    local target = targets[1]
    local action = Action(inst, target, ACTIONS.PICK, nil, "bullkelp")
    if action == nil then command.failed[target.GUID] = true return end
    command.gathered = true
    action:AddSuccessAction(function() command.failed[target.GUID] = true end)
    action:AddFailAction(function()
        if not action._my_friend_cancelled then command.failed[target.GUID] = true end
    end)
    return action
end
local function DryMeat(inst, command)
    local p = command.origin or command.player:GetPosition()
    local x, _, z = p:Get()
    local racks = TheSim:FindEntities(x, 0, z, 24, nil, {"INLIMBO", "burnt"})
    table.sort(racks, function(a, b) return DistSq(inst, a) < DistSq(inst, b) end)
    for _, rack in ipairs(racks) do
        local dryer = rack.components ~= nil and rack.components.dryer or nil
        local dryingrack = rack.components ~= nil and rack.components.dryingrack or nil
        local container = rack.components ~= nil and rack.components.container or nil
        if dryer ~= nil then
            for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
                if item:IsValid() and item.components.inventoryitem ~= nil
                    and item.components.inventoryitem:GetGrandOwner() == inst
                    and dryer:CanDry(item) then
                    local action = Action(inst, rack, ACTIONS.DRY, item, "dry_meat")
                    if action ~= nil then return action end
                end
            end
        elseif dryingrack ~= nil and container ~= nil then
            -- New racks use a real container.  Reuse the common storage action
            -- so the rack is opened once and every compatible ingredient is
            -- transferred in one batch instead of reopening for each item.
            local Tidy = require("my_friend_tidy")
            local action = Tidy.StoreItemsInto(inst, rack, function(_, item)
                return item ~= nil and item:IsValid()
                    and item.components ~= nil and item.components.dryable ~= nil
                    and container:CanTakeItemInSlot(item)
                    and container:CanAcceptCount(item, 1) > 0
            end, 32)
            if action ~= nil then
                action._my_friend_dialogue_kind = "dry_meat"
                return action
            end
        end
    end
    require("my_friend_commands").Clear(inst)
end

local function IsFinishedDrying(item)
    -- A new dryingrack keeps the raw dryable item while it is processing and
    -- replaces it with the finished product when drying completes.
    return item ~= nil and item:IsValid() and item.components ~= nil
        and item.components.inventoryitem ~= nil and item.components.dryable == nil
end

local function GetFinishedRackItem(rack)
    local c = rack.components ~= nil and rack.components.container or nil
    if c == nil then return end
    for _, item in pairs(c.slots or {}) do
        if IsFinishedDrying(item) then return item end
    end
end

local function GetDryingRackHarvestAction(inst, rack)
    local c = rack.components ~= nil and rack.components.container or nil
    local dryingrack = rack.components ~= nil and rack.components.dryingrack or nil
    local dryer = rack.components ~= nil and rack.components.dryer or nil
    if c ~= nil and dryingrack ~= nil then
        local item = GetFinishedRackItem(rack)
        if item == nil or inst.components.inventory:CanAcceptCount(item, 1) <= 0 then
            return
        end
        local action = Action(inst, rack, ACTIONS.HARVEST, item, "dry_meat_collect")
        if action ~= nil then
            action.validfn = function()
                return rack:IsValid() and c:GetItemSlot(item) ~= nil
                    and IsFinishedDrying(item)
                    and inst.components.inventory:CanAcceptCount(item, 1) > 0
            end
        end
        return action
    elseif dryer ~= nil and rack:HasTag("dried") then
        return Action(inst, rack, ACTIONS.HARVEST, nil, "dry_meat_collect")
    end
end

function M.GetNearbyDryingRackAction(inst)
    if inst == nil or not inst:IsValid() or inst:HasTag("playerghost")
        or inst.components == nil or inst.components.inventory == nil
        or inst._my_friend_under_threat or inst._my_friend_command ~= nil
        or inst._my_friend_container_action or inst._my_friend_storage_action ~= nil
        or require("my_friend_policy").IsBusy(inst) then return end
    local x, y, z = inst.Transform:GetWorldPosition()

    -- Put the product away immediately after harvesting when a refrigerator
    -- is nearby.  Keep this as a small follow-up state so the rack harvest
    -- itself remains the native HARVEST action.
    local pending = inst._my_friend_drying_collect_pending
    local pending_item
    if pending ~= nil then
        for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
            if item:IsValid() and item.prefab == pending.prefab
                and item.components ~= nil and item.components.inventoryitem ~= nil
                and item.components.inventoryitem:GetGrandOwner() == inst then
                pending_item = item
                break
            end
        end
        if pending_item == nil then
            inst._my_friend_drying_collect_pending = nil
            pending = nil
        end
    end
    if pending ~= nil then
        local fridge, distance
        for _, entity in ipairs(TheSim:FindEntities(x, y, z, 18, {"_container"},
            {"INLIMBO", "burnt", "fire"})) do
            if entity:HasTag("fridge") and entity.components.container ~= nil
                and entity.components.container.canbeopened
                and not entity.components.container.readonlycontainer
                and not entity.components.container:IsRestricted(inst)
                and entity.components.container:CanAcceptCount(pending_item, 1) > 0 then
                local d = DistSq(inst, entity)
                if distance == nil or d < distance then fridge, distance = entity, d end
            end
        end
        if fridge ~= nil then
            local prefab = pending.prefab
            local action = require("my_friend_tidy").StoreItemsInto(inst, fridge,
                function(_, item)
                    return item ~= nil and item:IsValid() and item.prefab == prefab
                        and item.components ~= nil and item.components.dryable == nil
                end, 24)
            if action ~= nil then
                action:AddSuccessAction(function()
                    inst._my_friend_drying_collect_pending = nil
                end)
                return action
            end
        end
        -- No refrigerator, or no available slot: leave the product carried.
        inst._my_friend_drying_collect_pending = nil
    end

    local racks = TheSim:FindEntities(x, y, z, 12, nil, {"INLIMBO", "burnt", "fire"})
    table.sort(racks, function(a, b) return DistSq(inst, a) < DistSq(inst, b) end)
    for _, rack in ipairs(racks) do
        local action = GetDryingRackHarvestAction(inst, rack)
        if action ~= nil then
            local item = action.invobject
            action:AddSuccessAction(function()
                -- HARVEST may merge the result into an existing stack, so
                -- retain the prefab instead of a potentially invalid entity.
                if item ~= nil and item.prefab ~= nil then
                    inst._my_friend_drying_collect_pending = {prefab = item.prefab}
                end
            end)
            return action
        end
    end
end

function M.GetAction(inst, command)
    if command.id == "rockfruit" then return RockFruit(inst, command) end
    if command.id == "bullkelp" then return BullKelp(inst, command) end
    if command.id == "dry_meat" then return DryMeat(inst, command) end
end
return M
