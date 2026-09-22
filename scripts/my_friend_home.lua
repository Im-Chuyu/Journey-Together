-- Manual home sites ("wait here" / "this is home") and the reduced behaviour
-- of a companion that joined a world which is already well past day 200.
-- Both cases share one rule: never lay out or build a base, just live around
-- a fixed point and keep the normal survival behaviours.
local M = {}

M.WANDER_RADIUS = 32
M.RETURN_DISTANCE = 30
M.LATE_JOIN_DAY = 200
M.ANCHOR_RANGE = 32
M.ASK_COOLDOWN = 150
M.ASK_RANGE = 12
M.ASK_PLAYER_RANGE = 20

-- Nearest of these becomes the centre of a switched base, in this order when
-- two are the same distance away.
local ANCHOR_PREFABS = {
    icebox = 1,
    saltbox = 2,
    cookpot = 3,
    portablecookpot = 3,
    archive_cookpot = 3,
    researchlab = 4,
    researchlab2 = 5,
}

local ALLOWED_PREFABS = {
    cutgrass = true,
    twigs = true,
}

local ASK_CANT_TAGS = {
    "INLIMBO", "NOCLICK", "catchable", "fire", "heavy", "irreplaceable",
    "mineactive", "outofreach", "playerghost",
}

function M.Get(inst)
    local home = inst ~= nil and inst._my_friend_home or nil
    if home == nil or type(home.x) ~= "number" or type(home.z) ~= "number" then return end
    return Vector3(home.x, 0, home.z)
end

function M.Mode(inst)
    local home = inst ~= nil and inst._my_friend_home or nil
    return home ~= nil and home.mode or nil
end

-- "hold" and "base" were chosen by a player: the companion must stay inside
-- its home circle. "roam" is the automatic home of a late joiner, which may
-- still leave to look for food when there is none around.
function M.IsStrict(inst)
    local mode = M.Mode(inst)
    return mode == "hold" or mode == "base"
end

-- Furthest a strict companion may plan to walk from home. A little wider
-- than the wander radius so a chest or icebox on the edge is still reachable.
function M.TravelLimit()
    return M.WANDER_RADIUS + 8
end

function M.IsPointInRange(inst, point)
    if not M.IsStrict(inst) then return true end
    local home = M.Get(inst)
    if home == nil or point == nil then return true end
    local limit = M.TravelLimit()
    return (point.x - home.x)^2 + (point.z - home.z)^2 <= limit * limit
end

-- A manual home replaces the automatic site outright; the companion keeps
-- whatever it already built but never lays out a new base again.
function M.Apply(inst)
    local point = M.Get(inst)
    if point == nil then return end
    inst._my_friend_base = {
        x = point.x,
        z = point.z,
        planted_grass = 0,
        planted_sapling = 0,
        site_version = 2,
        phase = "complete",
        complete = true,
        manual = true,
        visited_nodes = {},
        fertilizer_regions = {},
    }
    inst._my_friend_base_site_retry = nil
end

function M.Set(inst, point, mode)
    if inst == nil or point == nil then return false end
    inst._my_friend_home = {x = point.x, z = point.z, mode = mode or "base"}
    M.Apply(inst)
    inst._my_friend_replan_requested = true
    return true
end

function M.IsLateJoin(inst)
    return inst ~= nil and inst._my_friend_late_join == true
end

-- True when the companion must not run the base construction planner.
function M.NoConstruction(inst)
    return inst ~= nil and (inst._my_friend_home ~= nil or M.IsLateJoin(inst))
end

function M.IsPickupPermitted(inst)
    return inst ~= nil and inst._my_friend_pickup_permitted == true
end

-- A late joining companion only takes grass, twigs and food until a player
-- tells it that picking other things up is fine.
function M.IsRestricted(inst)
    return M.IsLateJoin(inst) and not M.IsPickupPermitted(inst)
end

function M.AllowsPrefab(inst, prefab)
    if not M.IsRestricted(inst) then return true end
    return prefab ~= nil and ALLOWED_PREFABS[prefab] == true
end

local function IsFoodEntity(entity)
    if entity == nil then return false end
    if entity.components ~= nil and entity.components.edible ~= nil then return true end
    if entity.components ~= nil and entity.components.crop ~= nil then return true end
    local pickable = entity.components ~= nil and entity.components.pickable or nil
    if pickable ~= nil and pickable.product ~= nil then
        if require("my_friend_behavior_ai").IsFoodProduct(pickable.product) then return true end
    end
    return false
end

-- Targets the companion may still collect while restricted. An explicit work
-- command always lifts the restriction.
function M.AllowsTarget(inst, entity)
    if not M.IsRestricted(inst) or inst._my_friend_command ~= nil then return true end
    if entity == nil then return false end
    if IsFoodEntity(entity) then return true end
    if ALLOWED_PREFABS[entity.prefab] then return true end
    local pickable = entity.components ~= nil and entity.components.pickable or nil
    return pickable ~= nil and ALLOWED_PREFABS[pickable.product] == true
end

function M.GrantPickup(inst, player)
    if inst == nil or not M.IsLateJoin(inst) then return false end
    if M.IsPickupPermitted(inst) then return false end
    inst._my_friend_pickup_permitted = true
    inst._my_friend_pickup_ask_after = nil
    inst._my_friend_pickup_ask_until = nil
    require("my_friend_dialogue").Say(inst, "pickup_allowed", player)
    return true
end

M.ASK_ANSWER_TIME = 90

-- "yes" only counts as an answer for a while after the companion asked.
function M.IsAskPending(inst)
    return inst ~= nil and GetTime() < (inst._my_friend_pickup_ask_until or 0)
end

local function FindNearbyPlayer(inst, range)
    local closest, best
    for _, player in ipairs(AllPlayers or {}) do
        if require("my_friend_policy").IsLocalPlayer(player)
            and not player:HasTag("playerghost") then
            local distance = inst:GetDistanceSqToInst(player)
            if distance <= range * range and (best == nil or distance < best) then
                closest, best = player, distance
            end
        end
    end
    return closest
end

-- Periodic. Asks whoever is nearby whether loose materials may be collected.
function M.UpdateAsk(inst)
    if inst == nil or not inst:IsValid() or not M.IsRestricted(inst) then return end
    if inst:HasTag("playerghost") or inst.components.health == nil
        or inst.components.health:IsDead() or inst._my_friend_under_threat
        or inst._my_friend_command ~= nil
        or require("my_friend_policy").IsBusy(inst) then return end
    local now = GetTime()
    if now < (inst._my_friend_pickup_ask_after or 0) then return end
    local player = FindNearbyPlayer(inst, M.ASK_PLAYER_RANGE)
    if player == nil then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local found = false
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, M.ASK_RANGE,
        {"_inventoryitem"}, ASK_CANT_TAGS)) do
        local inventoryitem = entity.components ~= nil and entity.components.inventoryitem or nil
        if entity ~= inst and inventoryitem ~= nil and inventoryitem.owner == nil
            and inventoryitem.canbepickedup and not M.AllowsTarget(inst, entity) then
            found = true
            break
        end
    end
    if not found then return end
    inst._my_friend_pickup_ask_after = now + M.ASK_COOLDOWN
    inst._my_friend_pickup_ask_until = now + M.ASK_ANSWER_TIME
    require("my_friend_dialogue").Say(inst, "ask_pickup", player)
end

-- Nearest storage or crafting station a switched base can be centred on.
function M.FindAnchor(inst, origin)
    if origin == nil then return end
    local best, bestscore
    for _, entity in ipairs(TheSim:FindEntities(origin.x, 0, origin.z,
        M.ANCHOR_RANGE, nil, {"INLIMBO", "burnt", "fire"})) do
        local rank = ANCHOR_PREFABS[entity.prefab]
        if rank == nil and entity:HasTag("fridge") then rank = 1 end
        if rank ~= nil and entity.Transform ~= nil then
            local x, _, z = entity.Transform:GetWorldPosition()
            local score = (x - origin.x)^2 + (z - origin.z)^2 + rank * .01
            if bestscore == nil or score < bestscore then best, bestscore = entity, score end
        end
    end
    return best
end

function M.Save(inst, data)
    local home = inst._my_friend_home
    if home ~= nil and type(home.x) == "number" and type(home.z) == "number" then
        data.my_friend_home = {x = home.x, z = home.z, mode = home.mode}
    end
    if M.IsLateJoin(inst) then data.my_friend_late_join = true end
    if M.IsPickupPermitted(inst) then data.my_friend_pickup_permitted = true end
end

function M.Load(inst, data)
    local home = data ~= nil and data.my_friend_home or nil
    if type(home) == "table" and type(home.x) == "number" and type(home.z) == "number"
        and home.x == home.x and home.z == home.z then
        inst._my_friend_home = {x = home.x, z = home.z,
            mode = (home.mode == "hold" or home.mode == "roam") and home.mode or "base"}
    else
        inst._my_friend_home = nil
    end
    inst._my_friend_late_join = data ~= nil and data.my_friend_late_join == true or nil
    inst._my_friend_pickup_permitted = data ~= nil and data.my_friend_pickup_permitted == true or nil
    -- Runs after my_friend_base_ai.OnLoad so the manual site wins.
    M.Apply(inst)
end

return M
