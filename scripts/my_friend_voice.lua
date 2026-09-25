local M = {}
local Language = require("my_friend_strings")
M.enabled = true
local CHANNEL = "my_friend_talk"
local LINE_CHANNEL = "my_friend_line"
local EVENTS_PER_BANK = 70

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
    if type(number) ~= "number" then return end
    local bank = math.floor((number - 1) / EVENTS_PER_BANK) + 1
    -- fn numbers are global across all banks: fs2 starts at fn71.
    return "fs" .. bank .. "/fs" .. bank .. "/fn" .. number
end

function M.PlayLine(inst, key, index)
    if not UsesCustomVoice() then return end
    if not TheWorld.ismastersim or inst == nil or inst.SoundEmitter == nil then return end
    local event = VoiceIndex(key, index)
    if event ~= nil then
        -- Replace the vanilla looping talk voice for this line. The custom
        -- event is a one-shot voice clip and does not need a stop task.
        M.Stop(inst, true)
        inst.SoundEmitter:KillSound(LINE_CHANNEL)
        -- Leave the event at the engine's normal volume.  The PlaySound
        -- volume argument is a mix multiplier, not a gain stage; values above
        -- 1 can be clamped or interact poorly with the FEV attenuation.
        inst.SoundEmitter:PlaySound(event, LINE_CHANNEL)
    end
end

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
    local sound = inst.talksoundoverride
        or (inst.talker_path_override or "dontstarve/characters/")
            .. (inst.soundsname or inst.prefab)
            .. (ghost and "/ghost_LP" or "/talk_LP")
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
    inst:ListenForEvent("death", function() M.Stop(inst, true) end)
    inst:ListenForEvent("ms_becameghost", function() M.Stop(inst, true) end)
    inst:ListenForEvent("onremove", function() M.Stop(inst, true) end)
end

return M
