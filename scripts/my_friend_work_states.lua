local M = {}

function M.Configure(sg)
    for _, name in ipairs({"chop", "mine", "hammer", "dig"}) do
        local digging = name == "dig"
        local state = sg.states[name]
        for _, event in ipairs(state ~= nil and state.timeline or {}) do
            local woodcutter = name == "chop" and event.time == 10 * FRAMES
            local normal = event.time == (digging and 35 or 14) * FRAMES
            if (woodcutter or normal) and not event._my_friend_repeat then
                event._my_friend_repeat = true
                local original, chopping = event.fn, name == "chop"
                event.fn = function(inst, ...)
                    if not inst:HasTag("my_friend") then return original(inst, ...) end
                    local previous = inst.sg.statemem.action
                    if digging and (previous == nil or previous._body_job == nil) then
                        return original(inst, ...)
                    end
                    if chopping and (inst.sg.statemem.iswoodcutter == true) ~= woodcutter then return end
                    local root = inst.brain ~= nil and inst.brain.bt ~= nil and inst.brain.bt.root or nil
                    if root ~= nil and root.RepeatWork ~= nil then
                        root:RepeatWork(previous)
                    end
                end
            end
        end
    end
end

return M
