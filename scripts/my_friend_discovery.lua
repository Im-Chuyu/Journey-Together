-- Runtime discovery only: no timers, entity references or epochs are saved.
local M = {}
local CELL = 32
local worlds = setmetatable({}, {__mode = "k"})
local function State()
    local world = TheWorld or Ents or M
    local state = worlds[world]
    if state == nil then state = {cells = {}, resources = {}}; worlds[world] = state end
    return state
end

local function CellKey(kind, x, z)
    return kind .. ":" .. math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
end

local function Bump(state, kind, x, z)
    local key = CellKey(kind, x, z)
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

function M.Touch(entity)
    if entity == nil then return end
    local watch = entity._my_friend_discovery_watch
    if watch == nil or watch.touching then return end
    watch.touching = true
    local state = State()
    local x, z = watch.x, watch.z
    local alive = entity:IsValid()
    if alive and entity.Transform ~= nil then
        local current_x, _, current_z = entity.Transform:GetWorldPosition()
        x, z = current_x, current_z
    end
    if x == nil then watch.touching = nil; return end
    local old_x, old_z = watch.x, watch.z
    for _, kind in ipairs(watch.kinds) do
        if watch.x ~= nil and (watch.x ~= x or watch.z ~= z) then
            Bump(state, kind, watch.x, watch.z)
        end
        Bump(state, kind, x, z)
    end
    watch.x, watch.z = x, z
    if watch.resource then
        if old_x ~= nil and (old_x ~= x or old_z ~= z) then Bump(state, "resources", old_x, old_z) end
        Bump(state, "resources", x, z)
        local c, keys = entity.components or {}, watch.resource_keys or {}
        watch.resource_keys = keys
        if entity.prefab ~= nil then keys[entity.prefab] = true end
        if c.pickable ~= nil and c.pickable.product ~= nil then keys[c.pickable.product] = true end
        if c.edible ~= nil or c.pickable ~= nil or c.crop ~= nil then keys.food = true end
        if alive and c.workable ~= nil then
            for prefab in pairs(require("my_friend_resource_memory").Products(entity)) do keys[prefab] = true end
        end
        for prefab in pairs(keys) do state.resources[prefab] = (state.resources[prefab] or 0) + 1 end
    end
    local ii = entity.components ~= nil and entity.components.inventoryitem or nil
    local owner = ii ~= nil and ii.owner or nil
    if owner ~= nil and owner ~= entity and owner.components ~= nil then
        if owner.components.inventory ~= nil then M.InventoryChanged(owner) end
        if owner.components.container ~= nil then M.Touch(owner) end
    end
    watch.touching = nil
end

local function Changed(entity, ...)
    M.Touch(entity)
    return ...
end

local function Wrap(component, name)
    local original = component[name]
    if type(original) ~= "function" then return end
    component[name] = function(self, ...)
        return Changed(self.inst, original(self, ...))
    end
end

function M.ConfigureEntity(entity)
    if entity == nil or entity.Transform == nil or entity.components == nil
        or entity._my_friend_discovery_watch ~= nil
        or TheWorld ~= nil and not TheWorld.ismastersim then return end
    local c, kinds, events = entity.components, {},
        {onremove = true, burnt = true, onburnt = true, onignite = true, onextinguish = true}
    if c.container ~= nil then
        kinds[#kinds + 1] = "containers"
        for _, event in ipairs({"itemget", "itemlose", "onopen", "onclose"}) do events[event] = true end
    end
    if entity:HasTag("structure") or entity._my_friend_base_structure then kinds[#kinds + 1] = "structures" end
    if entity.prefab == "grass" or entity.prefab == "sapling" then kinds[#kinds + 1] = "garden" end
    if c.dryer ~= nil or c.dryingrack ~= nil then kinds[#kinds + 1] = "drying" end
    local resource = c.inventoryitem ~= nil or c.pickable ~= nil or c.workable ~= nil or c.crop ~= nil
    if #kinds == 0 and not resource then return end
    entity._my_friend_discovery_watch = {kinds = kinds, resource = resource}
    if c.inventoryitem ~= nil then
        for _, event in ipairs({"ondropped", "onputininventory", "stacksizechange"}) do events[event] = true end
        if c.armor ~= nil or c.fueled ~= nil or c.finiteuses ~= nil then events.percentusedchange = true end
        if c.perishable ~= nil then events.perishchange = true end
    end
    if entity:HasTag("structure") then events.onbuilt = true end
    if c.pickable ~= nil then events.itemplanted, events.picked = true, true end
    if c.workable ~= nil then events.worked, events.workfinished = true, true end
    if entity.ListenForEvent ~= nil then
        for event in pairs(events) do entity:ListenForEvent(event, M.Touch) end
    end
    -- Regrowth and old-style drying completion do not emit native events.
    -- Preserve the original callbacks and all return values, including nils.
    if c.pickable ~= nil then
        for _, name in ipairs({"Regen", "FinishGrowing", "Fertilize", "OnTransplant", "MakeBarren", "MakeEmpty"}) do
            Wrap(c.pickable, name)
        end
    end
    if c.crop ~= nil then
        for _, name in ipairs({"Mature", "Harvest", "MakeWithered"}) do Wrap(c.crop, name) end
    end
    if c.dryer ~= nil and c.dryer.ondonedrying ~= nil then
        local original = c.dryer.ondonedrying
        c.dryer.ondonedrying = function(inst, ...) return Changed(inst, original(inst, ...)) end
    end
    M.Touch(entity)
    -- SpawnPrefab callers place structures after postinit; resolve that final
    -- position once. Native entity removal cancels its own delayed tasks.
    if #kinds > 0 and entity.DoTaskInTime ~= nil then
        entity:DoTaskInTime(0, function(inst) if inst:IsValid() then M.Touch(inst) end end)
    end
end

-- Both successful and empty discoveries survive until a relevant event or
-- a change of search area. Moving queries include a small discovery fringe;
-- callers still check their exact action range before using an entity.
function M.Query(inst, key, kind, x, y, z, radius, must, cant, oneof, moving)
    local state = State()
    local queries = inst._my_friend_discoveries or {}
    inst._my_friend_discoveries = queries
    local cache = queries[key]
    local margin = moving and 4 or 0
    if cache ~= nil and cache.world == state and cache.radius == radius
        and (cache.x - x)^2 + (cache.z - z)^2 <= margin^2
        and cache.version == Version(state, kind, cache.x, cache.z, radius + margin) then
        return cache.items, cache
    end
    local found = TheSim:FindEntities(x, y, z, radius + margin, must, cant, oneof)
    local items = {}
    for _, entity in ipairs(found) do
        M.ConfigureEntity(entity)
        local watch = entity._my_friend_discovery_watch
        local matches = watch ~= nil and kind == "resources" and watch.resource
        for _, category in ipairs(watch ~= nil and watch.kinds or {}) do
            if category == kind then matches = true break end
        end
        if matches then items[#items + 1] = entity end
    end
    cache = {world = state, x = x, z = z, radius = radius, items = items,
        version = Version(state, kind, x, z, radius + margin)}
    queries[key] = cache
    return items, cache
end

function M.ResourceVersion(needs)
    local state, value = State(), 0
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
