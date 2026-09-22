local M = {}
local CHANNEL = "my_friend_talk"

function M.Stop(inst, instant)
    if inst._my_friend_voice_task ~= nil then
        inst._my_friend_voice_task:Cancel()
        inst._my_friend_voice_task = nil
    end
    if inst.SoundEmitter ~= nil then
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
    M.Stop(inst, true)
    local sound = inst.talksoundoverride or (inst.talker_path_override or "dontstarve/characters/")
        .. (inst.soundsname or inst.prefab) .. (ghost and "/ghost_LP" or "/talk_LP")
    inst.SoundEmitter:PlaySound(sound, CHANNEL)
    inst._my_friend_voice_task = inst:DoTaskInTime(math.min(data ~= nil and data.duration or 2, 2),
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
