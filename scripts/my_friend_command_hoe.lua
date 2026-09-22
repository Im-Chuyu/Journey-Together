local M = {}
local Policy = require("my_friend_policy")
local EXCLUDE = {"INLIMBO", "FX", "DECOR"}
local Forestry = require("my_friend_forestry")
local RESOURCE = {
    cutgrass = true, twigs = true, log = true, rocks = true, flint = true,
    goldnugget = true, nitre = true, pinecone = true, acorn = true,
    twiggy_nut = true, marble = true, charcoal = true, cutreeds = true,
}

local function IsHealthyCrop(entity)
    if not entity:HasTag("farm_plant") and entity.components.farmplantstress == nil then return false end
    local growable = entity.components.growable
    local stage = growable ~= nil and growable:GetCurrentStageData() or nil
    return entity.weed_def == nil and not entity:HasTag("farm_plant_killjoy")
        and not (stage ~= nil and stage.name == "rotten")
end

local function Tiles(command)
    if command.hoe_tiles ~= nil then return command.hoe_tiles end
    local map, origin, tiles = TheWorld.Map, command.origin, {}
    local tx, tz = map:GetTileCoordsAtPoint(origin:Get())
    for ix = tx - 8, tx + 8 do
        for iz = tz - 8, tz + 8 do
            local x, _, z = map:GetTileCenterPoint(ix, iz)
            if map:IsFarmableSoilAtPoint(x, 0, z)
                and (x-origin.x)^2 + (z-origin.z)^2 <= 32^2 then
                local tile = {x = x, z = z, tx = ix, tz = iz, points = {},
                    attempts = {}, failures = {}, distance = (x-origin.x)^2 + (z-origin.z)^2}
                for gx = -1, 1 do
                    for gz = -1, 1 do
                        tile.points[#tile.points + 1] = Vector3(x + gx * 4/3, 0, z + gz * 4/3)
                    end
                end
                local inrange = true
                for _, point in ipairs(tile.points) do
                    if (point-origin):LengthSq() > 32^2 then inrange = false break end
                end
                if inrange then tiles[#tiles + 1] = tile end
            end
        end
    end
    table.sort(tiles, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.tx == b.tx and a.tz < b.tz or a.tx < b.tx
    end)
    -- Four touching tiles (square or straight line) whenever the ground allows.
    command.hoe_tiles = require("my_friend_farm_tiles").Select(tiles, 4)
    return command.hoe_tiles
end

local function Entities(tile)
    local entities = {}
    for _, entity in ipairs(TheSim:FindEntities(tile.x, 0, tile.z, 3, nil, EXCLUDE)) do
        local x, _, z = entity.Transform:GetWorldPosition()
        local tx, tz = TheWorld.Map:GetTileCoordsAtPoint(x, 0, z)
        if tx == tile.tx and tz == tile.tz then entities[#entities + 1] = entity end
    end
    return entities
end

local function GridSlot(tile, entity)
    for i, point in ipairs(tile.points) do
        if entity:GetDistanceSqToPoint(point) <= .12^2 then return i end
    end
end

local function Equip(inst, tool)
    local inv = inst.components.inventory
    if not require("my_friend_base_ai").CanUseHandToolInCurrentLight(inst) then return false end
    if inv:GetEquippedItem(EQUIPSLOTS.HANDS) ~= tool and not inv:Equip(tool) then return false end
    inst._my_friend_hand_tool_lock_until = GetTime() + 3
    return true
end

function M.Action(inst, command)
    local work = require("my_friend_command_work")
    local tiles = Tiles(command)
    for _, tile in ipairs(tiles) do
        if not tile.finished then
            local entities, occupied, clutter, soil = Entities(tile), {}, nil, nil
            for _, entity in ipairs(entities) do
                local workable = entity.components.workable
                local inventoryitem = entity.components.inventoryitem
                if entity ~= inst and inventoryitem ~= nil and inventoryitem.owner == nil
                    and inventoryitem.canbepickedup and not entity:HasTag("soil")
                    and not (command.hoe_failed_items or {})[entity.GUID] then
                    local useful = Forestry.IsUsefulLooseItem(entity)
                        or RESOURCE[entity.prefab] == true
                    local action = BufferedAction(inst, entity, ACTIONS.PICKUP)
                    action:AddSuccessAction(function()
                        command.hoe_items = command.hoe_items or {}
                        command.hoe_items[#command.hoe_items + 1] =
                            {item = entity, useful = useful, tile = tile}
                    end)
                    action:AddFailAction(function()
                        command.hoe_failed_items = command.hoe_failed_items or {}
                        command.hoe_failed_items[entity.GUID] = true
                    end)
                    return Policy.GuardAction(inst, action, 32)
                end
                if entity:HasTag("soil") and entity._plow == nil then
                    local slot = GridSlot(tile, entity)
                    if slot ~= nil and not entity:HasTag("NOBLOCK") and not occupied[slot] then
                        occupied[slot] = true
                    elseif (tile.failures[entity.GUID] or 0) < 3 then
                        soil = soil or entity
                    end
                elseif entity ~= inst and workable ~= nil and workable:CanBeWorked()
                    and workable:GetWorkAction() == ACTIONS.DIG and not IsHealthyCrop(entity)
                    and (tile.failures[entity.GUID] or 0) < 3 then
                    clutter = clutter or entity
                end
            end
            if command.hoe_items ~= nil then
                for i = #command.hoe_items, 1, -1 do
                    local entry = command.hoe_items[i]
                    if entry.item == nil or not entry.item:IsValid() or entry.useful then
                        table.remove(command.hoe_items, i)
                    elseif entry.item.components.inventoryitem:GetGrandOwner() == inst then
                        local point = Vector3(entry.tile.x + 4, 0, entry.tile.z + 4)
                        if inst:GetDistanceSqToPoint(point) > 2^2 then
                            local walk = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point)
                            walk.arrivedist = 1.5
                            return Policy.GuardAction(inst, walk, 32)
                        end
                        local drop = BufferedAction(inst, nil, ACTIONS.DROP, entry.item, point)
                        drop.options.wholestack = true
                        drop:AddSuccessAction(function() table.remove(command.hoe_items, i) end)
                        return Policy.GuardAction(inst, drop, 32)
                    else
                        table.remove(command.hoe_items, i)
                    end
                end
            end
            -- Clear the entire selected tile before testing whether it can be tilled.
            local target = clutter or soil
            if target ~= nil then
                local kind = clutter ~= nil and ACTIONS.DIG or ACTIONS.MY_FRIEND_LEVELSOIL
                local toolkind = clutter ~= nil and ACTIONS.DIG or ACTIONS.TILL
                local tool, preparation = work.Tool(inst, command, toolkind,
                    clutter ~= nil and "shovel" or "farm_hoe")
                if preparation ~= nil then return preparation end
                if tool == nil then work.Finish(inst, command, true) return end
                if not Equip(inst, tool) then return end
                local action = BufferedAction(inst, target, kind, tool)
                action.validfn = function()
                    return inst._my_friend_command == command and target:IsValid()
                        and (clutter == nil and target:HasTag("soil") and target._plow == nil
                            or clutter ~= nil and not IsHealthyCrop(target)
                                and target.components.workable ~= nil
                                and target.components.workable:CanBeWorked()
                                and target.components.workable:GetWorkAction() == ACTIONS.DIG)
                end
                action:AddFailAction(function()
                    if not action._my_friend_cancelled then
                        tile.failures[target.GUID] = (tile.failures[target.GUID] or 0) + 1
                    end
                end)
                return Policy.GuardAction(inst, action, 32)
            end
            local missing = false
            for i, point in ipairs(tile.points) do
                if not occupied[i] then
                    missing = true
                    if (tile.attempts[i] or 0) < 3
                        and TheWorld.Map:CanTillSoilAtPoint(point.x, 0, point.z, false) then
                        local tool, preparation = work.Tool(inst, command, ACTIONS.TILL, "farm_hoe")
                        if preparation ~= nil then return preparation end
                        if tool == nil then work.Finish(inst, command, true) return end
                        if not Equip(inst, tool) then return end
                        local action = BufferedAction(inst, nil, ACTIONS.TILL, tool, point)
                        action.validfn = function()
                            return inst._my_friend_command == command
                                and work.IsUsableTool(inst, tool, ACTIONS.TILL)
                                and tool.components.inventoryitem:GetGrandOwner() == inst
                                and TheWorld.Map:CanTillSoilAtPoint(point.x, 0, point.z, false)
                        end
                        local function Attempt()
                            if not action._my_friend_cancelled then
                                tile.attempts[i] = (tile.attempts[i] or 0) + 1
                            end
                        end
                        action:AddSuccessAction(Attempt)
                        action:AddFailAction(Attempt)
                        tile.rechecks = 0
                        return Policy.GuardAction(inst, action, 32)
                    end
                end
            end
            if missing then
                tile.rechecks = (tile.rechecks or 0) + 1
                -- Re-read live soil, including changes caused by neighbouring till actions.
                if tile.rechecks < 3 then
                    local wait = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, inst:GetPosition())
                    return Policy.GuardAction(inst, wait, 32)
                end
                command.hoe_incomplete = true
            end
            tile.finished = true
        end
    end
    -- Recheck completed tiles once more after work on their neighbours.
    command.hoe_final_checks = (command.hoe_final_checks or 0) + 1
    if command.hoe_final_checks <= 2 then
        local reopen = false
        for _, tile in ipairs(tiles) do
            local occupied = {}
            for _, entity in ipairs(Entities(tile)) do
                if entity:HasTag("soil") and not entity:HasTag("NOBLOCK") then
                    local slot = GridSlot(tile, entity)
                    if slot ~= nil then occupied[slot] = true end
                end
            end
            for i, point in ipairs(tile.points) do
                if not occupied[i] and (tile.attempts[i] or 0) < 3
                    and TheWorld.Map:CanTillSoilAtPoint(point.x, 0, point.z, false) then
                    tile.finished, tile.rechecks, reopen = nil, 0, true
                end
            end
        end
        if reopen then return M.Action(inst, command) end
    end
    work.Finish(inst, command)
    if command.hoe_incomplete then
        require("my_friend_dialogue").Reply(inst, "hoe_incomplete")
    end
end

return M
