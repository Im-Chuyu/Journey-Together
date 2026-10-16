-- Runtime discovery only: no timers, entity references or epochs are saved.
local M = {MAX_CELLS = 4096}
local CELL = 32
local worlds = setmetatable({}, {__mode = "k"})
local function State()
    local world = TheWorld or Ents or M
    local state = worlds[world]
    if state == nil then
        state = {cells = {}, resources = {}, cell_count = 0, generation = 0,
            observed = setmetatable({}, {__mode = "k"}), touching = setmetatable({}, {__mode = "k"})}
        worlds[world] = state
    end
    return state
end

local function CellKey(kind, x, z)
    return kind .. ":" .. math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
end

local function Bump(state, kind, x, z)
    local key = CellKey(kind, x, z)
    if state.cells[key] == nil then
        if state.cell_count >= M.MAX_CELLS then
            state.cells, state.cell_count = {}, 0
            state.generation = state.generation + 1
        end
        state.cell_count = state.cell_count + 1
    end
    state.cells[key] = (state.cells[key] or 0) + 1
end

local function Version(state, kind, x, z, radius)
    local value = 0
    for cx = math.floor((x - radius) / CELL), math.floor((x + radius) / CELL) do
        for cz = math.floor((z - radius) / CELL), math.floor((z + radius) / CELL) do
            value = value + (state.cells[kind .. ":" .. cx .. ":" .. cz] or 0)
        end
    end
    return value
end

function M.InventoryChanged(inst)
    inst._my_friend_discovery_inventory = (inst._my_friend_discovery_inventory or 0) + 1
end

local function IsResource(c)
    return c.inventoryitem ~= nil or c.pickable ~= nil or c.workable ~= nil or c.crop ~= nil
end

local function Interesting(entity)
    local c = entity.components
    return IsResource(c) or c.container ~= nil or c.dryer ~= nil or c.dryingrack ~= nil
        or entity._my_friend_base_structure or entity:IsValid() and entity:HasTag("structure")
end

local function Matches(entity, kind)
    local c = entity.components
    return kind == "resources" and IsResource(c)
        or kind == "containers" and c.container ~= nil
        or kind == "structures" and (entity._my_friend_base_structure
            or entity:IsValid() and entity:HasTag("structure"))
        or kind == "garden" and (entity.prefab == "grass" or entity.prefab == "sapling")
        or kind == "drying" and (c.dryer ~= nil or c.dryingrack ~= nil)
end

local function ResourceKeys(entity)
    local c, keys = entity.components, {}
    if not IsResource(c) then return keys end
    if entity.prefab ~= nil then keys[entity.prefab] = true end
    if c.pickable ~= nil and c.pickable.product ~= nil then keys[c.pickable.product] = true end
    if c.edible ~= nil or c.pickable ~= nil or c.crop ~= nil then keys.food = true end
    if c.workable ~= nil and entity:IsValid() then
        local action = c.workable:GetWorkAction()
        if action == ACTIONS.CHOP then keys.log = true
        elseif action == ACTIONS.MINE then
            for prefab in pairs(require("my_friend_resource_memory").MineProducts(entity)) do keys[prefab] = true end
        elseif action == ACTIONS.DIG then
            if entity.prefab == "grass" then keys.dug_grass = true end
            if entity.prefab == "sapling" then keys.dug_sapling = true end
        end
    end
    return keys
end

local KINDS = {"containers", "structures", "garden", "drying", "resources"}
local function KindMask(entity)
    local mask = 0
    for index, kind in ipairs(KINDS) do if Matches(entity, kind) then mask = mask + 2^(index - 1) end end
    return mask
end
local function MarkAt(state, entity, x, z, previous)
    for index, kind in ipairs(KINDS) do
        if Matches(entity, kind) or previous ~= nil and math.floor(previous / 2^(index - 1)) % 2 == 1 then
            Bump(state, kind, x, z)
        end
    end
end

function M.Touch(entity)
    if entity == nil or entity.components == nil
        or TheWorld ~= nil and not TheWorld.ismastersim then return end
    local state = State()
    if state.touching[entity] then return end
    local record = state.observed[entity]
    if record == nil and not Interesting(entity) then return end
    local x, z
    if record ~= nil then x, z = record.x, record.z end
    if entity:IsValid() and entity.Transform ~= nil then
        local current_x, _, current_z = entity.Transform:GetWorldPosition()
        x, z = current_x, current_z
    end
    if x == nil then return end
    state.touching[entity] = true
    if record ~= nil and (record.x ~= x or record.z ~= z) then MarkAt(state, entity, record.x, record.z, record.kinds) end
    MarkAt(state, entity, x, z, record ~= nil and record.kinds or nil)
    local keys = ResourceKeys(entity)
    for prefab in pairs(record ~= nil and record.keys or {}) do keys[prefab] = true end
    for prefab in pairs(keys) do state.resources[prefab] = (state.resources[prefab] or 0) + 1 end
    if record ~= nil then record.x, record.z, record.keys, record.kinds = x, z, keys, KindMask(entity) end
    local ii = entity.components.inventoryitem
    local owner = ii ~= nil and ii.owner or nil
    if owner ~= nil and owner ~= entity and owner.components ~= nil then
        if owner.components.inventory ~= nil then M.InventoryChanged(owner) end
        if owner.components.container ~= nil then M.Touch(owner) end
    end
    state.touching[entity] = nil
end

-- Only entities returned by a real query need previous-position metadata.
-- Values never point back to their weak keys.
local function Observe(entity)
    local state = State()
    if state.observed[entity] == nil then
        local x, _, z = entity.Transform:GetWorldPosition()
        state.observed[entity] = {x = x, z = z, keys = ResourceKeys(entity), kinds = KindMask(entity)}
    end
end

function M.OnSpawn(entity)
    if entity == nil or entity.Transform == nil or entity.components == nil
        or not Interesting(entity) or TheWorld ~= nil and not TheWorld.ismastersim then return end
    M.Touch(entity)
    local state, world = State(), TheWorld
    -- Prefab postinit precedes placement. Batch final-position invalidations
    -- into one world task, without a listener, closure or timer per entity.
    if state.queried and world ~= nil and world.DoTaskInTime ~= nil then
        state.pending = state.pending or setmetatable({}, {__mode = "k"})
        state.pending[entity] = true
        if not state.queued then
            state.queued = true
            world:DoTaskInTime(0, function()
                local pending = state.pending
                state.pending, state.queued = nil, nil
                for source in pairs(pending or {}) do if source:IsValid() then M.Touch(source) end end
            end)
        end
    end
end

M.ConfigureEntity = M.OnSpawn

local EVENTS = {}
for _, event in ipairs({"onremove", "burnt", "onburnt", "onignite", "onextinguish", "itemget", "itemlose",
    "onopen", "onclose", "ondropped", "onputininventory", "stacksizechange", "percentusedchange",
    "perishchange", "onbuilt", "itemplanted", "picked", "worked", "workfinished"}) do EVENTS[event] = true end

local function Changed(entity, ...)
    M.Touch(entity)
    return ...
end

local function WrapMethods(class, names)
    class._my_friend_discovery_methods = class._my_friend_discovery_methods or {}
    for _, name in ipairs(names) do
        local original = class[name]
        if type(original) == "function" and not class._my_friend_discovery_methods[name] then
            class._my_friend_discovery_methods[name] = true
            class[name] = function(self, ...) return Changed(self.inst, original(self, ...)) end
        end
    end
end

function M.Install(entity_script, components)
    if not entity_script._my_friend_discovery_events then
        entity_script._my_friend_discovery_events = true
        local original = entity_script.PushEvent_Internal
        entity_script.PushEvent_Internal = function(self, event, ...)
            if EVENTS[event] then return Changed(self, original(self, event, ...)) end
            return original(self, event, ...)
        end
    end
    components = components or {pickable = require("components/pickable"), crop = require("components/crop"),
        dryer = require("components/dryer")}
    WrapMethods(components.pickable, {"Regen", "FinishGrowing", "Fertilize", "OnTransplant", "MakeBarren", "MakeEmpty"})
    WrapMethods(components.crop, {"Mature", "Harvest", "MakeWithered"})
    -- Native DoDry calls Resume after changing ingredient/product, even when
    -- no event is emitted. Keep prefab callbacks untouched.
    WrapMethods(components.dryer, {"Resume", "StartDrying", "StopDrying", "Harvest", "OnLoad"})
end

-- Both successful and empty discoveries survive until a relevant event or
-- a change of search area. Moving queries include a small discovery fringe;
-- callers still check their exact action range before using an entity.
function M.Query(inst, key, kind, x, y, z, radius, must, cant, oneof, moving)
    local state = State()
    state.queried = true
    local queries = inst._my_friend_discoveries or {}
    inst._my_friend_discoveries = queries
    local cache = queries[key]
    local margin = moving and 4 or 0
    if cache ~= nil and cache.world == state and cache.generation == state.generation
        and cache.kind == kind and cache.radius == radius
        and (cache.x - x)^2 + (cache.z - z)^2 <= margin^2
        and cache.version == Version(state, kind, cache.x, cache.z, radius + margin) then
        local items = {}
        for _, guid in ipairs(cache.ids) do
            local entity = (Ents or {})[guid]
            if entity ~= nil and entity:IsValid() then items[#items + 1] = entity end
        end
        return items, cache
    end
    local found = TheSim:FindEntities(x, y, z, radius + margin, must, cant, oneof)
    local items, ids = {}, {}
    for _, entity in ipairs(found) do
        if entity:IsValid() and Matches(entity, kind) then
            Observe(entity)
            items[#items + 1], ids[#ids + 1] = entity, entity.GUID
        end
    end
    cache = {world = state, generation = state.generation, kind = kind, x = x, z = z, radius = radius, ids = ids,
        version = Version(state, kind, x, z, radius + margin)}
    queries[key] = cache
    return items, cache
end

function M.ResourceVersion(needs)
    local state, value = State(), 0
    state.queried = true
    for prefab in pairs(needs) do value = value + (state.resources[prefab] or 0) end
    return value
end

function M.RetryAt(inst)
    local now, earliest = GetTime(), math.huge
    for _, field in ipairs({"_my_friend_base_blocked", "_my_friend_collect_blocked",
        "_my_friend_harmful_resources", "_my_friend_storage_retry"}) do
        for _, deadline in pairs(inst[field] or {}) do
            if type(deadline) == "number" and deadline > now then earliest = math.min(earliest, deadline) end
        end
    end
    return earliest
end

return M
