local Dialogue = require("my_friend_dialogue")
local Ghost = require("my_friend_ghost_commands")
local M = {INTERVAL = 60, REQUESTS = 3}

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
    local now = GetTime()
    local state = inst._my_friend_ghost_help or {count = 0, next_at = now}
    inst._my_friend_ghost_help = state
    if now >= state.next_at then
        if state.count < M.REQUESTS then
            Dialogue.PublicSay(inst, "ghost_help", inst:GetDisplayName())
            state.count = state.count + 1
        elseif Ghost.Score(inst) == 0 and Ghost.RequestAutomatic(inst) then
            if not state.departed then
                Dialogue.PublicSay(inst, "ghost_help_depart", inst:GetDisplayName())
                state.departed = true
            end
        end
        state.next_at = now + M.INTERVAL
    end
    Schedule(inst, math.max(0, state.next_at - now))
end

function M.Start(inst)
    -- Defer until the ghost tag and saved state have both been restored.
    Schedule(inst, 0)
end

function M.OnSave(inst, data)
    local state = inst._my_friend_ghost_help
    if state ~= nil and inst:HasTag("playerghost") then
        data.my_friend_ghost_help = {count = state.count, departed = state.departed,
            remaining = math.max(0, state.next_at - GetTime())}
    end
end

function M.OnLoad(inst, data)
    local saved = data ~= nil and data.my_friend_ghost_help
    if type(saved) == "table" then
        inst._my_friend_ghost_help = {
            count = math.min(M.REQUESTS, math.max(0, tonumber(saved.count) or 0)),
            departed = saved.departed == true,
            next_at = GetTime() + math.min(M.INTERVAL, math.max(0, tonumber(saved.remaining) or 0)),
        }
    end
    M.Start(inst)
end

return M
