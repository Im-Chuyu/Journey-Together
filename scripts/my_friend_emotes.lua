local Policy = require("my_friend_policy")
local M = {}

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do if not Same(a[i], b[i]) then return false end end
    return true
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = Copy(v) end
    return result
end

function M.Available(inst)
    local leader = Policy.GetLeader(inst)
    return inst:IsValid() and leader ~= nil and Policy.IsLocalPlayer(leader)
        and not inst:HasTag("playerghost") and not leader:HasTag("playerghost")
        and not inst.components.health:IsDead() and inst:GetDistanceSqToInst(leader) <= 7^2
        and inst.sg ~= nil and not inst.sg:HasAnyStateTag("sleeping", "floating", "nopredict")
        and not inst.components.inventory:IsHeavyLifting()
        and inst:GetCurrentPlatform() == leader:GetCurrentPlatform()
        and inst._my_friend_command == nil and not inst._my_friend_under_threat
        and inst.components.combat.target == nil and inst:GetBufferedAction() == nil
        and inst._my_friend_backpack_target == nil and not inst._my_friend_container_action
        and inst._my_friend_storage_action == nil and not Policy.IsFollowGatheringPaused(inst)
        and not inst._my_friend_mount_stop_requested and not inst._my_friend_riding_dismounting
        and GetTime() >= (inst._my_friend_hurt_until or 0)
        and not require("my_friend_light_ai").IsDark(inst)
        and not require("my_friend_survival_ai").NeedsTemperatureHelp(inst)
        and inst.components.hunger:GetPercent() >= .4
end

function M.OnPlayerEmote(player, data)
    if type(data) ~= "table" or data.anim == nil or not Policy.IsLocalPlayer(player) then return end
    local friend = TheWorld._my_friend
    if friend == nil or not friend:IsValid() or Policy.GetLeader(friend) ~= player
        or not M.Available(friend) or Policy.IsBusy(friend)
        or GetTime() < (friend._my_friend_next_emote or 0) then return end
    local decision = friend._my_friend_decision
    if decision ~= nil and decision.task ~= "follow" and decision.task ~= "catch_up_mount" then return end
    -- Reject commands that SGwilson did not actually accept.
    player:DoTaskInTime(0, function()
        if not friend:IsValid() or not player:IsValid() or Policy.GetLeader(friend) ~= player
            or not M.Available(friend) or Policy.IsBusy(friend)
            or player.sg == nil or player.sg.currentstate.name ~= "emote"
            or GetTime() < (friend._my_friend_next_emote or 0) then return end
        local current = friend._my_friend_decision
        if current ~= nil and current.task ~= "follow" and current.task ~= "catch_up_mount" then return end
        local common = GetCommonEmotes ~= nil and GetCommonEmotes() or {}
        local options, matched = {}, nil
        for _, definition in pairs(common) do
            local free = definition.data
            local riding = friend.components.rider ~= nil and friend.components.rider:IsRiding()
            if free ~= nil and not free.requires_validation
                and (not free.mountonly or riding) and (free.mounted or not riding) then
                options[#options + 1] = free
                if Same(data.anim, free.anim) then matched = free end
            end
        end
        local chosen
        if matched ~= nil and math.random() < .7 then chosen = matched
        else
            local alternatives = {}
            for _, free in ipairs(options) do
                if free ~= matched then alternatives[#alternatives + 1] = free end
            end
            if #alternatives > 0 then chosen = alternatives[math.random(#alternatives)] end
        end
        if chosen == nil then return end
        local response = Copy(chosen)
        response.zoom = nil
        friend._my_friend_pending_emote = {data = response, leader = player, expires = GetTime() + 2}
        friend._my_friend_next_emote = GetTime() + 8
    end)
end

function M.TryIdle(inst)
    if inst._my_friend_pending_emote ~= nil or not M.Available(inst) or Policy.IsBusy(inst) then return end
    local decision = inst._my_friend_decision
    if decision == nil or decision.task ~= "follow" and decision.task ~= "catch_up_mount" then return end
    local now = GetTime()
    if inst._my_friend_idle_emote_after == nil then
        inst._my_friend_idle_emote_after = now + math.random(20, 40)
        return
    end
    if now < inst._my_friend_idle_emote_after or now < (inst._my_friend_next_emote or 0) then return end
    inst._my_friend_idle_emote_after = now + math.random(30, 60)
    if math.random() >= .5 then return end
    local riding = inst.components.rider ~= nil and inst.components.rider:IsRiding()
    local options = {}
    for _, definition in pairs(GetCommonEmotes ~= nil and GetCommonEmotes() or {}) do
        local data = definition.data
        if data ~= nil and data.anim ~= nil and not data.requires_validation
            and (not data.mountonly or riding) and (data.mounted or not riding) then
            options[#options + 1] = data
        end
    end
    if #options == 0 then return end
    local response = Copy(options[math.random(#options)])
    response.zoom = nil
    inst._my_friend_pending_emote = {data = response, leader = Policy.GetLeader(inst), expires = now + 2,
        idle_duration = math.random(4, 8)}
    inst._my_friend_next_emote = now + 8
end

function M.Score(inst)
    M.TryIdle(inst)
    local request = inst._my_friend_pending_emote
    if request == nil then return 0 end
    if request.expires ~= nil and GetTime() >= request.expires
        or Policy.GetLeader(inst) ~= request.leader or not M.Available(inst) then
        inst._my_friend_pending_emote = nil
        return 0
    end
    return 12
end

function M.ConfigurePlayer(player)
    if not TheWorld.ismastersim or player._my_friend_emote_listener then return end
    player._my_friend_emote_listener = true
    player:ListenForEvent("emote", M.OnPlayerEmote)
end

return M
