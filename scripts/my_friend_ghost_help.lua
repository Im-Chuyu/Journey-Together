local Dialogue = require("my_friend_dialogue")
local M = {INTERVAL = 60, REQUESTS = 2}

local function CancelTask(inst)
    if inst._my_friend_ghost_help_task ~= nil then
        inst._my_friend_ghost_help_task:Cancel()
        inst._my_friend_ghost_help_task = nil
    end
end

function M.Stop(inst)
    CancelTask(inst)
    inst._my_friend_ghost_help = nil
end

local function Schedule(inst, delay)
    CancelTask(inst)
    inst._my_friend_ghost_help_task = inst:DoTaskInTime(delay, M.Update)
end

function M.Update(inst)
    if not inst:IsValid() or not inst:HasTag("playerghost") then M.Stop(inst) return end
    inst._my_friend_ghost_help_task = nil
    local now = GetTime()
    local state = inst._my_friend_ghost_help or {count = 0, next_at = now}
    inst._my_friend_ghost_help = state
    if state.count >= M.REQUESTS then return end
    if now >= state.next_at then
        state.count = state.count + 1
        state.next_at = now + M.INTERVAL
        Dialogue.PublicSay(inst, "ghost_help", inst:GetDisplayName())
    end
    if state.count < M.REQUESTS then
        Schedule(inst, math.max(0, state.next_at - now))
    elseif inst.brain ~= nil then
        inst.brain:ForceUpdate()
    end
end

function M.IsWaitingForRescue(inst)
    local state = inst._my_friend_ghost_help
    return state ~= nil and state.count >= M.REQUESTS
end

function M.Start(inst)
    if M.IsWaitingForRescue(inst) then
        CancelTask(inst)
        return
    end
    -- Defer until the ghost tag and saved state have both been restored.
    Schedule(inst, 0)
end

function M.OnSave(inst, data)
    local state = inst._my_friend_ghost_help
    if state ~= nil and inst:HasTag("playerghost") then
        data.my_friend_ghost_help = {count = state.count,
            remaining = math.max(0, state.next_at - GetTime())}
    end
end

function M.OnLoad(inst, data)
    local saved = data ~= nil and data.my_friend_ghost_help
    if type(saved) == "table" then
        inst._my_friend_ghost_help = {
            count = math.min(M.REQUESTS, math.max(0, tonumber(saved.count) or 0)),
            next_at = GetTime() + math.min(M.INTERVAL, math.max(0, tonumber(saved.remaining) or 0)),
        }
    end
    M.Start(inst)
end

return M
