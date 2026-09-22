local M = {}
M.CELL_SIZE = 16
M.MAX_CELLS = 64
M.MAX_AGE = 960

local function Key(x, z)
    return math.floor(x / M.CELL_SIZE)..":"..math.floor(z / M.CELL_SIZE)
end

function M.MineProducts(entity)
    local result = {}
    local loot = entity.components ~= nil and entity.components.lootdropper or nil
    local function Add(prefab, chance)
        if type(prefab) == "string" and (chance == nil or chance > 0) then result[prefab] = 1 end
    end
    if loot ~= nil then
        for _, prefab in ipairs(loot.loot or {}) do Add(prefab) end
        for _, entry in ipairs(loot.chanceloot or {}) do Add(entry.prefab, entry.chance) end
        local shared = loot.chanceloottable ~= nil and
            LootTables ~= nil and LootTables[loot.chanceloottable] or nil
        for _, entry in ipairs(shared or {}) do
            if type(entry) == "table" then Add(entry[1], entry[2]) end
        end
    end
    if next(result) == nil then
        local prefab = entity.prefab or ""
        if prefab == "rock1" then result.rocks, result.flint, result.nitre = 1, 1, 1
        elseif prefab == "rock2" then result.rocks, result.flint, result.goldnugget = 1, 1, 1
        elseif string.find(prefab, "rock_flintless", 1, true) == 1 then result.rocks = 1
        elseif prefab == "rock_moon" then result.rocks, result.flint, result.moonrocknugget = 1, 1, 1
        end
    end
    return result
end

function M.Products(entity)
    local c = entity.components or {}
    if c.inventoryitem ~= nil and c.inventoryitem.owner == nil then
        return { [entity.prefab] = 1 }
    end
    local result = {}
    if c.pickable ~= nil and c.pickable:CanBePicked() and c.pickable.product ~= nil then
        result[c.pickable.product] = 1
    end
    if c.workable ~= nil and c.workable:CanBeWorked() then
        local action = c.workable:GetWorkAction()
        if action == ACTIONS.CHOP then result.log = 1
        elseif action == ACTIONS.MINE then
            for prefab, amount in pairs(M.MineProducts(entity)) do result[prefab] = amount end
        elseif action == ACTIONS.DIG then
            if entity.prefab == "grass" then result.dug_grass = 1 end
            if entity.prefab == "sapling" then result.dug_sapling = 1 end
        end
    end
    return result
end

function M.Observe(inst, entities, x, z, radius, now)
    local memory = inst._my_friend_resource_memory or {}
    inst._my_friend_resource_memory = memory
    -- Reobserving an area replaces its counts, including resources now gone.
    for key, cell in pairs(memory) do
        if now - cell.seen > M.MAX_AGE then memory[key] = nil
        elseif (cell.x - x)^2 + (cell.z - z)^2 <= radius^2 then
            cell.counts, cell.seen = {}, now
        end
    end
    local observed = {}
    for _, entity in ipairs(entities) do
        local ex, _, ez = entity.Transform:GetWorldPosition()
        local key = Key(ex, ez)
        if not observed[key] then
            local blocked = memory[key] ~= nil and memory[key].blocked_until or nil
            memory[key] = { x = ex, z = ez, seen = now, counts = {}, blocked_until = blocked }
            observed[key] = true
        end
        local counts = memory[key].counts
        for prefab, amount in pairs(M.Products(entity)) do
            counts[prefab] = (counts[prefab] or 0) + amount
        end
    end
    local sorted = {}
    for key, cell in pairs(memory) do sorted[#sorted + 1] = { key = key, seen = cell.seen } end
    table.sort(sorted, function(a, b) return a.seen > b.seen end)
    for index = M.MAX_CELLS + 1, #sorted do memory[sorted[index].key] = nil end
end

function M.Find(inst, needs, x, z, now, allowed)
    local best, bestscore
    for _, cell in pairs(inst._my_friend_resource_memory or {}) do
        local distance = math.sqrt((cell.x - x)^2 + (cell.z - z)^2)
        local age = now - cell.seen
        local value = 0
        for prefab, amount in pairs(needs) do
            if type(amount) == "number" and amount > 0 then
                value = value + math.min(amount, cell.counts[prefab] or 0)
            end
        end
        if value > 0 and age <= M.MAX_AGE and distance > 12
            and now >= (cell.blocked_until or 0)
            and (allowed == nil or allowed(cell)) then
            local score = value * 12 - distance * .3 - age * .02
            if bestscore == nil or score > bestscore then best, bestscore = cell, score end
        end
    end
    return best
end

function M.Block(inst, x, z, now)
    local cell = (inst._my_friend_resource_memory or {})[Key(x, z)]
    if cell ~= nil then cell.blocked_until = now + 120 end
end

function M.ExtraAllowance(hunger, urgent, free_slots, density)
    if urgent or hunger < .5 or free_slots <= 2 or density < 3 then return 0 end
    return math.min(6, math.max(1, free_slots - 2), density)
end

function M.Save(inst, now)
    local result = {}
    for _, cell in pairs(inst._my_friend_resource_memory or {}) do
        local age = math.max(0, now - cell.seen)
        if age <= M.MAX_AGE and #result < M.MAX_CELLS then
            result[#result + 1] = { x = cell.x, z = cell.z, age = age, counts = cell.counts }
        end
    end
    return result
end

function M.Load(inst, data, now)
    inst._my_friend_resource_memory = {}
    for index, cell in ipairs(type(data) == "table" and data or {}) do
        if index > M.MAX_CELLS then break end
        if type(cell) == "table" and type(cell.x) == "number" and type(cell.z) == "number"
            and cell.x == cell.x and cell.z == cell.z and math.abs(cell.x) < 100000
            and math.abs(cell.z) < 100000 and type(cell.age) == "number"
            and cell.age >= 0 and cell.age <= M.MAX_AGE and type(cell.counts) == "table" then
            local counts = {}
            for prefab, count in pairs(cell.counts) do
                if type(prefab) == "string" and type(count) == "number" and count > 0 then
                    counts[prefab] = math.min(100, count)
                end
            end
            inst._my_friend_resource_memory[Key(cell.x, cell.z)] = {
                x = cell.x, z = cell.z, seen = now - cell.age, counts = counts,
            }
        end
    end
end

return M
