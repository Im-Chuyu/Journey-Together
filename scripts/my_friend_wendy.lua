local M = {}

M.MANUAL_BEHAVIOUR_COOLDOWN = 120

local function GetGhost(inst)
    if inst == nil or inst.components == nil
        or inst.components.ghostlybond == nil then return end
    local bond = inst.components.ghostlybond
    local ghost = bond.ghost
    if not bond.summoned or ghost == nil or not ghost:IsValid()
        or ghost:IsInLimbo() then return end
    return ghost
end

local function ApplyBehaviour(ghost, aggressive)
    if ghost == nil then return false end
    if aggressive then
        if ghost.is_defensive == false then return true end
        if ghost.BecomeAggressive == nil then return false end
        ghost:BecomeAggressive()
    else
        if ghost.is_defensive == true then return true end
        if ghost.BecomeDefensive == nil then return false end
        ghost:BecomeDefensive()
    end
    return true
end

local function InCombat(inst)
    local combat = inst.components ~= nil and inst.components.combat or nil
    return combat ~= nil and combat.target ~= nil
        or inst._my_friend_under_threat == true
        or inst._my_friend_assist_target ~= nil
end

function M.Request(inst, aggressive)
    local ghost = GetGhost(inst)
    if ghost == nil or not ApplyBehaviour(ghost, aggressive) then return false end
    inst._my_friend_abigail_manual_until = GetTime() + M.MANUAL_BEHAVIOUR_COOLDOWN
    return true
end

function M.Update(inst)
    local ghost = GetGhost(inst)
    if ghost == nil or GetTime() < (inst._my_friend_abigail_manual_until or 0) then return end
    ApplyBehaviour(ghost, InCombat(inst))
end

return M
