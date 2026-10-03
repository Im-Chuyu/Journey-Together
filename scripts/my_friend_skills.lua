-- Body-owned skill selections. NPCs do not run the player login handshake.
local M = {}

function M.Save(inst)
    local updater = inst.components.skilltreeupdater
    if updater == nil then return end
    return {skilltreeblob = inst._my_friend_pending_skills
            and inst._my_friend_pending_skills.skilltreeblob
            or updater.skilltreeblob or updater.skilltree:EncodeSkillTreeData(inst.prefab),
        skilltreeblobprefab = inst.prefab}
end

local function ApplyNow(inst, data)
    local updater = inst.components.skilltreeupdater
    if updater == nil or data == nil or data.skilltreeblob == nil
        or data.skilltreeblobprefab ~= nil and data.skilltreeblobprefab ~= inst.prefab then return end
    local tree = updater.skilltree
    local desired, xp = tree:DecodeSkillTreeData(data.skilltreeblob)
    desired = desired or {}
    if not tree:ValidateCharacterData(inst.prefab, desired, xp) then return end
    local npc = inst:HasTag("my_friend") or inst.userid == nil
    local previous = {}
    for skill in pairs(updater:GetActivatedSkills() or {}) do previous[skill] = true end
    local skip = tree.skip_validation
    updater:SetSkipValidation(true)
    for skill in pairs(previous) do
        if not desired[skill] then
            if npc then
                if tree:DeactivateSkill(skill, inst.prefab) then updater:DeactivateSkill_Server(skill) end
            else updater:DeactivateSkill(skill) end
        end
    end
    local delta = math.max(0, (xp or 0) - updater:GetSkillXP())
    if delta > 0 then
        if npc then tree:AddSkillXP(delta, inst.prefab) else updater:AddSkillXP(delta) end
    end
    for skill in pairs(desired) do
        if not previous[skill] then
            if npc then
                if tree:ActivateSkill(skill, inst.prefab) then updater:ActivateSkill_Server(skill) end
            else updater:ActivateSkill(skill) end
        end
    end
    updater:SetSkipValidation(skip)
    updater.skilltreeblob, updater.skilltreeblobprefab = nil, nil
    inst._my_friend_pending_skills = nil
    inst:PushEvent("onsetskillselection_server")
end

function M.Apply(inst, data)
    if data == nil then return end
    if inst.userid ~= nil and not inst:HasTag("my_friend")
        and inst._PostActivateHandshakeState_Server ~= POSTACTIVATEHANDSHAKE.READY then
        inst._my_friend_pending_skills = data
        return
    end
    ApplyNow(inst, data)
end

function M.Attach(updater, inst)
    inst:ListenForEvent("ms_skilltreeinitialized", function()
        if inst._my_friend_pending_skills ~= nil then
            ApplyNow(inst, inst._my_friend_pending_skills)
        end
    end)
    local load = updater.OnLoad
    updater.OnLoad = function(self, data)
        load(self, data)
        inst:DoTaskInTime(0, function()
            if inst:HasTag("my_friend") then ApplyNow(inst, data) end
        end)
    end
    -- Offline NPCs must not send client activation events to the host player
    -- when a character prefab activates or deactivates a skill internally.
    for _, name in ipairs({"ActivateSkill", "DeactivateSkill"}) do
        local method = name
        local original = updater[method]
        updater[method] = function(self, skill, prefab, fromrpc)
            if not inst:HasTag("my_friend") then return original(self, skill, prefab, fromrpc) end
            local changed = self.skilltree[method](self.skilltree, skill, inst.prefab)
            if changed and not self.silent then self[method .. "_Server"](self, skill) end
        end
    end
end

return M
