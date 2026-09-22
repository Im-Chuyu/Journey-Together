local M = {}
local Policy = require("my_friend_policy")
local Inventory = require("my_friend_inventory")

local function Usable(inst, item, work, allow_empty)
    if item == nil or not item:IsValid() then return false end
    local c = item.components
    if c.inventoryitem == nil or c.inventoryitem.islockedinslot
        or c.equippable == nil or c.equippable:IsRestricted(inst)
        or not allow_empty and c.finiteuses ~= nil and c.finiteuses:GetUses() <= 0 then return false end
    if work == ACTIONS.TILL then return c.farmtiller ~= nil end
    if work == ACTIONS.FISH then return c.fishingrod ~= nil end
    if work == ACTIONS.POUR_WATER_GROUNDTILE then
        return c.wateryprotection ~= nil and item:HasTag("wateringcan")
    end
    return Inventory.IsUsableTool(inst, item, work)
end

function M.Finish(inst, command, unavailable)
    if inst._my_friend_command ~= command then return end
    require("my_friend_commands").Clear(inst)
    if unavailable then require("my_friend_dialogue").Reply(inst, "no_tool") end
end

local function Prepare(inst, command, action, key)
    action._my_friend_command_preparation = true
    action:AddFailAction(function()
        if not action._my_friend_cancelled then
            command.tool_failed[key] = true
        end
    end)
    return Policy.GuardAction(inst, action, 32)
end

-- Returns a held tool, a preparation action, or neither when impossible.
function M.Tool(inst, command, work, recipe_name, collect_materials, carried_only)
    local inv = inst.components.inventory
    for _, item in ipairs(inv:ReferenceAllItems()) do
        if Usable(inst, item, work) then return item end
    end
    if command.id == "chop" and command.chop_started then return end
    command.tool_failed = command.tool_failed or {}
    local origin = command.id == "fish" and inst:GetPosition()
        or command.id == "chop" and command.origin or command.player:GetPosition()
    local x, y, z = origin:Get()
    local entities = TheSim:FindEntities(x, y, z, command.id == "chop" and 16 or 32,
        nil, {"INLIMBO", "burnt", "fire"})
    table.sort(entities, function(a, b)
        return inst:GetDistanceSqToInst(a) < inst:GetDistanceSqToInst(b)
    end)
    local source
    if work == ACTIONS.POUR_WATER_GROUNDTILE then
        for _, target in ipairs(entities) do
            if target:HasTag("watersource") and not command.tool_failed[target.GUID] then
                source = target
                break
            end
        end
        for _, item in ipairs(inv:ReferenceAllItems()) do
            if source ~= nil and Usable(inst, item, work, true) and item.components.fillable ~= nil then
                return nil, Prepare(inst, command,
                    BufferedAction(inst, source, ACTIONS.FILL, item), source.GUID)
            end
        end
    end
    for _, target in ipairs(entities) do
        if not carried_only and not command.tool_failed[target.GUID] then
            if Usable(inst, target, work, source ~= nil) and target.components.inventoryitem.owner == nil
                and target.components.inventoryitem.canbepickedup
                and inv:CanAcceptCount(target, 1) > 0 then
                return nil, Prepare(inst, command,
                    BufferedAction(inst, target, ACTIONS.PICKUP), target.GUID)
            end
            local container = target.components.container
            if container ~= nil and target:HasTag("chest") and Inventory.CanWithdrawFrom(inst, target) then
                for _, item in pairs(container.slots) do
                    if Usable(inst, item, work, source ~= nil) and inv:CanAcceptCount(item, 1) > 0 then
                        local action = BufferedAction(inst, target, ACTIONS.MY_FRIEND_WITHDRAW)
                        action.arrivedist = Inventory.ContainerReach(inst, target)
                        action._my_friend_withdraw_plan = {{item = item, count = 1}}
                        return nil, Prepare(inst, command, action, target.GUID)
                    end
                end
            end
        end
    end
    local builder = inst.components.builder
    local recipe = GetValidRecipe(recipe_name)
    if builder == nil or recipe == nil or command.tool_failed[recipe_name]
        or work == ACTIONS.POUR_WATER_GROUNDTILE and source == nil then return end
    local materials
    if not builder:HasIngredients(recipe) then
        if not collect_materials then return end
        materials = require("my_friend_crafting_materials").Plan(inst, recipe)
        if materials == nil then return end
    end
    local tech = require("my_friend_crafting_tech")
    local function CanBuildHere()
        return tech.CanBuild(inst, recipe)
    end
    builder:EvaluateTechTrees()
    local station
    if not CanBuildHere() then
        for _, target in ipairs(entities) do
            if not command.tool_failed[target.GUID] and tech.StationCanTeach(inst, target, recipe)
                and inst:GetCurrentPlatform() == target:GetCurrentPlatform() then
                station = target
                break
            end
        end
        if station == nil then return end
    end
    if materials ~= nil and #materials > 0 then
        local entry = materials[1]
        local key = (entry.source or entry.item).GUID
        if command.tool_failed[key] then return end
        local action = require("my_friend_crafting_materials").GetAction(inst, materials)
        return nil, action ~= nil and Prepare(inst, command, action, key) or nil
    end
    if station ~= nil then
        if inst:GetDistanceSqToInst(station) > 4 then
            local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, station:GetPosition())
            action.arrivedist = 1.8
            return nil, Prepare(inst, command, action, station.GUID)
        end
        if not tech.Activate(inst, station, recipe) then return end
    end
    local action = BufferedAction(inst, nil, ACTIONS.MY_FRIEND_BUILD or ACTIONS.BUILD,
        nil, inst:GetPosition(), recipe.name)
    action.validfn = function()
        builder:EvaluateTechTrees()
        return builder:HasIngredients(recipe) and CanBuildHere()
    end
    action:AddSuccessAction(tech.OnBuilt(inst, recipe))
    action:AddSuccessAction(function()
        -- If this tool is exhausted, do not manufacture a second one in the
        -- same command (especially another empty watering can).
        if work == ACTIONS.POUR_WATER_GROUNDTILE then command.tool_failed[recipe_name] = true end
    end)
    return nil, Prepare(inst, command, action, recipe_name)
end

local function SoilOccupied(point)
    for _, entity in ipairs(TheSim:FindEntities(point.x, 0, point.z, .75,
        nil, {"INLIMBO", "FX", "DECOR"})) do
        if entity:HasTag("soil") or entity:HasTag("farm_plant")
            or entity.components.farmplantstress ~= nil then return true end
    end
    return false
end

local function FarmTargets(inst, command)
    local map = TheWorld.Map
    local x, _, z = command.origin:Get()
    local tx, tz = map:GetTileCoordsAtPoint(x, 0, z)
    local cache = command.farm_targets
    if cache ~= nil and cache.tx == tx and cache.tz == tz
        and GetTime() < cache.untiltime then return cache.points end
    local points = {}
    if command.farm_tiles == nil then
        local tiles = {}
        for ix = tx - 8, tx + 8 do
            for iz = tz - 8, tz + 8 do
                local cx, _, cz = map:GetTileCenterPoint(ix, iz)
                if map:IsFarmableSoilAtPoint(cx, 0, cz) and (cx-x)^2 + (cz-z)^2 <= 32^2 then
                    local eligible = command.id == "water"
                    if not eligible then
                        for gx = -1, 1 do
                            for gz = -1, 1 do
                                local point = Vector3(cx + gx * 4/3, 0, cz + gz * 4/3)
                                if not SoilOccupied(point)
                                    and (point.x-x)^2 + (point.z-z)^2 <= 32^2
                                    and map:CanTillSoilAtPoint(point.x, 0, point.z, false) then
                                    eligible = true
                                end
                            end
                        end
                    end
                    if eligible then
                        tiles[#tiles + 1] = {key = tostring(ix)..":"..tostring(iz),
                            tx = ix, tz = iz, distance = (cx-x)^2 + (cz-z)^2}
                    end
                end
            end
        end
        table.sort(tiles, function(a, b)
            return a.distance == b.distance and a.key < b.key or a.distance < b.distance
        end)
        -- Four touching tiles (square or straight line) whenever possible.
        command.farm_tiles = {}
        for _, tile in ipairs(require("my_friend_farm_tiles").Select(tiles, 4)) do
            command.farm_tiles[tile.key] = true
        end
    end
    -- Tile centres, not plant positions, define the stable nine-hole grid.
    for ix = tx - 8, tx + 8 do
        for iz = tz - 8, tz + 8 do
            local cx, _, cz = map:GetTileCenterPoint(ix, iz)
            if command.farm_tiles[tostring(ix)..":"..tostring(iz)]
                and map:IsFarmableSoilAtPoint(cx, 0, cz) and (cx-x)^2 + (cz-z)^2 <= 32^2 then
                local key = tostring(ix)..":"..tostring(iz)
                if command.id == "water" then
                    if (command.farm_done[key] or 0) < 4 and not command.farm_failed[key] then
                        points[#points + 1] = {point = Vector3(cx, 0, cz), key = key}
                    end
                else
                    for gx = -1, 1 do
                        for gz = -1, 1 do
                            local point = Vector3(cx + gx * 4/3, 0, cz + gz * 4/3)
                            local slot = key..":"..gx..":"..gz
                            if not command.farm_done[slot] and not command.farm_failed[slot]
                                and (point.x-x)^2 + (point.z-z)^2 <= 32^2 then
                                points[#points + 1] = {point = point, key = slot}
                            end
                        end
                    end
                end
            end
        end
    end
    local origin = inst:GetPosition()
    table.sort(points, function(a, b)
        return (a.point-origin):LengthSq() < (b.point-origin):LengthSq()
    end)
    command.farm_targets = {tx = tx, tz = tz, untiltime = GetTime() + 5, points = points}
    return points
end

function M.Farm(inst, command)
    if command.id == "hoe" then return require("my_friend_command_hoe").Action(inst, command) end
    command.farm_done, command.farm_failed = command.farm_done or {}, command.farm_failed or {}
    local target
    local x, _, z = command.origin:Get()
    for _, candidate in ipairs(FarmTargets(inst, command)) do
        local point, key = candidate.point, candidate.key
        if not command.farm_failed[key]
            and (command.farm_done[key] or 0) < (command.id == "water" and 4 or 1)
            and (point.x-x)^2 + (point.z-z)^2 <= 32^2
            and TheWorld.Map:IsFarmableSoilAtPoint(point.x, 0, point.z)
            and (command.id == "water" or not SoilOccupied(point)
                and TheWorld.Map:CanTillSoilAtPoint(point.x, 0, point.z, false)) then
            target = candidate
            break
        end
    end
    if target ~= nil and command.id == "hoe" then
        local clutter
        for _, entity in ipairs(TheSim:FindEntities(target.point.x, 0, target.point.z, 1.1, nil,
            {"INLIMBO", "FX", "DECOR"})) do
            local workable = entity.components ~= nil and entity.components.workable or nil
            if entity ~= inst and workable ~= nil and workable:CanBeWorked()
                and (workable:GetWorkAction() == ACTIONS.DIG
                    or entity:HasTag("farm_debris")
                    or entity:HasTag("farm_plant_killjoy")
                    or entity.components.farmplantstress ~= nil) then
                clutter = entity
                break
            end
        end
        if clutter ~= nil then
            local tool, prepare = M.Tool(inst, command, ACTIONS.DIG, "shovel")
            if prepare ~= nil then return prepare end
            if tool == nil then M.Finish(inst, command, true) return end
            return Policy.GuardAction(inst,
                BufferedAction(inst, clutter, ACTIONS.DIG, tool))
        end
    end
    if target == nil then M.Finish(inst, command) return end
    local work = command.id == "hoe" and ACTIONS.TILL or ACTIONS.POUR_WATER_GROUNDTILE
    local tool, prepare = M.Tool(inst, command, work, command.id == "hoe" and "farm_hoe" or "wateringcan")
    if prepare ~= nil then return prepare end
    if tool == nil then M.Finish(inst, command, true) return end
    if not require("my_friend_base_ai").CanUseHandToolInCurrentLight(inst) then return end
    local inv = inst.components.inventory
    if inv:GetEquippedItem(EQUIPSLOTS.HANDS) ~= tool and not inv:Equip(tool) then
        M.Finish(inst, command, true)
        return
    end
    inst._my_friend_hand_tool_lock_until = GetTime() + 3
    local action = BufferedAction(inst, nil, work, tool, target.point)
    action.validfn = function()
        return Usable(inst, tool, work)
            and tool.components.inventoryitem:GetGrandOwner() == inst
            and TheWorld.Map:IsFarmableSoilAtPoint(target.point.x, 0, target.point.z)
            and (work ~= ACTIONS.TILL or not SoilOccupied(target.point)
                and TheWorld.Map:CanTillSoilAtPoint(target.point.x, 0, target.point.z, false))
    end
    action:AddSuccessAction(function()
        command.farm_done[target.key] = (command.farm_done[target.key] or 0) + 1
    end)
    action:AddFailAction(function()
        if not action._my_friend_cancelled then command.farm_failed[target.key] = true end
    end)
    return Policy.GuardAction(inst, action, 32)
end

M.IsUsableTool = Usable
return M
