-- Changing the companion's character is a departure, not an instant swap.
-- The old body says goodbye to everyone on the public chat, walks away, and
-- only once no player is left within RANGE does it hand over to the newly
-- chosen character, which then arrives the way a first companion would.
local Policy = require("my_friend_policy")
local Characters = require("my_friend_characters")
local Navigation = require("my_friend_navigation")

local M = {}

-- No player may be this close for the handover to happen.
M.RANGE = 36
-- Outranks everything except being a ghost: a departing companion has no
-- other business left.
M.SCORE = 145
M.STEP = 10
M.DETOUR_STEP = 18
M.LEG_RANGE = 24
M.BLOCKED_TIMEOUT = 30
-- Safety valve: players who chase the companion forever would otherwise
-- leave the world with a companion that can never finish leaving.
M.TIMEOUT = 300

local function IsDeparting(inst)
    local departing = inst ~= nil and inst._my_friend_departing or nil
    return departing ~= nil and type(departing.character) == "string" and departing or nil
end

M.IsDeparting = IsDeparting

local function DistanceSq(a, b)
    return (a.x - b.x)^2 + (a.z - b.z)^2
end

local function NearestPlayer(inst, position, players)
    local closest, best
    for _, player in ipairs(AllPlayers or {}) do
        if Policy.IsLocalPlayer(player) then
            local point = position ~= nil and player:GetPosition() or nil
            if players ~= nil then players[#players + 1] = point end
            local distance = point ~= nil and DistanceSq(position, point) or inst:GetDistanceSqToInst(player)
            if best == nil or distance < best then closest, best = player, distance end
        end
    end
    return closest, best
end

-- Begins the goodbye. The character is only validated here; the actual
-- rebuild happens in Update once nobody is watching.
function M.Begin(inst, character)
    if inst == nil or not inst:IsValid() or IsDeparting(inst) ~= nil then return false end
    local Switch = require("my_friend_switch")
    if not Switch.CanSwitch(inst, character) then return false end
    -- "带走吧"/"送你" was said at some point before the change was ordered, so
    -- the companion keeps everything and it leaves the world with it.
    local keep = inst._my_friend_farewell_gift == true
    inst._my_friend_farewell_gift = nil
    inst._my_friend_departing = { character = character, started = GetTime(),
        keep_items = keep or nil }
    require("my_friend_commands").Clear(inst)
    -- Put the belongings down here, at the player's feet, before the walk
    -- starts. Dropping them at the end left the pile wherever the goodbye walk
    -- happened to finish, which could be most of a screen away.
    if not keep then Switch.DropBelongings(inst) end
    -- Stop following so the farewell walk is not fighting the follow node.
    local affinity = inst.components.my_friend_affinity
    if affinity ~= nil then
        affinity.requests = {}
        if inst.components.follower ~= nil then
            inst.components.follower:SetLeader(nil)
        end
    end
    inst._my_friend_replan_requested = true
    -- One line, to everyone, without reciting names.
    require("my_friend_dialogue").PublicSay(inst, "farewell")
    return true
end

function M.Score(inst)
    return IsDeparting(inst) ~= nil and M.SCORE or 0
end

function M.InTravelRange(inst, action, point)
    return action._my_friend_farewell == IsDeparting(inst)
        and DistanceSq(action._my_friend_farewell_origin, point) <= M.LEG_RANGE^2
end

local function ChooseGoal(inst, position, players, heading, step, minimum)
    local goal, best = nil, minimum
    for index = 0, 15 do
        local offset = math.ceil(index / 2) * (index % 2 == 0 and 1 or -1)
        local angle = heading + offset * PI2 / 16
        local point = Vector3(position.x + math.cos(angle) * step, 0, position.z + math.sin(angle) * step)
        if Navigation.IsLand(point) and not Navigation.IsBlocked(inst, point) then
            local clearance = math.huge
            for _, player in ipairs(players) do clearance = math.min(clearance, DistanceSq(point, player)) end
            if clearance > best then goal, best = point, clearance end
        end
    end
    return goal
end

function M.GetAction(inst)
    local departing = IsDeparting(inst)
    local now = GetTime()
    if departing == nil or departing.finishing or now < (departing.retry_at or 0)
        or Policy.IsBusy(inst) then return end
    local position = inst:GetPosition()
    local players = {}
    local player, distancesq = NearestPlayer(inst, position, players)
    if player == nil or distancesq > M.RANGE^2 then return end
    local source = player:GetPosition()
    local dx, dz = position.x - source.x, position.z - source.z
    local length = math.sqrt(distancesq)
    local heading = length > .01 and math.atan2(dz, dx) or math.random() * PI2
    local minimum = (length + .5)^2
    local point = ChooseGoal(inst, position, players, heading, M.STEP, minimum)
        or ChooseGoal(inst, position, players, heading, M.DETOUR_STEP, minimum)
    if point == nil then
        departing.blocked_since = departing.blocked_since or now
        departing.retry_at = now + 1
        return
    end
    local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point)
    action.arrivedist = .15
    action._my_friend_farewell, action._my_friend_farewell_origin = departing, position
    action:AddSuccessAction(function()
        if IsDeparting(inst) == departing then departing.blocked_since = nil end
    end)
    action:AddFailAction(function()
        if IsDeparting(inst) == departing and not action._my_friend_cancelled then
            departing.blocked_since = departing.blocked_since or GetTime()
            if not Navigation.IsBlocked(inst, point) then Navigation.Block(inst, point, false, true) end
        end
    end)
    return action
end

local function CanComplete(inst, departing)
    if not inst:IsValid() or inst:HasTag("playerghost")
        or inst.components.health == nil or inst.components.health:IsDead()
        or Policy.IsBusy(inst) then return false end
    local _, distancesq = NearestPlayer(inst)
    local now = GetTime()
    return distancesq == nil or distancesq > M.RANGE^2 or now - (departing.started or 0) >= M.TIMEOUT
        or departing.blocked_since ~= nil and now - departing.blocked_since >= M.BLOCKED_TIMEOUT
end

function M.Update(inst)
    local departing = IsDeparting(inst)
    if departing == nil or departing.finishing or not CanComplete(inst, departing) then return end
    departing.finishing = true
    -- Outside the entity's own task, because the handover removes it.
    TheWorld:DoTaskInTime(0, function()
        if IsDeparting(inst) ~= departing then return end
        if CanComplete(inst, departing) and M.Complete(inst, departing.character, departing.keep_items) ~= nil then
            return
        end
        departing.finishing = nil
    end)
end

-- Where a companion is expected to turn up, matching the first-spawn rule.
function M.ArrivalPoint(fallback)
    local portal = TheSim:FindFirstEntityWithTag("multiplayer_portal")
        or TheSim:FindFirstEntityWithTag("moonaltar")
    local anchor = portal or fallback
    if anchor == nil or anchor.Transform == nil then return end
    local x, y, z = anchor.Transform:GetWorldPosition()
    return Vector3(x + 2, y, z + 2)
end

function M.Complete(inst, character, keep_items)
    local configure = require("my_friend_migration").ConfigureFriend
    if configure == nil then
        print("[MyFriends] Farewell handover skipped: the world is not configured yet")
        return
    end
    local fallback = NearestPlayer(inst)
    local replacement = require("my_friend_switch").Switch(inst, character, configure, keep_items)
    if replacement == nil then return end
    -- If the old companion was the parked autonomous body of a possession
    -- session, Release() must remove this replacement instead of spawning an
    -- additional companion from the controlled player body.
    require("my_friend_possess").ReplaceTemporaryCompanion(inst, replacement)
    replacement._my_friend_switch_used = true
    local point = M.ArrivalPoint(fallback)
    if point ~= nil then replacement.Transform:SetPosition(point:Get()) end
    require("my_friend_abigail").Place(replacement)
    replacement._my_friend_replan_requested = true
    require("my_friend_dialogue").PublicSay(replacement, "switch_arrive")
    require("my_friend_body_chat").Public(replacement,
        require("my_friend_strings").Text("已经来到永恒领域，请前去迎接。",
            "I've arrived in the Constant. Come and say hello."))
    return replacement
end

-- ---------------------------------------------------------------------------
-- Who may start a switch.
-- ---------------------------------------------------------------------------

-- The very first change is a free one that the whole server shares: anybody
-- standing next to the companion may use it. Every later change belongs to
-- the player the companion is actually following, at full affinity.
function M.IsFreeChangeAvailable(inst)
    return inst ~= nil and inst._my_friend_switch_used ~= true
end

function M.CanRequest(inst, player)
    if inst == nil or player == nil or IsDeparting(inst) ~= nil then return false end
    if M.IsFreeChangeAvailable(inst) then return true end
    local affinity = inst.components ~= nil and inst.components.my_friend_affinity or nil
    return affinity ~= nil and Policy.GetLeader(inst) == player
        and affinity:Get(player) >= 100
end

function M.Save(inst, data)
    if inst._my_friend_switch_used then data.my_friend_switch_used = true end
    if inst._my_friend_farewell_gift then data.my_friend_farewell_gift = true end
    local departing = IsDeparting(inst)
    if departing ~= nil and Characters.IsCharacter(departing.character) then
        data.my_friend_departing = departing.character
        -- Without this a reload mid-walk would turn a "take it with you"
        -- goodbye back into a drop-everything one.
        if departing.keep_items then data.my_friend_departing_keep = true end
    end
end

function M.Load(inst, data)
    inst._my_friend_switch_used = data ~= nil and data.my_friend_switch_used == true or nil
    inst._my_friend_farewell_gift = data ~= nil and data.my_friend_farewell_gift == true or nil
    local character = data ~= nil and data.my_friend_departing or nil
    if type(character) == "string" and Characters.IsCharacter(character) then
        -- Resume the walk away; the timer restarts with the world.
        inst._my_friend_departing = { character = character, started = GetTime(),
            keep_items = data.my_friend_departing_keep == true or nil }
    else
        inst._my_friend_departing = nil
    end
end

return M
