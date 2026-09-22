local M = {}
M.RETRY_DELAY = 60

local function IsGather(action)
    local id = action ~= nil and action.action ~= nil and action.action.id or nil
    return id == "PICK" or id == "HARVEST" or id == "PICKUP"
        or id == "CHOP" or id == "MINE" or id == "DIG" or id == "HAMMER"
end

local function ResourceType(target)
    if target == nil then return end
    return target.prefab == "oasis_cactus" and "cactus" or target.prefab
end

function M.IsBlocked(inst, target)
    local blocked = inst._my_friend_harmful_resources
    if blocked == nil or target == nil then return false end
    local key = ResourceType(target)
    if key == nil then return false end
    local deadline = blocked[key]
    if deadline ~= nil and GetTime() >= deadline then blocked[key], deadline = nil, nil end
    return deadline ~= nil
end

function M.GuardAction(inst, action)
    if not IsGather(action) or action.target == nil then return end
    local valid = action.validfn
    action.validfn = function(act)
        return not M.IsBlocked(inst, act.target) and (valid == nil or valid(act))
    end
end

function M.OnPerform(inst, data)
    local action = data ~= nil and data.action or nil
    inst._my_friend_gather_contact = IsGather(action) and action.target ~= nil
        and {target = action.target, untiltime = GetTime() + 1} or nil
end

function M.OnDamage(inst, data)
    if data == nil or (data.amount or 0) >= 0 or inst:HasTag("playerghost")
        or data.oldpercent ~= nil and data.newpercent ~= nil
            and data.newpercent >= data.oldpercent then return end
    local contact = inst._my_friend_gather_contact
    if contact == nil or GetTime() > contact.untiltime then return end
    local target = contact.target
    -- Vanilla thorns pass the resource as afflicter. Support direct prefab
    -- causes too, but never blame a plant for starvation, weather or attackers.
    if data.afflicter ~= target and not (data.afflicter == nil and not data.overtime
        and data.cause == target.prefab) then return end
    local blocked, now = inst._my_friend_harmful_resources or {}, GetTime()
    for key, deadline in pairs(blocked) do if now >= deadline then blocked[key] = nil end end
    local resource_type = ResourceType(target)
    if resource_type == nil then return end
    blocked[resource_type] = now + M.RETRY_DELAY
    inst._my_friend_harmful_resources = blocked
    inst._my_friend_world_resource_query = nil
    inst._my_friend_replan_requested = true
    if inst._my_friend_work_target == target then
        inst._my_friend_work_target, inst._my_friend_work_action = nil, nil
        inst._my_friend_work_stall_deadline, inst._my_friend_hand_tool_lock_until = nil, nil
    end
    require("my_friend_dialogue").Say(inst, "gather_hurt")
end

function M.Configure(inst)
    if inst._my_friend_resource_safety_configured then return end
    inst._my_friend_resource_safety_configured = true
    inst:ListenForEvent("performaction", M.OnPerform)
    inst:ListenForEvent("healthdelta", M.OnDamage)
end

return M
