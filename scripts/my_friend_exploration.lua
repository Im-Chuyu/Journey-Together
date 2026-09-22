local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")
local M = {}
local CELL = 16

local function Key(x, z)
    return math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
end

local function Memory(inst)
    if inst._my_friend_explored == nil then
        inst._my_friend_explored = {visited = {}, serial = 0}
    end
    return inst._my_friend_explored
end

function M.Observe(inst)
    if inst:HasTag("playerghost") or GetTime() < (inst._my_friend_explore_observe or 0) then return end
    inst._my_friend_explore_observe = GetTime() + 1
    local p, memory = inst:GetPosition(), Memory(inst)
    local key = Key(p.x, p.z)
    if memory.last ~= key then
        memory.serial = memory.serial + 1
        memory.visited[key], memory.last = memory.serial, key
    end
end

function M.Save(inst, data)
    data.my_friend_explored = inst._my_friend_explored
end

function M.Load(inst, data)
    local memory = data ~= nil and data.my_friend_explored or nil
    if type(memory) == "table" and type(memory.visited) == "table"
        and type(memory.serial) == "number" then inst._my_friend_explored = memory end
end

local function Destination(inst, command)
    local origin, memory = inst:GetPosition(), Memory(inst)
    local cx, cz = math.floor(origin.x / CELL), math.floor(origin.z / CELL)
    local now, candidates = GetTime(), {}
    command.explore_blocked = command.explore_blocked or {}
    for key, deadline in pairs(command.explore_blocked) do
        if now >= deadline then command.explore_blocked[key] = nil end
    end
    for dx = -6, 6 do
        for dz = -6, 6 do
            local point = Vector3((cx + dx + .5) * CELL, 0, (cz + dz + .5) * CELL)
            local key = Key(point.x, point.z)
            local distance = (point.x - origin.x)^2 + (point.z - origin.z)^2
            if distance >= 12^2 and not command.explore_blocked[key]
                and Navigation.IsLand(point) and not Navigation.IsBlocked(inst, point) then
                local visited = memory.visited[key]
                candidates[#candidates + 1] = {point = point,
                    score = (visited ~= nil and 100000 + visited or 0) + math.sqrt(distance)}
            end
        end
    end
    table.sort(candidates, function(a, b) return a.score < b.score end)
    for _, candidate in ipairs(candidates) do
        if require("my_friend_recovery_safety").IsSafe(inst, candidate.point) then return candidate.point end
    end
end

function M.GetAction(inst)
    if not Policy.IsRoaming(inst) or Policy.IsBusy(inst) then return end
    local command, now = inst._my_friend_command, GetTime()
    local ride = require("my_friend_exploration_riding").GetTravelAction(inst)
    if ride ~= nil then return ride end
    if now < (command.explore_after or 0) then return end
    M.Observe(inst)
    local point = command.explore_target
    if point == nil or Navigation.IsBlocked(inst, point)
        or inst:GetDistanceSqToPoint(point) <= 2^2 then
        point = Destination(inst, command)
        command.explore_target = point
    end
    if point == nil then
        command.explore_after = now + 5
        return
    end
    local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point)
    action.arrivedist = 1
    action._my_friend_roaming = command
    action._my_friend_dialogue_kind = command.id == "fish" and "fish_search" or "explore"
    action:AddSuccessAction(function()
        if inst._my_friend_command == command then
            local memory = Memory(inst)
            memory.serial = memory.serial + 1
            memory.visited[Key(point.x, point.z)] = memory.serial
            command.explore_target = nil
        end
    end)
    action:AddFailAction(function()
        if not action._my_friend_cancelled and inst._my_friend_command == command then
            if action._my_friend_path_failed then
                require("my_friend_exploration_riding").OnTravelFailed(inst)
            end
            command.explore_blocked = command.explore_blocked or {}
            command.explore_blocked[Key(point.x, point.z)] = GetTime() + 600
            command.explore_target = nil
        end
    end)
    return action
end

return M
