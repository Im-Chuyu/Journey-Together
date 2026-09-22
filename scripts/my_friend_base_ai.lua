local Backpacks = require("my_friend_backpacks")
local EquipSlots = require("my_friend_equip_slots")
local LightAI = require("my_friend_light_ai")
local BehaviourAI = require("my_friend_behavior_ai")
local FoodAI = require("my_friend_food_ai")
local Policy = require("my_friend_policy")
local ResourceMemory = require("my_friend_resource_memory")
local WorldResources = require("my_friend_world_resources")
local Forestry = require("my_friend_forestry")
local Navigation = require("my_friend_navigation")
local InventoryAI = require("my_friend_inventory")
local Garden = require("my_friend_garden")
local Storage = require("my_friend_storage")
local Home = require("my_friend_home")
local CraftingTech = require("my_friend_crafting_tech")
local Reserves = require("my_friend_resource_reserves")
local EquipmentReserves = require("my_friend_equipment_reserves")

local M = {}

M.BASE_STRUCTURE_RANGE = 34
M.BASE_RETURN_DISTANCE = 12
M.BASE_WANDER_RADIUS = 10
-- How far the companion strays from the spot where its leader died.
M.VIGIL_RADIUS = 20
M.RESOURCE_SEARCH_RANGE = 36
M.ACTION_TIMEOUT = 7
M.RETRY_DELAY = 20
M.SEARCH_NODE_ARRIVE_DISTANCE = 8
M.SEARCH_NODE_TIMEOUT = 180
M.SEARCH_STALL_TIMEOUT = 4
M.SEARCH_PROGRESS_DISTANCE = .75
M.SEARCH_NODE_RETRY_DELAY = 600
M.SEARCH_AREA_DWELL_TIME = 35
M.SEARCH_AREA_PROBE_RADIUS = 12
M.WORK_STALL_TIMEOUT = 45
M.MINE_LOOT_RADIUS = 5
M.MINE_LOOT_GRACE_TIME = .75
M.MINE_LOOT_TIMEOUT = 20
M.WORK_LOOT_RETURN_TIMEOUT = 60
M.PROTOTYPER_DISTANCE = 2
M.INVENTORY_FREE_SLOT_RESERVE = 2
M.LOCAL_OPPORTUNITY_RANGE = 12
M.LOCAL_WORK_FREE_SLOTS = 4
M.LOCAL_BATCH_MIN_ACTIONS = 4
M.LOCAL_BATCH_MAX_ACTIONS = 10
M.BASE_FIRE_RANGE = 12
M.BASE_COLD_TEMPERATURE = 20
M.BASE_HOT_TEMPERATURE = 50
M.MAX_GATHER_RECURSION = 3
M.GRID_COLUMNS = 6
M.GRID_ROWS = 10
M.GRID_SPACING = 1.125
M.GARDEN_SPARE_COLUMNS = 2
M.TRANSPLANT_TARGET = 30
M.BASE_SITE_CLEAR_RADIUS = 16
M.BASE_SITE_TRANSPLANT_LIMIT = 6
M.BASE_SITE_CANDIDATE_LIMIT = 12
M.BASE_SITE_RETRY_DELAY = 30
M.BASE_CHEST_COUNT = 4
M.BASE_TREE_TARGET = Forestry.TREE_LIMIT
M.STABLE_LOCAL_COLLECT_CHANCE = 1
M.STABLE_LOCAL_COLLECT_COOLDOWN = 2
M.LOCAL_RESOURCE_MAX = 40
M.BASE_TERRAIN_SAMPLE_RADIUS = 64
M.BASE_TERRAIN_SAMPLE_STEP = 8
M.BASE_TERRAIN_PREFERRED_RATIO = .65
M.BASE_TERRAIN_NODE_HOPS = 3
M.TERRAIN_ROUTE_SAMPLE_STEP = 2
M.RESOURCE_THREAT_RANGE = 8
M.UNSAFE_RESOURCE_RETRY_DELAY = 60

local REQUIRED_STOCK_TARGETS = {
    cutgrass = 20,
    twigs = 20,
    rocks = 20,
    log = 40,
}

local CARRIED_RESERVES = {
    cutgrass = 20,
    twigs = 20,
    rocks = 20,
    flint = 20,
    log = 20,
    goldnugget = 20,
}

local CARRIED_MIN_RESERVES = {
    cutgrass = 2,
    twigs = 2,
}

local GROUND_RESOURCES = {
    boards = true,
    cutstone = true,
    transistor = true,
    cutgrass = true,
    twigs = true,
    rocks = true,
    flint = true,
    log = true,
    goldnugget = true,
    nitre = true,
    pinecone = true,
    acorn = true,
    twiggy_nut = true,
    dug_grass = true,
    dug_sapling = true,
    charcoal = true,
    cutreeds = true,
    poop = true,
    guano = true,
    spoiled_food = true,
    spoiled_fish = true,
    spoiled_fish_small = true,
    silk = true,
    spidergland = true,
    houndstooth = true,
    boneshard = true,
    marble = true,
    moonrocknugget = true,
    ice = true,
    livinglog = true,
}

local EXTRA_MINE_RESOURCES = {
    rock_ice = true,
    rock_ice_temperature = true,
    moonrock_pieces = true,
    moonstorm_glass = true,
    grotto_pool_moonglass = true,
    marbletree = true,
    marblepillar = true,
    marbleshrub = true,
    pond = true,
    rock_light = true,
    rubble = true,
    saltstack = true,
    seastack = true,
    shell_cluster = true,
}

local TRANSPLANT_LOOT = {
    grass = {
        primary = "dug_grass",
        prefabs = { dug_grass = true, cutgrass = true },
    },
    sapling = {
        primary = "dug_sapling",
        prefabs = { dug_sapling = true, twigs = true },
    },
}

local REFINABLE = {
    rope = true,
    boards = true,
    cutstone = true,
    transistor = true,
}

local RECIPE_DEPENDENCY = {
    boards = "researchlab",
    cutstone = "researchlab",
    transistor = "researchlab",
    shovel = "researchlab",
    treasurechest = "researchlab",
    researchlab2 = "researchlab",
    coldfirepit = "researchlab2",
    backpack = "researchlab",
}

local RECIPE_NAMES = {
    axe = "斧头",
    pickaxe = "鹤嘴锄",
    shovel = "铲子",
    hammer = "锤子",
    spear = "长矛",
    armorwood = "木甲",
    boards = "木板",
    cutstone = "石砖",
    transistor = "电子元件",
    researchlab = "科学机器",
    researchlab2 = "炼金引擎",
    backpack = "背包",
    firepit = "火坑",
    coldfirepit = "吸热火坑",
    treasurechest = "箱子",
}

local STRUCTURE_OFFSETS = {
    researchlab = { 0, 0 },
    firepit = { 0, -6 },
    researchlab2 = { 0, -10 },
    coldfirepit = { -5, -6 },
}

local CHEST_OFFSETS = {
    { -2, 0 },
    { -4, 0 },
    { 2, 0 },
    { 4, 0 },
}

local CANT_TAGS = {
    "INLIMBO", "NOCLICK", "catchable", "fire", "heavy", "irreplaceable",
    "mineactive", "outofreach", "playerghost",
}

local OPPORTUNITY_TAGS = {
    "_inventoryitem", "pickable", "readyforharvest", "tree",
    "boulder", "MINE_workable", "DIG_workable",
}

local function DistanceSqToPoint(inst, point)
    local x, _, z = inst.Transform:GetWorldPosition()
    local dx, dz = point.x - x, point.z - z
    return dx * dx + dz * dz
end

local function DistanceSq(a, b)
    return DistanceSqToPoint(a, b:GetPosition())
end

local function IsAlive(inst)
    return inst ~= nil and inst:IsValid()
        and (inst.components.health == nil or not inst.components.health:IsDead())
end

local function CanAct(inst, command)
    return IsAlive(inst) and not inst:HasTag("playerghost")
        and inst.components.inventory ~= nil and inst.components.builder ~= nil
        and not inst._my_friend_backpack_action
        and inst._my_friend_backpack_target == nil
        and (not inst._my_friend_container_action
            or command ~= nil and command.id == "food"
                and inst._my_friend_meal ~= nil
                and inst._my_friend_meal.command == command)
        and not inst._my_friend_storage_action
        and (inst.sg == nil or not inst.sg:HasStateTag("busy"))
end

local function HasLeader(inst)
    local follower = inst.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    return leader ~= nil and leader:IsValid()
end

local function StackSize(item)
    return item ~= nil and item.components.stackable ~= nil
        and item.components.stackable:StackSize() or (item ~= nil and 1 or 0)
end

local function CountInventory(inst, prefab)
    local inventory = inst.components.inventory
    if inventory == nil then return 0 end
    local _, count = inventory:Has(prefab, 9999, true)
    return count or 0
end

function M.SetTask(inst, text)
    if inst ~= nil then
        inst._my_friend_current_task = text
        inst._my_friend_resting_at_base_fire =
            text == "正在使用基地火坑" and true or nil
    end
end

function M.GetTask(inst)
    return inst ~= nil and inst._my_friend_current_task or nil
end

function M.IsCapacityNearlyFull(used, total, reserve)
    return total > 0 and total - used <= (reserve or M.INVENTORY_FREE_SLOT_RESERVE)
end

local function GetInventoryCapacity(inst)
    local inventory = inst.components.inventory
    local used = inventory:NumItems()
    local total = inventory:GetNumSlots()
    local overflow = inventory:GetOverflowContainer()
    if overflow ~= nil then
        used = used + overflow:NumItems()
        total = total + overflow:GetNumSlots()
    end
    return used, total
end

local function IsInventoryNearlyFull(inst)
    local used, total = GetInventoryCapacity(inst)
    return M.IsCapacityNearlyFull(used, total)
end

local function GetFreeSlots(inst)
    local used, total = GetInventoryCapacity(inst)
    return math.max(0, total - used)
end

local HasStorableInventory

local function HasRoomForCarriedPrefab(inst, prefab)
    if GetFreeSlots(inst) > 0 then return true end
    return inst.components.inventory:FindItem(function(item)
        return item.prefab == prefab and item.components.stackable ~= nil
            and not item.components.stackable:IsFull()
    end) ~= nil
end

local function GetChestCapacity(chests)
    local used, total = 0, 0
    for _, chest in ipairs(chests or {}) do
        local container = chest.components ~= nil and chest.components.container or nil
        if container ~= nil then
            used = used + container:NumItems()
            total = total + container:GetNumSlots()
        end
    end
    return used, total
end

function M.ShouldBuildNextChest(chest_count, chest_used, chest_total,
    inventory_nearly_full, has_storable, needs_transplant_storage)
    if (chest_count or 0) >= M.BASE_CHEST_COUNT then return false end
    if (chest_count or 0) == 0 then
        -- The first chest is part of the bootstrap plan. It must exist before
        -- large-scale digging starts, because dug plants are intentionally
        -- kept in the companion's inventory until they are replanted.
        return needs_transplant_storage == true
            or inventory_nearly_full == true or has_storable == true
    end
    return M.IsCapacityNearlyFull(chest_used or 0, chest_total or 0, 2)
        and (inventory_nearly_full == true or has_storable == true)
end

function M.ShouldCollectLocally(free_slots, has_existing_stack, work_action)
    if has_existing_stack then return true end
    local reserve = work_action and M.LOCAL_WORK_FREE_SLOTS
        or M.INVENTORY_FREE_SLOT_RESERVE
    return free_slots > reserve
end

function M.GetOpportunityPriority(kind, distance)
    local priorities = {
        food = 0,
        ground = 0,
        resource = 0,
        mine = 0,
        chop = 0,
        dig = 0,
        basic = 4,
    }
    return (priorities[kind] or 100) + math.max(0, distance or 0)
end

function M.IsDirectionProgress(ix, iz, tx, tz, ex, ez)
    local travel_x, travel_z = tx - ix, tz - iz
    local entity_x, entity_z = ex - ix, ez - iz
    return travel_x * entity_x + travel_z * entity_z >= 0
end

function M.GetLocalBatchLimit(free_slots)
    return math.max(M.LOCAL_BATCH_MIN_ACTIONS,
        math.min(M.LOCAL_BATCH_MAX_ACTIONS, math.floor((free_slots or 0) / 2)))
end

local function IsOwnedStructure(entity)
    return entity ~= nil and entity:IsValid()
        and entity._my_friend_base_structure == true
end

local function FindStructures(inst, prefab)
    local base = M.GetBasePoint(inst)
    if base == nil then return {} end
    local result = {}
    for _, entity in ipairs(TheSim:FindEntities(base.x, base.y, base.z,
        M.BASE_STRUCTURE_RANGE, nil, { "INLIMBO", "burnt" })) do
        if IsOwnedStructure(entity) and (prefab == nil or entity.prefab == prefab) then
            table.insert(result, entity)
        end
    end
    return result
end

local function FindStructure(inst, prefab)
    local closest, closest_distance
    for _, entity in ipairs(FindStructures(inst, prefab)) do
        local distance = DistanceSq(inst, entity)
        if closest_distance == nil or distance < closest_distance then
            closest, closest_distance = entity, distance
        end
    end
    return closest
end

local function FindOwnedChests(inst)
    return FindStructures(inst, "treasurechest")
end

function M.GetStockCapacity(inst, prefab)
    local capacity = 0
    for _, chest in ipairs(FindOwnedChests(inst)) do
        local container = chest.components.container
        if container ~= nil and not container.readonlycontainer
            and not container:IsRestricted(inst) and not container:IsOpenedByOthers(inst) then
            for slot = 1, container:GetNumSlots() do
                local item = container.slots[slot]
                if item == nil then
                    -- A conservative empty-slot budget for ordinary base materials.
                    capacity = capacity + 20
                elseif (prefab == nil or item.prefab == prefab)
                    and item.components.stackable ~= nil then
                    capacity = capacity + math.max(0, item.components.stackable:RoomLeft())
                end
            end
        end
    end
    return capacity
end

function M.IsStockStorageFull(inst)
    return M.IsComplete(inst) and M.GetStockCapacity(inst) <= 0
end

local function GetLayoutOrigin(inst)
    local researchlab = FindStructure(inst, "researchlab")
    return researchlab ~= nil and researchlab:GetPosition() or M.GetBasePoint(inst)
end

local function CountContainerPrefab(container, prefab)
    local count = 0
    if container ~= nil then
        for _, item in pairs(container.slots or {}) do
            if item.prefab == prefab then count = count + StackSize(item) end
        end
    end
    return count
end

function M.CountBaseStock(inst, prefab)
    local count = CountInventory(inst, prefab)
    for _, chest in ipairs(FindOwnedChests(inst)) do
        count = count + CountContainerPrefab(chest.components.container, prefab)
    end
    return count
end

-- Resources available to the companion include both carried items and owned
-- storage. Crafting and survival decisions should use the same total.
function M.CountAvailableStock(inst, prefab)
    return M.CountBaseStock(inst, prefab)
end

function M.CountBaseStoredStock(inst, prefab)
    local count = 0
    for _, chest in ipairs(FindOwnedChests(inst)) do
        count = count + CountContainerPrefab(chest.components.container, prefab)
    end
    return count
end

function M.AreRequiredStocksMet(stocks)
    for prefab, target in pairs(REQUIRED_STOCK_TARGETS) do
        if (stocks[prefab] or 0) < target then return false end
    end
    return true
end

function M.UpdateStockNeed(count, target)
    return math.max(0, (target or 0) - (count or 0))
end

function M.IsExtremeSeasonState(iswinter, issummer, hasthermalstone)
    return not hasthermalstone and (iswinter or issummer)
end

local function HasThermalStone(inst)
    return inst.components.inventory:FindItem(function(item)
        return item.prefab == "heatrock" or item:HasTag("heatrock")
    end) ~= nil
end

function M.IsExtremeSeason(inst)
    return TheWorld ~= nil and TheWorld.state ~= nil
        and M.IsExtremeSeasonState(TheWorld.state.iswinter == true,
            TheWorld.state.issummer == true, HasThermalStone(inst))
end

function M.GetBasePoint(inst)
    local data = inst._my_friend_base
    return data ~= nil and data.x ~= nil and Vector3(data.x, 0, data.z) or nil
end

local function IsPassable(point)
    return TheWorld.Map:IsPassableAtPoint(point.x, point.y, point.z)
        and not Navigation.IsNearHole(point)
end

function M.IsPreferredBaseTile(tile, tiles)
    tiles = tiles or WORLD_TILES
    return tiles ~= nil and (tile == tiles.SAVANNA
        or tile == tiles.GRASS or tile == tiles.DECIDUOUS)
end

function M.GetTerrainDomainAtPoint(x, y, z)
    if TheWorld == nil or TheWorld.Map == nil then return "blocked" end
    local map = TheWorld.Map
    if map.IsOceanTileAtPoint ~= nil and map:IsOceanTileAtPoint(x, y, z) then
        return "water"
    end
    if map.IsLandTileAtPoint ~= nil and map:IsLandTileAtPoint(x, y, z) then
        return "land"
    end
    return "blocked"
end

function M.IsPreferredBaseRegion(preferred_count, total_count, ocean_count)
    return total_count > 0 and (ocean_count or 0) == 0
        and preferred_count / total_count >= M.BASE_TERRAIN_PREFERRED_RATIO
end

local function IsResourceThreat(inst, entity, active_work)
    return BehaviourAI.IsThreat(inst, entity)
end

local function IsResourceUnsafe(inst, target, active_work)
    if require("my_friend_resource_safety").IsBlocked(inst, target) then return true end
    if target == nil or target.Transform == nil then return false end
    local x, y, z = target.Transform:GetWorldPosition()
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, M.RESOURCE_THREAT_RANGE,
        { "_combat" }, CANT_TAGS)) do
        if IsResourceThreat(inst, entity, active_work) then return true end
    end
    return false
end

function M.IsBaseEnvironmentClear(structure_count, transplanted_count)
    return (structure_count or 0) == 0
        and (transplanted_count or 0) < M.BASE_SITE_TRANSPLANT_LIMIT
end

local function CountTransplantedPlants(point)
    local count = 0
    for _, entity in ipairs(TheSim:FindEntities(point.x, point.y, point.z,
        M.BASE_SITE_CLEAR_RADIUS, nil, { "INLIMBO", "FX", "NOCLICK" })) do
        local pickable = entity.components ~= nil and entity.components.pickable or nil
        if pickable ~= nil and pickable.transplanted then
            count = count + 1
            if count >= M.BASE_SITE_TRANSPLANT_LIMIT then return count end
        end
    end
    return count
end

local function GetTopologyNodePoint(node)
    local x = node ~= nil and (node.x or node.cent ~= nil and node.cent[1]) or nil
    local z = node ~= nil and (node.y or node.cent ~= nil and node.cent[2]) or nil
    return type(x) == "number" and type(z) == "number"
        and Vector3(x, 0, z) or nil
end

local function BasePointScore(inst, point)
    if not IsPassable(point) then return end
    local preferred, total, ocean = 0, 0, 0
    local radius, step = 24, 6
    for dx = -radius, radius, step do
        for dz = -radius, radius, step do
            if dx * dx + dz * dz <= radius * radius then
                local sample = Vector3(point.x + dx, 0, point.z + dz)
                total = total + 1
                local tile = TheWorld.Map:GetTileAtPoint(sample.x, sample.y, sample.z)
                if M.IsPreferredBaseTile(tile) then preferred = preferred + 1 end
                if TheWorld.Map.IsOceanTileAtPoint ~= nil
                    and TheWorld.Map:IsOceanTileAtPoint(sample.x, sample.y, sample.z) then
                    ocean = ocean + 1
                end
            end
        end
    end
    local structures = TheSim:FindEntities(point.x, point.y, point.z,
        M.BASE_SITE_CLEAR_RADIUS, nil, { "INLIMBO", "FX", "NOCLICK" },
        { "structure", "wall" })
    local transplanted = CountTransplantedPlants(point)
    if not M.IsBaseEnvironmentClear(#structures, transplanted) then return end
    local blocked = TheSim:FindEntities(point.x, point.y, point.z, 10,
        nil, { "INLIMBO", "FX", "NOCLICK" },
        { "structure", "tree", "boulder", "wall", "blocker" })
    local region = WorldResources.RegionAtPoint(point.x, point.z)
    local region_bonus = region ~= nil and
        (region.kind == "grass" or region.kind == "savanna"
            or region.kind == "deciduous") and -18 or
        region ~= nil and (region.kind == "marsh" or region.kind == "rocky") and 12 or 0
    local score = #blocked * 2 + region_bonus + ocean * .5
        - preferred / math.max(1, total) * 10
    for _, radius in ipairs({ 4, 7, 10 }) do
        for index = 0, 7 do
            local angle = index * PI2 / 8
            local sample = Vector3(point.x + math.cos(angle) * radius, 0,
                point.z + math.sin(angle) * radius)
            if not IsPassable(sample) then score = score + 20 end
        end
    end
    -- Validate the actual construction footprint, not the purity of a biome.
    local slots = {
        {"researchlab", 0, 0}, {"treasurechest", -2, 0},
        {"treasurechest", -4, 0}, {"treasurechest", 2, 0},
        {"treasurechest", 4, 0}, {"firepit", 0, -6},
    }
    for _, slot in ipairs(slots) do
        local p = Vector3(point.x + slot[2], 0, point.z + slot[3])
        local recipe = GetValidRecipe(slot[1])
        if not IsPassable(p) or recipe ~= nil
            and not TheWorld.Map:CanDeployRecipeAtPoint(p, recipe, 0, inst) then return end
    end
    for index = 1, M.TRANSPLANT_TARGET * 2 do
        local dx, dz = M.GetGridCoordinates(index)
        local p = Vector3(point.x + dx, 0, point.z + dz)
        if not IsPassable(p) then return end
    end
    for _, entity in ipairs(TheSim:FindEntities(point.x, 0, point.z, 24,
        nil, {"INLIMBO", "FX", "NOCLICK"}, {"hostile", "monster", "spiderden", "houndmound"})) do
        if entity ~= inst then return end
    end
    return score
end

function M.FindBasePoint(inst)
    local origin = inst:GetPosition()
    local best, best_score, valid_sites = nil, nil, 0
    local anchors = { origin }
    local topology = TheWorld ~= nil and TheWorld.topology or nil
    if topology ~= nil and topology.nodes ~= nil then
        for _, node in pairs(topology.nodes) do
            local x = node ~= nil and (node.x or node.cent ~= nil and node.cent[1]) or nil
            local z = node ~= nil and (node.y or node.cent ~= nil and node.cent[2]) or nil
            if type(x) == "number" and type(z) == "number" then
                anchors[#anchors + 1] = Vector3(x, 0, z)
            end
        end
    end
    table.sort(anchors, function(a, b)
        local adx, adz = a.x - origin.x, a.z - origin.z
        local bdx, bdz = b.x - origin.x, b.z - origin.z
        return adx * adx + adz * adz < bdx * bdx + bdz * bdz
    end)
    for anchor_index, anchor in ipairs(anchors) do
        if anchor_index > 80 then break end
        for sample = 0, 32 do
            local radius = sample == 0 and 0 or math.ceil(sample / 8) * 6
            local angle = sample == 0 and 0 or (sample - 1) % 8 * PI2 / 8
            local point = Vector3(anchor.x + math.cos(angle) * radius, 0,
                anchor.z + math.sin(angle) * radius)
            local score = BasePointScore(inst, point)
            if score ~= nil then
                valid_sites = valid_sites + 1
                local dx, dz = point.x - origin.x, point.z - origin.z
                score = score + math.sqrt(dx * dx + dz * dz) * .2
                if best_score == nil or score < best_score then
                    best, best_score = point, score
                end
            end
        end
        if valid_sites >= M.BASE_SITE_CANDIDATE_LIMIT then break end
    end
    return best
end

-- Distance at which the companion decides it has strayed from home.
function M.GetBaseReturnDistance(inst)
    return Home.Get(inst) ~= nil and Home.RETURN_DISTANCE or M.BASE_RETURN_DISTANCE
end

function M.EnsureBase(inst)
    -- A manually chosen home replaces the automatic site, and a companion that
    -- joined an old world never looks for one at all.
    if Home.Get(inst) ~= nil then
        if inst._my_friend_base == nil or not inst._my_friend_base.manual then
            Home.Apply(inst)
        end
        return M.GetBasePoint(inst)
    end
    if Home.IsLateJoin(inst) then
        -- Settle wherever we are instead of laying out a base. This also
        -- covers arriving on a shard that has no home recorded yet. "roam"
        -- still lets the companion leave to forage when food runs out.
        Home.Set(inst, inst:GetPosition(), "roam")
        return M.GetBasePoint(inst)
    end
    local state = inst._my_friend_base
    if state ~= nil and state.site_version ~= 2 then
        -- Keep built bases. Only reconsider an old, unbuilt, obstructed site.
        local oldpoint = M.GetBasePoint(inst)
        if oldpoint ~= nil and FindStructure(inst, "researchlab") == nil
            and #FindOwnedChests(inst) == 0 and BasePointScore(inst, oldpoint) == nil then
            inst._my_friend_base = nil
        else
            state.site_version = 2
        end
    end
    if inst._my_friend_base == nil then
        local now = GetTime()
        if (inst._my_friend_base_site_retry or 0) > now then return end
        local point = M.FindBasePoint(inst)
        if point == nil then
            inst._my_friend_base_site_retry = now + M.BASE_SITE_RETRY_DELAY
            return
        end
        inst._my_friend_base_site_retry = nil
        inst._my_friend_base = {
            x = point.x,
            z = point.z,
            planted_grass = 0,
            planted_sapling = 0,
            site_version = 2,
        }
    end
    return M.GetBasePoint(inst)
end

function M.ShouldReturnToBase(inst)
    if HasLeader(inst) then return false end
    local base = M.GetBasePoint(inst)
    local limit = M.GetBaseReturnDistance(inst)
    if base == nil or DistanceSqToPoint(inst, base) <= limit * limit then
        return false
    end
    -- A player chosen home is always walked back to, whatever the season.
    if Home.IsStrict(inst) then return true end
    if not M.IsComplete(inst) then return false end
    if M.IsExtremeSeason(inst) then return true end
    return IsInventoryNearlyFull(inst) and #FindOwnedChests(inst) > 0
        and HasStorableInventory ~= nil and HasStorableInventory(inst)
end

local function MoveAction(inst, point, on_success)
    local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point)
    if on_success ~= nil then action:AddSuccessAction(on_success) end
    return action
end

local function MoveNearEntityAction(inst, target, distance)
    local action = BufferedAction(inst, target, ACTIONS.WALKTO)
    action.arrivedist = distance
    return action
end

function M.GetReturnAction(inst)
    if not CanAct(inst) or not M.ShouldReturnToBase(inst) then return end
    M.SetTask(inst, IsInventoryNearlyFull(inst)
        and "物品栏快满了，正在返回基地整理物资" or "正在返回基地")
    if inst._my_friend_base ~= nil then
        inst._my_friend_base.resource_search = nil
    end
    local action = MoveAction(inst, M.GetBasePoint(inst))
    action.arrivedist = M.GetBaseReturnDistance(inst) - 2
    return action
end

local function IsBlocked(inst, target)
    if require("my_friend_resource_safety").IsBlocked(inst, target) then return true end
    if target.Transform ~= nil and Navigation.IsBlocked(inst, target:GetPosition()) then return true end
    local blocked = inst._my_friend_base_blocked
    local deadline = blocked ~= nil and blocked[target.GUID or target] or nil
    if deadline ~= nil and GetTime() >= deadline then
        blocked[target.GUID or target] = nil
        deadline = nil
    end
    return deadline ~= nil
end

function M.PruneExpiredEntries(entries, now)
    if entries == nil then return 0 end
    local remaining = 0
    for key, deadline in pairs(entries) do
        if type(deadline) ~= "number" or deadline <= now then
            entries[key] = nil
        else
            remaining = remaining + 1
        end
    end
    return remaining
end

local function TimedAction(inst, target, action_type, invobject, point, preserve_work_target)
    local travel = target ~= nil and math.sqrt(DistanceSq(inst, target)) / 3 or 0
    local deadline = GetTime() + M.ACTION_TIMEOUT + travel
    local action = BufferedAction(inst, target, action_type, invobject, point)
    action.validfn = function()
        local allowed_until = math.max(deadline, action._my_friend_travel_until or 0,
            (action._my_friend_travel_finished or 0) + M.ACTION_TIMEOUT)
        return GetTime() < allowed_until and target ~= nil and target:IsValid()
    end
    action:AddFailAction(function()
        if action._my_friend_cancelled then return end
        if inst:IsValid() and target ~= nil then
            local workable = target:IsValid() and target.components ~= nil
                and target.components.workable or nil
            if preserve_work_target and inst._my_friend_work_target == target
                and not action._my_friend_path_failed
                and workable ~= nil and workable:CanBeWorked()
                and GetTime() < (inst._my_friend_work_stall_deadline or 0) then
                return
            end
            inst._my_friend_base_blocked = inst._my_friend_base_blocked or {}
            inst._my_friend_base_blocked[target.GUID or target] = GetTime() + M.RETRY_DELAY
        end
    end)
    action:AddSuccessAction(function()
        if inst._my_friend_base_blocked ~= nil and target ~= nil then
            inst._my_friend_base_blocked[target.GUID or target] = nil
        end
    end)
    return action
end

local function CanPickUp(inst, item, needed)
    local inventoryitem = item.components ~= nil and item.components.inventoryitem or nil
    return inventoryitem ~= nil and inventoryitem.owner == nil
        and inventoryitem.canbepickedup and not item:IsInLimbo()
        and (needed or not item._my_friend_discarded)
        and (needed or not Policy.IsBaseCacheItem(inst, item))
        and inst.components.inventory:CanAcceptCount(item, 1) > 0
end

local function GetNeededGroundAction(inst, needs, radius, include_cache)
    if needs == nil or next(needs) == nil then return end
    local x, y, z, range = Policy.SearchOrigin(inst, radius or M.RESOURCE_SEARCH_RANGE)
    local best, best_distance
    for _, item in ipairs(TheSim:FindEntities(x, y, z, range,
        {"_inventoryitem"}, CANT_TAGS)) do
        local inside_season_base = HasLeader(inst) or not M.IsComplete(inst)
            or not M.IsExtremeSeason(inst)
            or DistanceSqToPoint(item, M.GetBasePoint(inst)) <= M.BASE_RETURN_DISTANCE^2
        if (needs[item.prefab] or 0) > 0
            and inside_season_base
            and CanPickUp(inst, item, include_cache ~= false)
            and Policy.InRange(inst, item) and not IsBlocked(inst, item)
            and not IsResourceUnsafe(inst, item) then
            local distance = DistanceSq(inst, item)
            if best_distance == nil or distance < best_distance then
                best, best_distance = item, distance
            end
        end
    end
    if best ~= nil then
        M.SetTask(inst, "正在拾取地上需要的材料")
        return TimedAction(inst, best, ACTIONS.PICKUP)
    end
end

local function FindTool(inst, work_action)
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if InventoryAI.IsUsableTool(inst, item, work_action) then return item end
    end
end

-- EnsureRecipe only ever looks for a finished tool in the inventory and in
-- chests. A hammer lying on the ground -- very often the companion's own, in
-- the pile it dropped when it died -- is closer than any crafting trip.
local function GetGroundToolAction(inst, work_action)
    local x, y, z, range = Policy.SearchOrigin(inst, M.RESOURCE_SEARCH_RANGE)
    local best, best_distance
    for _, item in ipairs(TheSim:FindEntities(x, y, z, range,
        {"_inventoryitem"}, CANT_TAGS)) do
        if InventoryAI.IsUsableTool(inst, item, work_action)
            and CanPickUp(inst, item, true)
            and Policy.InRange(inst, item) and not IsBlocked(inst, item)
            and not IsResourceUnsafe(inst, item) then
            local distance = DistanceSq(inst, item)
            if best_distance == nil or distance < best_distance then
                best, best_distance = item, distance
            end
        end
    end
    if best ~= nil then return TimedAction(inst, best, ACTIONS.PICKUP) end
end

local function EquipTool(inst, tool)
    if tool == nil then return false end
    if inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS) ~= tool then
        return inst.components.inventory:Equip(tool) == true
    end
    return true
end

local function IngredientCount(inst, ingredient)
    return CountInventory(inst, ingredient.type)
end

local function IsNearStructure(inst, prefab, distance)
    local structure = FindStructure(inst, prefab)
    return structure ~= nil and DistanceSq(inst, structure) <= (distance or 6) ^ 2, structure
end

function M.GetStructureOffset(recipe_name, ordinal)
    local offset = recipe_name == "treasurechest"
        and CHEST_OFFSETS[math.min(math.max(ordinal or 1, 1), #CHEST_OFFSETS)]
        or STRUCTURE_OFFSETS[recipe_name] or { 0, 0 }
    return offset[1], offset[2]
end

local function FindBuildPoint(inst, recipe_name)
    local base = M.GetBasePoint(inst)
    local recipe = GetValidRecipe(recipe_name)
    local offset_x, offset_z = M.GetStructureOffset(recipe_name, 1)
    local anchor = recipe_name == "researchlab" and base or GetLayoutOrigin(inst)
    if recipe_name == "treasurechest" then
        local chests = FindOwnedChests(inst)
        offset_x, offset_z = M.GetStructureOffset(recipe_name, #chests + 1)
    end
    local origin = Vector3(anchor.x + offset_x, 0, anchor.z + offset_z)
    local function Available(point)
        return not Navigation.IsBlocked(inst, point)
            and TheWorld.Map:CanDeployRecipeAtPoint(point, recipe, 0, inst)
    end
    if Available(origin) then return origin end
    if recipe_name == "researchlab" then
        -- Before the first building exists, move the whole layout together.
        local replacement = M.FindBasePoint(inst)
        if replacement ~= nil and Available(replacement) then
            inst._my_friend_base.x, inst._my_friend_base.z = replacement.x, replacement.z
            return replacement
        end
        return
    end
    if recipe_name == "treasurechest" then
        local direction = offset_x < 0 and -1 or 1
        for distance = math.abs(offset_x) + 2, 10, 2 do
            local point = Vector3(anchor.x + direction * distance, 0, anchor.z)
            if Available(point) then
                return point
            end
        end
        return
    end
    for radius = 2, 10, 2 do
        for index = 0, 15 do
            local angle = index * PI2 / 16
            local point = Vector3(origin.x + math.cos(angle) * radius, 0,
                origin.z + math.sin(angle) * radius)
            if (recipe_name ~= "firepit" or point.z <= anchor.z - 4)
                and Available(point) then
                return point
            end
        end
    end
end

local function CreateBuildAction(inst, recipe_name, point, track_pending)
    local retry = inst._my_friend_build_retry or {}
    inst._my_friend_build_retry = retry
    M.PruneExpiredEntries(retry, GetTime())
    if retry[recipe_name] ~= nil then return end
    local recipe = GetValidRecipe(recipe_name)
    if recipe == nil or not inst.components.builder:HasIngredients(recipe) then return end
    if inst.components.builder.EvaluateTechTrees ~= nil then
        inst.components.builder:EvaluateTechTrees()
    end
    if not CraftingTech.CanBuild(inst, recipe) then
        local station, distance = CraftingTech.FindStation(inst, recipe, M.BASE_STRUCTURE_RANGE)
        if station == nil or IsBlocked(inst, station) then return end
        if distance > M.PROTOTYPER_DISTANCE^2 then
            if track_pending ~= false then inst._my_friend_pending_recipe = recipe_name end
            local approach = MoveNearEntityAction(inst, station, M.PROTOTYPER_DISTANCE - .5)
            approach:AddFailAction(function()
                if approach._my_friend_cancelled then return end
                retry[recipe_name] = GetTime() + M.RETRY_DELAY
                if inst._my_friend_pending_recipe == recipe_name then inst._my_friend_pending_recipe = nil end
            end)
            return approach
        end
        if not CraftingTech.Activate(inst, station, recipe) then return end
    end
    if point == nil then
        point = recipe.placer ~= nil and FindBuildPoint(inst, recipe_name) or nil
        if recipe.placer == nil then point = inst:GetPosition() end
    end
    if point == nil then return end
    local action = BufferedAction(inst, nil, ACTIONS.MY_FRIEND_BUILD or ACTIONS.BUILD,
        nil, point, recipe.name, recipe.build_distance)
    M.SetTask(inst, "正在制作"..(RECIPE_NAMES[recipe_name] or recipe_name))
    action:AddSuccessAction(CraftingTech.OnBuilt(inst, recipe))
    action:AddSuccessAction(function()
        retry[recipe_name] = nil
        if inst._my_friend_pending_recipe == recipe_name then
            inst._my_friend_pending_recipe = nil
        end
        -- Prototyper trips resume through the shared recipe planner too.
        -- Claim the bag here so every build path completes the same way.
        if recipe_name == "backpack" then
            local inventory = inst.components.inventory
            local item = EquipSlots.GetBackpack(inventory)
                or inventory:FindItem(function(value) return value.prefab == "backpack" end)
            if item ~= nil then
                Backpacks.MarkOwned(inst, item)
                if not EquipSlots.IsEquipped(inventory, item) then inventory:Equip(item) end
            end
        end
    end)
    action:AddFailAction(function()
        if action._my_friend_cancelled then return end
        retry[recipe_name] = GetTime() + M.RETRY_DELAY
        if recipe.placer ~= nil and action._my_friend_path_failed then
            -- Keep the failed site blocked beyond the recipe retry, otherwise
            -- both timers expire together and the same site wins again.
            Navigation.Block(inst, point, false)
        end
        if inst._my_friend_pending_recipe == recipe_name then inst._my_friend_pending_recipe = nil end
    end)
    action.validfn = function(act)
        if not inst.components.builder:HasIngredients(recipe) then return false end
        inst.components.builder:EvaluateTechTrees()
        local action_point = act:GetActionPoint()
        return CraftingTech.CanBuild(inst, recipe)
            and (recipe.placer == nil or action_point ~= nil
            and TheWorld.Map:CanDeployRecipeAtPoint(action_point, recipe, act.rotation or 0, inst)
            )
    end
    return action
end

function M.NeedsPrototyper(knows_recipe, dependency)
    return dependency ~= nil and not knows_recipe
end

local function MergeMissing(target, source)
    for prefab, amount in pairs(source or {}) do
        target[prefab] = (target[prefab] or 0) + amount
    end
end

local GetWithdrawAction

local function RecipeHasIngredients(inst, recipe, reserve)
    if reserve == nil then return inst.components.builder:HasIngredients(recipe) end
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        local required = math.max(1, math.ceil(ingredient.amount
            * (inst.components.builder.ingredientmod or 1)))
        if IngredientCount(inst, ingredient) - (reserve[ingredient.type] or 0) < required then
            return false
        end
    end
    return true
end

local function EnsureRecipe(inst, recipe_name, point, depth, wanted_count, allow_gather, reserve)
    depth = depth or 0
    wanted_count = wanted_count or 1
    if depth > 5 then return nil, {} end
    local recipe = GetValidRecipe(recipe_name)
    if recipe == nil then return nil, {} end
    local work_action = recipe_name == "axe" and ACTIONS.CHOP
        or recipe_name == "pickaxe" and ACTIONS.MINE
        or recipe_name == "shovel" and ACTIONS.DIG
        or recipe_name == "hammer" and ACTIONS.HAMMER or nil
    if work_action ~= nil then
        inst._my_friend_tool_needs = inst._my_friend_tool_needs or {}
        inst._my_friend_tool_needs[work_action.id] = GetTime() + 90
        if FindTool(inst, work_action) == nil then
            local stored_exists = false
            local chests = FindOwnedChests(inst)
            if HasLeader(inst) then
                local x, y, z, range = Policy.SearchOrigin(inst, 20)
                chests = TheSim:FindEntities(x, y, z, range, {"chest"}, {"INLIMBO", "burnt"})
            end
            for _, chest in ipairs(chests) do
                local container = chest.components.container
                local available = container ~= nil and not container.readonlycontainer
                    and not container:IsRestricted(inst) and not container:IsOpenedByOthers(inst)
                    and InventoryAI.StorageReady(inst, chest) and not IsBlocked(inst, chest)
                for _, item in pairs(available and container.slots or {}) do
                    if InventoryAI.IsUsableTool(inst, item, work_action) then
                        stored_exists = true
                        local stored = GetWithdrawAction(inst, {[item.prefab] = 1}, work_action)
                        if stored ~= nil then return stored, nil end
                    end
                end
            end
            if stored_exists then
                M.SetTask(inst, "已有工作工具，正在等待取用箱子或腾出空间")
                return M.GetInventoryReliefAction(inst), {}
            end
        end
        if not HasLeader(inst) and not inst._my_friend_recover_death_drops and M.IsStockStorageFull(inst)
            and not inst.components.builder:HasIngredients(recipe) then return nil, {} end
    end
    if wanted_count <= 1 and RecipeHasIngredients(inst, recipe, reserve) then
        return CreateBuildAction(inst, recipe_name, point), nil
    end

    local ingredient_needs = {}
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        local required = math.max(1, math.ceil(ingredient.amount
            * (inst.components.builder.ingredientmod or 1))) * wanted_count
        local short = required - math.max(0, IngredientCount(inst, ingredient)
            - (reserve ~= nil and reserve[ingredient.type] or 0))
        if short > 0 then ingredient_needs[ingredient.type] = short end
    end
    if allow_gather ~= false then
        local ground = GetNeededGroundAction(inst, ingredient_needs)
        if ground ~= nil then return ground, nil end
    end
    local base = inst._my_friend_base
    if base ~= nil and base.cache_x ~= nil then
        for _, item in ipairs(TheSim:FindEntities(base.cache_x, 0, base.cache_z,
            3, {"_inventoryitem"}, CANT_TAGS)) do
            if allow_gather ~= false and ingredient_needs[item.prefab] ~= nil and CanPickUp(inst, item, true)
                and Policy.InRange(inst, item) and not IsBlocked(inst, item) then
                M.SetTask(inst, "正在取回基地暂存的制作材料")
                return TimedAction(inst, item, ACTIONS.PICKUP), nil
            end
        end
    end
    local direct_withdraw = GetWithdrawAction(inst, ingredient_needs)
    if direct_withdraw ~= nil then return direct_withdraw, nil end

    local missing = {}
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        local required_per_build = math.max(1, math.ceil(ingredient.amount
            * (inst.components.builder.ingredientmod or 1)))
        local required = required_per_build * wanted_count
        local inventory_count = math.max(0, IngredientCount(inst, ingredient)
            - (reserve ~= nil and reserve[ingredient.type] or 0))
        if inventory_count < required then
            if REFINABLE[ingredient.type] then
                local child_recipe = GetValidRecipe(ingredient.type)
                local amount_given = child_recipe ~= nil and child_recipe.numtogive or 1
                local child_count = math.ceil((required - inventory_count)
                    / math.max(1, amount_given))
                local action, child_missing = EnsureRecipe(inst, ingredient.type, nil,
                    depth + 1, child_count, allow_gather, reserve)
                if action ~= nil then return action end
                MergeMissing(missing, child_missing)
            else
                missing[ingredient.type] = required - inventory_count
            end
        end
    end
    if next(missing) ~= nil then
        local withdraw = GetWithdrawAction(inst, missing)
        if withdraw ~= nil then return withdraw, nil end
    end
    if next(missing) == nil then
        return CreateBuildAction(inst, recipe_name, point), nil
    end
    return nil, missing
end

local function FindChestItems(inst, needs, work_action)
    local chests = FindOwnedChests(inst)
    if HasLeader(inst) then
        local x, y, z, range = Policy.SearchOrigin(inst, 20)
        chests = TheSim:FindEntities(x, y, z, range, {"chest"}, {"INLIMBO", "burnt"})
    end
    for _, chest in ipairs(chests) do
        local container = chest.components.container
        if container ~= nil and not container.readonlycontainer
            and not container:IsRestricted(inst) and not container:IsOpenedByOthers(inst)
            and not IsBlocked(inst, chest) then
            local remaining = {}
            for prefab, amount in pairs(needs or {}) do remaining[prefab] = amount end
            local plan = {}
            for _, item in pairs(container.slots or {}) do
                local amount = remaining[item.prefab] or 0
                if amount > 0 and not item.components.inventoryitem.islockedinslot then
                    local equip = item.components.equippable
                    local usable = work_action == nil
                        or InventoryAI.IsUsableTool(inst, item, work_action)
                    local count = math.min(StackSize(item), amount,
                        inst.components.inventory:CanAcceptCount(item, amount))
                    if usable and work_action ~= nil and equip ~= nil
                        and inst.components.inventory:GetEquippedItem(equip.equipslot) == nil
                        and M.CanUseHandToolInCurrentLight(inst) then count = 1 end
                    if usable and count > 0 then
                        plan[#plan + 1] = { item = item, count = count }
                        remaining[item.prefab] = amount - count
                    end
                end
            end
            if #plan > 0 then return chest, plan end
        end
    end
end

GetWithdrawAction = function(inst, needs, work_action)
    if inst._my_friend_storage_action then return end
    local chest, plan = FindChestItems(inst, needs, work_action)
    local item = plan ~= nil and plan[1].item or nil
    if chest == nil or ACTIONS.MY_FRIEND_WITHDRAW == nil then return end
    M.SetTask(inst, work_action ~= nil and "正在从箱子取出工作工具" or "正在从箱子取制作材料")
    local action = TimedAction(inst, chest, ACTIONS.MY_FRIEND_WITHDRAW)
    action._my_friend_withdraw_plan = plan
    action._my_friend_equip_tool = work_action
    inst._my_friend_storage_action = action
    action:AddFailAction(function()
        if inst:IsValid() and inst._my_friend_storage_action == action then
            inst._my_friend_storage_action = nil
        end
    end)
    return action
end

local function NeedAny(needs, ...)
    for index = 1, select("#", ...) do
        if needs[select(index, ...)] ~= nil then return true end
    end
    return false
end

local function HasText(value, pattern)
    return type(value) == "string" and value:lower():find(pattern, 1, true) ~= nil
end

function M.GetTerrainAffinity(topology_id, needs)
    topology_id = type(topology_id) == "string" and topology_id:lower() or ""
    needs = needs or {}
    local score = 0
    if NeedAny(needs, "rocks", "flint", "goldnugget", "nitre") then
        if HasText(topology_id, "rocky") then score = score + 16 end
        if HasText(topology_id, "badland") then score = score + 12 end
        if HasText(topology_id, "bare") then score = score + 10 end
        if HasText(topology_id, "desert") then score = score + 8 end
        if HasText(topology_id, "mosaic") then score = score + 7 end
        if HasText(topology_id, "meteor") then score = score + 6 end
        if needs.flint ~= nil and (HasText(topology_id, "grass")
            or HasText(topology_id, "savanna")) then score = score + 3 end
    end
    if needs.goldnugget ~= nil then
        if HasText(topology_id, "rocky") then score = score + 8 end
        if HasText(topology_id, "badland") then score = score + 5 end
    end
    if needs.log ~= nil or needs.pinecone ~= nil or needs.acorn ~= nil then
        if HasText(topology_id, "forest") then score = score + 12 end
        if HasText(topology_id, "deciduous") then score = score + 11 end
        if HasText(topology_id, "crappy") then score = score + 5 end
        if HasText(topology_id, "spider") then score = score + 2 end
        if needs.pinecone ~= nil and HasText(topology_id, "forest") then
            score = score + 8
        end
        if needs.acorn ~= nil and HasText(topology_id, "deciduous") then
            score = score + 10
        end
    end
    if NeedAny(needs, "cutgrass", "twigs", "dug_grass", "dug_sapling") then
        if HasText(topology_id, "grass") then score = score + 14 end
        if HasText(topology_id, "savanna") then score = score + 12 end
        if HasText(topology_id, "plain") and not HasText(topology_id, "bare") then
            score = score + 8
        end
        if HasText(topology_id, "mosaic") then score = score + 6 end
        if HasText(topology_id, "forest") and (needs.twigs or needs.dug_sapling) then
            score = score + 4
        end
    end
    if needs.cutreeds ~= nil and HasText(topology_id, "marsh") then
        score = score + 18
    end
    if needs.food ~= nil then
        if HasText(topology_id, "grass") then score = score + 14 end
        if HasText(topology_id, "deciduous") then score = score + 12 end
        if HasText(topology_id, "forest") then score = score + 8 end
        if HasText(topology_id, "savanna") then score = score + 5 end
    end
    if HasText(topology_id, "ocean") then score = score - 20 end
    return score
end

function M.GetNeedKey(needs)
    local names = {}
    for prefab in pairs(needs or {}) do table.insert(names, prefab) end
    table.sort(names)
    return table.concat(names, ",")
end

local function NodePoint(node)
    local x = node ~= nil and (node.x or node.cent ~= nil and node.cent[1]) or nil
    local z = node ~= nil and (node.y or node.cent ~= nil and node.cent[2]) or nil
    return type(x) == "number" and type(z) == "number" and Vector3(x, 0, z) or nil
end

local function IsSearchNodeBlocked(inst, index)
    local blocked = inst._my_friend_search_nodes
    local deadline = blocked ~= nil and blocked[index] or nil
    if deadline ~= nil and GetTime() >= deadline then
        blocked[index] = nil
        deadline = nil
    end
    return deadline ~= nil
end

local function BlockSearchNode(inst, index)
    inst._my_friend_search_nodes = inst._my_friend_search_nodes or {}
    inst._my_friend_search_nodes[index] = GetTime() + M.SEARCH_NODE_RETRY_DELAY
end

local function MarkVisitedNode(inst, index)
    if index == nil then return end
    local state = inst._my_friend_base
    state.visited_nodes = state.visited_nodes or {}
    state.visited_nodes[index] = true
end

local function IsVisitedNode(inst, index)
    local state = inst._my_friend_base
    return state.visited_nodes ~= nil and state.visited_nodes[index] == true
end

local function FindTerrainNode(inst, needs)
    local topology = TheWorld ~= nil and TheWorld.topology or nil
    if topology == nil or topology.nodes == nil or topology.ids == nil then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local start = TheWorld.Map:GetNodeIdAtPoint(x, y, z)
    if start == nil or topology.nodes[start] == nil then return end
    local start_domain = M.GetTerrainDomainAtPoint(x, y, z)
    if start_domain ~= "land" then return end

    local queue, head = { { index = start, depth = 0 } }, 1
    local visited = { [start] = true }
    local best_index, best_point, best_score
    local old_index, old_point, old_score
    local function IsRouteClear(from_point, to_point)
        if from_point == nil or to_point == nil then return false end
        local dx, dz = to_point.x - from_point.x, to_point.z - from_point.z
        local distance = math.sqrt(dx * dx + dz * dz)
        local steps = math.max(1, math.ceil(distance / M.TERRAIN_ROUTE_SAMPLE_STEP))
        for step = 1, steps - 1 do
            local t = step / steps
            local px, pz = from_point.x + dx * t, from_point.z + dz * t
            if not TheWorld.Map:IsPassableAtPoint(px, 0, pz, false, false)
                or Navigation.IsNearHole(Vector3(px, 0, pz)) then
                return false
            end
        end
        return true
    end
    while head <= #queue do
        local entry = queue[head]
        head = head + 1
        local node = topology.nodes[entry.index]
        local point = NodePoint(node)
        local affinity = M.GetTerrainAffinity(topology.ids[entry.index], needs)
        local node_domain = point ~= nil and M.GetTerrainDomainAtPoint(
            point.x, point.y, point.z) or "blocked"
        if point ~= nil and affinity > 0 and not IsSearchNodeBlocked(inst, entry.index)
            and node_domain == start_domain
            and TheWorld.Map:IsPassableAtPoint(point.x, point.y, point.z) then
            local dx, dz = point.x - x, point.z - z
            local score = affinity * 100 - entry.depth * 12
                - math.sqrt(dx * dx + dz * dz) * .03
            if IsVisitedNode(inst, entry.index) then
                if old_score == nil or score > old_score then
                    old_index, old_point, old_score = entry.index, point, score
                end
            elseif best_score == nil or score > best_score then
                best_index, best_point, best_score = entry.index, point, score
            end
        end
        if entry.depth < 64 then
            for _, neighbour in ipairs(node.neighbours or {}) do
                local neighbour_node = topology.nodes[neighbour]
                local neighbour_point = NodePoint(neighbour_node)
                local neighbour_domain = neighbour_point ~= nil
                    and M.GetTerrainDomainAtPoint(neighbour_point.x,
                        neighbour_point.y, neighbour_point.z) or "blocked"
                if neighbour_node ~= nil and not visited[neighbour]
                    and neighbour_domain == start_domain
                    and IsRouteClear(point, neighbour_point) then
                    visited[neighbour] = true
                    table.insert(queue, { index = neighbour, depth = entry.depth + 1 })
                end
            end
        end
    end
    return best_index or old_index, best_point or old_point
end

function M.IsSearchProgress(distance, best_distance, threshold)
    return best_distance == nil
        or distance <= best_distance - (threshold or M.SEARCH_PROGRESS_DISTANCE)
end

local function MoveSearchAction(inst, point, search)
    local action = MoveAction(inst, point)
    local last = inst:GetPosition()
    local last_progress = GetTime()
    action.validfn = function()
        local state = inst._my_friend_base
        if state == nil or state.resource_search ~= search then return false end
        local now = GetTime()
        if now < (action._my_friend_travel_until or 0) then
            last, last_progress = inst:GetPosition(), now
            return true
        end
        local current = inst:GetPosition()
        if (current.x - last.x)^2 + (current.z - last.z)^2 >= .25 then
            last = current
            last_progress = now
        elseif now - last_progress >= 6 then
            if search.node ~= nil then BlockSearchNode(inst, search.node) end
            ResourceMemory.Block(inst, search.x, search.z, now)
            state.resource_search = nil
            return false
        end
        return true
    end
    action:AddFailAction(function()
        if not action._my_friend_cancelled
            and (action._my_friend_path_failed or GetTime() - last_progress >= 6) then
            if search.target ~= nil then
                inst._my_friend_base_blocked = inst._my_friend_base_blocked or {}
                inst._my_friend_base_blocked[search.target.GUID or search.target] = GetTime() + 60
            end
            if search.node ~= nil then BlockSearchNode(inst, search.node) end
            inst._my_friend_world_resource_query = nil
        end
        if inst._my_friend_base ~= nil and inst._my_friend_base.resource_search == search then
            inst._my_friend_base.resource_search = nil
        end
    end)
    action:AddSuccessAction(function()
        if inst._my_friend_base ~= nil and inst._my_friend_base.resource_search == search then
            inst._my_friend_base.resource_search = nil
        end
    end)
    return action
end

local function FindExpandingSearchPoint(inst)
    local state = inst._my_friend_base
    state.search_step = (state.search_step or 0) + 1
    local ring = math.floor((state.search_step - 1) / 12)
    local angle = (state.search_step - 1) % 12 * PI2 / 12
        + (state.search_angle or 0)
    local radius = math.min(160, 32 + ring * 16)
    local base = M.GetBasePoint(inst) or inst:GetPosition()
    local allow_water = inst.components.locomotor:CanPathfindOnWater()
    local domain = M.GetTerrainDomainAtPoint(base.x, base.y, base.z)
    for attempt = 1, 8 do
        local candidate_angle = angle + (attempt - 1) * PI2 / 8
        local offset = FindWalkableOffset(base, candidate_angle, radius, 16, true,
            false, nil, allow_water)
        if offset ~= nil then
            local point = base + offset
            local candidate_domain = M.GetTerrainDomainAtPoint(point.x, point.y, point.z)
            if candidate_domain == domain and (candidate_domain ~= "water" or allow_water) then
                return point
            end
        end
    end
end

local function IsWildPlant(entity)
    local pickable = entity.components ~= nil and entity.components.pickable or nil
    return (entity.prefab == "grass" or entity.prefab == "sapling")
        and pickable ~= nil and not pickable.transplanted
end

local function GetTerrainSearchAction(inst, needs, excluded_work_action)
    if HasLeader(inst) or M.EnsureBase(inst) == nil then return end
    local state = inst._my_friend_base
    local can_work = M.CanUseHandToolInCurrentLight(inst)
    -- Local collectors have already considered these resources. Travelling
    -- to a rejected nearby target can succeed without moving, forever.
    local local_range = needs.food ~= nil and BehaviourAI.COLLECT_RANGE or M.RESOURCE_SEARCH_RANGE
    local resource = WorldResources.Find(inst, needs, function(entity)
        return DistanceSq(inst, entity) <= local_range^2 or IsBlocked(inst, entity)
            or entity:HasTag("tree") and (Forestry.InPlot(inst, entity)
                or M.IsComplete(inst) and not Forestry.IsMature(entity))
            or not can_work and entity.components.inventoryitem == nil
                and entity.components.workable ~= nil
                and not (entity.components.pickable ~= nil
                    and (needs[entity.components.pickable.product] ~= nil
                        or needs.food ~= nil and BehaviourAI.IsFoodProduct(entity.components.pickable.product))
                    and entity.components.pickable:CanBePicked())
            or excluded_work_action ~= nil and entity.components.workable ~= nil
                and entity.components.workable:GetWorkAction() == excluded_work_action
            or needs.food ~= nil and inst._my_friend_collect_blocked ~= nil
                and GetTime() < (inst._my_friend_collect_blocked[entity.GUID or entity] or 0)
            or (needs.dug_grass ~= nil or needs.dug_sapling ~= nil)
                and entity.components.inventoryitem == nil and not IsWildPlant(entity)
            or needs.log ~= nil and entity.components.inventoryitem == nil
                and M.IsComplete(inst)
                and DistanceSqToPoint(entity, M.GetBasePoint(inst)) <= (M.BASE_STRUCTURE_RANGE + 4)^2
    end)
    if resource ~= nil then
        local point = resource:GetPosition()
        state.resource_search = { key = M.GetNeedKey(needs), target = resource,
            x = point.x, z = point.z }
        M.SetTask(inst, "正在前往已知资源的位置")
        local action = MoveSearchAction(inst, point, state.resource_search)
        action.arrivedist = 6
        return action
    end
    state.resource_search = nil
    M.SetTask(inst, "暂时没有可采集的目标")
end

function M.GetFoodSearchAction(inst)
    if not CanAct(inst) or HasLeader(inst) or not FoodAI.NeedsFoodSupply(inst) then return end
    -- A companion told to wait somewhere never sets off on a cross-map
    -- foraging trip: it forages within its home circle and raids the icebox.
    if Home.IsStrict(inst) then return end
    return GetTerrainSearchAction(inst, { food = true })
end

local function IsWildTransplant(inst, entity)
    local base = M.GetBasePoint(inst)
    return not Forestry.InPlot(inst, entity)
        and (base == nil or DistanceSqToPoint(entity, base) > (M.BASE_STRUCTURE_RANGE + 4) ^ 2)
end

local function IsSearchDirectionProgress(inst, entity)
    local search = inst._my_friend_base ~= nil
        and inst._my_friend_base.resource_search or nil
    if search == nil or DistanceSq(inst, entity) <= 16 then return true end
    local ix, _, iz = inst.Transform:GetWorldPosition()
    local ex, _, ez = entity.Transform:GetWorldPosition()
    local tx = search.probe_x or search.x
    local tz = search.probe_z or search.z
    return M.IsDirectionProgress(ix, iz, tx, tz, ex, ez)
end

function M.ShouldRetainWorkTarget(can_be_worked, work_action, expected_action,
    available, before_stall_deadline)
    return can_be_worked == true and work_action == expected_action
        and available == true and before_stall_deadline == true
end

function M.IsRepeatingWorkAction(inst, action)
    return inst ~= nil and inst.sg ~= nil and action ~= nil
        and action.action ~= nil and action.action.id ~= nil
        and (action.action == ACTIONS.CHOP or action.action == ACTIONS.MINE)
        and inst.sg:HasStateTag("pre"..string.lower(action.action.id))
end

function M.IsMineResourceState(has_boulder, prefab)
    return has_boulder == true or EXTRA_MINE_RESOURCES[prefab] == true
end

local function IsMineResource(entity)
    return M.IsMineResourceState(entity:HasTag("boulder"), entity.prefab)
end

local function ClearWorkTarget(inst)
    inst._my_friend_forest_clear_target = nil
    inst._my_friend_work_target = nil
    inst._my_friend_work_action = nil
    inst._my_friend_work_left = nil
    inst._my_friend_work_stall_deadline = nil
    inst._my_friend_hand_tool_lock_until = nil
end

function M.AbandonStalledWork(inst, target)
    target = target or inst._my_friend_work_target
    if target ~= nil and target:IsValid() then
        inst._my_friend_base_blocked = inst._my_friend_base_blocked or {}
        inst._my_friend_base_blocked[target.GUID or target] = GetTime() + 20
    end
    ClearWorkTarget(inst)
    local base = inst._my_friend_base
    if base ~= nil then base.resource_search = nil end
    inst._my_friend_world_resource_query = nil
end

function M.RefreshWorkTarget(inst)
    local target = inst._my_friend_work_target
    if target == nil then return end
    local workable = target:IsValid() and target.components.workable or nil
    if workable == nil or not workable:CanBeWorked()
        or workable:GetWorkAction() ~= inst._my_friend_work_action then
        ClearWorkTarget(inst)
    elseif GetTime() >= (inst._my_friend_work_stall_deadline or 0) then
        -- A stalled target must not be selected again by the next resource scan.
        inst._my_friend_base_blocked = inst._my_friend_base_blocked or {}
        inst._my_friend_base_blocked[target.GUID or target] = GetTime() + M.RETRY_DELAY
        ClearWorkTarget(inst)
    end
end

local function GetLockedWorkTarget(inst, needs, excluded_work_action)
    M.RefreshWorkTarget(inst)
    local target = inst._my_friend_work_target
    local action_type = inst._my_friend_work_action
    local workable = target ~= nil and target:IsValid() and target.components ~= nil
        and target.components.workable or nil
    local can_work = workable ~= nil and workable:CanBeWorked() or false
    local work_action = can_work and workable:GetWorkAction() or nil
    local available = target ~= nil and target:IsValid()
        and action_type ~= excluded_work_action
        and not IsBlocked(inst, target)
        and Policy.InRange(inst, target)
    if available and action_type == ACTIONS.CHOP and M.IsComplete(inst)
        and not Forestry.IsMature(target) and not Forestry.IsClearanceTarget(inst, target) then
        ClearWorkTarget(inst)
        return
    end
    if available and IsResourceUnsafe(inst, target, true) then
        inst._my_friend_base_blocked = inst._my_friend_base_blocked or {}
        inst._my_friend_base_blocked[target.GUID or target] =
            GetTime() + M.UNSAFE_RESOURCE_RETRY_DELAY
        ClearWorkTarget(inst)
        return
    end
    if M.ShouldRetainWorkTarget(can_work, work_action, action_type, available,
        GetTime() < (inst._my_friend_work_stall_deadline or 0)) then
        return target, action_type
    end
    ClearWorkTarget(inst)
end

local function LockWorkTarget(inst, target, action_type)
    if action_type == ACTIONS.CHOP or action_type == ACTIONS.MINE then
        if inst._my_friend_work_target ~= target then
            local workable = target.components ~= nil and target.components.workable or nil
            inst._my_friend_work_left = workable ~= nil and workable:GetWorkLeft() or nil
            inst._my_friend_work_stall_deadline = GetTime() + M.WORK_STALL_TIMEOUT
        end
        inst._my_friend_work_target = target
        inst._my_friend_work_action = action_type
        inst._my_friend_hand_tool_lock_until = GetTime() + M.WORK_STALL_TIMEOUT
    end
end

local function FindGatherTarget(inst, needs, excluded_work_action)
    local x, y, z, range = Policy.SearchOrigin(inst, M.RESOURCE_SEARCH_RANGE)
    local best, best_action, best_score
    local can_work = M.CanUseHandToolInCurrentLight(inst)
    local entities = TheSim:FindEntities(x, y, z, range,
        nil, CANT_TAGS,
        { "_inventoryitem", "pickable", "tree", "boulder", "MINE_workable",
            "DIG_workable" })
    if not HasLeader(inst) then
        ResourceMemory.Observe(inst, entities, x, z, range, GetTime())
    end
    for _, entity in ipairs(entities) do
        local inside_season_base = HasLeader(inst) or not M.IsComplete(inst) or not M.IsExtremeSeason(inst)
            or DistanceSqToPoint(entity, M.GetBasePoint(inst)) <= M.BASE_RETURN_DISTANCE ^ 2
        if entity ~= inst and inside_season_base and not IsBlocked(inst, entity) then
            if IsResourceUnsafe(inst, entity) then
                inst._my_friend_base_blocked = inst._my_friend_base_blocked or {}
                inst._my_friend_base_blocked[entity.GUID or entity] =
                    GetTime() + M.UNSAFE_RESOURCE_RETRY_DELAY
            else
            local action_type, score
            if needs[entity.prefab] ~= nil
                and CanPickUp(inst, entity, true) then
                action_type = ACTIONS.PICKUP
                score = DistanceSq(inst, entity)
            else
                local pickable = entity.components ~= nil and entity.components.pickable or nil
                if pickable ~= nil and pickable.caninteractwith and pickable:CanBePicked()
                    and needs[pickable.product] ~= nil
                    and HasRoomForCarriedPrefab(inst, pickable.product) then
                    action_type = ACTIONS.PICK
                    score = DistanceSq(inst, entity) + 2
                end
                local workable = entity.components ~= nil and entity.components.workable or nil
                local work_action = workable ~= nil and workable:CanBeWorked()
                    and workable:GetWorkAction() or nil
                if not can_work or HasLeader(inst)
                    and (work_action == ACTIONS.CHOP or work_action == ACTIONS.MINE) then
                    work_action = nil
                end
                if action_type == nil and work_action ~= excluded_work_action
                    and work_action == ACTIONS.CHOP and needs.log ~= nil
                    and not Forestry.InPlot(inst, entity)
                    and (not M.IsComplete(inst) or Forestry.IsMature(entity))
                    and (HasLeader(inst) or not M.IsComplete(inst) or IsWildTransplant(inst, entity)) then
                    action_type = ACTIONS.CHOP
                    score = DistanceSq(inst, entity) + 4
                elseif action_type == nil and work_action ~= excluded_work_action
                    and work_action == ACTIONS.MINE
                    and NeedAny(needs, "rocks", "flint", "goldnugget", "nitre") then
                    for prefab in pairs(ResourceMemory.MineProducts(entity)) do
                        if needs[prefab] ~= nil then
                            action_type = ACTIONS.MINE
                            score = DistanceSq(inst, entity)
                                + (needs.goldnugget ~= nil and prefab == "goldnugget" and -16 or 5)
                            break
                        end
                    end
                elseif action_type == nil and work_action ~= excluded_work_action
                    and work_action == ACTIONS.DIG
                    and IsWildPlant(entity)
                    and (needs.dug_grass ~= nil and entity.prefab == "grass"
                            and HasRoomForCarriedPrefab(inst, "dug_grass")
                        or needs.dug_sapling ~= nil and entity.prefab == "sapling"
                            and HasRoomForCarriedPrefab(inst, "dug_sapling")) then
                    action_type = ACTIONS.DIG
                    score = DistanceSq(inst, entity) + 3
                end
            end
            if action_type ~= nil and (best_score == nil or score < best_score) then
                best, best_action, best_score = entity, action_type, score
            end
            end
        end
    end
    return best, best_action
end

local function CreateGatherAction(inst, target, action_type, tool)
    local forest_clear = Forestry.IsClearanceTarget(inst, target)
    local persistent_work = action_type == ACTIONS.CHOP or action_type == ACTIONS.MINE
    if persistent_work then LockWorkTarget(inst, target, action_type) end
    local transplant_loot = action_type == ACTIONS.DIG and TRANSPLANT_LOOT[target.prefab] or nil
    if action_type == ACTIONS.DIG and target:HasTag("stump") then
        transplant_loot = {primary = "log", prefabs = {log = true}}
    elseif action_type == ACTIONS.DIG and forest_clear and transplant_loot == nil then
        transplant_loot = {}
    end
    local work_position = (persistent_work or transplant_loot ~= nil)
        and target:GetPosition() or nil
    M.SetTask(inst, action_type == ACTIONS.CHOP and "正在砍树"
        or action_type == ACTIONS.MINE and "正在采矿"
        or action_type == ACTIONS.DIG and "正在挖取移植物"
        or action_type == ACTIONS.PICK and "正在采集基础物资"
        or "正在拾取基础物资")
    local action = TimedAction(inst, target, action_type, tool, nil, persistent_work)
    if persistent_work then
        action:AddSuccessAction(function()
            local workable = target ~= nil and target:IsValid()
                and target.components ~= nil and target.components.workable or nil
            if workable ~= nil and workable:CanBeWorked()
                and workable:GetWorkAction() == action_type then
                local work_left = workable:GetWorkLeft()
                if inst._my_friend_work_left == nil
                    or work_left < inst._my_friend_work_left then
                    inst._my_friend_work_left = work_left
                    inst._my_friend_work_stall_deadline = GetTime() + M.WORK_STALL_TIMEOUT
                end
                inst._my_friend_work_target = target
                inst._my_friend_work_action = action_type
            else
                local defer_stump = action_type == ACTIONS.CHOP and FindTool(inst, ACTIONS.DIG) == nil
                if action_type == ACTIONS.CHOP and work_position ~= nil then
                    Forestry.RecordChop(inst, target, work_position, defer_stump)
                end
                if work_position ~= nil then
                    inst._my_friend_work_cleanup = {
                        x = work_position.x,
                        z = work_position.z,
                        action = action_type,
                        forest_clear = forest_clear,
                        stump = action_type == ACTIONS.CHOP and not defer_stump
                            and target:IsValid() and target:HasTag("stump") and target or nil,
                        started = GetTime(),
                        deadline = GetTime() + M.MINE_LOOT_TIMEOUT,
                    }
                end
                if action_type == ACTIONS.CHOP and work_position ~= nil then
                    require("my_friend_chop_loot").Record(inst, target, work_position, defer_stump)
                end
                ClearWorkTarget(inst)
            end
        end)
    elseif transplant_loot ~= nil then
        action:AddSuccessAction(function()
            if inst:IsValid() and work_position ~= nil then
                inst._my_friend_work_cleanup = {
                    x = work_position.x,
                    z = work_position.z,
                    action = ACTIONS.DIG,
                    forest_clear = forest_clear,
                    primary = transplant_loot.primary,
                    prefabs = transplant_loot.prefabs,
                    started = GetTime(),
                    deadline = GetTime() + M.MINE_LOOT_TIMEOUT,
                }
            end
        end)
    end
    if forest_clear then
        local plot = inst._my_friend_base.forest
        action:AddFailAction(function()
            if action._my_friend_cancelled then return end
            if inst._my_friend_base ~= nil and inst._my_friend_base.forest == plot
                and (not persistent_work or action._my_friend_path_failed
                    or GetTime() >= (inst._my_friend_work_stall_deadline or 0)) then
                plot.clear_failures = (plot.clear_failures or 0) + 1
                if plot.clear_failures >= 3 then Forestry.RejectPlot(inst, plot) end
            end
        end)
        action:AddSuccessAction(function() plot.clear_failures = nil end)
    end
    return action
end

local function HasPartialStack(inst, prefab)
    return prefab ~= nil and inst.components.inventory:FindItem(function(item)
        return item.prefab == prefab and item.components.stackable ~= nil
            and not item.components.stackable:IsFull()
    end) ~= nil
end

local function IsOpportunityAhead(inst, entity)
    return IsSearchDirectionProgress(inst, entity)
end

local function GetLocalOpportunityAction(inst, needs, stable_only)
    if M.IsExtremeSeason(inst) then return end
    local free_slots = GetFreeSlots(inst)
    local state = inst._my_friend_base
    local now = GetTime()
    if stable_only then
        if now < (state.stable_local_collect_at or 0) then return end
        state.stable_local_collect_at = now + M.STABLE_LOCAL_COLLECT_COOLDOWN
    end
    local axe = FindTool(inst, ACTIONS.CHOP)
    local pickaxe = FindTool(inst, ACTIONS.MINE)
    local shovel = FindTool(inst, ACTIONS.DIG)
    local need_grass = (state.planted_grass or 0) < M.TRANSPLANT_TARGET
    local need_sapling = (state.planted_sapling or 0) < M.TRANSPLANT_TARGET
    local x, y, z = inst.Transform:GetWorldPosition()
    local best, best_action, best_tool, best_kind, best_score

    for _, entity in ipairs(TheSim:FindEntities(x, y, z,
        M.LOCAL_OPPORTUNITY_RANGE, nil, CANT_TAGS, OPPORTUNITY_TAGS)) do
        if entity ~= inst and not IsBlocked(inst, entity) then
            if IsResourceUnsafe(inst, entity) then
                inst._my_friend_base_blocked = inst._my_friend_base_blocked or {}
                inst._my_friend_base_blocked[entity.GUID or entity] =
                    GetTime() + M.UNSAFE_RESOURCE_RETRY_DELAY
            else
            local action_type, tool, kind, product
            if entity.components ~= nil and entity.components.inventoryitem ~= nil
                and (GROUND_RESOURCES[entity.prefab]
                    or entity.components.edible ~= nil)
                and CanPickUp(inst, entity) then
                    action_type, kind, product = ACTIONS.PICKUP,
                        entity.components.edible ~= nil and "food" or "ground",
                        entity.prefab
            else
                local pickable = entity.components ~= nil and entity.components.pickable or nil
                if pickable ~= nil and pickable.caninteractwith and pickable:CanBePicked()
                    and BehaviourAI.IsFoodProduct(pickable.product) then
                    action_type, kind, product = ACTIONS.PICK, "food", pickable.product
                end
                local crop = entity.components ~= nil and entity.components.crop or nil
                if action_type == nil and crop ~= nil and crop:IsReadyForHarvest() then
                    action_type, kind, product = ACTIONS.HARVEST, "food", crop.product_prefab
                end
                local workable = entity.components ~= nil and entity.components.workable or nil
                local work_action = workable ~= nil and workable:CanBeWorked()
                    and workable:GetWorkAction() or nil
                if action_type == nil and work_action == ACTIONS.MINE
                    and pickaxe ~= nil and IsMineResource(entity) then
                    action_type, tool, kind = ACTIONS.MINE, pickaxe, "mine"
                elseif action_type == nil and work_action == ACTIONS.CHOP
                    and axe ~= nil and IsWildTransplant(inst, entity)
                    and (not M.IsComplete(inst) or Forestry.IsMature(entity)) then
                    action_type, tool, kind = ACTIONS.CHOP, axe, "chop"
                elseif action_type == nil and work_action == ACTIONS.DIG
                    and shovel ~= nil and IsWildPlant(entity)
                    and (need_grass and entity.prefab == "grass"
                        or need_sapling and entity.prefab == "sapling") then
                    action_type, tool, kind = ACTIONS.DIG, shovel, "dig"
                elseif action_type == nil and pickable ~= nil
                    and pickable.caninteractwith and pickable:CanBePicked()
                    and GROUND_RESOURCES[pickable.product] then
                    action_type, kind, product = ACTIONS.PICK, "resource", pickable.product
                end
            end

            local is_work = action_type == ACTIONS.MINE or action_type == ACTIONS.CHOP
                or action_type == ACTIONS.DIG
            local resource_count = product ~= nil and CountInventory(inst, product) or 0
            local under_resource_limit = kind ~= "resource"
                or resource_count < M.LOCAL_RESOURCE_MAX
            local wanted = needs == nil or kind == "food" and FoodAI.NeedsFoodSupply(inst)
                or product ~= nil and needs[product] ~= nil
                or kind == "mine" and NeedAny(needs, "rocks", "flint", "goldnugget", "nitre")
                or kind == "chop" and needs.log ~= nil
                or kind == "dig" and NeedAny(needs, "dug_grass", "dug_sapling")
            if action_type ~= nil
                and wanted
                and not Garden.IsFertilizer(entity)
                and under_resource_limit
                and M.ShouldCollectLocally(free_slots, HasPartialStack(inst, product), is_work)
                and (not is_work or M.CanUseHandToolInCurrentLight(inst)) then
                local distance = math.sqrt(DistanceSq(inst, entity))
                local score = M.GetOpportunityPriority(kind, distance)
                if best_score == nil or score < best_score then
                    best, best_action, best_tool, best_kind, best_score =
                        entity, action_type, tool, kind, score
                end
            end
            end
        end
    end
    if best == nil then return end
    if best_tool ~= nil and not EquipTool(inst, best_tool) then return end
    local action = CreateGatherAction(inst, best, best_action, best_tool)
    if best_kind == "food" then
        M.SetTask(inst, "正在收集附近食物")
    elseif best_kind == "ground" then
        M.SetTask(inst, "正在捡起路过的物资")
    end
    action:AddSuccessAction(function()
        if inst._my_friend_base ~= nil then
            inst._my_friend_base.local_batch_count =
                (inst._my_friend_base.local_batch_count or 0) + 1
        end
    end)
    return action
end

local function GetToolRecipe(action_type)
    return action_type == ACTIONS.CHOP and "axe"
        or action_type == ACTIONS.MINE and "pickaxe"
        or action_type == ACTIONS.DIG and "shovel"
        or action_type == ACTIONS.HAMMER and "hammer" or nil
end

local function GetGatherAction(inst, needs, excluded_work_action, depth, allow_withdraw)
    depth = depth or 0
    local ground = GetNeededGroundAction(inst, needs)
    if ground ~= nil then return ground end
    local withdraw = allow_withdraw ~= false and GetWithdrawAction(inst, needs) or nil
    if withdraw ~= nil then return withdraw end
    local target, action_type
    if M.CanUseHandToolInCurrentLight(inst)
        and (not HasLeader(inst) or inst._my_friend_work_action ~= ACTIONS.CHOP
            and inst._my_friend_work_action ~= ACTIONS.MINE) then
        target, action_type = GetLockedWorkTarget(inst, needs, excluded_work_action)
    end
    if target == nil then
        target, action_type = FindGatherTarget(inst, needs, excluded_work_action)
    end
    if target == nil then
        if HasLeader(inst) then return end
        if M.IsComplete(inst) and M.IsExtremeSeason(inst) then return end
        -- Prepare the trip's tool before leaving storage, not after arriving at ore.
        local work = (needs.rocks ~= nil or needs.goldnugget ~= nil or needs.nitre ~= nil
                or needs.flint ~= nil) and ACTIONS.MINE
            or (needs.log ~= nil or needs.pinecone ~= nil or needs.acorn ~= nil) and ACTIONS.CHOP
            or (needs.dug_grass ~= nil or needs.dug_sapling ~= nil) and ACTIONS.DIG or nil
        if work ~= nil and work ~= excluded_work_action and FindTool(inst, work) == nil then
            local action, missing = EnsureRecipe(inst, GetToolRecipe(work))
            if action ~= nil then return action end
            if missing ~= nil and next(missing) ~= nil and depth < M.MAX_GATHER_RECURSION then
                return GetGatherAction(inst, missing, work, depth + 1, allow_withdraw)
            end
        end
        return GetTerrainSearchAction(inst, needs, excluded_work_action)
    end
    local recipe_name = GetToolRecipe(action_type)
    local tool
    if recipe_name ~= nil then
        tool = FindTool(inst, action_type)
        if tool == nil then
            local action, missing = EnsureRecipe(inst, recipe_name)
            if action ~= nil then return action end
            if missing ~= nil and next(missing) ~= nil then
                if depth >= M.MAX_GATHER_RECURSION then
                    ClearWorkTarget(inst)
                    if HasLeader(inst) then return end
                    if M.IsComplete(inst) and M.IsExtremeSeason(inst) then return end
                    return GetTerrainSearchAction(inst, missing, action_type)
                end
                return GetGatherAction(inst, missing, action_type, depth + 1, allow_withdraw)
            end
            return
        end
        if not M.CanUseHandToolInCurrentLight(inst) then return end
        if not EquipTool(inst, tool) then return end
        inst._my_friend_tool_needs = inst._my_friend_tool_needs or {}
        inst._my_friend_tool_needs[action_type.id] = GetTime() + 90
    end
    return CreateGatherAction(inst, target, action_type, tool)
end

local function GetPlannedOpportunityAction(inst, requested)
    if HasLeader(inst) or inst._my_friend_base == nil or inst._my_friend_base.complete
        or FindStructure(inst, "researchlab") == nil or Backpacks.NeedsCraftedBackpack(inst)
        or inst._my_friend_work_target ~= nil or inst._my_friend_work_cleanup ~= nil then return end
    local hunger = inst.components.hunger
    local urgent = TheWorld.state.isdusk or TheWorld.state.isnight
        or M.IsExtremeSeason(inst) or LightAI.IsEnvironmentDark(inst)
    local free_slots = GetFreeSlots(inst)
    if urgent or free_slots <= 4 or hunger == nil or hunger:GetPercent() < .5 then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local entities = TheSim:FindEntities(x, y, z, 8, nil, CANT_TAGS,
        {"_inventoryitem", "pickable"})
    local density = {}
    for _, entity in ipairs(entities) do
        for prefab, count in pairs(ResourceMemory.Products(entity)) do
            density[prefab] = (density[prefab] or 0) + count
        end
    end
    -- Small rolling reserves for the next construction steps, not the entire
    -- base bill at once. Extras are pickups/picks only, never a detour to work.
    local targets = { cutgrass = 12, twigs = 12, flint = 6, log = 20, rocks = 16, goldnugget = 2 }
    local best, best_action, distance
    for _, entity in ipairs(entities) do
        local pickable = entity.components.pickable
        local prefab = pickable ~= nil and pickable.product or entity.prefab
        local cap = targets[prefab]
        local allowance = ResourceMemory.ExtraAllowance(hunger:GetPercent(), urgent,
            free_slots, density[prefab] or 0)
        if cap ~= nil and requested ~= nil and requested[prefab] ~= nil
            and allowance > 0 and CountInventory(inst, prefab) < cap
            and not IsBlocked(inst, entity) and IsOpportunityAhead(inst, entity)
            and not IsResourceUnsafe(inst, entity) then
            local action = CanPickUp(inst, entity) and ACTIONS.PICKUP
                or pickable ~= nil and pickable.caninteractwith and pickable:CanBePicked()
                    and HasRoomForCarriedPrefab(inst, prefab) and ACTIONS.PICK or nil
            local d = DistanceSq(inst, entity)
            if action ~= nil and (distance == nil or d < distance) then
                best, best_action, distance = entity, action, d
            end
        end
    end
    if best ~= nil then return CreateGatherAction(inst, best, best_action) end
end

local function GetPendingWorkAction(inst)
    if not M.CanUseHandToolInCurrentLight(inst) then return end
    local target, action_type = GetLockedWorkTarget(inst, nil, nil)
    if target == nil then return end
    local tool = FindTool(inst, action_type)
    if tool == nil then
        local recipe_name = GetToolRecipe(action_type)
        local action, missing
        if recipe_name ~= nil then action, missing = EnsureRecipe(inst, recipe_name) end
        if action ~= nil then return action end
        if missing ~= nil and next(missing) ~= nil then
            local withdraw = GetWithdrawAction(inst, missing)
            if withdraw ~= nil then return withdraw end
            -- Replacing a broken tool can require another tool (e.g. chopping
            -- wood for a pickaxe). Use the normal bounded tool planner.
            return GetGatherAction(inst, missing, action_type)
        end
        return
    end
    if not M.CanUseHandToolInCurrentLight(inst) then return end
    if not EquipTool(inst, tool) then
        return
    end
    return CreateGatherAction(inst, target, action_type, tool)
end

function M.GetRepeatWorkAction(inst, target, action_type)
    if target == nil or not target:IsValid() or inst._my_friend_under_threat then return end
    -- Breaking our own skeleton takes several swings. It is not gathering, so
    -- it bypasses the work target, stock and leader-range rules below.
    if action_type == ACTIONS.HAMMER and target:HasTag("my_friend_remains") then
        return M.GetRemainsAction(inst, target)
    end
    M.RefreshWorkTarget(inst)
    local command = inst._my_friend_command
    if command ~= nil and require("my_friend_commands").Get(inst) ~= command then return end
    if HasLeader(inst) and (action_type == ACTIONS.CHOP or action_type == ACTIONS.MINE)
        and not (command ~= nil and (command.id == "chop" and action_type == ACTIONS.CHOP
            or command.id == "mine" and action_type == ACTIONS.MINE
            or command.id == "rockfruit" and command.cracking
                and action_type == ACTIONS.MINE)) then return end
    local fixed_chop = command ~= nil and command.id == "chop" and action_type == ACTIONS.CHOP
    if target == nil or target ~= inst._my_friend_work_target
        or action_type ~= inst._my_friend_work_action or inst._my_friend_under_threat
        or (fixed_chop and target:GetDistanceSqToPoint(command.origin) > 16^2
            or not fixed_chop and not Policy.InRange(inst, target))
        or not HasLeader(inst) and M.IsStockStorageFull(inst) then return end
    if not target:IsValid() or IsBlocked(inst, target)
        or not M.CanUseHandToolInCurrentLight(inst) or IsResourceUnsafe(inst, target, true) then return end
    if action_type == ACTIONS.CHOP and M.IsComplete(inst)
        and not Forestry.IsMature(target) and not Forestry.IsClearanceTarget(inst, target) then return end
    local workable = target.components.workable
    if workable == nil or not workable:CanBeWorked() or workable:GetWorkAction() ~= action_type then return end
    local tool = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if tool == nil or tool.components.tool == nil
        or tool.components.tool:GetEffectiveness(action_type) <= 0 then return end
    local action = CreateGatherAction(inst, target, action_type, tool)
    if fixed_chop then
        action._my_friend_command_origin = command.origin
    end
    if command ~= nil then action = require("my_friend_commands").Commit(inst, action) end
    return Policy.GuardAction(inst, action)
end

local function GetRecipeGoalAction(inst, recipe_name)
    local action, missing = EnsureRecipe(inst, recipe_name)
    if action ~= nil then return action end
    if missing ~= nil and next(missing) ~= nil then
        local ground = GetNeededGroundAction(inst, missing)
        if ground ~= nil then return ground end
        local nearby = GetPlannedOpportunityAction(inst, missing)
        if nearby ~= nil then return nearby end
        return GetGatherAction(inst, missing)
    end
end

-- Shared autonomous crafting entry point. When allow_gather is false it still
-- withdraws materials from the companion's base chests and refines recipes,
-- but never turns an optional task into a world-wide gathering trip.
function M.GetRecipeGoalAction(inst, recipe_name, allow_gather, reserve)
    local action, missing = EnsureRecipe(inst, recipe_name, nil, nil, nil, allow_gather, reserve)
    if action ~= nil then
        if allow_gather == false and inst._my_friend_pending_recipe == recipe_name then
            inst._my_friend_pending_recipe = nil
        end
        return action
    end
    if missing ~= nil and next(missing) ~= nil and allow_gather ~= false then
        local ground = GetNeededGroundAction(inst, missing)
        if ground ~= nil then return ground end
        local nearby = GetPlannedOpportunityAction(inst, missing)
        if nearby ~= nil then return nearby end
        return GetGatherAction(inst, missing)
    end
end

-- Command materials are gathered by my_friend_crafting_materials. Keep the
-- build step shared with autonomous crafting without starting unrelated work.
function M.GetRecipeAction(inst, recipe_name, point, track_pending)
    return CreateBuildAction(inst, recipe_name, point, track_pending)
end

function M.GetRemainsAction(inst, target)
    -- Deliberately not CanAct(): a backpack that is merely queued for pickup
    -- must not stop the companion from clearing its own bones. A backpack
    -- pickup that is actually running still does, via _backpack_action below.
    if not IsAlive(inst) or inst:HasTag("playerghost")
        or inst.components.inventory == nil or inst.components.builder == nil
        or inst._my_friend_backpack_action or inst._my_friend_container_action
        or inst._my_friend_storage_action
        or inst.sg ~= nil and inst.sg:HasStateTag("busy")
        or target == nil or not target:IsValid()
        or not target:HasTag("my_friend_remains") or not Policy.InRange(inst, target) then return end
    local workable = target.components.workable
    if workable == nil or not workable:CanBeWorked()
        or workable:GetWorkAction() ~= ACTIONS.HAMMER then return end
    inst._my_friend_tool_needs = inst._my_friend_tool_needs or {}
    inst._my_friend_tool_needs[ACTIONS.HAMMER.id] = GetTime() + 120
    local tool = FindTool(inst, ACTIONS.HAMMER)
    if tool == nil then
        local ground = GetGroundToolAction(inst, ACTIONS.HAMMER)
        if ground ~= nil then
            M.SetTask(inst, "正在去捡一把锤子")
            return ground
        end
        return GetRecipeGoalAction(inst, "hammer")
    end
    if not M.CanUseHandToolInCurrentLight(inst) or not EquipTool(inst, tool) then return end
    M.SetTask(inst, "正在敲掉自己的遗骸")
    return TimedAction(inst, target, ACTIONS.HAMMER, tool)
end

local RefreshGarden

function M.GetConstructionPhase(inst)
    local state = inst._my_friend_base
    if state == nil then return "site" end
    if FindStructure(inst, "researchlab") == nil then return "researchlab" end
    RefreshGarden(inst)
    if Backpacks.NeedsCraftedBackpack(inst) then return "backpack" end
    if #FindOwnedChests(inst) < M.BASE_CHEST_COUNT then return "treasurechest" end
    if (state.planted_grass or 0) < M.TRANSPLANT_TARGET
        or (state.planted_sapling or 0) < M.TRANSPLANT_TARGET then return "transplant" end
    if FindStructure(inst, "firepit") == nil then return "firepit" end
    return "complete"
end

local function RecipeAmount(inst, recipe_name, prefab)
    local recipe = GetValidRecipe(recipe_name)
    for _, ingredient in ipairs(recipe ~= nil and recipe.ingredients or {}) do
        if ingredient.type == prefab then
            return math.ceil(ingredient.amount * (inst.components.builder.ingredientmod or 1))
        end
    end
    return 0
end

local function CountNeededTransplants(inst)
    local state = inst._my_friend_base
    return math.min(CountInventory(inst, "dug_grass"),
            math.max(0, M.TRANSPLANT_TARGET - (state.planted_grass or 0)))
        + math.min(CountInventory(inst, "dug_sapling"),
            math.max(0, M.TRANSPLANT_TARGET - (state.planted_sapling or 0)))
end

local function GetNearbyMineAction(inst)
    local state = inst._my_friend_base
    if state == nil or state.complete or state.planting_trip
        or HasLeader(inst) or Backpacks.NeedsCraftedBackpack(inst)
        or GetFreeSlots(inst) < M.LOCAL_WORK_FREE_SLOTS
        or inst.components.hunger:GetPercent() < .5
        or FoodAI.GetFoodSupply(inst) < FoodAI.GetDailyHunger(inst) * .25
        or M.IsExtremeSeason(inst) or TheWorld.state.isdusk or TheWorld.state.isnight
        or CountNeededTransplants(inst) >= 6 then return end

    local firepit_rocks = FindStructure(inst, "firepit") == nil
        and RecipeAmount(inst, "firepit", "rocks") or 0
    local needs = {}
    for prefab, target in pairs({rocks = firepit_rocks + REQUIRED_STOCK_TARGETS.rocks,
        flint = 6, goldnugget = 4}) do
        local missing = target - M.CountBaseStock(inst, prefab)
        if missing > 0 and HasRoomForCarriedPrefab(inst, prefab) then needs[prefab] = missing end
    end
    if next(needs) == nil then return end
    -- Do not repick our overflow cache as an optional stockpiling task.
    local ground = GetNeededGroundAction(inst, needs, 8, false)
    if ground ~= nil then return ground end
    if GetTime() < (state.side_mine_after or 0)
        or not M.CanUseHandToolInCurrentLight(inst) then return end

    local pickaxe = FindTool(inst, ACTIONS.MINE)
    local recipe = GetValidRecipe("pickaxe")
    local can_craft = recipe ~= nil and inst.components.builder:KnowsRecipe(recipe)
        and inst.components.builder:HasIngredients(recipe)
        and CountInventory(inst, "twigs") >= RecipeAmount(inst, "pickaxe", "twigs") + 2
    if pickaxe == nil and not can_craft then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local best, distance
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, 8, {"MINE_workable"}, CANT_TAGS)) do
        local workable = entity.components.workable
        if workable ~= nil and workable:CanBeWorked()
            and workable:GetWorkAction() == ACTIONS.MINE
            and not IsBlocked(inst, entity) and IsOpportunityAhead(inst, entity)
            and not IsResourceUnsafe(inst, entity) then
            local wanted = false
            for prefab in pairs(ResourceMemory.MineProducts(entity)) do
                if needs[prefab] ~= nil then wanted = true break end
            end
            local uses = pickaxe ~= nil and pickaxe.components.finiteuses or nil
            local enough_tool = pickaxe == nil or uses == nil
                or uses:GetUses() >= math.ceil(workable:GetWorkLeft()
                    / pickaxe.components.tool:GetEffectiveness(ACTIONS.MINE))
                    * (uses.consumption[ACTIONS.MINE] or 1)
            local d = DistanceSq(inst, entity)
            if wanted and enough_tool and (distance == nil or d < distance) then
                best, distance = entity, d
            end
        end
    end
    if best == nil then return end
    if pickaxe == nil then return CreateBuildAction(inst, "pickaxe") end
    if not EquipTool(inst, pickaxe) then return end
    state.side_mine_after = GetTime() + 45
    return CreateGatherAction(inst, best, ACTIONS.MINE, pickaxe)
end

local function GetChestBatchCount(inst)
    local state = inst._my_friend_base
    local built = #FindOwnedChests(inst)
    if built >= M.BASE_CHEST_COUNT then state.chest_batch_goal = nil return 0 end
    local free, hunger = GetFreeSlots(inst), inst.components.hunger:GetPercent()
    local fooddays = FoodAI.GetFoodSupply(inst) / FoodAI.GetDailyHunger(inst)
    if state.chest_batch_goal == nil or state.chest_batch_goal <= built then
        local batch = free >= 6 and hunger >= .5 and fooddays >= .5 and 4
            or free >= 4 and hunger >= .4 and fooddays >= .25 and 2 or 1
        state.chest_batch_goal = math.min(M.BASE_CHEST_COUNT, built + batch)
    elseif free <= 2 or hunger < .35 then
        -- A changed survival/inventory situation may shorten the outing.
        state.chest_batch_goal = math.min(state.chest_batch_goal, built + 1)
    end
    return math.max(1, state.chest_batch_goal - built)
end

local function GetChestBatchAction(inst)
    local count = GetChestBatchCount(inst)
    if count == 0 then return end
    local boards_per_chest = RecipeAmount(inst, "treasurechest", "boards")
    local logs_per_board = RecipeAmount(inst, "boards", "log")
    if boards_per_chest == 0 or logs_per_board == 0 then
        return GetRecipeGoalAction(inst, "treasurechest")
    end
    local base = GetLayoutOrigin(inst)
    local near_base = DistanceSqToPoint(inst, base) <= M.BASE_RETURN_DISTANCE^2
    local boards = CountInventory(inst, "boards")
    local logs = CountInventory(inst, "log")
    local one_bill = math.max(0, boards_per_chest - boards) * logs_per_board
    if near_base and (boards >= boards_per_chest or logs >= one_bill) then
        return GetRecipeGoalAction(inst, "treasurechest")
    end
    local needed_boards = math.max(0, count * boards_per_chest - M.CountBaseStock(inst, "boards"))
    local ground_boards = GetNeededGroundAction(inst, {boards = needed_boards})
    if ground_boards ~= nil then return ground_boards end
    local needed_logs = math.max(0, needed_boards * logs_per_board + 2
        - M.CountBaseStock(inst, "log"))
    if needed_logs > 0 and not IsInventoryNearlyFull(inst) then
        M.SetTask(inst, "正在为这一批箱子收集木材")
        return GetGatherAction(inst, {log = needed_logs}, nil, nil, false)
    end
    return GetRecipeGoalAction(inst, "treasurechest")
end

local function GetProtectedCounts(inst)
    local function ReserveRecipe(targets, name, count, depth)
        local recipe = GetValidRecipe(name)
        if recipe == nil or depth > 4 then return end
        for _, ingredient in ipairs(recipe.ingredients or {}) do
            local amount = math.ceil(ingredient.amount
                * (inst.components.builder.ingredientmod or 1)) * count
            targets[ingredient.type] = (targets[ingredient.type] or 0) + amount
            if REFINABLE[ingredient.type] then
                local missing = amount - CountInventory(inst, ingredient.type)
                local child = GetValidRecipe(ingredient.type)
                if missing > 0 and child ~= nil then
                    ReserveRecipe(targets, ingredient.type,
                        math.ceil(missing / (child.numtogive or 1)), depth + 1)
                end
            end
        end
    end
    local targets = { cutgrass = 2, twigs = 2, log = 2, flint = 2 }
    local function ProtectRecovery(reserves)
        if inst._my_friend_recover_death_drops and FindTool(inst, ACTIONS.HAMMER) == nil then
            local recipe = GetValidRecipe("hammer")
            for _, ingredient in ipairs(recipe ~= nil and recipe.ingredients or {}) do
                reserves[ingredient.type] = math.max(reserves[ingredient.type] or 0,
                    math.ceil(ingredient.amount * (inst.components.builder.ingredientmod or 1))
                        + (CARRIED_MIN_RESERVES[ingredient.type] or 0))
            end
        end
        return reserves
    end
    local phase = M.GetConstructionPhase(inst)
    if phase == "complete" then
        local reserves = {}
        for prefab, count in pairs(CARRIED_RESERVES) do reserves[prefab] = count end
        local plot = inst._my_friend_base.forest
        if plot == nil or not plot.returning and plot.batch == nil then
            local missing = M.BASE_TREE_TARGET - #Forestry.Trees(inst)
            if missing > 0 then
                for _, prefab in ipairs({"pinecone", "acorn", "twiggy_nut"}) do
                    local keep = math.min(missing, CountInventory(inst, prefab))
                    reserves[prefab], missing = keep, missing - keep
                end
            end
        end
        Garden.ProtectFertilizer(inst, reserves, inst._my_friend_garden_barren or 0)
        if inst._my_friend_pending_recipe ~= nil then
            ReserveRecipe(reserves, inst._my_friend_pending_recipe, 1, 0)
        end
        if inst._my_friend_equipment_recipe ~= nil then
            ReserveRecipe(reserves, inst._my_friend_equipment_recipe, 1, 0)
        end
        return ProtectRecovery(reserves)
    end
    if phase == "transplant" or phase == "treasurechest" then
        targets.dug_grass = math.max(0, M.TRANSPLANT_TARGET - (inst._my_friend_base.planted_grass or 0))
        targets.dug_sapling = math.max(0, M.TRANSPLANT_TARGET - (inst._my_friend_base.planted_sapling or 0))
        if FindTool(inst, ACTIONS.DIG) == nil then ReserveRecipe(targets, "shovel", 1, 0) end
        if FindStructure(inst, "firepit") == nil then ReserveRecipe(targets, "firepit", 1, 0) end
        targets.flint = math.max(targets.flint, 4)
    end
    if phase == "treasurechest" then
        ReserveRecipe(targets, phase, GetChestBatchCount(inst), 0)
    elseif phase ~= "transplant" then
        ReserveRecipe(targets, phase, 1, 0)
    end
    if inst._my_friend_pending_recipe ~= nil then
        ReserveRecipe(targets, inst._my_friend_pending_recipe, 1, 0)
    end
    if inst._my_friend_equipment_recipe ~= nil then
        ReserveRecipe(targets, inst._my_friend_equipment_recipe, 1, 0)
    end
    return ProtectRecovery(targets)
end

local function GridPoint(base, index)
    local x, z = M.GetGridCoordinates(index)
    return Vector3(base.x + x, 0, base.z + z)
end

function M.GetGridCoordinates(index)
    local zero = math.max(0, index - 1)
    local column = zero % M.GRID_COLUMNS
    local row = math.floor(zero / M.GRID_COLUMNS)
    return (column - (M.GRID_COLUMNS - 1) / 2) * M.GRID_SPACING,
        7 + row * M.GRID_SPACING
end

local function IsGardenPoint(base, point)
    local half_width = ((M.GRID_COLUMNS - 1) / 2 + M.GARDEN_SPARE_COLUMNS)
        * M.GRID_SPACING + .5
    return math.abs(point.x - base.x) <= half_width
        and point.z >= base.z + 6.5
        and point.z <= base.z + 7 + (M.GRID_ROWS - 1) * M.GRID_SPACING + .5
end

RefreshGarden = function(inst)
    local state = inst._my_friend_base
    if state == nil or GetTime() < (state.garden_check_at or 0) then return end
    state.garden_check_at = GetTime() + 3
    local base = GetLayoutOrigin(inst)
    if base == nil then return end
    local grass, sapling, barren = 0, 0, 0
    for _, entity in ipairs(TheSim:FindEntities(base.x, 0, base.z,
        M.BASE_STRUCTURE_RANGE, nil, {"INLIMBO", "burnt", "FX"})) do
        if (entity.prefab == "grass" or entity.prefab == "sapling")
            and entity.components.pickable ~= nil
            and entity.components.pickable.transplanted
            and IsGardenPoint(base, entity:GetPosition()) then
            if entity.prefab == "grass" then grass = grass + 1
            else sapling = sapling + 1 end
            if entity.prefab == "grass" and entity.components.pickable:CanBeFertilized() then
                barren = barren + 1
            end
        end
    end
    state.planted_grass = math.min(M.TRANSPLANT_TARGET, grass)
    state.planted_sapling = math.min(M.TRANSPLANT_TARGET, sapling)
    inst._my_friend_garden_barren = barren
end

local function GetFertilizerPickup(inst)
    local state = inst._my_friend_base
    if state == nil or not M.IsComplete(inst) then return end
    if HasLeader(inst) or GetFreeSlots(inst) <= 2 or inst._my_friend_under_threat
        or M.IsStockStorageFull(inst)
        or M.IsExtremeSeason(inst) then
        state.fertilizer_trip = nil
        return
    end
    local now, trip = GetTime(), state.fertilizer_trip
    if trip ~= nil and (now >= trip.deadline
        or Garden.Supply(inst, FindOwnedChests(inst)) >= trip.wanted
        or trip.pickups >= 10) then
        state.fertilizer_trip = nil
        return
    end
    if trip == nil then
        if now < (state.fertilizer_search_after or 0) then return end
        -- A failed search also consumes this outing. Never retry it every tick.
        state.fertilizer_search_after = now + 2 * TUNING.TOTAL_DAY_TIME
        trip = {pickups = 0, wanted = 10, deadline = now + TUNING.TOTAL_DAY_TIME}
        state.fertilizer_trip = trip
    end
    local target = Garden.FindLoose(inst, 24, function(item)
        return not IsBlocked(inst, item) and not IsResourceUnsafe(inst, item)
            and Navigation.IsLand(item:GetPosition())
    end)
    if target == nil then
        local action, pending = require("my_friend_fertilizer_search").Action(inst, trip)
        if not pending then state.fertilizer_trip = nil end
        return action, pending
    end
    M.SetTask(inst, "正在外出收集这一批肥料")
    local action = TimedAction(inst, target, ACTIONS.PICKUP)
    action._my_friend_dialogue_kind = "fertilizer_collect"
    action:AddSuccessAction(function() trip.pickups = trip.pickups + 1 end)
    action:AddFailAction(function()
        if state.fertilizer_trip == trip then state.fertilizer_trip = nil end
    end)
    return action, true
end

local function GetGardenAction(inst)
    if not M.IsComplete(inst) then return end
    local plants, barren = Garden.Plants(inst, GetLayoutOrigin(inst),
        M.BASE_STRUCTURE_RANGE, IsGardenPoint)
    inst._my_friend_garden_barren = barren
    if inst._my_friend_base.fertilizer_trip ~= nil then
        local collecting, pending = GetFertilizerPickup(inst)
        if collecting ~= nil or pending then return collecting, pending end
    end
    local fertilizer = Garden.Carried(inst)
    local stored_fertilizer = false
    if fertilizer ~= nil and barren > 0 then
        for _, plant in ipairs(plants) do
            if plant.prefab == "grass" and plant.components.pickable:CanBeFertilized()
                and not IsBlocked(inst, plant) and not IsResourceUnsafe(inst, plant) then
                local action = TimedAction(inst, plant, ACTIONS.FERTILIZE, fertilizer)
                local valid = action.validfn
                action.validfn = function(act)
                    return valid(act) and plant.components.pickable:CanBeFertilized()
                        and Garden.IsFertilizer(fertilizer)
                end
                action:AddSuccessAction(function() inst._my_friend_base.garden_check_at = 0 end)
                M.SetTask(inst, "正在给基地草丛施肥")
                return action
            end
        end
    elseif barren > 0 then
        for _, chest in ipairs(FindOwnedChests(inst)) do
            for _, item in pairs(chest.components.container.slots) do
                if Garden.IsFertilizer(item) then
                    stored_fertilizer = true
                    local action = GetWithdrawAction(inst, {[item.prefab] = math.min(10, barren)})
                    if action ~= nil then return action end
                end
            end
        end
    end
    if not M.IsStockStorageFull(inst) then
        for _, plant in ipairs(plants) do
            local pickable = plant.components.pickable
            local product = pickable.product
            local surplus = math.max(0, CountInventory(inst, product) - (CARRIED_RESERVES[product] or 0))
            if pickable.caninteractwith and pickable:CanBePicked()
                and not IsBlocked(inst, plant) and not IsResourceUnsafe(inst, plant)
                and HasRoomForCarriedPrefab(inst, product)
                and M.GetStockCapacity(inst, product) > surplus then
                M.SetTask(inst, "正在采收基地长好的草丛和树苗")
                local action = TimedAction(inst, plant, ACTIONS.PICK)
                action:AddSuccessAction(function()
                    inst._my_friend_garden_harvest_count = (inst._my_friend_garden_harvest_count or 0) + 1
                    if inst._my_friend_garden_harvest_count >= 6
                        and CountInventory(inst, product) > (CARRIED_RESERVES[product] or 0) then
                        inst._my_friend_garden_delivery = true
                    end
                end)
                return action
            end
        end
    end
    if (inst._my_friend_garden_harvest_count or 0) > 0
        and (CountInventory(inst, "cutgrass") > CARRIED_RESERVES.cutgrass
            or CountInventory(inst, "twigs") > CARRIED_RESERVES.twigs) then
        inst._my_friend_garden_delivery = true
        return
    end
    if barren > 0 and fertilizer == nil and not stored_fertilizer
        and not M.IsExtremeSeason(inst) then
        return GetFertilizerPickup(inst)
    end
end

local function FindDeployPoint(inst, item, start_index, end_index)
    local base = GetLayoutOrigin(inst)
    local state = inst._my_friend_base
    state.garden_blocked = state.garden_blocked or {}
    M.PruneExpiredEntries(state.garden_blocked, GetTime())
    local function Available(point, slot)
        local key = item.prefab..":"..slot
        if state.garden_blocked[key] == nil and IsPassable(point)
            and not Navigation.IsBlocked(inst, point)
            and item.components.deployable:CanDeploy(point, nil, inst, 0) then
            return point, key
        end
    end
    -- Always revisit empty slots: the number planted is not a slot index.
    for index = start_index, end_index do
        local point = GridPoint(base, index)
        local available, key = Available(point, tostring(index))
        if available ~= nil then return available, key end
    end
    -- Bounded spare columns accommodate obstacles without moving the garden.
    local first_row = math.floor((start_index - 1) / M.GRID_COLUMNS)
    local last_row = math.floor((end_index - 1) / M.GRID_COLUMNS)
    for extra = 1, M.GARDEN_SPARE_COLUMNS do
        for row = first_row, last_row do
            for _, side in ipairs({-1, 1}) do
                local point = Vector3(base.x + side
                    * ((M.GRID_COLUMNS - 1) / 2 + extra) * M.GRID_SPACING, 0,
                    base.z + 7 + row * M.GRID_SPACING)
                local slot = string.format("spare:%d:%d:%d", extra, row, side)
                local available, key = Available(point, slot)
                if available ~= nil then return available, key end
            end
        end
    end
end

local function GetTransplantAction(inst, plant_only)
    local state = inst._my_friend_base
    RefreshGarden(inst)
    local grass_total = (state.planted_grass or 0) + CountInventory(inst, "dug_grass")
    local sapling_total = (state.planted_sapling or 0) + CountInventory(inst, "dug_sapling")
    local carried = CountNeededTransplants(inst)
    if carried == 0 then state.planting_trip = nil end
    if plant_only and carried == 0 then return end
    local near_base = DistanceSqToPoint(inst, GetLayoutOrigin(inst)) <= M.BASE_RETURN_DISTANCE^2
    if (grass_total < M.TRANSPLANT_TARGET or sapling_total < M.TRANSPLANT_TARGET)
        and not plant_only and not state.planting_trip
        and not (carried >= 6 or carried > 0 and (near_base or IsInventoryNearlyFull(inst))) then
        local needs = {}
        if grass_total < M.TRANSPLANT_TARGET then
            needs.dug_grass = M.TRANSPLANT_TARGET - grass_total
        end
        if sapling_total < M.TRANSPLANT_TARGET then
            needs.dug_sapling = M.TRANSPLANT_TARGET - sapling_total
        end
        local ground = GetNeededGroundAction(inst, needs)
        if ground ~= nil then return ground end
        -- Ground transplants need no shovel; only prepare it for digging.
        if FindTool(inst, ACTIONS.DIG) == nil then return GetRecipeGoalAction(inst, "shovel") end
        return GetGatherAction(inst, needs)
    end

    for _, data in ipairs({
        { prefab = "dug_grass", field = "planted_grass", first = 1, last = 30 },
        { prefab = "dug_sapling", field = "planted_sapling", first = 31, last = 60 },
    }) do
        if (state[data.field] or 0) < M.TRANSPLANT_TARGET then
            local item = inst.components.inventory:FindItem(function(value)
                return value.prefab == data.prefab and value.components.deployable ~= nil
            end)
            if item ~= nil then
                local point, slot = FindDeployPoint(inst, item, data.first, data.last)
                if point ~= nil then
                    state.planting_trip = true
                    state.garden_waiting = nil
                    state.resource_search = nil
                    local action = BufferedAction(inst, nil, ACTIONS.DEPLOY, item, point)
                    M.SetTask(inst, "正在把移植物种回基地")
                    action.validfn = function()
                        return item:IsValid() and item.components.deployable ~= nil
                            and IsGardenPoint(GetLayoutOrigin(inst), point)
                            and item.components.deployable:CanDeploy(point, nil, inst, 0)
                    end
                    action:AddFailAction(function()
                        if action._my_friend_cancelled then return end
                        if inst:IsValid() and inst._my_friend_base == state then
                            state.garden_blocked[slot] = GetTime() + M.RETRY_DELAY
                        end
                    end)
                    action:AddSuccessAction(function()
                        if inst._my_friend_base ~= nil then
                            inst._my_friend_base[data.field] = math.min(M.TRANSPLANT_TARGET,
                                (inst._my_friend_base[data.field] or 0) + 1)
                            inst._my_friend_base.garden_check_at = 0
                        end
                    end)
                    return action
                end
                state.garden_waiting = true
            end
        end
    end
    state.planting_trip = nil
end

local function GetNearbyTransplantAction(inst)
    if GetFreeSlots(inst) <= 3
        or inst.components.hunger:GetPercent() < .4 then return end
    local state = inst._my_friend_base
    local grass, sapling = CountInventory(inst, "dug_grass"), CountInventory(inst, "dug_sapling")
    -- A small side batch must not consume all the space reserved for timber.
    if CountNeededTransplants(inst) >= 6 then return end
    local ground = GetNeededGroundAction(inst, {
        dug_grass = M.TRANSPLANT_TARGET - grass - (state.planted_grass or 0),
        dug_sapling = M.TRANSPLANT_TARGET - sapling - (state.planted_sapling or 0),
    }, 8)
    if ground ~= nil then return ground end
    if not M.CanUseHandToolInCurrentLight(inst) then return end
    local shovel = FindTool(inst, ACTIONS.DIG)
    if shovel == nil then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local best, best_distance
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, 8, {"DIG_workable"}, CANT_TAGS)) do
        local wanted = entity.prefab == "grass" and grass + (state.planted_grass or 0) < M.TRANSPLANT_TARGET
            or entity.prefab == "sapling" and sapling + (state.planted_sapling or 0) < M.TRANSPLANT_TARGET
        local workable = entity.components.workable
        if wanted and IsWildPlant(entity) and not IsBlocked(inst, entity)
            and workable ~= nil and workable:CanBeWorked() and workable:GetWorkAction() == ACTIONS.DIG
            and not IsResourceUnsafe(inst, entity) then
            local d = DistanceSq(inst, entity)
            if best_distance == nil or d < best_distance then best, best_distance = entity, d end
        end
    end
    if best ~= nil and EquipTool(inst, shovel) then
        return CreateGatherAction(inst, best, ACTIONS.DIG, shovel)
    end
end

local function ForestTargetAllowed(inst, entity)
    return not IsBlocked(inst, entity) and not IsResourceUnsafe(inst, entity)
end

local function GetStumpAction(inst)
    if not M.CanUseHandToolInCurrentLight(inst) then return end
    local shovel = FindTool(inst, ACTIONS.DIG)
    if shovel == nil then return end
    local stump = Forestry.GetStump(inst, function(tree)
        local workable = tree.components.workable
        return workable ~= nil and workable:CanBeWorked()
            and workable:GetWorkAction() == ACTIONS.DIG and ForestTargetAllowed(inst, tree)
            and DistanceSq(inst, tree) <= M.RESOURCE_SEARCH_RANGE ^ 2
            and Policy.InRange(inst, tree, M.RESOURCE_SEARCH_RANGE)
    end)
    if stump == nil then return end
    if not EquipTool(inst, shovel) then return end
    local action = CreateGatherAction(inst, stump, ACTIONS.DIG, shovel)
    M.SetTask(inst, "正在挖掉砍伐后的树根")
    return action
end

local function EnsureForest(inst)
    return Forestry.EnsurePlot(inst, GetLayoutOrigin(inst), IsPassable, function(point)
        for _, entity in ipairs(TheSim:FindEntities(point.x, 0, point.z, 8,
            {"_combat"}, CANT_TAGS)) do
            if BehaviourAI.IsThreat(inst, entity) then return false end
        end
        return true
    end)
end

local function GetForestClearAction(inst)
    local plot = EnsureForest(inst)
    if plot == nil or plot.returning then return nil, false end
    local work, blocker = Forestry.InspectPlot(inst, plot)
    if blocker ~= nil then Forestry.RejectPlot(inst, plot) return nil, true end
    if #work == 0 then
        if (plot.clear_loot or 0) > 0 then plot.returning = true end
        return nil, false
    end
    if M.IsExtremeSeason(inst)
        or inst.components.hunger:GetPercent() < .4
        or GetFreeSlots(inst) <= M.INVENTORY_FREE_SLOT_RESERVE then
        if (plot.clear_loot or 0) > 0 then plot.returning = true end
        return nil, true
    end
    for _, entry in ipairs(work) do
        local target, action_type = entry.target, entry.action
        local useful = GROUND_RESOURCES[target.prefab] or Forestry.IsUsefulLooseItem(target)
        local discard = action_type == ACTIONS.PICKUP and not useful
        if ForestTargetAllowed(inst, target) and (discard or not M.IsStockStorageFull(inst)) then
            local recipe_name = GetToolRecipe(action_type)
            local tool
            if recipe_name ~= nil then
                if not M.CanUseHandToolInCurrentLight(inst) then return nil, true end
                tool = FindTool(inst, action_type)
                if tool == nil then return GetRecipeGoalAction(inst, recipe_name), true end
                if not EquipTool(inst, tool) then return nil, true end
            end
            if action_type ~= ACTIONS.PICKUP or CanPickUp(inst, target, true) then
                inst._my_friend_forest_clear_target = target
                inst._my_friend_tool_needs = inst._my_friend_tool_needs or {}
                if tool ~= nil then inst._my_friend_tool_needs[action_type.id] = GetTime() + 90 end
                local action = CreateGatherAction(inst, target, action_type, tool)
                if action_type == ACTIONS.PICKUP then
                    local prefab, amount = target.prefab, StackSize(target)
                    action:AddSuccessAction(function()
                        if discard then
                            Forestry.QueueDiscard(inst, prefab, amount, plot)
                        else
                            plot.clear_loot = (plot.clear_loot or 0) + 1
                            if plot.clear_loot >= 6 or IsInventoryNearlyFull(inst) then plot.returning = true end
                        end
                    end)
                end
                M.SetTask(inst, "正在清理林区里的杂树、植物和矿石")
                return action, true
            end
        end
    end
    return nil, true
end

local function GetForestDiscardAction(inst)
    local queue = inst._my_friend_forest_discard
    while queue ~= nil and #queue > 0 do
        local entry = queue[1]
        local item = inst.components.inventory:FindItem(function(value)
            return value.prefab == entry.prefab and value.components.inventoryitem ~= nil
                and not value.components.inventoryitem.islockedinslot
                and not value.components.inventoryitem.cannotdrop
        end)
        if item == nil or entry.count <= 0 then
            table.remove(queue, 1)
        else
            if GROUND_RESOURCES[item.prefab] or Forestry.IsUsefulLooseItem(item) then
                table.remove(queue, 1)
                return
            end
            local point = entry.point
            if point == nil or not Navigation.IsLand(point) then
                point = Forestry.DiscardPoint(inst, entry, GetLayoutOrigin(inst), function(candidate)
                    return Navigation.IsLand(candidate) and not Navigation.IsBlocked(inst, candidate)
                        and Navigation.IsClear(inst:GetPosition(), candidate, Navigation.Caps(inst))
                end)
                entry.point = point
            end
            if point == nil then return end
            M.SetTask(inst, "正在把林区杂物搬到基地和林区以外")
            if DistanceSqToPoint(inst, point) > 2^2 then
                local action = MoveAction(inst, point)
                action.arrivedist = 1
                action:AddFailAction(function() entry.point = nil end)
                return action
            end
            local amount = StackSize(item)
            local action = BufferedAction(inst, nil, ACTIONS.DROP, item, point)
            action.options.wholestack = true
            action:AddSuccessAction(function()
                entry.count = math.max(0, entry.count - amount)
                if item:IsValid() then item._my_friend_discarded = true end
            end)
            action.validfn = function()
                return item:IsValid() and DistanceSqToPoint(inst, point) <= 3^2
                    and DistanceSqToPoint(inst, GetLayoutOrigin(inst)) > 38^2
            end
            return action
        end
    end
end

local function GetTreePlantAction(inst)
    local plot = EnsureForest(inst)
    if plot == nil or plot.batch ~= nil or plot.returning
        or #Forestry.Trees(inst) >= M.BASE_TREE_TARGET or M.IsExtremeSeason(inst) then return end
    local item = inst.components.inventory:FindItem(function(value)
        return (value.prefab == "pinecone" or value.prefab == "acorn"
            or value.prefab == "twiggy_nut") and value.components.deployable ~= nil
    end)
    if item == nil then
        if M.IsStockStorageFull(inst) or GetFreeSlots(inst) <= M.INVENTORY_FREE_SLOT_RESERVE then return end
        for _, prefab in ipairs({"pinecone", "acorn", "twiggy_nut"}) do
            local stored = GetWithdrawAction(inst, {[prefab] = math.min(5,
                M.BASE_TREE_TARGET - #Forestry.Trees(inst))})
            if stored ~= nil then return stored end
        end
        return GetNeededGroundAction(inst, {pinecone = 1, acorn = 1, twiggy_nut = 1}, 12)
    end
    local point, index = Forestry.FindPlantPoint(inst, item, IsPassable)
    if point == nil then return end
    local action = BufferedAction(inst, nil, ACTIONS.DEPLOY, item, point)
    local deadline = GetTime() + M.ACTION_TIMEOUT + math.sqrt(DistanceSqToPoint(inst, point)) / 3
    action.validfn = function()
        return inst._my_friend_base.forest == plot and GetTime() < math.max(deadline,
            action._my_friend_travel_until or 0,
            (action._my_friend_travel_finished or 0) + M.ACTION_TIMEOUT)
            and item:IsValid() and item.components.deployable ~= nil
            and #Forestry.Trees(inst) < M.BASE_TREE_TARGET
            and item.components.deployable:CanDeploy(point, nil, inst, 0)
    end
    action:AddFailAction(function()
        if action._my_friend_cancelled then return end
        plot.blocked[index] = GetTime() + M.RETRY_DELAY
        plot.deploy_failures = (plot.deploy_failures or 0) + 1
        if plot.deploy_failures >= 3 then Forestry.RejectPlot(inst, plot) end
    end)
    action:AddSuccessAction(function()
        plot.deploy_failures = nil
        Forestry.RecordPlant(inst, plot, point)
    end)
    M.SetTask(inst, "正在远离基地的方形林区补种树木")
    return action
end

local function GetBaseWoodAction(inst)
    local plot = EnsureForest(inst)
    if plot == nil or plot.returning or M.IsStockStorageFull(inst)
        or M.IsExtremeSeason(inst) or not M.CanUseHandToolInCurrentLight(inst)
        or inst.components.hunger:GetPercent() < .4 then return end
    local spare = M.GetStockCapacity(inst, "log")
        - math.max(0, CountInventory(inst, "log") - CARRIED_RESERVES.log)
    if GetFreeSlots(inst) <= M.INVENTORY_FREE_SLOT_RESERVE or spare < 4 then
        if plot.batch ~= nil then plot.returning = true end
        return
    end
    local tree = Forestry.GetBatchTarget(inst, function(entity)
        return ForestTargetAllowed(inst, entity)
    end, spare >= Forestry.BATCH_SIZE * 4 and GetFreeSlots(inst) >= 4)
    if tree == nil then return end
    local axe = FindTool(inst, ACTIONS.CHOP)
    if axe == nil then return GetRecipeGoalAction(inst, "axe") end
    if not EquipTool(inst, axe) then return end
    return CreateGatherAction(inst, tree, ACTIONS.CHOP, axe)
end

local function FindFuelItem(inst, source)
    for _, prefab in ipairs({"log", "twigs", "cutgrass"}) do
        local item = inst.components.inventory:FindItem(function(candidate)
            return candidate.prefab == prefab
                and source.components.fueled:CanAcceptFuelItem(candidate)
        end)
        if item ~= nil then return item end
    end
end

local function CreateFuelAction(inst, source)
    if IsBlocked(inst, source) then return end
    local fuel = FindFuelItem(inst, source)
    if fuel ~= nil then
        M.SetTask(inst, "正在使用基地火坑")
        return TimedAction(inst, source, ACTIONS.ADDFUEL, fuel)
    end
    for _, prefab in ipairs({"log", "twigs", "cutgrass"}) do
        local action = GetWithdrawAction(inst, {[prefab] = 1})
        if action ~= nil then return action end
    end
end

local function GetFuelAction(inst)
    local temperature = inst.components.temperature
    local current = temperature ~= nil and temperature.current or nil
    local dark = LightAI.IsEnvironmentDark(inst)
    local source_prefab = M.GetBaseFirePrefab(dark, current)
    local source = source_prefab ~= nil and FindStructure(inst, source_prefab) or nil
    local fueled = source ~= nil and source.components.fueled or nil
    if fueled == nil then return end
    if fueled:GetPercent() >= .35 then
        if dark and source.prefab == "firepit" then
            M.SetTask(inst, "正在使用基地火坑")
        end
        return
    end
    return CreateFuelAction(inst, source)
end

function M.GetBaseFirePrefab(environment_dark, current_temperature)
    if current_temperature ~= nil and current_temperature >= M.BASE_HOT_TEMPERATURE then
        return "coldfirepit"
    end
    if environment_dark
        or current_temperature ~= nil and current_temperature <= M.BASE_COLD_TEMPERATURE then
        return "firepit"
    end
end

function M.ShouldPreferBaseFire(inst)
    if not M.IsComplete(inst) or HasLeader(inst) or inst._my_friend_under_threat then return false end
    local state = TheWorld ~= nil and TheWorld.state or nil
    local base = M.GetBasePoint(inst)
    return state ~= nil and (state.isdusk or state.isnight or TheWorld:HasTag("cave"))
        and base ~= nil and DistanceSqToPoint(inst, base) <= M.BASE_FIRE_RANGE^2
end

local function FindNightBaseFire(inst)
    local temperature = inst.components.temperature
    local prefab = M.GetBaseFirePrefab(true, temperature ~= nil and temperature.current or nil)
    return prefab ~= nil and FindStructure(inst, prefab) or nil
end

function M.GetBaseFireAction(inst)
    local prefer_fire = M.ShouldPreferBaseFire(inst)
    if not CanAct(inst) or HasLeader(inst) or inst._my_friend_under_threat
        or not prefer_fire and (inst._my_friend_work_target ~= nil
            or inst._my_friend_work_cleanup ~= nil) then
        return
    end
    local base = M.GetBasePoint(inst)
    if base == nil or DistanceSqToPoint(inst, base) > M.BASE_FIRE_RANGE ^ 2 then return end
    local world_dark = TheWorld ~= nil and TheWorld.state ~= nil
        and (TheWorld.state.isnight or TheWorld.state.isdusk
            or TheWorld:HasTag("cave"))
    local firepit = world_dark and FindNightBaseFire(inst) or nil
    if firepit ~= nil and firepit.components.fueled ~= nil then
        if firepit.components.fueled:GetPercent() < .35 then
            local fuel = CreateFuelAction(inst, firepit)
            if fuel ~= nil then return fuel end
        end
        if prefer_fire and not firepit.components.fueled:IsEmpty()
            and not LightAI.IsExternallyLit(inst) and not IsBlocked(inst, firepit)
            and DistanceSq(inst, firepit) > 2.5^2 then
            M.SetTask(inst, "正在靠近基地火坑照明")
            return MoveNearEntityAction(inst, firepit, 2)
        end
        M.SetTask(inst, "正在使用基地火坑")
        return
    end
    return GetFuelAction(inst)
end

local function GetMaintenanceNeeds(inst)
    local needs = {}
    if M.IsStockStorageFull(inst) then return needs end
    for prefab, target in pairs(REQUIRED_STOCK_TARGETS) do
        local carried_surplus = math.max(0, CountInventory(inst, prefab) - (CARRIED_RESERVES[prefab] or 0))
        local missing = M.UpdateStockNeed(M.CountBaseStoredStock(inst, prefab) + carried_surplus, target)
        local room = M.GetStockCapacity(inst, prefab)
            - math.max(0, CountInventory(inst, prefab) - (CARRIED_RESERVES[prefab] or 0))
        if missing > 0 and room > 0 then needs[prefab] = math.min(missing, room) end
    end
    return needs
end

local function GetCarriedReserveNeeds(inst)
    local needs = {}
    local has_light_equipment = LightAI.HasUsableEquippedLight(inst)
        or LightAI.FindBestStoredLight(inst) ~= nil
    for _, prefab in ipairs({"cutgrass", "twigs", "log", "flint"}) do
        local target = Reserves.FOLLOW_TARGETS[prefab]
        local count = CountInventory(inst, prefab)
        local minimum = CARRIED_MIN_RESERVES[prefab] or 0
        local reserve_target = has_light_equipment and minimum or target
        local required = count < minimum and minimum or reserve_target
        local missing = M.UpdateStockNeed(count, required)
        if missing > 0 then needs[prefab] = missing end
    end
    return needs
end

function M.GetCarriedReserveTarget(count, minimum, target)
    return (count or 0) < (minimum or 0) and (minimum or 0) or (target or 0)
end

local function IsEquippedItem(inst, item)
    return EquipSlots.IsEquipped(inst.components.inventory, item)
end

local function IsEssentialCarriedItem(inst, item, equipment)
    if item == nil then return true end
    if equipment[item] ~= nil then return true end
    if item.prefab == "beefalofeed" and require("my_friend_riding").GetBoundBeefalo(inst) ~= nil then
        return true
    end
    if item:HasTag("backpack") or item:HasTag("heatrock") then return true end
    local components = item.components
    if components == nil then return false end
    local eater = inst.components.eater
    if components.edible ~= nil and eater ~= nil
        and eater:CanEat(item) and eater:PrefersToEat(item)
        or LightAI.IsLightEquipment(item) then return true end
    return false
end

local function IsStorableItem(inst, item, equipment)
    local inventoryitem = item ~= nil and item.components ~= nil
        and item.components.inventoryitem or nil
    if inventoryitem == nil or inventoryitem.islockedinslot then return false end
    if equipment[item] ~= nil or IsEquippedItem(inst, item) then return false end
    if Storage.IsCargo(inst, item) then return false end
    if item:HasTag("irreplaceable") or item:HasTag("heavy") then return false end
    if Garden.IsFertilizer(item) then return true end
    local tool = item.components.tool
    if tool ~= nil and M.IsComplete(inst) then
        local plot = inst._my_friend_base.forest
        for _, action in ipairs({ACTIONS.CHOP, ACTIONS.MINE, ACTIONS.DIG, ACTIONS.HAMMER}) do
            if tool:GetEffectiveness(action) > 0 then
                if inst._my_friend_work_action == action
                    or inst._my_friend_tool_needs ~= nil
                        and GetTime() < (inst._my_friend_tool_needs[action.id] or 0)
                    or plot ~= nil and plot.batch ~= nil and not plot.returning
                        and (action == ACTIONS.CHOP or action == ACTIONS.DIG)
                    or action == ACTIONS.DIG and #(inst._my_friend_base.tree_stumps or {}) > 0 then
                    return false
                end
            end
        end
        return true
    end
    if IsEssentialCarriedItem(inst, item, equipment) then return false end
    local transplant_needed = (item.prefab == "dug_grass"
            and (inst._my_friend_base.planted_grass or 0) < M.TRANSPLANT_TARGET)
        or (item.prefab == "dug_sapling"
            and (inst._my_friend_base.planted_sapling or 0) < M.TRANSPLANT_TARGET)
    return not transplant_needed
end

local function CountCarriedForStorage(inst, prefab)
    -- Inventory:Has excludes equipped tools and may include open external chests.
    local count = 0
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if item.prefab == prefab then count = count + StackSize(item) end
    end
    return count
end

local function GetStoreAction(inst)
    if ACTIONS.MY_FRIEND_STORE == nil or inst._my_friend_storage_action then return end
    local chest, plan, best_score
    local protected = GetProtectedCounts(inst)
    local equipment = EquipmentReserves.GetKeep(inst)
    local chests = FindOwnedChests(inst)
    local preferred = {}
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if IsStorableItem(inst, item, equipment) then
            preferred[item] = Storage.PreferredChest(inst, chests, item)
        end
    end
    for _, candidate in ipairs(chests) do
        local container = candidate.components.container
        if container ~= nil and InventoryAI.StorageReady(inst, candidate) and not container.readonlycontainer
            and not container:IsRestricted(inst) and not container:IsOpenedByOthers(inst)
            and not IsBlocked(inst, candidate) then
            local candidate_plan, remaining_by_prefab, merge_count = {}, {}, 0
            for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
                if IsStorableItem(inst, item, equipment) and preferred[item] == candidate then
                    if remaining_by_prefab[item.prefab] == nil then
                        remaining_by_prefab[item.prefab] = math.max(0,
                            CountCarriedForStorage(inst, item.prefab) - (protected[item.prefab] or 0))
                    end
                    local count = math.min(StackSize(item), remaining_by_prefab[item.prefab],
                        container:CanAcceptCount(item))
                    if count > 0 then
                        candidate_plan[#candidate_plan + 1] = {item = item, count = count}
                        remaining_by_prefab[item.prefab] = remaining_by_prefab[item.prefab] - count
                        local room = 0
                        for _, stored in pairs(container.slots) do
                            if InventoryAI.CanMerge(stored, item) then
                                room = room + stored.components.stackable:RoomLeft()
                            end
                        end
                        merge_count = merge_count + math.min(count, room)
                    end
                end
            end
            local score = merge_count * 1000 - DistanceSq(inst, candidate)
            if #candidate_plan > 0 and (best_score == nil or score > best_score) then
                chest, plan, best_score = candidate, candidate_plan, score
            end
        end
    end
    if chest == nil then return end
    local action = TimedAction(inst, chest, ACTIONS.MY_FRIEND_STORE, plan[1].item)
    action._my_friend_store_plan = plan
    inst._my_friend_storage_action = action
    action:AddFailAction(function()
        if inst:IsValid() and inst._my_friend_storage_action == action then
            inst._my_friend_storage_action = nil
        end
    end)
    M.SetTask(inst, "正在回基地整理物资")
    return action
end

local function GetOrganizeAction(inst)
    if ACTIONS.MY_FRIEND_ORGANIZE == nil or inst._my_friend_storage_action then return end
    local chests = FindOwnedChests(inst)
    local transfer = Storage.GetAction(inst, chests, TimedAction)
    if transfer ~= nil then
        M.SetTask(inst, "正在跨箱归并相同物资")
        return transfer
    end
    for _, chest in ipairs(chests) do
        local container = chest.components.container
        if container ~= nil and not container.readonlycontainer
            and not container:IsRestricted(inst) and not container:IsOpenedByOthers(inst)
            and InventoryAI.StorageReady(inst, chest)
            and not IsBlocked(inst, chest) and InventoryAI.NeedsContainerMerge(container) then
            local action = TimedAction(inst, chest, ACTIONS.MY_FRIEND_ORGANIZE)
            inst._my_friend_storage_action = action
            action:AddFailAction(function()
                if inst._my_friend_storage_action == action then inst._my_friend_storage_action = nil end
            end)
            M.SetTask(inst, "正在合并箱子里的零散物资")
            return action
        end
    end
end

function M.GetRecoveryStoreAction(inst)
    if not CanAct(inst) or HasLeader(inst) or inst._my_friend_base == nil then return end
    return GetStoreAction(inst) or M.GetInventoryReliefAction(inst)
end

function M.GetRecoveryDeliveryAction(inst)
    if not inst._my_friend_recovery_delivery or HasLeader(inst) or not CanAct(inst) then return end
    local action = M.GetRecoveryStoreAction(inst)
    if action ~= nil then return action end
    inst._my_friend_recovery_delivery = nil
end

function M.GetInventoryReliefAction(inst)
    if not CanAct(inst) or HasLeader(inst) or M.EnsureBase(inst) == nil then return end
    if GetFreeSlots(inst) > M.INVENTORY_FREE_SLOT_RESERVE then return end
    -- No base of its own: use any chests it already owns, never start a
    -- ground cache next to somebody else's camp.
    if Home.NoConstruction(inst) then return GetStoreAction(inst) end
    local phase = M.GetConstructionPhase(inst)
    if phase == "complete" then return GetStoreAction(inst) or GetOrganizeAction(inst) end
    local recipe = GetValidRecipe(phase)
    -- Spend ready building materials before making a storage trip.
    if recipe ~= nil and recipe.placer ~= nil
        and inst.components.builder:HasIngredients(recipe) then return end
    if phase == "backpack" and GetFreeSlots(inst) > 0
        and recipe ~= nil and inst.components.builder:HasIngredients(recipe) then return end
    if (phase == "transplant" or phase == "treasurechest")
        and CountNeededTransplants(inst) > 0 then
        local plant = GetTransplantAction(inst, true)
        if plant ~= nil then return plant end
    end
    local protected = GetProtectedCounts(inst)
    local items = inst.components.inventory:ReferenceAllItems()
    local best, bestscore
    local supply = FoodAI.GetFoodSupply(inst)
    local equipment = EquipmentReserves.GetKeep(inst)
    for _, item in ipairs(items) do
        local c = item.components
        if c ~= nil and c.inventoryitem ~= nil and not c.inventoryitem.cannotdrop
            and equipment[item] == nil
            and not Storage.IsCargo(inst, item)
            and not IsEquippedItem(inst, item) and not item:HasAnyTag("irreplaceable", "heavy", "backpack") then
            local removable = CountInventory(inst, item.prefab) - StackSize(item)
                >= (protected[item.prefab] or 0)
            local score = 0
            if c.edible ~= nil and inst.components.eater ~= nil
                and inst.components.eater:CanEat(item) and inst.components.eater:PrefersToEat(item) then
                local health, calories = FoodAI.GetFoodDeltas(inst, item)
                local nutrition = health >= 0 and math.max(0, calories) * StackSize(item) or 0
                removable = supply - nutrition >= FoodAI.GetDailyHunger(inst)
                score = 30 + nutrition
            elseif c.tool ~= nil then
                removable = false
                for _, other in ipairs(items) do
                    if other ~= item and other.prefab == item.prefab then removable = true break end
                end
                score = 20
            elseif IsEssentialCarriedItem(inst, item, equipment) then
                removable = false
            elseif (protected[item.prefab] or 0) > 0 then
                score = 15
            end
            if removable and (bestscore == nil or score < bestscore) then best, bestscore = item, score end
        end
    end
    if best == nil then return end
    ClearWorkTarget(inst)
    for _, chest in ipairs(FindOwnedChests(inst)) do
        local container = chest.components.container
        if container ~= nil and InventoryAI.StorageReady(inst, chest) and not container:IsFull() and not container:IsOpenedByOthers(inst)
            and container:CanTakeItemInSlot(best) and ACTIONS.MY_FRIEND_STORE ~= nil then
            local action = BufferedAction(inst, chest, ACTIONS.MY_FRIEND_STORE, best)
            action._my_friend_store_plan = {{item = best, count = StackSize(best)}}
            inst._my_friend_storage_action = action
            action:AddFailAction(function()
                if inst._my_friend_storage_action == action then inst._my_friend_storage_action = nil end
            end)
            M.SetTask(inst, "正在回基地腾出制作空间")
            return action
        end
    end
    local state, base = inst._my_friend_base, GetLayoutOrigin(inst)
    local point = state.cache_x ~= nil and Vector3(state.cache_x, 0, state.cache_z) or nil
    if point == nil then
        for _, offset in ipairs({{9, 1}, {-9, 1}, {12, 3}, {-12, 3}, {14, -2}}) do
            local candidate = Vector3(base.x + offset[1], 0, base.z + offset[2])
            if IsPassable(candidate) then point = candidate break end
        end
        if point == nil then return end
        state.cache_x, state.cache_z = point.x, point.z
    end
    M.SetTask(inst, "正在基地暂存非急需物资")
    if DistanceSqToPoint(inst, point) > 4 then
        local action = MoveAction(inst, point)
        action.arrivedist = 1
        return action
    end
    local action = BufferedAction(inst, nil, ACTIONS.DROP, best, point)
    action.options.wholestack = true
    return action
end

HasStorableInventory = function(inst)
    local protected = GetProtectedCounts(inst)
    local equipment = EquipmentReserves.GetKeep(inst)
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if IsStorableItem(inst, item, equipment)
            and CountCarriedForStorage(inst, item.prefab)
                > (protected[item.prefab] or 0) then
            return true
        end
    end
    return false
end

function M.GetSurplusStoreAction(inst)
    if not CanAct(inst) or HasLeader(inst) or not M.IsComplete(inst)
        or inst._my_friend_under_threat or inst._my_friend_chest_transfer ~= nil then return end
    local near_base = DistanceSqToPoint(inst, GetLayoutOrigin(inst)) <= M.BASE_RETURN_DISTANCE^2
    local full = IsInventoryNearlyFull(inst)
    if not full and (inst._my_friend_work_target ~= nil or inst._my_friend_work_cleanup ~= nil) then return end
    local forest = inst._my_friend_base.forest
    if not near_base and not full and forest ~= nil and forest.batch ~= nil
        and not forest.returning then return end
    local surplus = 0
    for prefab, reserve in pairs(CARRIED_RESERVES) do
        surplus = surplus + math.max(0, CountCarriedForStorage(inst, prefab) - reserve)
    end
    -- Unload promptly at home, but finish a useful batch before a remote trip.
    if not near_base and not full and surplus < 12
        and not inst._my_friend_garden_delivery
        and not (forest ~= nil and forest.returning) then return end
    if not HasStorableInventory(inst) then return end
    return GetStoreAction(inst)
end

function M.ShouldReturnCollected(collected, missing, nearly_full)
    if nearly_full then return collected > 0 end
    return collected >= math.min(math.max(1, missing or 0), 12)
end

local function ShouldStoreForNeeds(inst, needs)
    local collected, missing = 0, 0
    for prefab, amount in pairs(needs or {}) do
        missing = missing + amount
        collected = collected + math.max(0,
            CountInventory(inst, prefab) - (CARRIED_RESERVES[prefab] or 0))
    end
    return M.ShouldReturnCollected(collected, missing, IsInventoryNearlyFull(inst))
end

local function GetWorkCleanupAction(inst)
    local cleanup = inst._my_friend_work_cleanup
    if cleanup == nil then return nil, false end
    if not HasLeader(inst) and M.IsStockStorageFull(inst) then
        inst._my_friend_work_cleanup = nil
        return nil, false
    end
    local now = GetTime()
    if now >= cleanup.deadline then
        inst._my_friend_work_cleanup = nil
        return nil, false
    end

    -- Finish this tree before selecting another gathering or base task. Only
    -- the shovel eligibility captured at felling time creates this request.
    local stump = cleanup.stump
    if stump ~= nil then
        local workable = stump:IsValid() and stump.components.workable or nil
        local shovel = FindTool(inst, ACTIONS.DIG)
        if workable == nil or not stump:HasTag("stump") or not workable:CanBeWorked()
            or workable:GetWorkAction() ~= ACTIONS.DIG or shovel == nil
            or IsBlocked(inst, stump) or IsResourceUnsafe(inst, stump)
            or DistanceSq(inst, stump) > M.RESOURCE_SEARCH_RANGE^2
            or not Policy.InRange(inst, stump, M.RESOURCE_SEARCH_RANGE) then
            cleanup.stump = nil
        elseif M.CanUseHandToolInCurrentLight(inst) and EquipTool(inst, shovel) then
            local action = TimedAction(inst, stump, ACTIONS.DIG, shovel)
            action:AddSuccessAction(function()
                cleanup.stump = nil
                cleanup.started, cleanup.deadline = GetTime(), GetTime() + M.MINE_LOOT_TIMEOUT
            end)
            action:AddFailAction(function()
                if not action._my_friend_cancelled then cleanup.stump = nil end
            end)
            M.SetTask(inst, "正在挖掉刚砍伐的树根")
            return action, true
        end
    end

    local closest, closest_distance
    local protected = GetProtectedCounts(inst)
    local early_build = not HasLeader(inst) and not M.IsComplete(inst)
        and (FindStructure(inst, "researchlab") == nil or Backpacks.NeedsCraftedBackpack(inst))
    for _, item in ipairs(TheSim:FindEntities(cleanup.x, 0, cleanup.z,
        M.MINE_LOOT_RADIUS, { "_inventoryitem" }, CANT_TAGS)) do
        local accepted = cleanup.forest_clear or M.IsCleanupLoot(cleanup.prefabs, item.prefab)
        if early_build and protected[item.prefab] == nil
            and item.prefab ~= "goldnugget" and item.prefab ~= cleanup.primary then
            accepted = false
        end
        if GetFreeSlots(inst) <= M.INVENTORY_FREE_SLOT_RESERVE
            and protected[item.prefab] == nil and item.prefab ~= cleanup.primary
            and not HasPartialStack(inst, item.prefab) then accepted = false end
        if accepted and CanPickUp(inst, item)
            and not IsBlocked(inst, item) then
            local distance = M.GetCleanupLootScore(DistanceSq(inst, item),
                item.prefab, cleanup.primary)
            if closest_distance == nil or distance < closest_distance then
                closest, closest_distance = item, distance
            end
        end
    end
    if closest ~= nil then
        M.SetTask(inst, cleanup.action == ACTIONS.CHOP
            and "正在捡完砍树掉落物"
            or cleanup.action == ACTIONS.DIG and "正在捡起刚铲出的移植物"
            or "正在捡完采矿掉落物")
        return TimedAction(inst, closest, ACTIONS.PICKUP), true
    end
    if now - cleanup.started >= M.MINE_LOOT_GRACE_TIME then
        inst._my_friend_work_cleanup = nil
        return nil, false
    end
    return nil, true
end

function M.IsCleanupLoot(prefabs, prefab)
    return prefabs ~= nil and prefabs[prefab] == true
        or prefabs == nil and GROUND_RESOURCES[prefab] == true
end

function M.GetCleanupLootScore(distance, prefab, primary)
    return (distance or 0) - (prefab == primary and 1000 or 0)
end

local function GetBaseAction(inst)
    if not CanAct(inst) or HasLeader(inst) or inst._my_friend_under_threat then return end
    -- Home bound companions only live around their home point: no site search,
    -- no construction, no stockpiling. Food, light, warmth and safety are
    -- handled by their own brain nodes and are unaffected.
    if Home.NoConstruction(inst) then
        M.EnsureBase(inst)
        M.SetTask(inst, Home.Get(inst) ~= nil and "正在自己的落脚点附近生活"
            or "正在世界上四处走走")
        return
    end
    local now = GetTime()
    M.PruneExpiredEntries(inst._my_friend_base_blocked, now)
    M.PruneExpiredEntries(inst._my_friend_search_nodes, now)
    if M.EnsureBase(inst) == nil then
        M.SetTask(inst, "正在寻找适合建立基地的地形")
        return
    end
    local phase = M.GetConstructionPhase(inst)
    inst._my_friend_base.phase = phase
    if phase ~= "complete" then inst._my_friend_base.complete = false end
    -- Inheriting a finished camp does not finish the new resident's backpack.
    -- Keep its material/build sequence ahead of housekeeping and old jobs.
    if phase == "backpack" then
        return M.GetBackpackCraftAction(inst) or M.GetInventoryReliefAction(inst)
    end
    if inst._my_friend_chest_transfer ~= nil then
        local transfer = Storage.GetAction(inst, FindOwnedChests(inst), TimedAction)
        if transfer ~= nil then return transfer end
    end
    local discard = GetForestDiscardAction(inst)
    if discard ~= nil then return discard end
    if DistanceSqToPoint(inst, GetLayoutOrigin(inst)) <= M.BASE_RETURN_DISTANCE^2 then
        if phase == "complete" then
            local store = M.GetSurplusStoreAction(inst)
            if store ~= nil then return store end
        end
    end
    if M.IsStockStorageFull(inst) then
        ClearWorkTarget(inst)
        inst._my_friend_base.resource_search = nil
        local forest = inst._my_friend_base.forest
        if forest ~= nil and forest.batch ~= nil then forest.returning = true end
    end
    local relief = M.GetInventoryReliefAction(inst)
    if relief ~= nil then return relief end
    if M.ShouldReturnToBase(inst) then return M.GetReturnAction(inst) end
    local pending_recipe = inst._my_friend_pending_recipe
    if pending_recipe ~= nil then
        local dependency = RECIPE_DEPENDENCY[pending_recipe]
        local tool_action = pending_recipe == "shovel" and ACTIONS.DIG
            or pending_recipe == "axe" and ACTIONS.CHOP
            or pending_recipe == "pickaxe" and ACTIONS.MINE
            or pending_recipe == "hammer" and ACTIONS.HAMMER
        if tool_action ~= nil and FindTool(inst, tool_action) ~= nil
            or GetValidRecipe(pending_recipe) == nil
            or dependency ~= nil and FindStructure(inst, dependency) == nil
                and not inst.components.builder:KnowsRecipe(pending_recipe) then
            inst._my_friend_pending_recipe = nil
        else
            -- Finish a prototyping trip before selecting another remote work target.
            local pending = GetRecipeGoalAction(inst, pending_recipe)
            if pending ~= nil then return pending end
            inst._my_friend_pending_recipe = nil
        end
    end
    local pending_work = not M.IsStockStorageFull(inst) and GetPendingWorkAction(inst) or nil
    if pending_work ~= nil then return pending_work end
    local work_loot, cleaning_work = GetWorkCleanupAction(inst)
    if cleaning_work then return work_loot end
    if inst._my_friend_base.fertilizer_trip ~= nil then
        local collecting, pending = GetFertilizerPickup(inst)
        if collecting ~= nil or pending then return collecting end
    end
    if IsInventoryNearlyFull(inst) and #FindOwnedChests(inst) > 0
        and HasStorableInventory(inst) then
        local store = GetStoreAction(inst)
        if store ~= nil then return store end
    end

    if not M.IsExtremeSeason(inst) and FoodAI.NeedsFoodSupply(inst)
        and inst.components.hunger:GetPercent() < .3 then
        local food_search = GetTerrainSearchAction(inst, { food = true })
        if food_search ~= nil then
            M.SetTask(inst, "正在前往有食物的地形觅食")
            return food_search
        end
    end

    if phase ~= "complete" then
        local minimum = {}
        for prefab, amount in pairs(CARRIED_MIN_RESERVES) do
            local missing = amount - CountInventory(inst, prefab)
            if missing > 0 then minimum[prefab] = missing end
        end
        if next(minimum) ~= nil then return GetGatherAction(inst, minimum) end
    end
    if FindStructure(inst, "researchlab") == nil then
        return GetRecipeGoalAction(inst, "researchlab")
    end
    if Backpacks.NeedsCraftedBackpack(inst) then
        return M.GetBackpackCraftAction(inst)
    end
    local state = inst._my_friend_base
    local chests = FindOwnedChests(inst)
    local needs_plants = (state.planted_grass or 0) < M.TRANSPLANT_TARGET
        or (state.planted_sapling or 0) < M.TRANSPLANT_TARGET
    local carried_plants = CountNeededTransplants(inst)
    if carried_plants == 0 then state.planting_trip = nil end
    local near_base = DistanceSqToPoint(inst, GetLayoutOrigin(inst)) <= M.BASE_RETURN_DISTANCE^2
    if (near_base or state.planting_trip or carried_plants >= 6)
        and carried_plants > 0 and needs_plants then
        local chest_recipe = GetValidRecipe("treasurechest")
        if near_base and #chests < M.BASE_CHEST_COUNT and chest_recipe ~= nil
            and inst.components.builder:HasIngredients(chest_recipe) then
            local build = CreateBuildAction(inst, "treasurechest")
            if build ~= nil then return build end
        end
        local plant = GetTransplantAction(inst, true)
        if plant ~= nil then return plant end
    end
    local plants_to_collect = {}
    local missing_grass = M.TRANSPLANT_TARGET - (state.planted_grass or 0)
        - CountInventory(inst, "dug_grass")
    local missing_sapling = M.TRANSPLANT_TARGET - (state.planted_sapling or 0)
        - CountInventory(inst, "dug_sapling")
    if missing_grass > 0 then plants_to_collect.dug_grass = missing_grass end
    if missing_sapling > 0 then plants_to_collect.dug_sapling = missing_sapling end
    if next(plants_to_collect) ~= nil and carried_plants < 6 then
        local ground = GetNeededGroundAction(inst, plants_to_collect,
            FindTool(inst, ACTIONS.DIG) == nil and M.RESOURCE_SEARCH_RANGE or 8)
        if ground ~= nil then return ground end
    end
    if not near_base and (#chests < M.BASE_CHEST_COUNT or needs_plants) then
        local mine = GetNearbyMineAction(inst)
        if mine ~= nil then return mine end
    end
    if next(plants_to_collect) ~= nil and FindTool(inst, ACTIONS.DIG) == nil then
        return GetRecipeGoalAction(inst, "shovel")
    end
    if needs_plants and not near_base then
        local nearby = GetNearbyTransplantAction(inst)
        if nearby ~= nil then return nearby end
    end
    if #chests < M.BASE_CHEST_COUNT then
        local chest = GetChestBatchAction(inst)
        if chest ~= nil then return chest end
        if carried_plants > 0 then return GetTransplantAction(inst, true) end
        return
    end
    if phase == "transplant" then
        local plant = GetTransplantAction(inst)
        if plant ~= nil then return plant end
        if FindStructure(inst, "firepit") ~= nil then return end
    end
    if FindStructure(inst, "firepit") == nil then
        return GetRecipeGoalAction(inst, "firepit")
    end
    if needs_plants then return end
    if not inst._my_friend_base.complete then
        inst._my_friend_base.complete = true
        inst._my_friend_base.phase = "complete"
        inst._my_friend_base.maintenance_after = now + 15
        inst._my_friend_base.resource_search = nil
        M.SetTask(inst, "基地建好了，正在休息")
        return
    end
    if now < (inst._my_friend_base.maintenance_after or 0) then return end

    local forest = EnsureForest(inst)
    if forest ~= nil and forest.returning then
        if not near_base then
            local action = MoveAction(inst, GetLayoutOrigin(inst))
            action.arrivedist = M.BASE_RETURN_DISTANCE - 2
            M.SetTask(inst, "这一批采伐完成，正在回基地入库")
            return action
        end
        inst._my_friend_tool_needs = nil
        local store = GetStoreAction(inst)
        if store ~= nil then return store end
        if M.IsStockStorageFull(inst)
            or CountInventory(inst, "log") > CARRIED_RESERVES.log
                and M.GetStockCapacity(inst, "log") <= 0 then
            M.SetTask(inst, "箱子没有足够空间，暂停囤货")
            return
        end
        forest.returning = nil
        forest.clear_loot = nil
        state.maintenance_after = now + 5
        return
    end

    if (near_base or inst._my_friend_garden_delivery) and HasStorableInventory(inst) then
        local store = GetStoreAction(inst)
        if store ~= nil then return store end
    end
    if inst._my_friend_garden_delivery then
        inst._my_friend_garden_delivery = nil
        inst._my_friend_garden_harvest_count = 0
    end
    local garden, gardening = GetGardenAction(inst)
    if garden ~= nil or gardening then return garden end
    if inst._my_friend_garden_delivery then return GetStoreAction(inst) end
    local clearance, clearing = GetForestClearAction(inst)
    if clearance ~= nil then return clearance end
    if clearing then
        if IsInventoryNearlyFull(inst) then
            local store = GetStoreAction(inst)
            if store ~= nil then return store end
        end
        state.resource_search = nil
        M.SetTask(inst, "林区清理暂缓，等待背包空间或安全作业条件")
        return
    end
    local wood = GetBaseWoodAction(inst)
    if wood ~= nil then return wood end
    -- Tree roots are cleanup work. Let planting, fertilizing and the managed
    -- forest finish first, and only clear nearby remembered roots afterwards.
    local stump = GetStumpAction(inst)
    if stump ~= nil then return stump end
    -- An exhausted or interrupted batch must unload before planting or mining.
    if forest ~= nil and forest.returning then return end
    local tree = GetTreePlantAction(inst)
    if tree ~= nil then return tree end
    if M.IsStockStorageFull(inst) then
        state.resource_search = nil
        M.SetTask(inst, "箱子已满，正在基地附近休息")
        return
    end

    local needs = GetMaintenanceNeeds(inst)
    if next(needs) ~= nil then
        if ShouldStoreForNeeds(inst, needs) then
            local store = GetStoreAction(inst)
            if store ~= nil then return store end
        end
        local ground = GetNeededGroundAction(inst, needs,
            M.IsExtremeSeason(inst) and M.BASE_RETURN_DISTANCE or nil)
        if ground ~= nil then return ground end
        -- Managed timber waits for a mature batch; never bypass it with solo cuts.
        needs.log = nil
        if next(needs) == nil then
            local store = GetStoreAction(inst)
            if store ~= nil then return store end
            state.resource_search = nil
            return
        end
        if M.IsExtremeSeason(inst) then
            inst._my_friend_base.resource_search = nil
            M.SetTask(inst, "正在基地内等待适合外出的天气")
            return
        end
        local nearby = GetLocalOpportunityAction(inst, needs, false)
        if nearby ~= nil then return nearby end
        return GetGatherAction(inst, needs, nil, nil, false)
    end
    inst._my_friend_base.resource_search = nil
    inst._my_friend_tool_needs = nil
    if HasStorableInventory(inst) then
        local store = GetStoreAction(inst)
        if store ~= nil then return store end
    end
    -- Start cross-chest housekeeping only after construction, personal tools
    -- and supplies. A replacement companion inherits chests, not a backpack.
    if near_base then
        local organize = GetOrganizeAction(inst)
        if organize ~= nil then return organize end
    end
    M.SetTask(inst, "正在基地附近生活")
end

function M.GetAction(inst)
    if not CanAct(inst) or HasLeader(inst) or inst._my_friend_under_threat then return end
    local action = GetBaseAction(inst)
    if action ~= nil then return action end
    if inst._my_friend_base == nil or M.IsComplete(inst) then return end
    if not M.CanUseHandToolInCurrentLight(inst) and not LightAI.IsDark(inst) then
        -- A hand-held torch permits picking, looting and carrying, not tool work.
        local needs = {}
        for prefab, amount in pairs({cutgrass = 10, twigs = 10, flint = 4,
            log = 20, rocks = 12, goldnugget = 1}) do
            local missing = amount - CountInventory(inst, prefab)
            if missing > 0 and HasRoomForCarriedPrefab(inst, prefab) then needs[prefab] = missing end
        end
        if next(needs) ~= nil and not IsInventoryNearlyFull(inst) then
            local target, action_type = FindGatherTarget(inst, needs)
            action = target ~= nil and CreateGatherAction(inst, target, action_type) or nil
            if action ~= nil then
                M.SetTask(inst, "正在持灯拾取和采摘物资")
                return action
            end
        end
        M.SetTask(inst, "附近没有适合持灯完成的工作，等待天亮")
    else
        M.SetTask(inst, inst._my_friend_base.garden_waiting
            and "基地种植区暂时受阻，等待可用种植位置"
            or "正在等待下一项可执行的建家工作")
    end
end

function M.GetCommandAction(inst)
    local command = inst._my_friend_command
    -- A meal retains the container lock between actions. Its own command must
    -- pass that lock to queue EAT/return; unrelated work still waits.
    if not CanAct(inst, command) then return end
    local leader = Policy.GetLeader(inst)
    if command == nil or leader == nil or command.player ~= leader
        or GetTime() > (command.deadline or 0) then
        if command ~= nil then inst._my_friend_command = nil end
        return
    end
    local id = command.id
    if id == "butterfly" then
        return require("my_friend_command_butterfly").GetAction(inst, command)
    end
    if id == "rockfruit" or id == "bullkelp" or id == "dry_meat" then
        return require("my_friend_command_special_gather").GetAction(inst, command)
    end
    if id == "carry_statue" then
        return require("my_friend_command_carry").GetAction(inst, command)
    end
    if command.special ~= nil then
        return require("my_friend_special_actions").GetAction(inst, command)
    end
    local Dig = require("my_friend_command_dig")
    if Dig.IsCommand(id) then
        return Dig.Action(inst, command, CreateGatherAction, HasRoomForCarriedPrefab)
    end
    if id == "chop" then
        local action, pending = require("my_friend_chop_loot").Action(inst, command)
        if pending then return action end
    elseif id == "mine" then
        -- Commands outrank the autonomous cleanup node. Finish this rock's
        -- drops here before another rock can replace its cleanup record.
        local action, pending = GetWorkCleanupAction(inst)
        command.waiting = pending or nil
        if pending then return Policy.GuardAction(inst, action) end
    end
    if command.delivering then
        local delivery = require("my_friend_tidy").WorkDelivery(inst, command)
        if delivery ~= nil then return delivery end
        command.delivering = nil
        if command.finished_gathering then
            require("my_friend_commands").Clear(inst)
            return
        end
    end
    if id == "food" then
        local ContainerAI = require("my_friend_container_ai")
        local carried = ContainerAI.GetCarriedFoodAction(inst, command)
        if carried ~= nil then return carried end
        if inst._my_friend_command ~= command then return end
        if not CanAct(inst) then return end
        local food = FoodAI.FindCommandFood(inst, true)
        if food == nil then
            local container = ContainerAI.GetCommandFoodAction(inst, command)
            if container ~= nil then return container end
            food = FoodAI.FindCommandFood(inst, false)
        end
        local eat = food ~= nil and FoodAI.GetEatAction(inst, food) or nil
        if eat ~= nil then
            eat:AddSuccessAction(function()
                if inst._my_friend_command == command then require("my_friend_commands").Clear(inst) end
            end)
            return eat
        end
        if FoodAI.GetFoodSupply(inst) >= FoodAI.GetDailyHunger(inst) * 2
            or (command.food_gathers or 0) >= 8 then
            require("my_friend_commands").Clear(inst)
            return
        end
        local gather = BehaviourAI.GetFoodAction(inst, true)
        if gather == nil then require("my_friend_commands").Clear(inst) end
        if gather ~= nil then
            gather:AddSuccessAction(function()
                command.food_gathers = (command.food_gathers or 0) + 1
            end)
        end
        return gather
    elseif id == "hoe" or id == "water" then
        return require("my_friend_command_work").Farm(inst, command)
    elseif id == "tidy" or id == "seeds" or id == "equipment" then
        return require("my_friend_tidy").GetAction(inst, command)
    end
    local origin = id == "chop" and command.origin or leader:GetPosition()
    local x, y, z = origin:Get()
    local radius = id == "chop" and 16 or 32
    local entities = TheSim:FindEntities(x, y, z, radius, nil,
        CANT_TAGS, {"_inventoryitem", "pickable", "tree", "boulder", "MINE_workable", "CHOP_workable"})
    local best, kind, tool, distance
    local function consider(entity, action, required, candidate_tool)
        if entity == nil or IsBlocked(inst, entity)
            or entity:GetDistanceSqToPoint(origin) > radius^2
            or required and not HasRoomForCarriedPrefab(inst, required) then return end
        local d = DistanceSq(inst, entity)
        if distance == nil or d < distance then best, kind, tool, distance = entity, action, candidate_tool, d end
    end
    for _, entity in ipairs(entities) do
        local workable = entity.components ~= nil and entity.components.workable or nil
        local pickable = entity.components ~= nil and entity.components.pickable or nil
        if id == "grass" then
            if entity.prefab == "grass" and pickable ~= nil and pickable:CanBePicked()
                then consider(entity, ACTIONS.PICK, pickable.product or "cutgrass") end
            if entity.prefab == "sapling" and pickable ~= nil and pickable:CanBePicked()
                then consider(entity, ACTIONS.PICK, pickable.product or "twigs") end
        elseif id == "mine" and workable ~= nil and workable:CanBeWorked()
            and workable:GetWorkAction() == ACTIONS.MINE then
            consider(entity, ACTIONS.MINE)
        elseif id == "chop" and workable ~= nil and workable:CanBeWorked()
            and workable:GetWorkAction() == ACTIONS.CHOP and not entity:HasTag("stump")
            and Forestry.IsMature(entity) then
            consider(entity, ACTIONS.CHOP)
        elseif id == "harvest" then
            if entity.components.inventoryitem ~= nil and CanPickUp(inst, entity, true)
                and not (command.delivered or {})[entity.GUID]
                and (require("my_friend_tidy").IsSeed(entity)
                    or entity.components.edible ~= nil and entity:HasTag("veggie")) then
                consider(entity, ACTIONS.PICKUP)
            elseif pickable ~= nil and pickable:CanBePicked() then
                consider(entity, ACTIONS.PICK, pickable.product)
            elseif entity.components.crop ~= nil and entity.components.crop:IsReadyForHarvest() then
                consider(entity, ACTIONS.HARVEST, entity.components.crop.product_prefab)
            end
        end
    end
    if best == nil then
        local delivery = require("my_friend_tidy").WorkDelivery(inst, command)
        if delivery ~= nil then
            command.delivering, command.finished_gathering = true, true
            return delivery
        end
        require("my_friend_commands").Clear(inst)
        return
    end
    if id == "chop" or id == "mine" then
        local work = require("my_friend_command_work")
        local preparation
        tool, preparation = work.Tool(inst, command, kind, id == "chop" and "axe" or "pickaxe")
        if preparation ~= nil then return preparation end
        if tool == nil then work.Finish(inst, command, true) return end
        if not M.CanUseHandToolInCurrentLight(inst) then return end
    end
    if tool ~= nil and not EquipTool(inst, tool) then return end
    local action = CreateGatherAction(inst, best, kind, tool)
    if id == "chop" then
        action._my_friend_command_origin = command.origin
        action:AddSuccessAction(function() command.chop_started = true end)
    end
    if id == "harvest" then
        command.harvest_products = command.harvest_products or {}
        local product = best.components.pickable ~= nil and best.components.pickable.product
            or best.components.crop ~= nil and best.components.crop.product_prefab or best.prefab
        command.harvest_products[product] = true
    end
    action:AddSuccessAction(function()
        if inst:IsValid() and inst._my_friend_command == command
            and GetFreeSlots(inst) <= M.INVENTORY_FREE_SLOT_RESERVE then
            if id == "grass" or id == "harvest" then command.delivering = true
            elseif id ~= "chop" then inst._my_friend_command = nil end
        end
    end)
    return Policy.GuardAction(inst, action, 32)
end

function M.IsComplete(inst)
    return inst._my_friend_base ~= nil and inst._my_friend_base.complete == true
end

function M.GetStoragePressure(inst)
    return inst.components.inventory ~= nil and IsInventoryNearlyFull(inst)
end

function M.GetReserveAction(inst)
    if not CanAct(inst) then return end
    if not HasLeader(inst) and not M.IsComplete(inst) then return end
    local cleanup, cleaning = GetWorkCleanupAction(inst)
    if cleaning then return Policy.GuardAction(inst, cleanup) end
    local needs = GetCarriedReserveNeeds(inst)
    if not HasLeader(inst) and Home.NoConstruction(inst) then return end
    if Home.IsRestricted(inst) and inst._my_friend_command == nil then
        for prefab in pairs(needs) do
            if not Home.AllowsPrefab(inst, prefab) then needs[prefab] = nil end
        end
    end
    if next(needs) == nil then return end
    if not HasLeader(inst) and M.IsStockStorageFull(inst) then
        return Policy.GuardAction(inst, GetWithdrawAction(inst, needs))
    end
    local opportunity = GetPlannedOpportunityAction(inst)
    if opportunity ~= nil then return opportunity end
    return Policy.GuardAction(inst, GetGatherAction(inst, needs))
end

function M.GetCleanupAction(inst)
    if not CanAct(inst) then return end
    local action = GetWorkCleanupAction(inst)
    return Policy.GuardAction(inst, action)
end

function M.GetBackpackCraftAction(inst)
    if not CanAct(inst) or not Backpacks.NeedsCraftedBackpack(inst) then return end
    local recipe = GetValidRecipe("backpack")
    if recipe == nil then return end
    local needs = {}
    for _, ingredient in ipairs(recipe.ingredients) do
        local reserve = (ingredient.type == "cutgrass" or ingredient.type == "twigs") and 2 or 0
        local _, carried = inst.components.inventory:Has(ingredient.type, 9999, false)
        local count = math.ceil(ingredient.amount * (inst.components.builder.ingredientmod or 1))
            + reserve - (carried or 0)
        if count > 0 then needs[ingredient.type] = count end
    end
    if next(needs) ~= nil then
        return Policy.GuardAction(inst, GetGatherAction(inst, needs))
    end
    local action = CreateBuildAction(inst, recipe.name)
    if action == nil then return end
    return Policy.GuardAction(inst, action)
end

function M.CanUseHandToolInCurrentLight(inst)
    if LightAI.IsExternallyLit(inst) or not LightAI.IsEnvironmentDark(inst) then return true end
    local inventory = inst.components.inventory
    if inventory == nil then return false end
    for _, slot in ipairs(EquipSlots.All()) do
        if slot ~= EQUIPSLOTS.HANDS
            and LightAI.IsLightEquipment(inventory:GetEquippedItem(slot)) then return true end
    end
    return false
end

function M.GetWanderPoint(inst, avoid_points)
    -- Keeping vigil over a fallen leader overrides both home and base.
    local vigil = Policy.GetVigilPoint(inst)
    local manual = not vigil and Home.Get(inst) or nil
    local base = vigil or manual or (not vigil and M.EnsureBase(inst) or nil)
    if base == nil then base = inst:GetPosition() end
    local center = base
    local radius = vigil ~= nil and M.VIGIL_RADIUS
        or M.IsExtremeSeason(inst) and 3
        or manual ~= nil and Home.WANDER_RADIUS or M.BASE_WANDER_RADIUS
    local fire = M.ShouldPreferBaseFire(inst) and FindNightBaseFire(inst) or nil
    local near_fire = fire ~= nil and fire.components.fueled ~= nil
        and not fire.components.fueled:IsEmpty()
    if near_fire then
        center, radius = fire:GetPosition(), 2.5
    end
    local origin_domain = M.GetTerrainDomainAtPoint(center.x, center.y, center.z)
    if origin_domain == "blocked" then origin_domain = "land" end

    -- Sample several directions and reject water/holes. The old single random
    -- sample could repeatedly select the same blocked shoreline direction.
    local best, best_score
    local start_angle = math.random() * PI2
    for index = 0, 15 do
        local angle = start_angle + index * PI2 / 16
        local distance = radius * (.25 + .75 * math.random())
        local offset = FindWalkableOffset(center, angle, distance, 12,
            true, false, nil, false)
        if offset ~= nil then
            local point = center + offset
            local valid_domain = M.GetTerrainDomainAtPoint(point.x, point.y, point.z)
            if valid_domain == origin_domain
                and IsPassable(point)
                and (not near_fire or LightAI.IsPointExternallyLit(inst, point)
                    and Navigation.IsWalkClear(inst, point, point, Navigation.Caps(inst))) then
                local score = DistanceSqToPoint(inst, point) * .02
                for _, old in ipairs(avoid_points or {}) do
                    local dx, dz = point.x - old.x, point.z - old.z
                    local distance_sq = dx * dx + dz * dz
                    if distance_sq < 16 then
                        score = score + (16 - distance_sq) * 20
                    end
                end
                if best_score == nil or score < best_score then
                    best, best_score = point, score
                end
            end
        end
    end
    return best
end

function M.OnBuildStructure(inst, structure)
    if structure == nil or not structure:IsValid() then return end
    structure._my_friend_base_structure = true
    structure:AddTag("my_friend_base_structure")
    if structure.prefab == "treasurechest" then
        structure:AddTag("my_friend_base_storage")
    end
end

function M.WrapBaseStructure(inst)
    if inst._my_friend_base_save_wrapped then return end
    inst._my_friend_base_save_wrapped = true
    local old_save, old_load = inst.OnSave, inst.OnLoad
    inst.OnSave = function(self, data)
        local refs = old_save ~= nil and old_save(self, data) or nil
        if self._my_friend_base_structure then data.my_friend_base_structure = true end
        return refs
    end
    inst.OnLoad = function(self, data, ents)
        if old_load ~= nil then old_load(self, data, ents) end
        if data ~= nil and data.my_friend_base_structure then
            M.OnBuildStructure(nil, self)
        end
    end
end

function M.OnSave(inst, data)
    require("my_friend_exploration").Save(inst, data)
    Home.Save(inst, data)
    local state = inst._my_friend_base
    if state ~= nil then
        data.my_friend_base = {
            x = state.x,
            z = state.z,
            planted_grass = state.planted_grass or 0,
            planted_sapling = state.planted_sapling or 0,
            search_angle = state.search_angle,
            search_step = state.search_step,
            visited_nodes = state.visited_nodes,
            tree_plant_index = state.tree_plant_index,
            forest = Forestry.OnSave(inst),
            tree_stumps = state.tree_stumps,
            cache_x = state.cache_x,
            cache_z = state.cache_z,
            site_version = state.site_version,
            phase = state.phase,
            complete = state.complete,
            fertilizer_cooldown = math.max(0, (state.fertilizer_search_after or 0) - GetTime()),
            fertilizer_regions = state.fertilizer_regions,
        }
    end
end

function M.OnLoad(inst, data)
    require("my_friend_exploration").Load(inst, data)
    local saved = data ~= nil and data.my_friend_base or nil
    -- Home.Load runs last so a manual site always overrides the saved layout.
    if saved ~= nil and type(saved.x) == "number" and type(saved.z) == "number" then
        inst._my_friend_base = {
            x = saved.x,
            z = saved.z,
            planted_grass = math.min(M.TRANSPLANT_TARGET, saved.planted_grass or 0),
            planted_sapling = math.min(M.TRANSPLANT_TARGET, saved.planted_sapling or 0),
            search_angle = saved.search_angle,
            search_step = saved.search_step,
            visited_nodes = saved.visited_nodes or {},
            tree_plant_index = saved.tree_plant_index,
            cache_x = type(saved.cache_x) == "number" and type(saved.cache_z) == "number" and saved.cache_x or nil,
            cache_z = type(saved.cache_x) == "number" and type(saved.cache_z) == "number" and saved.cache_z or nil,
            site_version = saved.site_version,
            phase = saved.phase,
            complete = saved.complete == true,
            fertilizer_regions = saved.fertilizer_regions or {},
            fertilizer_search_after = GetTime() + (type(saved.fertilizer_cooldown) == "number"
                and saved.fertilizer_cooldown == saved.fertilizer_cooldown
                and math.min(2 * TUNING.TOTAL_DAY_TIME, math.max(0, saved.fertilizer_cooldown)) or 0),
        }
        Forestry.OnLoad(inst, saved)
    end
    Home.Load(inst, data)
end

return M
