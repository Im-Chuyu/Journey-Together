local M = {}
local SHADOWS = {terrorbeak = true, crawlinghorror = true, nightmarebeak = true,
    nightmareterror = true}
M.ACTIVE_DEFENCE_BEFORE_DAY = 500

function M.IsActiveDefenceWorld()
    local cycles = TheWorld ~= nil and TheWorld.state ~= nil and TheWorld.state.cycles or nil
    return type(cycles) == "number" and cycles + 1 < M.ACTIVE_DEFENCE_BEFORE_DAY
end

function M.IsPriorityEnemy(target)
    return target ~= nil and (SHADOWS[target.prefab] == true
        or target:HasAnyTag("hound", "shadowcreature", "shadow_aligned"))
        and not target:HasAnyTag("player", "my_friend")
end

function M.CanAttack(target)
    return target ~= nil and target:IsValid()
        and (target.prefab ~= "lunarthrall_plant" or target.tired == true)
end

function M.BurnsWhenElectrocuted(target)
    -- CommonStates ignites creatures using this SG memory flag plus their
    -- burnable component. A plant/tree tag alone also matches ordinary crops.
    local c = target ~= nil and target.components or nil
    local mem = target ~= nil and target.sg ~= nil and target.sg.mem or nil
    return target ~= nil and target:IsValid() and c ~= nil
        and c.combat ~= nil and c.health ~= nil and not c.health:IsDead()
        and c.burnable ~= nil and not target:HasTag("fireimmune")
        and mem ~= nil and mem.burn_on_electrocute == true and not mem.noelectrocute
end

function M.Configure(inst)
    local combat = inst.components.combat
    if combat == nil or combat._my_friend_target_guard then return end
    combat._my_friend_target_guard = true
    local can = combat.CanTarget
    combat.CanTarget = function(self, target, ...)
        if target ~= nil and not M.CanAttack(target) then return false end
        return can(self, target, ...)
    end
end

return M
