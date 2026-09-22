-- Focused gathering commands for the uncommon plants that should be handled
-- separately from the companion's normal resource planner.
local Policy = require("my_friend_policy")
local Dialogue = require("my_friend_dialogue")
local Navigation = require("my_friend_navigation")
local Tidy = require("my_friend_tidy")

local M = {}
M.RANGE = 20
M.REED_SEARCH_RANGE = 64
M.REED_TIMEOUT = 120

local function DistanceSq(a, b)
    return a:GetDistanceSqToInst(b)
end

local function Origin(command)
    return command.origin or command.player:GetPosition()
end

local function Reachable(inst, target)
    return target ~= nil and target:IsValid()
        and not target:HasAnyTag("INLIMBO", "burnt", "fire")
        and not Navigation.IsBlocked(inst, target:GetPosition())
end

local function Pickable(entity, prefab)
    local pickable = entity.components ~= nil and entity.components.pickable or nil
    return entity.prefab == prefab and pickable ~= nil and pickable:CanBePicked()
end

local function FindNearby(inst, command, prefab, radius, predicate)
    local point = Origin(command)
    local x, _, z = point:Get()
    local best, distance
    for _, entity in ipairs(TheSim:FindEntities(x, 0, z, radius, nil,
        {"INLIMBO", "burnt", "fire"})) do
        if Pickable(entity, prefab) and (predicate == nil or predicate(entity))
            and entity:GetDistanceSqToPoint(point) <= radius * radius
            and Reachable(inst, entity) then
            local d = DistanceSq(inst, entity)
            if distance == nil or d < distance then best, distance = entity, d end
        end
    end
    return best
end

local function IsMarsh(entity)
    local p = entity:GetPosition()
    local region = require("my_friend_world_resources").RegionAtPoint(p.x, p.z)
    if region ~= nil and region.kind == "marsh" then return true end
    local tiles = WORLD_TILES or GROUND
    return TheWorld.Map ~= nil and tiles ~= nil and tiles.MARSH ~= nil
        and TheWorld.Map:GetTileAtPoint(p.x, 0, p.z) == tiles.MARSH
end

local function FindReeds(inst, command)
    local point = Origin(command)
    local x, _, z = point:Get()
    local best, distance
    for _, entity in ipairs(TheSim:FindEntities(x, 0, z, M.REED_SEARCH_RANGE, nil,
        {"INLIMBO", "burnt", "fire"})) do
        if Pickable(entity, "reeds") and IsMarsh(entity)
            and Reachable(inst, entity) then
            local d = DistanceSq(inst, entity)
            if distance == nil or d < distance then best, distance = entity, d end
        end
    end
    return best
end

local function PickAction(inst, command, target, dialogue_kind)
    if not Reachable(inst, target) then return end
    local action = BufferedAction(inst, target, ACTIONS.PICK)
    action.arrivedist = 2
    action._my_friend_dialogue_kind = dialogue_kind
    action.validfn = function()
        return inst._my_friend_command == command and Reachable(inst, target)
            and target:GetDistanceSqToPoint(Origin(command)) <= M.RANGE * M.RANGE
            and target.components.pickable:CanBePicked()
    end
    return Policy.GuardAction(inst, action, 32)
end

local function HasProduct(inst, prefabs)
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if item:IsValid() and prefabs[item.prefab]
            and item.components ~= nil and item.components.inventoryitem ~= nil
            and item.components.inventoryitem:GetGrandOwner() == inst then
            return item
        end
    end
end

local function HandOver(inst, command, item)
    if command.player == nil or not command.player:IsValid()
        or DistanceSq(inst, command.player) > 32 * 32 then return end
    local action = Tidy.HandOver(inst, command, item)
    if action ~= nil then
        action:AddSuccessAction(function()
            if inst._my_friend_command == command then
                require("my_friend_commands").Clear(inst)
                Dialogue.RandomReply(inst, command.id == "banana" and "banana_done" or "monkeytail_done")
            end
        end)
    end
    return action
end

local function StoreInFridge(inst, command, item)
    local x, y, z = inst.Transform:GetWorldPosition()
    local best, distance
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, 24, {"_container"},
        {"INLIMBO", "burnt", "fire"})) do
        if entity:HasTag("fridge") and entity.components.container ~= nil
            and entity.components.container:CanAcceptCount(item, 1) > 0 then
            local d = DistanceSq(inst, entity)
            if distance == nil or d < distance then best, distance = entity, d end
        end
    end
    if best == nil then return end
    local action = Tidy.StoreItemsInto(inst, best, function(_, candidate)
        return candidate ~= nil and candidate:IsValid()
            and (command.id == "banana" and candidate.prefab == "cave_banana"
                or command.id == "monkeytail" and candidate.prefab == "cutreeds")
    end, 32)
    if action ~= nil then
        action:AddSuccessAction(function()
            if inst._my_friend_command == command then
                require("my_friend_commands").Clear(inst)
                Dialogue.RandomReply(inst, command.id == "banana" and "banana_done" or "monkeytail_done")
            end
        end)
    end
    return action
end

local function Deliver(inst, command, prefabs)
    local done_key = command.id == "banana" and "banana_done" or "monkeytail_done"
    local none_key = command.id == "banana" and "banana_none" or "monkeytail_none"
    local item = HasProduct(inst, prefabs)
    if item == nil then
        require("my_friend_commands").Clear(inst)
        Dialogue.RandomReply(inst, command.gathered and done_key or none_key)
        return
    end
    -- Return bananas or reeds to the player first. A nearby fridge is the
    -- fallback; if neither is available the command ends with the item kept
    -- in the companion's own inventory.
    local action = HandOver(inst, command, item) or StoreInFridge(inst, command, item)
    if action ~= nil then return action end
    require("my_friend_commands").Clear(inst)
    Dialogue.RandomReply(inst, command.gathered and done_key or none_key)
end

local function Monkeytail(inst, command)
    command.phase = command.phase or "monkeytail"
    if command.phase == "deliver" then
        return Deliver(inst, command, {cutreeds = true})
    end
    if command.phase == "monkeytail" then
        if command.scan_after ~= nil and GetTime() < command.scan_after then
            command.waiting = true
            return
        end
        command.waiting, command.scan_after = nil, nil
        local target = FindNearby(inst, command, "monkeytail", M.RANGE)
        if target ~= nil then
            local action = PickAction(inst, command, target, "gather")
            if action ~= nil then
                action:AddSuccessAction(function()
                    command.gathered = true
                    command.scan_after = GetTime() + 5
                end)
                return action
            end
        end
        command.phase = "reeds"
        command.reed_deadline = GetTime() + M.REED_TIMEOUT
    end
    if command.phase == "reeds" then
        if GetTime() >= (command.reed_deadline or 0) then
            command.phase = "deliver"
            return Deliver(inst, command, {cutreeds = true})
        end
        local target = FindReeds(inst, command)
        if target ~= nil then
            local action = PickAction(inst, command, target, "gather")
            if action ~= nil then
                action:AddSuccessAction(function() command.gathered = true end)
                return action
            end
        else
            command.phase = "deliver"
            return Deliver(inst, command, {cutreeds = true})
        end
    end
end

local function Banana(inst, command)
    command.phase = command.phase or "banana"
    if command.phase == "deliver" then return Deliver(inst, command, {cave_banana = true}) end
    local target = FindNearby(inst, command, "bananabush", M.RANGE)
    if target ~= nil then
        local action = PickAction(inst, command, target, "gather")
        if action ~= nil
            then action:AddSuccessAction(function() command.gathered = true end) return action end
    end
    command.phase = "deliver"
    return Deliver(inst, command, {cave_banana = true})
end

function M.GetAction(inst, command)
    return command.id == "banana" and Banana(inst, command) or Monkeytail(inst, command)
end

return M
