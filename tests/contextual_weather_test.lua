-- Run from the mod root: lua tests/contextual_weather_test.lua [native scripts path]
-- Native WorldState drives the real contextual callbacks and Dialogue.RandomReply.
local native = arg[1] or "../yuanma/scripts"
package.path = "./scripts/?.lua;" .. native .. "/?.lua;" .. package.path
require("class")
TUNING = {AUTUMN_LENGTH = 20, WINTER_LENGTH = 15, SPRING_LENGTH = 20,
    SUMMER_LENGTH = 15, STARTING_TEMP = 20, TOTAL_DAY_TIME = 480}
TheSim = nil
local now, spoken = 0, {}
function GetTime() return now end
package.loaded.json = {}
package.loaded.my_friend_speech = {
    Key = function(_, key) return key end,
    Random = function(inst, key)
        spoken[#spoken + 1] = {inst = inst, key = key}
        return true
    end,
}
local WorldState = require("components/worldstate")
local Context = require("my_friend_contextual_events")

local function Entity()
    local entity = {components = {}, events = {}, tasks = {}, valid = true, x = 0, tags = {}}
    entity.Transform = {GetWorldPosition = function() return entity.x, 0, 0 end}
    function entity:IsValid() return self.valid end
    function entity:HasTag(tag) return self.tags[tag] == true end
    function entity:GetDisplayName() return "Leader" end
    function entity:GetDistanceSqToInst(other) return (self.x - other.x)^2 end
    function entity:ListenForEvent(event, fn)
        self.events[event] = self.events[event] or {}
        table.insert(self.events[event], fn)
    end
    function entity:PushEvent(event, data)
        for _, fn in ipairs(self.events[event] or {}) do fn(self, data) end
    end
    function entity:DoTaskInTime(delay, fn)
        local task = {delay = delay, fn = fn}
        function task:Cancel() self.cancelled = true end
        table.insert(self.tasks, task)
        return task
    end
    function entity:DoPeriodicTask() error("weather must not create periodic tasks") end
    return entity
end

local function Setup(precipitation, configure)
    now, spoken = 0, {}
    local world, friend, leader = Entity(), Entity(), Entity()
    TheWorld = world
    world.ismastersim = true
    world.components.worldstate = WorldState(world)
    world.state = world.components.worldstate.data
    function world:WatchWorldState(variable, fn)
        self.components.worldstate:AddWatcher(variable, self, fn, self)
    end
    world:PushEvent("precipitationchanged", precipitation or "none")
    friend.tags.my_friend = true
    friend.components.talker = {}
    friend.components.follower = {GetLeader = function() return leader end}
    leader.userid = "KU_weather"
    AllPlayers = {leader}
    world._my_friend = friend
    Context.AttachWorld(world)
    if configure ~= false then Context.ConfigureFriend(friend) end
    return world, friend, leader
end

local passed = 0
local function Test(name, fn)
    fn()
    passed = passed + 1
    print("PASS " .. name)
end
local function Key(index, expected) assert(spoken[index] and spoken[index].key == expected) end
local function Precip(world, kind) world:PushEvent("precipitationchanged", kind) end

Test("each rain start speaks again, even at the same clock time", function()
    local world = Setup()
    for i = 1, 5 do
        Precip(world, "rain")
        assert(#spoken == i)
        Key(i, "rain_request")
        Precip(world, "none")
        assert(#spoken == i)
    end
end)

Test("each snow start speaks again using existing winter lines", function()
    local world = Setup()
    for i = 1, 5 do
        Precip(world, "snow")
        assert(#spoken == i)
        Key(i, "season_winter")
        Precip(world, "none")
    end
end)

Test("continuous precipitation does not repeat after 120 seconds", function()
    local world, friend = Setup()
    Precip(world, "rain")
    now = 500
    Precip(world, "rain")
    assert(#spoken == 1 and #friend.tasks == 0)
    Precip(world, "snow")
    now = 1000
    Precip(world, "snow")
    assert(#spoken == 2 and #friend.tasks == 0)
end)

Test("rain and snow transitions have independent start/reset state", function()
    local world = Setup()
    for i, kind in ipairs({"rain", "snow", "rain", "snow"}) do
        Precip(world, kind)
        assert(#spoken == i)
        Key(i, kind == "rain" and "rain_request" or "season_winter")
    end
end)

Test("rain gear and ambient dialogue cooldown do not suppress weather starts", function()
    local world, friend = Setup()
    friend.components.inventory = {GetEquippedItem = function()
        return {components = {waterproofer = {GetEffectiveness = function() return 1 end}}}
    end}
    friend._my_friend_dialogue = {after = {rain_request = 9999, season_winter = 9999},
        ambient_after = 9999, speech_after = 9999, queue = {}}
    Precip(world, "rain")
    Precip(world, "snow")
    assert(#spoken == 2)
end)

Test("existing rain or snow on configuration triggers once", function()
    for _, kind in ipairs({"rain", "snow"}) do
        local world, friend = Setup(kind)
        assert(#spoken == 1)
        Context.ConfigureFriend(friend)
        Context.AttachWorld(world)
        Precip(world, kind)
        assert(#spoken == 1)
        Precip(world, "none")
        Precip(world, kind)
        assert(#spoken == 2)
    end
end)

Test("weather callback before configuration does not double speak", function()
    local world, friend = Setup(nil, false)
    Precip(world, "rain")
    Context.ConfigureFriend(friend)
    assert(#spoken == 1)
end)

Test("distant or absent leaders remain excluded without blocking the next spell", function()
    local world, friend, leader = Setup()
    leader.x = 21
    Precip(world, "rain")
    leader.x = 0
    Precip(world, "rain")
    assert(#spoken == 0)
    Precip(world, "none")
    Precip(world, "rain")
    assert(#spoken == 1)
    AllPlayers = {}
    Precip(world, "snow")
    assert(#spoken == 1)
    AllPlayers = {leader}
    Precip(world, "none")
    Precip(world, "snow")
    assert(#spoken == 2)
end)

Test("missing or removed companions are ignored and new companions initialise", function()
    local world, friend = Setup()
    friend.valid = false
    Precip(world, "rain")
    world._my_friend = nil
    Precip(world, "snow")
    assert(#spoken == 0)
    friend.valid = true
    world._my_friend = friend
    Precip(world, "none")
    Precip(world, "snow")
    assert(#spoken == 1)
end)

Test("season transitions still work independently of snow", function()
    local world = Setup()
    world:PushEvent("seasontick", {season = "winter"})
    assert(#spoken == 1)
    Key(1, "season_winter")
    world:PushEvent("seasontick", {season = "winter"})
    assert(#spoken == 1)
    Precip(world, "snow")
    assert(#spoken == 2)
end)

print(string.format("%d contextual weather tests passed", passed))
