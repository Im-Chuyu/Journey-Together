-- Event-driven companion dialogue and non-rollback world memory.
-- No global scan is created: world state callbacks inspect only the active
-- companion. Weather dialogue runs once per precipitation start, without polling.
local json = require("json")
local Policy = require("my_friend_policy")
local Dialogue = require("my_friend_dialogue")
local M = {}

local DAY_NEAR = "time_rewind_near"
local DAY_FAR = "time_rewind_far"
local SEASON_LINES = {
    spring = "season_spring", summer = "season_summer",
    autumn = "season_autumn", winter = "season_winter",
}
local FOLLOW_REUNION = "follow_reunion"

local function Friend(world)
    local friend = world ~= nil and world._my_friend or nil
    return friend ~= nil and friend:IsValid() and friend:HasTag("my_friend") and friend or nil
end
local function NearbyLeader(friend)
    local leader = Policy.GetLeader(friend)
    if leader == nil or not Policy.IsLocalPlayer(leader) then return end
    if Policy.DistanceSq(friend, leader) > 20^2 then return end
    return leader
end
local function Speak(friend, key, leader)
    if friend == nil or key == nil or NearbyLeader(friend) == nil then return false end
    return Dialogue.RandomReply(friend, key, leader ~= nil and leader:GetDisplayName() or nil)
end

local function SpeakSeason(friend, key)
    if friend == nil or key == nil or not friend:IsValid() then return false end
    return Dialogue.RandomReply(friend, key)
end

local function UserID(player)
    return player ~= nil and type(player.userid) == "string" and player.userid or nil
end

local function CancelRewindTask(friend)
    if friend ~= nil and friend._my_friend_context_rewind_task ~= nil then
        friend._my_friend_context_rewind_task:Cancel()
        friend._my_friend_context_rewind_task = nil
    end
end

local Persist

local function TryScheduleRewind(world, friend)
    local state = world ~= nil and world._my_friend_context_days or nil
    if state == nil or state.rewind_key == nil or state.rewind_leader_userid == nil or friend == nil
        or not friend:IsValid() then return false end
    local key, userid = state.rewind_key, state.rewind_leader_userid
    local leader = NearbyLeader(friend)
    if leader == nil or UserID(leader) ~= userid then return false end
    if friend._my_friend_context_rewind_task ~= nil then return true end
    friend._my_friend_context_rewind_task = friend:DoTaskInTime(5, function()
        friend._my_friend_context_rewind_task = nil
        if state.rewind_key ~= key or state.rewind_leader_userid ~= userid
            or not friend:IsValid() then return end
        local current = NearbyLeader(friend)
        if current == nil or UserID(current) ~= userid then return end
        state.rewind_key, state.rewind_leader_userid = nil, nil
        Persist(state)
        Speak(friend, key, current)
    end)
    return true
end

Persist = function(state)
    if state.writing or state.key == nil then state.dirty = true; return end
    state.writing, state.dirty = true, false
    TheSim:SetPersistentString(state.key, json.encode({current = state.current, previous = state.previous,
        last_leader_userid = state.last_leader_userid,
        rewind_key = state.rewind_key, rewind_leader_userid = state.rewind_leader_userid,
        follow_days = state.follow_days, follow_pending = state.follow_pending}),
        false, function()
            state.writing = false
            if state.dirty then Persist(state) end
        end)
end

local function CurrentDay(world, state)
    return state ~= nil and type(state.current) == "number" and state.current
        or world ~= nil and world.state ~= nil and world.state.cycles or 0
end

local function ApplyFollowEvent(world, state, friend, event)
    if state == nil or event == nil or type(event.userid) ~= "string" then return false end
    state.follow_days = state.follow_days or {}
    state.follow_pending = state.follow_pending or {}
    local day = CurrentDay(world, state)
    if event.kind == "stop" then
        state.follow_days[event.userid] = day
        state.follow_pending[event.userid] = true
        return true
    elseif event.kind == "start" then
        if not state.follow_pending[event.userid] then return false end
        local previous = state.follow_days[event.userid]
        local delta = type(previous) == "number" and day - previous or nil
        state.follow_days[event.userid] = day
        state.follow_pending[event.userid] = nil
        if delta ~= nil and delta >= 2 and friend ~= nil then
            local leader = NearbyLeader(friend)
            if leader ~= nil and UserID(leader) == event.userid then
                Speak(friend, FOLLOW_REUNION, leader)
            end
        end
        return true
    end
    return false
end

local function RecordFollowEvent(friend, kind, player)
    local world = TheWorld
    local state = world ~= nil and world._my_friend_context_days or nil
    local userid = UserID(player)
    if state == nil or userid == nil then return false end
    local event = {kind = kind, userid = userid}
    if not state.loaded then
        state.pending_follow_events = state.pending_follow_events or {}
        state.pending_follow_events[#state.pending_follow_events + 1] = event
        return true
    end
    local changed = ApplyFollowEvent(world, state, friend, event)
    if changed then Persist(state) end
    return changed
end

local function RememberLeader(world, friend, leader)
    local state = world ~= nil and world._my_friend_context_days or nil
    local userid = UserID(leader)
    if state == nil or userid == nil or state.last_leader_userid == userid then return end
    state.last_leader_userid = userid
    if state.loaded then Persist(state) end
end

local function DayChanged(world, cycles)
    local state = world._my_friend_context_days
    if state == nil or not state.loaded or type(cycles) ~= "number" or state.current == cycles then return end
    local previous = state.current
    state.previous, state.current = previous, cycles
    local delta = state.current - state.previous
    local key = delta < 0 and delta >= -2 and DAY_NEAR
        or delta < -2 and delta >= -5 and DAY_FAR or nil
    local friend = Friend(world)
    CancelRewindTask(friend)
    state.rewind_key = key
    state.rewind_leader_userid = key ~= nil and state.last_leader_userid or nil
    Persist(state)
    TryScheduleRewind(world, friend)
end

local function SeasonChanged(world, season)
    local state = world._my_friend_context_days
    if state == nil or state.season == season then return end
    state.season = season
    local key = SEASON_LINES[season]
    -- Seasonal lines describe the world change itself and do not require an
    -- active follower relationship. Other contextual lines keep their leader
    -- and distance checks.
    if key ~= nil then SpeakSeason(Friend(world), key) end
end

local function ReconcileCycles(world)
    if world == nil or world.state == nil then return end
    local state = world._my_friend_context_days
    if state == nil or not state.loaded then return end
    -- A zero-delay reconciliation can run before the world state replica has
    -- applied the value that already arrived through the event callback. The
    -- previous value is that stale reading; do not undo the just-recorded
    -- rollback with it.
    if state.current ~= world.state.cycles and state.previous == world.state.cycles then
        return
    end
    DayChanged(world, world.state.cycles)
end

local function WeatherChanged(world, field, active, key)
    local friend = Friend(world)
    if friend == nil then return end
    active = active == true
    if friend[field] == active then return end
    friend[field] = active
    -- Use the callback value directly. Rain and snow can change in sequence
    -- during one native precipitation event. No dialogue cooldown is applied.
    if active then Speak(friend, key) end
end

function M.ConfigureFriend(friend)
    if friend == nil or friend._my_friend_context_configured then return end
    friend._my_friend_context_configured = true
    friend:ListenForEvent("onremove", function()
        CancelRewindTask(friend)
        friend._my_friend_context_rewind_task = nil
    end)
    friend:ListenForEvent("leaderchanged", function(_, data)
        local leader = data ~= nil and data.new or Policy.GetLeader(friend)
        RememberLeader(TheWorld, friend, leader)
        TryScheduleRewind(TheWorld, friend)
    end)
    if TheWorld ~= nil and TheWorld.state ~= nil then
        WeatherChanged(TheWorld, "_my_friend_context_raining", TheWorld.state.israining, "rain_request")
        WeatherChanged(TheWorld, "_my_friend_context_snowing", TheWorld.state.issnowing, "season_winter")
    end
    RememberLeader(TheWorld, friend, Policy.GetLeader(friend))
    TryScheduleRewind(TheWorld, friend)
end

function M.RecordFollowStopped(friend, player)
    return RecordFollowEvent(friend, "stop", player)
end

function M.RecordFollowStarted(friend, player)
    local changed = RecordFollowEvent(friend, "start", player)
    TryScheduleRewind(TheWorld, friend)
    return changed
end

function M.AttachWorld(world)
    if world == nil or not world.ismastersim or world._my_friend_context_attached then return end
    world._my_friend_context_attached = true
    local session = world.meta ~= nil and world.meta.session_identifier or nil
    local shard = TheShard ~= nil and TheShard:GetShardId() or "local"
    local state = {loaded = false, current = nil, previous = nil, season = world.state.season,
        last_leader_userid = nil,
        rewind_key = nil, rewind_leader_userid = nil,
        follow_days = {}, follow_pending = {}, pending_follow_events = {},
        key = type(session) == "string" and session ~= ""
            and "my_friend_context_" .. session .. "_" .. tostring(shard) or nil}
    world._my_friend_context_days = state
    world:ListenForEvent("cycleschanged", function(_, cycles) DayChanged(world, cycles) end)
    -- Loading a rollback can update the world state before the prefab's
    -- initial event reaches this listener. Watch the authoritative state and
    -- reconcile once more after persistent memory finishes loading.
    world:WatchWorldState("cycles", function(_, cycles) DayChanged(world, cycles) end)
    world:WatchWorldState("season", function(_, season) SeasonChanged(world, season) end)
    world:WatchWorldState("israining", function(_, raining)
        WeatherChanged(world, "_my_friend_context_raining", raining, "rain_request")
    end)
    world:WatchWorldState("issnowing", function(_, snowing)
        WeatherChanged(world, "_my_friend_context_snowing", snowing, "season_winter")
    end)
    if state.key == nil or TheSim == nil then
        state.loaded = true
        state.current, state.previous = world.state.cycles or 0, world.state.cycles or 0
        local pending = state.pending_follow_events
        state.pending_follow_events = {}
        for _, event in ipairs(pending) do
            ApplyFollowEvent(world, state, Friend(world), event)
        end
        TryScheduleRewind(world, Friend(world))
        world:DoTaskInTime(0, function() ReconcileCycles(world) end)
        world:DoTaskInTime(5, function() ReconcileCycles(world) end)
        return
    end
    TheSim:GetPersistentString(state.key, function(ok, value)
        local decoded
        if ok and value ~= nil and value ~= "" then
            local good, data = pcall(json.decode, value)
            if good and type(data) == "table" and type(data.current) == "number"
                and type(data.previous) == "number" then decoded = data end
        end
        local cycles = world.state.cycles or 0
        state.current = decoded ~= nil and decoded.current or cycles
        state.previous = decoded ~= nil and decoded.previous or state.current
        state.last_leader_userid = decoded ~= nil
            and type(decoded.last_leader_userid) == "string"
            and decoded.last_leader_userid or nil
        state.rewind_key = decoded ~= nil and type(decoded.rewind_key) == "string"
            and decoded.rewind_key or nil
        state.rewind_leader_userid = decoded ~= nil
            and type(decoded.rewind_leader_userid) == "string"
            and decoded.rewind_leader_userid or nil
        local historical_delta = state.current - state.previous
        if state.rewind_key == nil and historical_delta < 0
            and historical_delta >= -5 then
            state.rewind_key = historical_delta >= -2 and DAY_NEAR or DAY_FAR
            state.rewind_leader_userid = state.last_leader_userid
        end
        state.follow_days = decoded ~= nil and type(decoded.follow_days) == "table"
            and decoded.follow_days or {}
        state.follow_pending = decoded ~= nil and type(decoded.follow_pending) == "table"
            and decoded.follow_pending or {}
        state.loaded = true
        local pending = state.pending_follow_events
        state.pending_follow_events = {}
        local friend, changed = Friend(world), false
        if state.last_leader_userid == nil and friend ~= nil then
            local current = Policy.GetLeader(friend)
            local userid = UserID(current)
            if userid ~= nil then
                state.last_leader_userid = userid
                changed = true
            end
        end
        for _, event in ipairs(pending) do
            changed = ApplyFollowEvent(world, state, friend, event) or changed
        end
        if changed then Persist(state) end
        TryScheduleRewind(world, friend)
        world:DoTaskInTime(0, function() ReconcileCycles(world) end)
        world:DoTaskInTime(5, function() ReconcileCycles(world) end)
    end)
end

return M
