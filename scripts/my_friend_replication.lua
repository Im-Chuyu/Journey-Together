local M = {}
local EquipSlots = require("my_friend_equip_slots")

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

function M.Sync(inst)
    local inventory = inst.components.inventory
    if inventory == nil then return end
    local replica = inst.replica.inventory
    if replica ~= nil and replica.classified ~= nil then
        replica.classified.Network:SetClassifiedTarget(nil)
    end
    for _, item in ipairs(inventory:ReferenceAllItems()) do
        M.PublishItem(item)
    end
    local overflow = EquipSlots.BackpackContainer(inventory)
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
    local data = GetSkinData ~= nil and GetSkinData(skin) or nil
    if type(data) == "table" and type(data.base_prefab) == "string" then
        return data.base_prefab == prefab
    end
    -- Skin ids are "<character>_<variant>"; fall back to that when the skin
    -- database is not reachable, as on a dedicated server.
    return skin:sub(1, #prefab + 1) == prefab .. "_"
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
        if type(skin) ~= "string" or skin ~= "" and (IsValidClothing == nil
            or not IsValidClothing(skin) or CLOTHING[skin].type ~= part) then return false end
    end
    local before = skinner:GetClothing()
    -- Like dressing a vanilla mannequin, the skin owner is the player who
    -- applies the outfit. A newly spawned companion has no player userid.
    inst.AnimState:AssignItemSkins(player.userid, base, clothing.body,
        clothing.hand, clothing.legs, clothing.feet)
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
    local name = saved.skin_name
    if type(name) == "string" and name ~= "" and not BelongsToCharacter(name, inst.prefab) then
        -- Left over from a character switch: fall back to this body's default.
        name = ""
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
