-- Bounded, server-side observations. Handles are session-local and never saved.
local Discovery = require("my_friend_discovery")
local Inventory = require("my_friend_inventory")
local Platforms = require("my_friend_platforms")
local FarmTiles = require("my_friend_farm_tiles")
local M = {}
local MAX_HANDLES = 2048
function M.Handle(state, entity)
    if entity == nil or not entity:IsValid() or entity.GUID == nil then return end
    local previous = state.by_guid[entity.GUID]
    if previous ~= nil and state.handles[previous] ~= nil then
        return previous
    end
    state.handle_serial = state.handle_serial + 1
    local id = "e" .. tostring(state.handle_serial)
    state.handles[id] = {guid = entity.GUID}
    state.by_guid[entity.GUID] = id
    -- A read batch can describe hundreds of entities before trimming output.
    -- Keep the working set bounded without evicting its first page mid-batch.
    local slot = state.handle_cursor or 1
    local old = state.handle_order[slot]
    if old ~= nil then
        local entry = state.handles[old]
        if entry ~= nil then state.by_guid[entry.guid] = nil end
        state.handles[old] = nil
    end
    state.handle_order[slot], state.handle_cursor = id, slot % MAX_HANDLES + 1
    return id
end
function M.Resolve(state, handle)
    if type(handle) ~= "string" then return end
    local record = state.handles[handle]
    local pins = state.active ~= nil and state.active.pins or nil
    local guid = record ~= nil and record.guid or pins ~= nil and pins[handle] or nil
    local entity = guid ~= nil and (Ents or {})[guid] or nil
    return entity ~= nil and entity:IsValid() and entity or nil
end
function M.Size(item)
    return item ~= nil and item:IsValid() and (item.components.stackable ~= nil
        and item.components.stackable:StackSize() or 1) or 0
end
function M.Items(inst)
    local items = require("my_friend_food_storage").ReferenceItems(inst)
    local active = inst.components.inventory:GetActiveItem()
    if active ~= nil then
        local found = false
        for _, item in ipairs(items) do if item == active then found = true end end
        if not found then items[#items + 1] = active end
    end
    return items
end
function M.Distance(a, b)
    if a ~= nil and b ~= nil then
        return math.floor(math.sqrt((a.x - b.x)^2 + (a.z - b.z)^2) * 10 + .5) / 10
    end
end

function M.Name(entity)
    -- Vanilla farm soil's display name depends on the local controller.
    if entity.prefab == "farm_soil" or entity.prefab == "quagmire_soil" then return entity.prefab end
    return entity.GetDisplayName ~= nil and entity:GetDisplayName() or entity.prefab
end

function M.PlayerProfile(player, same_shard)
    local c = player.components or {}
    local client = type(player.userid) == "string" and TheNet ~= nil and TheNet.GetClientTableForUser ~= nil
        and TheNet:GetClientTableForUser(player.userid) or nil
    local name = client ~= nil and client.name or nil
    if type(name) ~= "string" or name == "" then name = M.Name(player) end
    local character_name = STRINGS.NAMES ~= nil and STRINGS.NAMES[string.upper(player.prefab)] or player.prefab
    return {userid = player.userid, name = name, prefab = player.prefab, kind = "player", same_shard = same_shard,
        character = {id = player.prefab, name = character_name}, ghost = player:HasTag("playerghost"),
        health = c.health ~= nil and c.health.currenthealth or nil,
        health_max = c.health ~= nil and c.health.maxhealth or nil,
        hunger = c.hunger ~= nil and c.hunger.current or nil, hunger_max = c.hunger ~= nil and c.hunger.max or nil,
        sanity = c.sanity ~= nil and c.sanity.current or nil, sanity_max = c.sanity ~= nil and c.sanity.max or nil}
end

local function HasPhysics(entity)
    return entity.Physics ~= nil and entity.Physics:IsActive()
end

function M.Describe(inst, state, entity, opening, scene)
    local c = entity.components or {}
    local location = opening or entity
    local p = location.Transform ~= nil and location:GetPosition() or nil
    local item = c.inventoryitem
    local record = entity.isplayer and M.PlayerProfile(entity) or {prefab = entity.prefab, name = M.Name(entity),
        kind = item ~= nil and "item"
            or c.container ~= nil and "container" or c.health ~= nil and "creature" or "structure"}
    record.handle = M.Handle(state, entity)
    record.position = p ~= nil and {x = p.x, z = p.z} or nil
    if c.health ~= nil then record.alive, record.health = not c.health:IsDead(), c.health.currenthealth end
    if entity:HasTag("epic") then record.boss = true end
    if entity:HasTag("heavy") then record.heavy=true end
    if item ~= nil then
        record.count = M.Size(entity)
        record.carried = item:GetGrandOwner() == inst
        record.pickable = item.owner == nil and item.canbepickedup == true
        record.can_store = item.cangoincontainer ~= false
        record.location = item.owner == nil and "ground" or item.owner == inst and "self" or "container_or_other"
        record.container = opening ~= nil and M.Handle(state, opening)
            or item.owner ~= nil and item.owner.components.container ~= nil
                and not item.owner:HasTag("pocketdimension_container") and M.Handle(state, item.owner) or nil
        record.backpack = entity:HasTag("backpack") or nil
        if item.cangoincontainer == false then record.delivery = "drop_near_recipient" end
    end
    if c.equippable ~= nil then
        record.slot = tostring(c.equippable.equipslot)
        record.equipped = c.equippable:IsEquipped() == true
        if record.equipped then record.location = "equipped" end
    end
    if c.finiteuses ~= nil then record.durability = c.finiteuses:GetPercent() end
    if c.perishable ~= nil then
        local percent = c.perishable:GetPercent()
        record.freshness = {percent = percent,
            state = percent >= (TUNING.PERISH_FRESH or .5) and "fresh"
                or percent > (TUNING.PERISH_STALE or .2) and "stale" or "spoiled"}
    end
    if c.edible ~= nil and inst.components.eater ~= nil then
        local food = require("my_friend_food_ai")
        local health, hunger, sanity = food.GetFoodDeltas(inst, entity)
        local can_eat = inst.components.eater:CanEat(entity) and inst.components.eater:PrefersToEat(entity)
        record.food = {health = health, hunger = hunger, sanity = sanity,
            can_eat = can_eat, safe_to_eat = can_eat and food.CanSafelyEat(inst, entity)}
    end
    if c.tool ~= nil then
        record.tool_actions = {}
        for action in pairs(c.tool.actions or {}) do
            if type(action) == "table" and type(action.id) == "string" then
                record.tool_actions[#record.tool_actions + 1] = action.id
            end
        end
        table.sort(record.tool_actions)
    end
    if c.fillable~=nil then
        record.fillable=true
        if c.finiteuses~=nil then
            record.fill_percent=c.finiteuses:GetPercent()
            record.fill_full=record.fill_percent>=1
        end
    end
    if c.deployable~=nil then record.deployable=true end
    if c.farmplantable~=nil or c.plantable~=nil then record.plantable=true end
    record.planting_action = c.farmplantable ~= nil and "PLANTSOIL" or c.plantable ~= nil and "PLANT"
        or c.deployable ~= nil and entity:HasAnyTag("treeseed", "deployedplant") and "DEPLOY" or nil
    if c.farmtiller ~= nil then record.farm_tiller = true end
    if c.terraformer~=nil then record.terraformer=true end
    if entity:HasTag("watersource") then record.watersource=true end
    record.burnable = c.burnable ~= nil or entity:HasTag("canlight")
    record.building = entity:HasTag("structure")
    record.burning = c.burnable ~= nil and c.burnable.IsBurning~=nil and c.burnable:IsBurning() or false
    if c.fuel ~= nil then record.fuel = {type=c.fuel.fueltype, value=c.fuel.fuelvalue} end
    if c.fueled ~= nil then
        record.fueled = {type=c.fueled.fueltype, secondary=c.fueled.secondaryfueltype,
            current=c.fueled.currentfuel, maximum=c.fueled.maxfuel, accepting=c.fueled.accepting,
            percent=c.fueled:GetPercent()}
    end
    local storage = require("my_friend_body_storage")
    local container = storage.Resolve(entity)
    if container ~= nil and container.GetNumSlots ~= nil then
        local used = 0
        for _ in pairs(container.slots or {}) do used=used+1 end
        record.capacity = {slots=container:GetNumSlots(), used=used,
            free=math.max(0,container:GetNumSlots()-used), accepts_stacks=container.acceptsstacks ~= false,
            infinite_stacks=container.infinitestacksize == true}
    end
    if entity:HasTag("soil") then record.soil = true end
    if entity.prefab == "farm_soil" then record.plantable_hole = FarmTiles.IsOpenHole(entity) end
    if FarmTiles.IsWeed(entity) then record.weed = true end
    if c.farmplanttendable ~= nil then record.tendable=c.farmplanttendable.tendable == true end
    if c.growable ~= nil then record.growth_stage=c.growable.stage end
    if c.farmsoildrinker ~= nil and TheWorld.components~=nil and TheWorld.components.farming_manager ~= nil then
        record.soil_moist=TheWorld.components.farming_manager:IsSoilMoistAtPoint(p.x,0,p.z)
    end
    if c.armor ~= nil then record.armor = c.armor:GetPercent() end
    if container ~= nil then
        if item == nil then record.kind = "container" end
        record.accessible = storage.Accessible(inst, entity)
        record.shared_storage = c.container_proxy ~= nil or nil
    end
    if p ~= nil and entity ~= inst and (item == nil or item.owner == nil) then
        local surface, platform = Platforms.Surface(p, location)
        record.distance, record.surface, record.platform = M.Distance(inst:GetPosition(), p), surface, M.Handle(state, platform)
    elseif location.GetCurrentPlatform ~= nil then
        record.platform = M.Handle(state, location:GetCurrentPlatform())
    end
    if c.walkableplatform ~= nil then record.boat = true end
    if c.stewer ~= nil then
        record.cooking = {running = c.stewer:IsCooking(), ready = c.stewer:IsDone(), product = c.stewer.product,
            remaining = c.stewer.GetTimeToCook ~= nil and c.stewer:GetTimeToCook() or nil,
            harvestable = c.stewer:IsDone() and Inventory.CanWithdrawFrom(inst, entity, true)}
    end
    if item ~= nil then
        local uses = {healer = "HEAL", sewing = "SEW", repairer = "REPAIR", fuel = "ADDFUEL", fertilizer = "FERTILIZE"}
        record.uses = {}
        record.uses_complete = false
        for component, action in pairs(uses) do if c[component] ~= nil then record.uses[#record.uses + 1] = action end end
        if c.book ~= nil and inst.components.reader ~= nil then record.uses[#record.uses + 1] = "READ" end
        if entity:HasTag("reviver") then record.reviver = true end
        if c.pocketwatch ~= nil and inst.prefab == "wanda" and inst:HasTag("pocketwatchcaster") then
            record.uses[#record.uses + 1] = "CAST_POCKETWATCH"
            record.watch_ready = c.pocketwatch.inactive == true
        end
        table.sort(record.uses)
    end
    if c.prototyper ~= nil then record.prototyper = true end
    record.interactions, record.occupied, record.switched_on = require("my_friend_body_interactions").Describe(inst, entity)
    if c.pickable ~= nil then
        record.can_pick = c.pickable:CanBePicked()
        record.pick_product = c.pickable.product
        record.pick_count = c.pickable.numtoharvest
    end
    if c.cookable ~= nil then record.roast_product = c.cookable.product end
    if item ~= nil then
        local cooking = require("cooking")
        local aliases = {cookedsmallmeat="smallmeat_cooked",cookedmonstermeat="monstermeat_cooked",cookedmeat="meat_cooked"}
        local ingredient = (cooking.ingredients or {})[aliases[entity.prefab] or entity.prefab]
        if ingredient ~= nil then record.cooking_tags = ingredient.tags end
    end
    if c.workable ~= nil and c.workable:CanBeWorked() then
        local action = c.workable:GetWorkAction()
        record.work = action ~= nil and action.id or nil
        record.work_left = c.workable.workleft
    end
    if entity:HasTag("tree") then record.tree = true end
    if scene then
        record.physical = HasPhysics(entity) or nil
        record.physics_radius = entity.GetPhysicsRadius ~= nil and entity:GetPhysicsRadius(0) or nil
        record.deploy_radius = entity.deploy_smart_radius or entity.deploy_extra_spacing
        record.ground_hole = entity:HasTag("groundhole") or nil
        record.ground_target_blocker = entity:HasTag("groundtargetblocker") or nil
        record.farm_debris = entity:HasTag("farm_debris") or nil
        record.farm_plant = entity:HasTag("farm_plant") or nil
        record.burnt = entity:HasTag("burnt") or nil
        record.fire = entity:HasTag("fire") or nil
    end
    return record
end
function M.Snapshot(inst, state)
    local c, p = inst.components, inst:GetPosition()
    local out = {prefab = inst.prefab, name = inst:GetDisplayName(), position = {x = p.x, z = p.z},
        health = c.health ~= nil and c.health.currenthealth or nil,
        hunger = c.hunger ~= nil and c.hunger.current or nil,
        sanity = c.sanity ~= nil and c.sanity.current or nil,
        moisture = c.moisture ~= nil and c.moisture:GetMoisture() or nil,
        temperature = c.temperature ~= nil and c.temperature:GetCurrent() or nil,
        busy = require("my_friend_policy").IsBusy(inst), ghost = inst:HasTag("playerghost"),
        task = inst._my_friend_current_task, inventory = {}, action = state.active ~= nil and {
            action_id = state.active.id, skill = state.active.skill, status = state.active.status,
            stage = state.active.stage, progress = state.active.progress} or nil}
    out.owner = state.owner._my_friend_remote_transport and state.owner.speaker or M.Describe(inst, state, state.owner)
    out.world_control = state.owner._my_friend_remote_transport and state.owner.world_control
        or require("my_friend_body_world").Status(state.owner)
    local leader = require("my_friend_policy").GetLeader(inst)
    out.following = leader ~= nil
    out.leader = leader ~= nil and M.Describe(inst, state, leader) or nil
    out.revision = state.revision
    out.character = {id = inst.prefab, name = inst:GetDisplayName()}
    out.custom_name=inst._my_friend_custom_name
    out.renamed=type(inst._my_friend_custom_name)=="string" and inst._my_friend_custom_name~=""
    out.character.is_mod=false
    for _,prefab in ipairs(MODCHARACTERLIST or {}) do
        if prefab==inst.prefab then out.character.is_mod=true;break end
    end
    out.health_kind=c.oldager~=nil and "remaining_lifespan" or "health"
    out.health_max=c.health~=nil and c.health.maxhealth or nil
    if inst.prefab=="wanda" and c.oldager~=nil and c.health~=nil and TUNING~=nil
        and type(TUNING.WANDA_MAX_YEARS_OLD)=="number" and c.oldager.GetCurrentYearPercent~=nil then
        out.age=require("my_friend_wanda").GetAge(inst)
        out.age_max=TUNING.WANDA_MAX_YEARS_OLD
    end
    out.language = (package.loaded.my_friend_strings or {}).language or "zh"
    out.manual_task = inst._my_friend_command ~= nil and inst._my_friend_command.id or nil
    out.emergency = require("my_friend_body_api").Blocked(inst, state, state.pending or state.active)
    out.blockers = out.emergency and require("my_friend_body_api").Blockers(inst,state,state.pending or state.active) or {}
    out.handle = M.Handle(state,inst)
    out.base,out.home = require("my_friend_home").Status(inst)
    out.location = require("my_friend_body_terrain").Location(inst)
    local surface, platform = Platforms.Surface(p, inst)
    local riding = c.rider ~= nil and c.rider:IsRiding()
    out.mobility = {
        riding = riding == true,
        mount = riding and c.rider.GetMount ~= nil and M.Handle(state, c.rider:GetMount()) or nil,
        surface = surface,
        platform = platform ~= nil and M.Handle(state, platform) or nil,
    }
    if c.builder ~= nil then
        out.prepared_builds = {}
        for recipe in pairs(c.builder.buffered_builds or {}) do out.prepared_builds[#out.prepared_builds + 1] = recipe end
        table.sort(out.prepared_builds)
    end
    out.pending = state.pending ~= nil and {action_id = state.pending.id, skill = state.pending.skill, stage = state.pending.stage} or nil
    if TheWorld ~= nil then
        local prefab = TheWorld.prefab
        local weather = TheWorld.state or {}
        local shard_id = TheShard ~= nil and TheShard:GetShardId() or nil
        out.world = {
            kind = prefab == "forest" and "surface" or prefab == "cave" and "caves" or "unknown",
            prefab = prefab, shard_id = shard_id ~= nil and tostring(shard_id) or nil,
            day = TheWorld.state ~= nil and (weather.cycles or 0) + 1 or nil, season = weather.season,
            phase = weather.phase, time = weather.time, temperature = weather.temperature,
            raining = weather.israining, snowing = weather.issnowing,
        }
    end
    local environment = state.environment
    if environment ~= nil and GetTime() - environment.observed_at < 90
        and (p.x - environment.position.x)^2 + (p.z - environment.position.z)^2 <= 4^2 then
        out.environment = environment
    end
    out.control = state.active == nil and "autonomous" or "action"
    out.planning = require("my_friend_body_api").PlanActive(inst)
    for _, item in ipairs(M.Items(inst)) do
        if item:IsValid() and #out.inventory < 40 then out.inventory[#out.inventory + 1] = M.Describe(inst, state, item) end
    end
    return out
end
local function DistanceSq(a, b)
    return (a.x - b.x)^2 + (a.z - b.z)^2
end

local function SortNearby(inst, entities, center)
    local distances = {}
    for _, entity in ipairs(entities) do
        distances[entity] = center ~= nil and DistanceSq(center, entity:GetPosition()) or inst:GetDistanceSqToInst(entity)
    end
    table.sort(entities, function(a, b)
        return distances[a] == distances[b] and a.GUID < b.GUID or distances[a] < distances[b]
    end)
end

local SCENE_EXCLUDE = {"INLIMBO", "FX", "CLASSIFIED"}

function M.SceneVisible(entity)
    if not entity:IsValid() or entity.components == nil
        or entity:HasAnyTag("INLIMBO", "FX", "CLASSIFIED") then return false end
    local item = entity.components.inventoryitem
    return (item == nil or item.owner == nil) and (entity.entity == nil or entity.entity:IsVisible()
        and (entity.entity:GetParent() == nil or entity:HasTag("childdeployblocker")))
end

local function Visible(inst, e, radius_sq)
    if e == inst or not e:IsValid() or e.components == nil or e:HasAnyTag("INLIMBO", "FX", "burnt", "fire") then return false end
    local item = e.components.inventoryitem
    return (item == nil or item.owner == nil) and inst:GetDistanceSqToInst(e) <= radius_sq
end

-- Observation must see moving entities too, including containers on boats.
-- Share one native scan for scopes at the same radius inside a single request.
function M.Nearby(inst, radius, cache)
    if cache ~= nil and cache[radius] ~= nil then return cache[radius] end
    local p, entities, seen = inst:GetPosition(), {}, {}
    for _, e in ipairs(TheSim:FindEntities(p.x, 0, p.z, radius, nil, {"INLIMBO", "FX", "burnt", "fire"})) do
        if not seen[e.GUID] and Visible(inst, e, radius^2) then
            entities[#entities + 1], seen[e.GUID] = e, true
        end
    end
    SortNearby(inst, entities)
    if cache ~= nil then cache[radius] = entities end
    return entities
end

local function Creature(e)
    return e.isplayer or e.components.health ~= nil and e.components.locomotor ~= nil
end

local function Interactive(e)
    local c = e.components
    return c.sittable ~= nil or c.machine ~= nil or c.activatable ~= nil
        or e:HasTag("soil") or FarmTiles.IsWeed(e) or c.farmplanttendable ~= nil or c.farmsoildrinker ~= nil
        or c.watersource ~= nil or e:HasTag("watersource")
        or c.heater ~= nil or c.burnable ~= nil or c.fueled ~= nil
end

local function InScope(e, scope)
    if scope == "items" then
        local item = e.components.inventoryitem
        return item ~= nil and item.owner == nil
    elseif scope == "players" then return e.isplayer == true
    elseif scope == "creatures" then return Creature(e)
    elseif scope == "interactions" then return Interactive(e)
    elseif scope == "boats" then return e.components.walkableplatform ~= nil
    elseif scope == "containers" then return e.components.container ~= nil or e.components.container_proxy ~= nil
    elseif scope == "nearby" or scope == "all" then
        return Discovery.Matches(e, "resources") or Discovery.Matches(e, "containers")
            or e.components.container_proxy ~= nil or e.components.walkableplatform ~= nil
            or Discovery.Matches(e, "structures") or Creature(e) or Interactive(e)
    end
    return Discovery.Matches(e, scope)
end

local function SceneNearby(inst, center, radius, cache)
    local key = string.format("scene:%.17g:%.17g:%.17g", center.x, center.z, radius)
    if cache ~= nil and cache[key] ~= nil then return cache[key] end
    local entities = {}
    for _, entity in ipairs(TheSim:FindEntities(center.x, 0, center.z, radius, nil, SCENE_EXCLUDE)) do
        if entity ~= inst and M.SceneVisible(entity) and inst:GetDistanceSqToInst(entity) <= 32^2
            and (InScope(entity, "nearby") or HasPhysics(entity)
                or entity.deploy_smart_radius ~= nil or entity.deploy_extra_spacing ~= nil
                or entity:HasAnyTag("groundhole", "groundtargetblocker", "farm_debris", "farm_plant", "wall", "burnt", "fire")) then
            entities[#entities + 1] = entity
        end
    end
    SortNearby(inst, entities, center)
    if cache ~= nil then cache[key] = entities end
    return entities
end

function M.RefreshEnvironment(inst, state)
    local p = inst:GetPosition()
    local out = {items = {}, bosses = {}, buildings = {}, containers = {}, creatures = {}, players = {},
        position = {x = p.x, z = p.z}, observed_at = GetTime(), radius = 20, summary = true, limited = false}
    for _, e in ipairs(M.Nearby(inst, out.radius)) do
        local record
        local function Add(group)
            if #group >= 12 then out.limited = true; return end
            record = record or M.Describe(inst, state, e)
            group[#group + 1] = record
        end
        if not e.isplayer and e:HasTag("epic") and Creature(e) then Add(out.bosses)
        elseif not e.isplayer then
            local item = e.components.inventoryitem
            if item ~= nil and item.owner == nil and item.canbepickedup == true then Add(out.items) end
            if Discovery.Matches(e, "structures") then Add(out.buildings) end
            if InScope(e, "containers") then Add(out.containers) end
            if Creature(e) then Add(out.creatures) end
        end
    end
    local players = {}
    for _, player in ipairs(AllPlayers or {}) do
        if player ~= inst and player:IsValid() and inst:GetDistanceSqToInst(player) <= out.radius^2 then
            players[#players + 1] = player
        end
    end
    SortNearby(inst, players)
    for i = 1, math.min(12, #players) do out.players[i] = M.Describe(inst, state, players[i]) end
    out.limited = out.limited or #players > 12
    state.environment = out
end

local SCOPES = {nearby = true, inventory = true, all = true, structures = true, creatures = true, farm = true, scene = true,
    players = true, containers = true, items = true, terrain = true, interactions = true, boats = true}
local WORK = {CHOP=true, MINE=true, DIG=true, HAMMER=true, PICK=true, HARVEST=true}

function M.ValidWork(action, target_type)
    return (action == nil or WORK[action] == true)
        and (target_type == nil or target_type == "tree" or target_type == "weed")
end

function M.MatchesWork(entity, action, target_type)
    if target_type == "tree" and not entity:HasTag("tree") then return false end
    if target_type == "weed" and not FarmTiles.IsWeed(entity) then return false end
    if action == nil then return true end
    local c = entity.components
    if action == "PICK" then return c.pickable ~= nil and c.pickable:CanBePicked() end
    if c.workable ~= nil and c.workable:CanBeWorked() and c.workable:GetWorkAction() == ACTIONS[action] then return true end
    return action == "HARVEST" and (c.harvestable ~= nil or c.crop ~= nil or c.grower ~= nil)
end

local function Offset(value)
    return value == nil or type(value) == "number" and value >= 0 and value <= 10000 and value % 1 == 0
end

function M.ValidScan(args)
    local p = args.position
    return (args.scope == nil or SCOPES[args.scope] == true)
        and M.ValidWork(args.action, args.target_type)
        and (args.action == nil and args.target_type == nil or args.target == nil and args.container == nil
            and (args.scope == nil or args.scope == "nearby" or args.scope == "all" or args.scope == "scene"))
        and (args.filter == nil or type(args.filter) == "string" and #args.filter <= 120)
        and (args.radius == nil or type(args.radius) == "number" and args.radius >= 1 and args.radius <= 32)
        and (args.scope ~= "scene" or args.radius == nil or args.radius <= 16)
        and (p == nil or args.scope == "scene" and type(p) == "table"
            and type(p.x) == "number" and math.abs(p.x) < 1000000
            and type(p.z) == "number" and math.abs(p.z) < 1000000)
        and Offset(args.offset) and Offset(args.contents_offset)
        and (args.target == nil or type(args.target) == "string" and #args.target <= 32
            and args.scope == nil and args.container == nil and args.contents == nil
            and args.filter == nil and args.offset == nil)
        and (args.container == nil or args.scope == "containers" and type(args.container) == "string" and #args.container <= 32)
        and (args.contents_offset == nil or args.container ~= nil and args.contents == true)
end

function M.Scan(inst, state, args, cache)
    local storage = require("my_friend_body_storage")
    local scope, filter = args.scope or "nearby", (args.filter or ""):lower()
    local scene = scope == "scene"
    local targeted_work = args.action ~= nil or args.target_type ~= nil
    local radius = math.min(32, math.max(1, args.radius or (scene and 8 or 32)))
    local entities, seen, found = {}, {}, {}
    local offset=args.offset or 0
    local target = args.container ~= nil and M.Resolve(state, args.container) or nil
    if args.container ~= nil and storage.Resolve(target) == nil then return nil, "unknown_handle:container" end
    if args.target ~= nil then
        target = M.Resolve(state, args.target)
        if target == nil then return nil, "unknown_handle:target" end
        if target == inst or not M.SceneVisible(target)
            or inst:GetDistanceSqToInst(target) > radius^2 then return nil, "target_out_of_view" end
    end
    local function Add(e)
        if e:IsValid() and not seen[e.GUID] then
            entities[#entities + 1], seen[e.GUID] = e, true
        end
    end
    local p = inst:GetPosition()
    local center = args.position or p
    local center_distance = scene and DistanceSq(p, center) or 0
    if center_distance > 32^2 then return nil, "position_out_of_view" end
    local area_clipped = scene and math.sqrt(center_distance) + radius > 32
    if scope == "terrain" then return require("my_friend_body_terrain").Scan(inst,state,args) end
    if scope == "farm" then return require("my_friend_body_terrain").Farm(inst, state, args) end
    if scope == "inventory" or scope == "all" then for _, e in ipairs(M.Items(inst)) do Add(e) end end
    if target ~= nil then
        if args.target ~= nil or Visible(inst, target, radius^2) then Add(target) end
    elseif scope ~= "inventory" then
        local nearby = scene and SceneNearby(inst, center, radius, cache) or M.Nearby(inst, radius, cache)
        for _, e in ipairs(nearby) do
            if scene or targeted_work and M.MatchesWork(e, args.action, args.target_type)
                or not targeted_work and InScope(e, scope) then Add(e) end
        end
    end
    if scope == "inventory" or scope == "all" then SortNearby(inst, entities) end
    local content_count,matched,contents_limited = 0,0,false
    for _, e in ipairs(entities) do
        if e ~= inst and (not targeted_work or M.MatchesWork(e, args.action, args.target_type))
            and (scope ~= "items" or e.components.inventoryitem ~= nil and e.components.inventoryitem.owner == nil)
            and ((e.prefab or ""):lower():find(filter, 1, true)
                or tostring(M.Name(e) or ""):lower():find(filter, 1, true)) then
            matched=matched+1
            if matched>offset and #found<40 then
                local record = M.Describe(inst, state, e, nil, scene or args.target ~= nil)
                if scene then record.distance = M.Distance(center, e:GetPosition()) end
                if args.contents == true and record.accessible then
                    local items = storage.Resolve(e):GetAllItems()
                    table.sort(items, function(a, b) return a.GUID < b.GUID end)
                    local start = args.contents_offset or 0
                    record.contents, record.contents_matched, record.contents_offset = {}, #items, start
                    for i = start + 1, math.min(#items, start + 20, start + 64 - content_count) do
                        record.contents[#record.contents + 1] = M.Describe(inst, state, items[i], e)
                        content_count = content_count + 1
                    end
                    if start + #record.contents < #items then
                        record.contents_next_offset = start + #record.contents
                        record.contents_limited, contents_limited = true, true
                    end
                end
                found[#found + 1] = record
            end
        end
    end
    local more=matched>offset+#found
    return {entities=found,scope=scope,filter=args.filter,action=args.action,target_type=args.target_type,
        position={x=center.x,z=center.z},radius=radius,observed_at=GetTime(),area_clipped=area_clipped or nil,
        offset=offset,matched=matched,returned=#found,next_offset=more and offset+#found or nil,
        entities_limited=more,contents_limited=contents_limited,limited=more or contents_limited or area_clipped}
end
return M
