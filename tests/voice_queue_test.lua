-- Real speech, dialogue, language maps and voice code; only engine boundaries are stubbed.
-- Run from the mod root: lua tests/voice_queue_test.lua
package.path = "./scripts/?.lua;" .. package.path
local now, serial, tasks, text, announcements
function GetTime() return now end
STRINGS = {}
CHATPRIORITIES = {LOW = 1}
TheWorld = {ismastersim = true}
TheNet = {Announce = function(_, message) announcements[#announcements + 1] = message end}
local Language = require("my_friend_strings")
local Voice = require("my_friend_voice")
local Durations = require("my_friend_voice_durations")
local Speech = require("my_friend_speech")
local Dialogue = require("my_friend_dialogue")
Speech.BuildStrings()
local LINE = "my_friend_line"

local function Advance(target)
    while true do
        local next_task
        for _, task in ipairs(tasks) do
            if not task.cancelled and not task.done and task.at <= target
                and (next_task == nil or task.at < next_task.at
                    or task.at == next_task.at and task.serial < next_task.serial) then
                next_task = task
            end
        end
        if next_task == nil then break end
        now, next_task.done = next_task.at, true
        next_task.fn(next_task.inst)
    end
    now = target
end

local function Actor()
    local inst = {prefab = "wendy", _my_friend_is_companion = true, valid = true,
        tags = {my_friend = true}, events = {}, components = {}, dead = false}
    function inst:IsValid() return self.valid end
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:ListenForEvent(event, fn)
        self.events[event] = self.events[event] or {}
        table.insert(self.events[event], fn)
    end
    function inst:PushEvent(event, data)
        for _, fn in ipairs(self.events[event] or {}) do fn(self, data) end
    end
    function inst:DoTaskInTime(delay, fn)
        serial = serial + 1
        local task = {at = now + delay, serial = serial, fn = fn, inst = self}
        function task:Cancel() self.cancelled = true end
        tasks[#tasks + 1] = task
        return task
    end
    inst.components.health = {IsDead = function() return inst.dead end}
    inst.SoundEmitter = {active = {}, clips = {}, durations = {}, failed = {}}
    local emitter = inst.SoundEmitter
    function emitter:PlayingSound(channel)
        if self.unreported and channel == LINE then return false end
        if self.stuck and channel == LINE then return true end
        return self.active[channel] ~= nil and now < self.active[channel]
    end
    function emitter:KillSound(channel) self.active[channel] = nil end
    function emitter:PlaySound(event, channel, volume, spatial)
        if self.failed[event] then error("simulated missing sound bank") end
        if channel == LINE then
            self.clips[#self.clips + 1] = {event = event, at = now, volume = volume, spatial = spatial}
        end
        local number = tonumber(event:match("fn(%d+)$"))
        if channel ~= nil then
            self.active[channel] = now + (self.durations[event] or Durations[number] or 1)
        end
    end
    local talker = {chatter = {}}
    function talker:MakeChatter() end
    function talker:IsTalking() return false end
    function talker:Chatter(key, index, duration)
        text[#text + 1] = {key = key, index = index, duration = duration, at = now}
        inst:PushEvent("ontalk", {duration = duration})
    end
    inst.components.talker = talker
    Speech.Configure(inst)
    return inst, emitter
end

local passed = 0
local function Test(name, fn)
    now, serial, tasks, text, announcements = 0, 0, {}, {}, {}
    Language.language, Voice.enabled, TheWorld.ismastersim = "zh", true, true
    fn()
    passed = passed + 1
    print("PASS " .. name)
end
local function Event(key, index)
    local id = STRINGS.MY_FRIEND_VOICE_INDEX["wendy/" .. key .. ":" .. (index or 1)]
        or STRINGS.MY_FRIEND_VOICE_INDEX[key .. ":" .. (index or 1)]
    assert(id)
    local bank = math.floor((id - 1) / 70) + 1
    return "fs" .. bank .. "/fs" .. bank .. "/fn" .. id, id
end
local function WaitFor(key, index)
    local _, id = Event(key, index)
    return Durations[id] + .1
end

Test("simultaneous replies retain immediate text and FIFO audio by recorded durations", function()
    local inst, emitter = Actor()
    assert(Speech.Say(inst, "rain_request", 1))
    assert(Speech.Say(inst, "season_winter", 2))
    assert(Dialogue.Reply(inst, "plant_trees_done"))
    assert(#text == 3 and #emitter.clips == 1)
    local first = WaitFor("rain_request", 1)
    local second = first + WaitFor("season_winter", 2)
    Advance(first - .01)
    assert(#emitter.clips == 1)
    Advance(first)
    assert(#emitter.clips == 2 and emitter.clips[2].event == Event("season_winter", 2))
    Advance(second)
    assert(#emitter.clips == 3 and emitter.clips[3].event == Event("plant_trees_done"))
    Advance(second + WaitFor("plant_trees_done"))
    assert(inst._my_friend_voice_lines == nil)
    for _, clip in ipairs(emitter.clips) do assert(clip.volume == 1 and clip.spatial == false) end
end)

Test("audio lasting more than seven seconds finishes before the next starts", function()
    local inst, emitter = Actor()
    local finish = WaitFor("book_last_stored")
    assert(finish > 7)
    Speech.Reply(inst, "book_last_stored")
    Speech.Say(inst, "season_winter", 1)
    Advance(finish - .01)
    assert(#emitter.clips == 1)
    Advance(finish)
    assert(#emitter.clips == 2 and emitter.clips[2].at == finish)
end)

Test("a new event after a short clip ends plays immediately without a seven-second lock", function()
    local inst, emitter = Actor()
    Voice.PlayLine(inst, "rain_request", 1)
    Advance(6)
    assert(inst._my_friend_voice_lines == nil)
    Voice.PlayLine(inst, "season_winter", 1)
    assert(#emitter.clips == 2 and emitter.clips[2].at == 6)
end)

Test("only missing duration metadata uses the seven-second fallback", function()
    local inst, emitter = Actor()
    local _, id = Event("rain_request")
    local duration = Durations[id]
    Durations[id] = nil
    emitter.unreported = true
    Voice.PlayLine(inst, "rain_request", 1)
    Durations[id] = duration
    Voice.PlayLine(inst, "season_winter", 1)
    Advance(6.99)
    assert(#emitter.clips == 1)
    Advance(7)
    assert(#emitter.clips == 2)
end)

Test("a permanently active named channel cannot strand queued audio", function()
    local inst, emitter = Actor()
    emitter.stuck = true
    Voice.PlayLine(inst, "rain_request", 1)
    Voice.PlayLine(inst, "season_winter", 1)
    Advance(WaitFor("rain_request"))
    assert(#emitter.clips == 2)
    Advance(now + WaitFor("season_winter"))
    assert(inst._my_friend_voice_lines == nil)
end)

Test("a server reporting no playback still sequences known clips by their actual duration", function()
    local inst, emitter = Actor()
    emitter.unreported = true
    Voice.PlayLine(inst, "rain_request", 1)
    Voice.PlayLine(inst, "season_winter", 1)
    local finish = WaitFor("rain_request")
    Advance(finish - .01)
    assert(#emitter.clips == 1)
    Advance(finish)
    assert(#emitter.clips == 2 and emitter.clips[2].at < 7)
end)

Test("new text and donetalking neither truncate clips nor drain queued audio", function()
    local inst, emitter = Actor()
    Speech.Reply(inst, "book_last_stored")
    Advance(1)
    inst:PushEvent("donetalking")
    Dialogue.RandomReply(inst, "season_winter")
    assert(emitter:PlayingSound(LINE) and #emitter.clips == 1)
    Advance(WaitFor("book_last_stored"))
    assert(#emitter.clips == 2)
end)

Test("public announcements and ordinary replies share the same audio queue", function()
    local inst, emitter = Actor()
    Dialogue.PublicSay(inst, "ghost_help", "Wendy")
    Dialogue.RandomReply(inst, "rain_request")
    assert(#announcements == 1 and #text == 1 and #emitter.clips == 1)
    Advance(7)
    assert(#emitter.clips == 2)
end)

Test("audio-bank error leaves text intact, bounds native fallback and continues queue", function()
    local inst, emitter = Actor()
    for i = 1, 3 do emitter.failed[Event("rain_request", i)] = true end
    Dialogue.RandomReply(inst, "rain_request")
    assert(#text == 1 and #emitter.clips == 0 and emitter:PlayingSound("my_friend_talk"))
    Advance(2)
    assert(emitter.active.my_friend_talk == nil)
    Dialogue.RandomReply(inst, "season_winter")
    assert(#text == 2)
    Advance(7)
    assert(#emitter.clips == 1)
end)

Test("all permanent voice IDs have positive duration metadata", function()
    for _, id in pairs(STRINGS.MY_FRIEND_VOICE_INDEX) do
        assert(type(Durations[id]) == "number" and Durations[id] > 0 and Durations[id] < math.huge)
    end
    assert(#Durations == 695)
end)

Test("death, ghost transition and removal cancel current and pending audio", function()
    for _, event in ipairs({"death", "ms_becameghost", "onremove"}) do
        local inst, emitter = Actor()
        Voice.PlayLine(inst, "rain_request", 1)
        Voice.PlayLine(inst, "season_winter", 1)
        local stale = inst._my_friend_voice_lines.task
        inst:PushEvent(event)
        assert(inst._my_friend_voice_lines == nil and not emitter:PlayingSound(LINE))
        stale.fn(inst)
        assert(#emitter.clips == 1)
    end
    Advance(30)
end)

Test("queued callbacks recheck entity validity and parked companion state", function()
    for _, field in ipairs({"valid", "_my_friend_is_companion", "_my_friend_possess_parked"}) do
        local inst, emitter = Actor()
        Voice.PlayLine(inst, "rain_request", 1)
        Voice.PlayLine(inst, "season_winter", 1)
        inst[field] = field == "_my_friend_possess_parked"
        Advance(now + 7)
        assert(#emitter.clips == 1 and inst._my_friend_voice_lines == nil)
    end
end)

Test("queues belong to each companion and preserve repeated event requests", function()
    local a, ea = Actor()
    local b, eb = Actor()
    Voice.PlayLine(a, "rain_request", 1)
    Voice.PlayLine(a, "rain_request", 1)
    Voice.PlayLine(b, "season_winter", 1)
    assert(#ea.clips == 1 and #eb.clips == 1)
    Advance(7)
    assert(#ea.clips == 2 and #eb.clips == 1)
end)

Test("unmapped text does not consume an audio slot", function()
    local inst, emitter = Actor()
    Voice.PlayLine(inst, "no_such_key", 1)
    assert(inst._my_friend_voice_lines == nil)
    Voice.PlayLine(inst, "rain_request", 1)
    assert(#emitter.clips == 1 and emitter.clips[1].at == 0)
end)

Test("disabled voices and English/Russian do not queue custom audio", function()
    for _, language in ipairs({"en", "ru", "zh"}) do
        local inst, emitter = Actor()
        Language.language = language
        Voice.enabled = language ~= "zh"
        Dialogue.RandomReply(inst, "rain_request")
        assert(#emitter.clips == 0 and inst._my_friend_voice_lines == nil)
    end
end)

Test("Traditional Chinese still uses custom FIFO and clients do not run it", function()
    local inst, emitter = Actor()
    Language.language = "zh_tw"
    Voice.PlayLine(inst, "rain_request", 1)
    Voice.PlayLine(inst, "season_winter", 1)
    Advance(7)
    assert(#emitter.clips == 2)
    TheWorld.ismastersim = false
    Voice.PlayLine(inst, "rain_request", 1)
    assert(#emitter.clips == 2)
end)

print(string.format("%d voice queue tests passed", passed))
