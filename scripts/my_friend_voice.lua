local M = {}
local Language = require("my_friend_strings")
local Durations
M.enabled = true
local CHANNEL = "my_friend_talk"
local LINE_CHANNEL = "my_friend_line"
local EVENTS_PER_BANK = 70
local UNKNOWN_LINE_DURATION = 7
local LINE_END_PADDING = .1

local function NativeSound(inst, ghost)
    return inst.talksoundoverride
        or (inst.talker_path_override or "dontstarve/characters/")
            .. (inst.soundsname or inst.prefab)
            .. (ghost and "/ghost_LP" or "/talk_LP")
end

local function UsesCustomVoice()
    return M.enabled and (Language.language == "zh" or Language.language == "zh_tw")
end

local function VoiceIndex(key, index)
    local map = STRINGS ~= nil and STRINGS.MY_FRIEND_VOICE_INDEX or nil
    local number = map ~= nil and map[key .. ":" .. tostring(index)] or nil
    if number == nil and type(key) == "string" then
        local bare = key:match("^[^/]+/(.+)$")
        number = bare ~= nil and map ~= nil
            and map[bare .. ":" .. tostring(index)] or number
    end
    if type(number) ~= "number" or number < 1
        or number ~= math.floor(number) then return end
    local bank = math.floor((number - 1) / EVENTS_PER_BANK) + 1
    -- fn numbers are global across all banks: fs2 starts at fn71.
    return "fs" .. bank .. "/fs" .. bank .. "/fn" .. number, number
end

local function CanPlayLine(inst)
    return UsesCustomVoice() and TheWorld ~= nil and TheWorld.ismastersim
        and inst ~= nil and inst:IsValid()
        and inst._my_friend_is_companion == true
        and not inst._my_friend_possess_parked
        and not (inst:HasTag("playerghost") and inst.components.health ~= nil
            and not inst.components.health:IsDead())
        and inst.SoundEmitter ~= nil
end

local function ClearLines(inst)
    local state = inst._my_friend_voice_lines
    if state ~= nil and state.task ~= nil then state.task:Cancel() end
    inst._my_friend_voice_lines = nil
    if inst:IsValid() and inst.SoundEmitter ~= nil then inst.SoundEmitter:KillSound(LINE_CHANNEL) end
end

local PumpLines
local function ScheduleLines(inst, state, delay)
    if state.task ~= nil then return end
    state.task = inst:DoTaskInTime(delay, function()
        if inst._my_friend_voice_lines ~= state then return end
        state.task = nil
        PumpLines(inst, state)
    end)
end

PumpLines = function(inst, state)
    if not CanPlayLine(inst) then ClearLines(inst); return end
    local remaining = state.ready_at - GetTime()
    if remaining > 0 then ScheduleLines(inst, state, remaining); return end
    -- A named event can remain registered after its audio ends, especially on
    -- a server without an audio device. Never wait indefinitely on PlayingSound.
    inst.SoundEmitter:KillSound(LINE_CHANNEL)
    local line = table.remove(state.queue, 1)
    if line == nil then inst._my_friend_voice_lines = nil; return end
    M.Stop(inst, true)
    -- Keep the normal volume and the companion's spatial emitter. Naming the
    -- event lets lifecycle cleanup stop it and prevents overlapping clips.
    local ok = pcall(inst.SoundEmitter.PlaySound, inst.SoundEmitter,
        line.event, LINE_CHANNEL, 1, false)
    if not ok then
        -- Audio failure must not affect text or strand later queued lines.
        local ghost = inst:HasTag("playerghost")
        pcall(inst.SoundEmitter.PlaySound, inst.SoundEmitter,
            NativeSound(inst, ghost), CHANNEL)
        inst._my_friend_voice_task = inst:DoTaskInTime(2, function()
            if inst:IsValid() then M.Stop(inst) else inst._my_friend_voice_task = nil end
        end)
    end
    local duration = ok and line.duration or 2
    state.ready_at = GetTime() + duration
    ScheduleLines(inst, state, duration)
end

function M.PlayLine(inst, key, index)
    if not CanPlayLine(inst) then return end
    local event, number = VoiceIndex(key, index)
    if event == nil then return end
    Durations = Durations or require("my_friend_voice_durations")
    M.Configure(inst)
    local state = inst._my_friend_voice_lines
    if state == nil then
        state = {queue = {}, ready_at = 0}
        inst._my_friend_voice_lines = state
    end
    local duration = Durations[number]
    duration = type(duration) == "number" and duration > 0
        and duration < math.huge and duration + LINE_END_PADDING or UNKNOWN_LINE_DURATION
    state.queue[#state.queue + 1] = {event = event, duration = duration}
    if state.task == nil then PumpLines(inst, state) end
end

-- Stop only the native talk loop. Bubble completion and a new ontalk event
-- must not cut off a custom clip or discard its queued successors.
function M.Stop(inst, instant)
    if inst._my_friend_voice_task ~= nil then
        inst._my_friend_voice_task:Cancel()
        inst._my_friend_voice_task = nil
    end
    if inst.SoundEmitter ~= nil then
        if UsesCustomVoice() then
            -- SGwilson uses the "talk" channel for the character's built-in
            -- voice. It must not overlap the custom dialogue event.
            inst.SoundEmitter:KillSound("talk")
        end
        local ending = inst:HasTag("playerghost") and inst.endghosttalksound or inst.endtalksound
        if not instant and ending ~= nil and inst.SoundEmitter:PlayingSound(CHANNEL) then
            inst.SoundEmitter:PlaySound(ending)
        end
        inst.SoundEmitter:KillSound(CHANNEL)
    end
end

function M.Play(inst, data)
    if not TheWorld.ismastersim or not inst:HasTag("my_friend") or inst.SoundEmitter == nil
        or TheWorld.speechdisabled or inst:HasTag("mime")
        or inst.sg ~= nil and inst.sg:HasStateTag("sleeping") then return end
    local ghost = inst:HasTag("playerghost")
    if not ghost and inst.components.health ~= nil and inst.components.health:IsDead() then return end
    if UsesCustomVoice() then
        -- The custom line is started by PlayLine.  Stop the stategraph's
        -- built-in talk channel so it cannot overlap the custom clip.
        inst.SoundEmitter:KillSound("talk")
        inst.SoundEmitter:KillSound(CHANNEL)
        return
    end
    -- English and all other language modes keep the original character voice.
    -- This also covers PublicSay, which does not go through PlayLine.
    -- When the stategraph already started its native "talk" channel, keep
    -- that instance and avoid layering a second copy on the companion.
    if inst.SoundEmitter:PlayingSound("talk") then return end
    M.Stop(inst, true)
    local sound = NativeSound(inst, ghost)
    inst.SoundEmitter:PlaySound(sound, CHANNEL)
    inst._my_friend_voice_task = inst:DoTaskInTime(
        math.min(data ~= nil and data.duration or 2, 2),
        function() M.Stop(inst) end)
end

function M.Configure(inst)
    if not TheWorld.ismastersim or inst._my_friend_voice_configured then return end
    inst._my_friend_voice_configured = true
    inst:ListenForEvent("ontalk", M.Play)
    inst:ListenForEvent("donetalking", function() M.Stop(inst) end)
    local function StopAll()
        M.Stop(inst, true)
        ClearLines(inst)
    end
    inst:ListenForEvent("death", StopAll)
    inst:ListenForEvent("ms_becameghost", StopAll)
    inst:ListenForEvent("onremove", StopAll)
end

return M
