local Home = require("my_friend_home")
local M = {RECHECK_RANGE = 3, NEARBY_RANGE = 20, TRAVEL_MARGIN = 8}

local function IsStation(station)
    return station ~= nil and station:IsValid() and station.prefab == "bookstation"
        and not station:HasAnyTag("INLIMBO", "burnt", "fire")
        and station.components.container ~= nil
end

local function Key(point)
    return string.format("%.2f:%.2f", point.x, point.z)
end

local function InBase(base, point)
    return (point.x - base.x)^2 + (point.z - base.z)^2 <= Home.WANDER_RADIUS^2
end

local function Observe(inst, base, stations)
    local memory = inst._my_friend_bookstations or {}
    inst._my_friend_bookstations = memory
    for _, station in ipairs(stations) do
        if IsStation(station) then
            local point = station:GetPosition()
            if InBase(base, point) then
                memory[Key(point)] = {x = point.x, z = point.z, entity = station}
            end
        end
    end
end

function M.RememberBase(inst, point, facilities)
    if inst.prefab ~= "wickerbottom" or point == nil then return end
    inst._my_friend_book_base = {x = point.x, z = point.z}
    inst._my_friend_bookstations = {}
    if facilities ~= nil then Observe(inst, point, facilities) else M.Scan(inst) end
end

local function SyncBase(inst)
    if inst.prefab ~= "wickerbottom" then return end
    local home = inst._my_friend_home
    local base = inst._my_friend_book_base
    if home ~= nil and home.mode == "base"
        and (base == nil or home.x ~= base.x or home.z ~= base.z) then
        base = {x = home.x, z = home.z}
        inst._my_friend_book_base, inst._my_friend_bookstations = base, {}
    elseif base == nil then
        local point = require("my_friend_base_ai").GetBasePoint(inst)
        if point ~= nil then
            base = {x = point.x, z = point.z}
            inst._my_friend_book_base = base
        end
    end
    return base
end

function M.IsAtBase(inst)
    local base = SyncBase(inst)
    return base ~= nil and InBase(base, inst:GetPosition())
end

function M.Prune(inst)
    if inst.prefab ~= "wickerbottom" then return end
    local base = SyncBase(inst)
    if base == nil then return end
    for key, record in pairs(inst._my_friend_bookstations or {}) do
        if not InBase(base, record) or record.entity ~= nil
            and (not IsStation(record.entity) or Key(record.entity:GetPosition()) ~= key) then
            inst._my_friend_bookstations[key] = nil
        end
    end
end

function M.Scan(inst)
    if inst.prefab ~= "wickerbottom" then return end
    local base = SyncBase(inst)
    if base == nil then return end
    -- Explicit discovery only. A read request may refresh the base once if
    -- remembered shelves do not provide its book; idle/store never scan.
    Observe(inst, base, TheSim:FindEntities(base.x, 0, base.z, Home.WANDER_RADIUS,
        {"structure"}, {"INLIMBO", "burnt", "fire"}))
end

function M.ScanNearby(inst, command)
    if inst.prefab ~= "wickerbottom" or command == nil or command.special ~= "read"
        or inst._my_friend_command ~= command or command.bookstations_nearby_scanned then return false end
    command.bookstations_nearby_scanned = true
    local point = inst:GetPosition()
    command.book_search_origin = Vector3(point.x, 0, point.z)
    command.bookstations_nearby = {}
    local stations = TheSim:FindEntities(point.x, 0, point.z, M.NEARBY_RANGE,
        {"structure"}, {"INLIMBO", "burnt", "fire"})
    for _, station in ipairs(stations) do
        if IsStation(station) then
            local p = station:GetPosition()
            if (p.x - point.x)^2 + (p.z - point.z)^2 <= M.NEARBY_RANGE^2 then
                command.bookstations_nearby[Key(p)] = {x = p.x, z = p.z, entity = station}
            end
        end
    end
    -- Shelves discovered inside the base join persistent memory. Shelves
    -- outside it belong only to this request, never to its save data.
    local base = SyncBase(inst)
    if base ~= nil then Observe(inst, base, stations) end
    return true
end

local function NearbyRecords(inst)
    local command = inst._my_friend_command
    if command == nil or command.special ~= "read" then return {} end
    local records, origin = command.bookstations_nearby or {}, command.book_search_origin
    for key, record in pairs(records) do
        local station = record.entity
        if origin == nil or not IsStation(station) or Key(station:GetPosition()) ~= key
            or (record.x - origin.x)^2 + (record.z - origin.z)^2 > M.NEARBY_RANGE^2 then
            records[key] = nil
        end
    end
    return records
end

function M.HasRecords(inst)
    if inst.prefab ~= "wickerbottom" then return false end
    M.Prune(inst)
    return next(inst._my_friend_bookstations or {}) ~= nil
end

function M.Stations(inst)
    if inst.prefab ~= "wickerbottom" then return {} end
    M.Prune(inst)
    local result, seen = {}, {}
    for _, record in pairs(inst._my_friend_bookstations or {}) do
        if IsStation(record.entity) then
            result[#result + 1], seen[record.entity] = record.entity, true
        end
    end
    for _, record in pairs(NearbyRecords(inst)) do
        if not seen[record.entity] then result[#result + 1] = record.entity end
    end
    return result
end

function M.IsRemembered(inst, station)
    local base = inst._my_friend_book_base
    if inst.prefab ~= "wickerbottom" or not IsStation(station) then return false end
    local point = station:GetPosition()
    local record = (inst._my_friend_bookstations or {})[Key(point)]
    if base ~= nil and record ~= nil and record.entity == station and InBase(base, point) then return true end
    record = NearbyRecords(inst)[Key(point)]
    return record ~= nil and record.entity == station
end

function M.InTravelRange(inst, action, point)
    if not M.IsActionValid(inst, action) then return false end
    local base = inst._my_friend_book_base
    if base ~= nil and InBase(base, point) then return true end
    local origin = action._my_friend_book_origin
    local target = action._my_friend_bookstation
    local record = (inst._my_friend_bookstations or {})[action._my_friend_book_visit]
    local goal = target ~= nil and target:GetPosition() or record
    if origin == nil or goal == nil then return false end
    -- A bounded corridor lets a companion outside its base reach a known
    -- shelf. A base-centred radius alone rejects the very first route step.
    local dx, dz = goal.x - origin.x, goal.z - origin.z
    local length = dx * dx + dz * dz
    local t = length > 0 and math.max(0, math.min(1,
        ((point.x - origin.x) * dx + (point.z - origin.z) * dz) / length)) or 0
    return (point.x - origin.x - dx * t)^2 + (point.z - origin.z - dz * t)^2 <= M.TRAVEL_MARGIN^2
end

function M.IsActionValid(inst, action)
    if inst.prefab ~= "wickerbottom" then return false end
    if action._my_friend_book_command ~= nil
        and action._my_friend_book_command ~= inst._my_friend_command then return false end
    if action._my_friend_bookstation ~= nil then
        return M.IsRemembered(inst, action._my_friend_bookstation)
    end
    return inst._my_friend_book_base ~= nil
        and (inst._my_friend_bookstations or {})[action._my_friend_book_visit] ~= nil
end

function M.Guard(inst, action, station)
    if M.IsRemembered(inst, station) then
        action._my_friend_bookstation = station
        action._my_friend_book_origin = inst:GetPosition()
        action._my_friend_book_command = inst._my_friend_command
    end
    return require("my_friend_policy").GuardAction(inst, action)
end

-- On a restored world a remembered shelf may not have been resolved yet.
-- Walking to its saved position gives the normal book workflow another scan.
function M.GetVisitAction(inst, command)
    if inst.prefab ~= "wickerbottom" then return end
    M.Prune(inst)
    local closest, distance
    local visited = command ~= nil and command.bookstations_visited or {}
    for key, record in pairs(inst._my_friend_bookstations or {}) do
        if record.entity == nil and not visited[key] then
            local point = Vector3(record.x, 0, record.z)
            local d = inst:GetDistanceSqToPoint(point)
            if closest == nil or d < distance then closest, distance = {key = key, point = point}, d end
        end
    end
    if closest == nil then return end
    local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, closest.point)
    action._my_friend_book_visit = closest.key
    action._my_friend_book_origin = inst:GetPosition()
    action._my_friend_book_command = command
    action.arrivedist = 2
    action.validfn = function()
        return inst._my_friend_bookstations[closest.key] ~= nil
            and (command == nil or inst._my_friend_command == command)
    end
    action:AddSuccessAction(function()
        if not inst:IsValid() or command ~= nil and inst._my_friend_command ~= command then return end
        if command ~= nil then
            command.bookstations_visited = command.bookstations_visited or {}
            command.bookstations_visited[closest.key] = true
        end
        -- Resolve only this saved coordinate after arriving; do not rescan
        -- the base or discover additional shelves during every action tick.
        local base = inst._my_friend_book_base
        local record = (inst._my_friend_bookstations or {})[closest.key]
        if record == nil or base == nil then return end
        inst._my_friend_bookstations[closest.key] = nil
        for _, station in ipairs(TheSim:FindEntities(record.x, 0, record.z, M.RECHECK_RANGE,
            {"structure"}, {"INLIMBO", "burnt", "fire"})) do
            if IsStation(station) and Key(station:GetPosition()) == closest.key then
                record.entity = station
                inst._my_friend_bookstations[closest.key] = record
                break
            end
        end
    end)
    action:AddFailAction(function()
        if not action._my_friend_cancelled and command ~= nil then
            command.bookstations_visited = command.bookstations_visited or {}
            command.bookstations_visited[closest.key] = true
        end
    end)
    return require("my_friend_policy").GuardAction(inst, action)
end

function M.Save(inst, data)
    if inst.prefab ~= "wickerbottom" or inst._my_friend_book_base == nil then return end
    M.Prune(inst)
    local records = {}
    for _, record in pairs(inst._my_friend_bookstations or {}) do
        records[#records + 1] = {x = record.x, z = record.z}
    end
    local base = inst._my_friend_book_base
    data.my_friend_bookstations = {base = {x = base.x, z = base.z}, stations = records}
end

function M.Load(inst, data)
    if inst.prefab ~= "wickerbottom" then return end
    inst._my_friend_book_base, inst._my_friend_bookstations = nil, {}
    local saved = data ~= nil and data.my_friend_bookstations or nil
    local function Valid(point)
        return type(point) == "table" and type(point.x) == "number" and type(point.z) == "number"
            and point.x == point.x and point.z == point.z
            and math.abs(point.x) < math.huge and math.abs(point.z) < math.huge
    end
    if type(saved) ~= "table" or not Valid(saved.base) then return end
    inst._my_friend_book_base = {x = saved.base.x, z = saved.base.z}
    for _, point in ipairs(type(saved.stations) == "table" and saved.stations or {}) do
        if Valid(point) and InBase(saved.base, point) then
            inst._my_friend_bookstations[Key(point)] = {x = point.x, z = point.z}
        end
    end
end

return M
