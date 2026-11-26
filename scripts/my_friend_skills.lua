-- Body-owned skill selections. NPCs do not run the player login handshake.
local M = {}

local function MatchesBody(data, prefab)
    return type(data) == "table" and type(data.skilltreeblob) == "string"
        and (data.skilltreeblobprefab == nil or data.skilltreeblobprefab == prefab)
end

local function NeedsHandshake(inst)
    return inst.userid ~= nil and inst.userid ~= "" and not inst:HasTag("my_friend")
        and inst._PostActivateHandshakeState_Server ~= POSTACTIVATEHANDSHAKE.READY
end

function M.Save(inst)
    local updater = inst.components.skilltreeupdater
    if updater == nil then return end
    local prefab = inst.prefab
    local pending = inst._my_friend_pending_skills
    if MatchesBody(pending, prefab) then
        return {skilltreeblob = pending.skilltreeblob, skilltreeblobprefab = prefab}
    end
    local blob
    if (inst:HasTag("my_friend") or NeedsHandshake(inst))
        and MatchesBody(updater, prefab) then blob = updater.skilltreeblob end
    -- A listen host's profile backup can differ from the skills actually
    -- selected on the borrowed body. Capture the active selection.
    return {skilltreeblob = blob or updater.skilltree:EncodeSkillTreeData(prefab, true),
        skilltreeblobprefab = prefab}
end

local function ApplyNow(inst, data)
    local updater = inst.components.skilltreeupdater
    if updater == nil or not MatchesBody(data, inst.prefab) then return end
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
    if not MatchesBody(data, inst.prefab) then return end
    if NeedsHandshake(inst) then
        inst._my_friend_pending_skills = data
        return
    end
    inst._my_friend_pending_skills = nil
    ApplyNow(inst, data)
end

function M.Attach(updater, inst)
    inst:ListenForEvent("ms_skilltreeinitialized", function()
        if inst._my_friend_pending_skills ~= nil then
            M.Apply(inst, inst._my_friend_pending_skills)
        end
    end)
    local load = updater.OnLoad
    updater.OnLoad = function(self, data)
        load(self, data)
        if MatchesBody(data, inst.prefab) then
            inst:DoTaskInTime(0, function()
                -- SpawnSaveRecord can be followed by a newer body snapshot in
                -- the same tick. Only restore the blob still awaiting load.
                if inst:IsValid() and inst:HasTag("my_friend") and inst.components.skilltreeupdater == self
                    and self.skilltreeblob == data.skilltreeblob
                    and self.skilltreeblobprefab == data.skilltreeblobprefab then ApplyNow(inst, data) end
            end)
        end
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
