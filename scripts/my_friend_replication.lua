local M = {}
local EquipSlots = require("my_friend_equip_slots")
local SYNC_PERIOD = 1.5

-- NPC inventories have no owning client. Publish their read-only replicas;
-- all transfers still pass the existing server-side distance/affinity checks.
function M.PublishItem(item)
    if item == nil or not item:IsValid() then return end
    item:ForceOutOfLimbo(true)
    if item.Network ~= nil then item.Network:SetClassifiedTarget(nil) end
    local replica = item.replica.inventoryitem
    if replica ~= nil and replica.classified ~= nil then
        replica.classified.Network:SetClassifiedTarget(nil)
    end
end

function M.ForceRefresh(inst)
    if inst ~= nil and inst:IsValid() then
        inst._my_friend_replication_signature = nil
        inst._my_friend_replication_next = 0
    end
end

function M.Sync(inst)
    local now = GetTime()
    if now < (inst._my_friend_replication_next or 0) then return end
    inst._my_friend_replication_next = now + SYNC_PERIOD
    local inventory = inst.components.inventory
    if inventory == nil then return end
    local items = inventory:ReferenceAllItems()
    local overflow = EquipSlots.BackpackContainer(inventory)
    local signature_parts = {}
    for _, item in ipairs(items) do
        signature_parts[#signature_parts + 1] = tostring(item.GUID or item)
    end
    signature_parts[#signature_parts + 1] =
        "overflow:" .. tostring(overflow ~= nil and overflow.inst.GUID or 0)
    local signature = table.concat(signature_parts, ",")
    -- Inventory contents are the expensive part of this operation. Reuse the
    -- existing classified targets while the item set is unchanged. Refreshes
    -- are requested explicitly when a panel opens or inventory ownership
    -- changes, so steady-state play does not emit periodic updates.
    if signature == inst._my_friend_replication_signature then
        return
    end
    inst._my_friend_replication_signature = signature
    local replica = inst.replica.inventory
    if replica ~= nil and replica.classified ~= nil then
        replica.classified.Network:SetClassifiedTarget(nil)
    end
    for _, item in ipairs(items) do
        M.PublishItem(item)
    end
    if overflow ~= nil then
        M.PublishItem(overflow.inst)
        for _, item in pairs(overflow.slots) do M.PublishItem(item) end
        local container = overflow.inst.replica.container
        if container ~= nil and container.classified ~= nil then
            container.classified.Network:SetClassifiedTarget(nil)
        end
    end
end

-- A base skin is per character: applying "wendy_none" to Wilson makes him
-- render as Wendy. Clothing is shared by everyone, so only the base is gated.
local function BelongsToCharacter(skin, prefab)
    if type(skin) ~= "string" or skin == "" or type(prefab) ~= "string" then return false end
    if skin == prefab or skin == prefab .. "_none" then return true end
    local data = type(GetSkinData) == "function" and GetSkinData(skin) or nil
    if type(data) == "table" and type(data.base_prefab) == "string" then
        return data.base_prefab == prefab
    end
    -- Skin ids are "<character>_<variant>"; fall back to that when the skin
    -- database is not reachable, as on a dedicated server.
    return skin:sub(1, #prefab + 1) == prefab .. "_"
end

-- Restricted characters (Wortox, Wormwood, Wurt, etc.) deliberately start
-- with the Wilson build when their prefab is spawned outside the normal
-- character-select flow. Companions are spawned directly by the server, so
-- give a fresh body its own default build before any companion systems or
-- saved wardrobe data are applied.
function M.ApplyDefaultAppearance(inst)
    if inst == nil or not inst:IsValid() or inst.AnimState == nil
        or type(inst.prefab) ~= "string" then return end
    inst.AnimState:SetBuild(inst.prefab)
    local skinner = inst.components ~= nil and inst.components.skinner or nil
    if skinner ~= nil then
        skinner:SetSkinName(inst.prefab .. "_none", true)
        M.ApplySkinMode(inst, false)
    end
end

-- A skin has to be committed through the character's own entry point.
--
-- skinner:SetSkinMode("normal_skin") looks like the obvious call, but it skips
-- inst.CustomSetSkinMode -- the hook a character with alternate forms uses to
-- pick the right build (vanilla Woodie's were-forms; most transforming mod
-- characters copy the pattern) -- and it drops inst.overrideskinmodebuild,
-- which vanilla Wurt and many mod characters rely on. Without that build,
-- SetSkinMode falls back to base_skin = inst.prefab, and a mod character whose
-- build is not simply named after its prefab ends up re-applying its old look,
-- so the wardrobe appeared to do nothing at all.
--
-- ApplySkinOverrides is the routine the player prefab itself uses, so it picks
-- whichever of those paths the character actually wants.
function M.ApplySkinMode(inst, ghost)
    local skinner = inst.components ~= nil and inst.components.skinner or nil
    if skinner == nil then return end
    if ghost then
        if inst.CustomSetSkinMode ~= nil then
            inst:CustomSetSkinMode("ghost_skin", inst.overrideskinmodebuild)
        else
            skinner:SetSkinMode("ghost_skin")
        end
    elseif inst.ApplySkinOverrides ~= nil then
        inst:ApplySkinOverrides()
    elseif inst.CustomSetSkinMode ~= nil then
        inst:CustomSetSkinMode(inst.overrideskinmode or "normal_skin",
            inst.overrideskinmodebuild)
    else
        skinner:SetSkinMode(inst.overrideskinmode or "normal_skin",
            inst.overrideskinmodebuild)
    end
end

function M.ApplyWardrobe(inst, player, base, clothing, owned)
    local skinner = inst.components.skinner
    if skinner == nil or type(base) ~= "string" then return false end
    if base == "" or base == inst.prefab then base = inst.prefab .. "_none" end
    if not BelongsToCharacter(base, inst.prefab)
        or base ~= inst.prefab .. "_none" and not (owned or {})[base] then return false end
    for _, part in ipairs({"body", "hand", "legs", "feet"}) do
        local skin = clothing[part]
        local entry = type(CLOTHING) == "table" and CLOTHING[skin] or nil
        if type(skin) ~= "string" or skin ~= "" and (type(IsValidClothing) ~= "function"
            or not IsValidClothing(skin) or type(entry) ~= "table"
            or entry.type ~= part) then return false end
    end
    local before = skinner:GetClothing()
    -- Like dressing a vanilla mannequin, the skin owner is the player who
    -- applies the outfit. A newly spawned companion has no player userid.
    inst.AnimState:AssignItemSkins(player.userid, base, clothing.body,
        clothing.hand, clothing.legs, clothing.feet)
    inst._my_friend_skin_owner = player.userid
    M.ApplySkinMode(inst, inst:HasTag("playerghost"))
    skinner:SetSkinName(base, true)
    skinner:ClearAllClothing()
    for _, part in ipairs({"body", "hand", "legs", "feet"}) do
        if clothing[part] ~= "" then skinner:SetClothing(clothing[part]) end
    end
    local applied = skinner:GetClothing()
    if applied.base ~= base then return false end
    local previous_base = before.base ~= nil and before.base ~= "" and before.base
        or inst.prefab .. "_none"
    local changed = previous_base ~= applied.base
    for _, part in ipairs({"body", "hand", "legs", "feet"}) do
        if applied[part] ~= clothing[part] then return false end
        changed = changed or before[part] ~= applied[part]
    end
    inst:PushEvent("my_friend_skin_changed")
    return true, changed
end

function M.RestoreSkin(inst, data)
    local skinner = inst.components.skinner
    local saved = data ~= nil and (data.my_friend_skin or data.skinner) or nil
    if skinner == nil or saved == nil then return end
    if type(POSTACTIVATEHANDSHAKE) == "table" and POSTACTIVATEHANDSHAKE.READY ~= nil
        and inst.userid ~= nil and not inst:HasTag("my_friend")
        and inst._PostActivateHandshakeState_Server ~= POSTACTIVATEHANDSHAKE.READY then
        inst._my_friend_pending_skin = saved
        if inst._my_friend_skin_ready_fn == nil then
            inst._my_friend_skin_ready_fn = function()
                local pending = inst._my_friend_pending_skin
                inst._my_friend_pending_skin = nil
                inst:RemoveEventCallback("ms_skilltreeinitialized", inst._my_friend_skin_ready_fn)
                inst._my_friend_skin_ready_fn = nil
                if pending ~= nil then M.RestoreSkin(inst, {my_friend_skin = pending}) end
            end
            inst:ListenForEvent("ms_skilltreeinitialized", inst._my_friend_skin_ready_fn)
        end
    end
    local name = saved.skin_name
    local clothing = saved.clothing or {}
    inst._my_friend_skin_owner = saved.owner or inst._my_friend_skin_owner or inst.userid
    if type(name) == "string" and name ~= "" and not BelongsToCharacter(name, inst.prefab) then
        -- Left over from a character switch: fall back to this body's default.
        name = ""
    end
    if inst._my_friend_skin_owner ~= nil then
        inst.AnimState:AssignItemSkins(inst._my_friend_skin_owner, name or (inst.prefab .. "_none"),
            clothing.body or "", clothing.hand or "", clothing.legs or "", clothing.feet or "")
    end
    M.ApplySkinMode(inst, inst:HasTag("playerghost"))
    skinner:SetSkinName(type(name) == "string" and name or "", true)
    skinner:ClearAllClothing()
    for _, part in ipairs({"body", "hand", "legs", "feet"}) do
        local value = saved.clothing ~= nil and saved.clothing[part] or nil
        if type(value) == "string" and value ~= "" then skinner:SetClothing(value) end
    end
    inst:PushEvent("my_friend_skin_changed")
end

return M
