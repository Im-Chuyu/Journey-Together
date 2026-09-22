local M = {}

-- Abigail belongs to Wendy's ghostlybond. Every entry point is gated on it so
-- that a companion switched to any other character runs none of this code.
function M.IsOwner(inst)
    return inst ~= nil and inst.components ~= nil
        and inst.components.ghostlybond ~= nil
end

-- The Clean Sweeper only reskins a pet whose _playerlink is the caster. The
-- companion's Abigail is linked to the companion, so the vanilla check is
-- lifted for players the companion likes (same 50 affinity as its own outfit).
M.RESKIN_AFFINITY = 50

function M.CanPlayerReskin(inst, player)
    local affinity = inst ~= nil and inst.components ~= nil
        and inst.components.my_friend_affinity or nil
    return affinity ~= nil and require("my_friend_policy").IsLocalPlayer(player)
        and affinity:Get(player) >= M.RESKIN_AFFINITY
end

function M.IsCompanionGhost(ghost)
    local owner = ghost ~= nil and ghost._playerlink or nil
    return owner ~= nil and owner.IsValid ~= nil and owner:IsValid()
        and owner:HasTag("my_friend") and owner or nil
end

-- Wraps a reskin_tool callback: while it runs, the ghost pretends its owner
-- is the caster so the vanilla ownership test passes.
function M.WrapReskin(fn)
    return function(tool_or_doer, a, b, c)
        -- spell fn is (tool, target, pos, caster); can_cast is (doer, target, pos, tool)
        local target = a
        local caster = tool_or_doer ~= nil and tool_or_doer:HasTag("player") and tool_or_doer or c
        local owner = M.IsCompanionGhost(target)
        if owner == nil or caster == nil or not M.CanPlayerReskin(owner, caster) then
            return fn(tool_or_doer, a, b, c)
        end
        local link = target._playerlink
        target._playerlink = caster
        local ok, result = pcall(fn, tool_or_doer, a, b, c)
        target._playerlink = link
        if not ok then error(result, 0) end
        return result
    end
end

-- The spell reads the chosen skin into tool._cached_reskinname synchronously;
-- remember it on the companion so the next summon keeps it.
function M.RememberSkin(ghost, tool)
    local owner = M.IsCompanionGhost(ghost)
    if owner == nil or tool == nil or tool._cached_reskinname == nil then return end
    local skin = tool._cached_reskinname[ghost.prefab]
    owner._my_friend_abigail_skin = type(skin) == "string" and skin ~= "" and skin or nil
end

function M.ConfigureGhost(inst, ghost)
    ghost._my_friend_abigail_owner = inst._my_friend_id
    -- Abigail is a companion of Wendy. Keep her out of companion target
    -- scans and make vanilla combat treat her as a friendly companion too.
    if not ghost:HasTag("companion") then ghost:AddTag("companion") end
    if not ghost:HasTag("my_friend") then ghost:AddTag("my_friend") end
    ghost.reskin_tool_cannot_target_this = nil
    if ghost._my_friend_leash_owner ~= inst then
        ghost._my_friend_leash_owner = inst
        if inst.components.leader ~= nil then inst.components.leader:SetForceLeash() end
        local follower = ghost.components.follower
        if follower ~= nil then
            if follower:GetLeader() ~= inst then follower:SetLeader(inst) end
            follower:EnableLeashing()
            follower:StartLeashing()
        end
    end
end

function M.Update(inst)
    if not M.IsOwner(inst) then return end
    local bond = inst.components.ghostlybond
    local ghost = bond ~= nil and bond.ghost or nil
    if ghost == nil or not ghost:IsValid() or inst:HasTag("playerghost")
        or inst.components.health:IsDead() then return end
    local hp = ghost.components.health
    if hp == nil then return end
    M.ConfigureGhost(inst, ghost)
    -- A companion is not an online player. Keep its summoned ghost simulating
    -- outside player range so the native Abigail brain can fly back normally.
    ghost.entity:SetCanSleep(not bond.summoned)
    if bond.summoned and not ghost:IsInLimbo()
        and ghost:GetDistanceSqToInst(inst) > 40^2 then
        if ghost.components.combat ~= nil then ghost.components.combat:SetTarget(nil) end
    end
    local calm = not require("my_friend_policy").IsBusy(inst)
        and not inst._my_friend_under_threat and inst.components.combat.target == nil
        and not require("my_friend_light_ai").IsDark(inst)
        and GetTime() >= (inst._my_friend_hurt_until or 0)
    if not calm then return end
    if bond.summoned and hp:GetPercent() < .2 then
        inst._my_friend_abigail_resting = true
        bond:Recall()
        return
    end
    if inst._my_friend_abigail_resting then
        if hp:GetPercent() <= .5 then return end
        inst._my_friend_abigail_resting = nil
    end
    local decision = inst._my_friend_decision
    if bond.notsummoned and (decision == nil or (decision.score or 0) <= 40)
        and GetTime() >= (inst._my_friend_abigail_next or 0) then
        inst._my_friend_abigail_next = GetTime() + 30
        -- linked_skinname is what a skinned Abigail's flower would carry.
        bond:Summon({skin_id = 0, linked_skinname = inst._my_friend_abigail_skin},
            inst:GetPosition())
    end
end

function M.CleanupDuplicates(inst)
    if not M.IsOwner(inst) then return end
    local bond = inst.components.ghostlybond
    if bond == nil or inst._my_friend_id == nil then return end
    for _, entity in pairs(Ents) do
        if entity.prefab == "abigail" and entity ~= bond.ghost and entity:IsValid()
            and entity._my_friend_abigail_owner == inst._my_friend_id
            and (entity._playerlink == nil or not entity._playerlink:IsValid()) then
            entity:Remove()
        end
    end
end

-- Capture first, then destroy only the source owner's bonded ghost. Native
-- OnRemoveEntity otherwise leaves a summoned ghost behind and may respawn it.
function M.RemoveSource(inst)
    if not M.IsOwner(inst) then return end
    local bond = inst.components.ghostlybond
    if bond == nil then return end
    if bond.spawnghosttask ~= nil then
        bond.spawnghosttask:Cancel()
        bond.spawnghosttask = nil
    end
    local ghost = bond.ghost
    if ghost ~= nil and ghost:IsValid() then
        inst:RemoveEventCallback("onremove", bond._ghost_onremove, ghost)
        inst:RemoveEventCallback("death", bond._ghost_death, ghost)
        bond.ghost = nil
        ghost:Remove()
    end
end

function M.Place(inst)
    if not M.IsOwner(inst) then return end
    local bond = inst.components.ghostlybond
    local ghost = bond ~= nil and bond.ghost or nil
    if ghost ~= nil and ghost:IsValid() and not bond.notsummoned then
        ghost.Transform:SetPosition(inst.Transform:GetWorldPosition())
    end
end

function M.Recall(inst, duration)
    if not M.IsOwner(inst) then return false end
    local bond = inst.components.ghostlybond
    if bond == nil then return false end
    if bond.summoned then bond:Recall() end
    inst._my_friend_abigail_next = GetTime() + (duration or 480)
    inst._my_friend_abigail_resting = nil
    return true
end

return M
