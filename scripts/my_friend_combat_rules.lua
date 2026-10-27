local M = {}
local SHADOWS = {terrorbeak = true, crawlinghorror = true, nightmarebeak = true,
    nightmareterror = true}
M.ACTIVE_DEFENCE_BEFORE_DAY = 500
M.FOLLOW_DISENGAGE_TIME = 5
M.FOLLOW_COMBAT_RANGE = 32

function M.IsBeyondFollowCombatRange(inst)
    if inst == nil then return false end
    local policy = require("my_friend_policy")
    local leader = policy.GetLeader(inst)
    return leader ~= nil and not policy.IsRoaming(inst)
        and policy.DistanceSq(inst, leader) > M.FOLLOW_COMBAT_RANGE^2
end

function M.IsFollowTargetPaused(inst, target)
    local state = inst ~= nil and inst._my_friend_follow_combat_pause or nil
    if state == nil then return false end
    local leader = require("my_friend_policy").GetLeader(inst)
    if GetTime() >= state.until_time or leader == nil or leader.GUID ~= state.leader_guid then
        inst._my_friend_follow_combat_pause = nil
        inst._my_friend_threat_scan, inst._my_friend_assist_scan, inst._my_friend_combat_check = nil, nil, nil
        return false
    end
    return target ~= nil and state.targets[target.GUID] == true
end

function M.DisengageForFollow(inst, player)
    M.IsFollowTargetPaused(inst)
    local previous = inst._my_friend_follow_combat_pause
    local targets = previous ~= nil and previous.leader_guid == player.GUID and previous.targets or {}
    local function Remember(target)
        if type(target) == "table" and target.IsValid ~= nil and target:IsValid()
            and target.GUID ~= nil and target.components ~= nil
            and target.components.combat ~= nil and target.components.health ~= nil
            and not target.components.health:IsDead() and not target:HasAnyTag("player", "my_friend") then
            targets[target.GUID] = true
        end
    end
    local combat = inst.components.combat
    if combat ~= nil then Remember(combat.target) end
    Remember(inst._my_friend_assist_target)
    Remember(inst._my_friend_combat_equipment_target)
    local root = inst.brain ~= nil and inst.brain.bt ~= nil and inst.brain.bt.root or nil
    local function RememberNode(node)
        if node == nil then return end
        Remember(node.target)
        for _, child in ipairs(node.children or {}) do RememberNode(child) end
    end
    if root ~= nil and root.active ~= nil and (root.active.id == "combat" or root.active.id == "assist") then
        RememberNode(root.active.node)
    end
    local action = inst.GetBufferedAction ~= nil and inst:GetBufferedAction() or nil
    if action ~= nil and action.action == ACTIONS.ATTACK then Remember(action.target) end
    if GetTime() < (inst._my_friend_hurt_evade_until or 0) and inst._my_friend_hurt_fire_distance == nil then
        Remember(inst._my_friend_hurt_attacker)
    end
    inst._my_friend_follow_combat_pause = next(targets) ~= nil
        and {leader_guid = player.GUID, targets = targets, until_time = GetTime() + M.FOLLOW_DISENGAGE_TIME} or nil
    if M.IsFollowTargetPaused(inst, inst._my_friend_hurt_attacker) and inst._my_friend_hurt_fire_distance == nil then
        inst._my_friend_hurt_until, inst._my_friend_hurt_evade_until = nil, nil
    end
    if combat ~= nil then combat:SetTarget(nil) end
    inst._my_friend_assist_target, inst._my_friend_assist_started = nil, nil
    inst._my_friend_assist_candidate, inst._my_friend_assist_until = nil, nil
    inst._my_friend_threat_scan, inst._my_friend_assist_scan, inst._my_friend_combat_check = nil, nil, nil
    inst._my_friend_combat_hand_item, inst._my_friend_combat_hand_until = nil, nil
    inst._my_friend_combat_equipment_target = nil
    inst._my_friend_under_threat, inst._my_friend_can_fight = false, false
    if action ~= nil and action.action == ACTIONS.ATTACK then
        action._my_friend_cancelled = true
        inst:ClearBufferedAction()
        local locomotor = inst.components.locomotor
        if locomotor ~= nil and locomotor.bufferedaction == action then locomotor:Clear() end
    end
    inst._my_friend_replan_requested = true
    if inst.brain ~= nil then inst.brain:ForceUpdate() end
end

function M.IsActiveDefenceWorld()
    local cycles = TheWorld ~= nil and TheWorld.state ~= nil and TheWorld.state.cycles or nil
    return type(cycles) == "number" and cycles + 1 < M.ACTIVE_DEFENCE_BEFORE_DAY
end

function M.IsPriorityEnemy(target)
    return target ~= nil and (SHADOWS[target.prefab] == true
        or target:HasAnyTag("hound", "shadowcreature", "shadow_aligned"))
        and not target:HasAnyTag("player", "my_friend")
end

function M.CanAttack(target, inst)
    local hand = inst ~= nil and inst.components ~= nil and inst.components.inventory ~= nil
        and inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS) or nil
    if hand ~= nil and (hand.prefab == "torch" or hand:HasTag("torch")) then return false end
    if target ~= nil and target:IsValid() and inst ~= nil then
        local behavior = require("my_friend_behavior_ai")
        if behavior.ShouldRetreatUnequipped(inst, target) then
            behavior.RememberUnequippedRetreat(inst, target)
            return false
        end
    end
    return target ~= nil and target:IsValid()
        and not M.IsBeyondFollowCombatRange(inst)
        and not M.IsFollowTargetPaused(inst, target)
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
        if target ~= nil and not M.CanAttack(target, self.inst) then return false end
        return can(self, target, ...)
    end
end

return M
