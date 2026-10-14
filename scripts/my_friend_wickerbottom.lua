local Home = require("my_friend_home")
local M = {RECHECK_RANGE = 3}

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

function M.RememberBase(inst, point)
    if inst.prefab ~= "wickerbottom" or point == nil then return end
    inst._my_friend_book_base = {x = point.x, z = point.z}
    inst._my_friend_bookstations = {}
    M.Scan(inst)
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
    -- Discovery is explicit: once when assigning a base, or once per read
    -- command when all remembered shelves are gone. Idle/store never scan.
    Observe(inst, base, TheSim:FindEntities(base.x, 0, base.z, Home.WANDER_RADIUS,
        {"structure"}, {"INLIMBO", "burnt", "fire"}))
end

function M.HasRecords(inst)
    if inst.prefab ~= "wickerbottom" then return false end
    M.Prune(inst)
    return next(inst._my_friend_bookstations or {}) ~= nil
end

function M.Stations(inst)
    if inst.prefab ~= "wickerbottom" then return {} end
    M.Prune(inst)
    local result = {}
    for _, record in pairs(inst._my_friend_bookstations or {}) do
        if IsStation(record.entity) then result[#result + 1] = record.entity end
    end
    return result
end

function M.IsRemembered(inst, station)
    local base = inst._my_friend_book_base
    if inst.prefab ~= "wickerbottom" or base == nil or not IsStation(station) then return false end
    local point = station:GetPosition()
    local record = (inst._my_friend_bookstations or {})[Key(point)]
    return record ~= nil and record.entity == station and InBase(base, point)
end

function M.InTravelRange(inst, action, point)
    if not M.IsActionValid(inst, action) then return false end
    local base = inst._my_friend_book_base
    return (point.x - base.x)^2 + (point.z - base.z)^2 <= Home.TravelLimit()^2
end

function M.IsActionValid(inst, action)
    if inst.prefab ~= "wickerbottom" then return false end
    if action._my_friend_bookstation ~= nil then
        return M.IsRemembered(inst, action._my_friend_bookstation)
    end
    return inst._my_friend_book_base ~= nil
        and (inst._my_friend_bookstations or {})[action._my_friend_book_visit] ~= nil
end

function M.Guard(inst, action, station)
    if M.IsRemembered(inst, station) then action._my_friend_bookstation = station end
    return require("my_friend_policy").GuardAction(inst, action)
end

-- On a restored world a remembered shelf may not have been resolved yet.
-- Walking to its saved position gives the normal book workflow another scan.
function M.GetVisitAction(inst, command)
    if inst.prefab ~= "wickerbottom" then return end
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
    action.arrivedist = 2
    action.validfn = function()
        return inst._my_friend_bookstations[closest.key] ~= nil
            and (command == nil or inst._my_friend_command == command)
    end
    action:AddSuccessAction(function()
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
