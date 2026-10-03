-- Exchange the local player's body with the companion's body.
--
-- DST's PlayerController is attached to ThePlayer, so control is transferred
-- with the same seamless body swap used by the game for character changes.
-- The old player body is rebuilt as an autonomous companion at its old
-- position, while the companion body becomes the new player body.

local M = {}
local RestoreCompanion
local RestoreActiveSession
local Characters = require("my_friend_characters")

local function PlayerOwnsCharacter(player, prefab)
    if player == nil or type(prefab) ~= "string" then return false end
    if player.prefab == prefab or not Characters.IsPaid(prefab) then return true end
    local reported = _G.MyFriendOwnedCharacters ~= nil
        and _G.MyFriendOwnedCharacters[player.userid] or nil
    return reported ~= nil and reported[prefab] == true
end

local function SafeSkinForPlayer(player, prefab, skin)
    if type(skin) ~= "string" or skin == "" or skin == prefab
        or skin == prefab .. "_none" then return nil end
    local owned = _G.MyFriendSkinNames ~= nil
        and _G.MyFriendSkinNames[player.userid] or nil
    return owned ~= nil and owned[skin] == true and skin or nil
end

local function SafeClothingForPlayer(player, clothing)
    local safe = {}
    local owned = _G.MyFriendSkinNames ~= nil
        and _G.MyFriendSkinNames[player.userid] or nil
    for _, part in ipairs({"body", "hand", "legs", "feet"}) do
        local value = clothing ~= nil and clothing[part] or nil
        safe[part] = type(value) == "string" and value ~= ""
            and owned ~= nil and owned[value] == true and value or ""
    end
    return safe
end

local function World()
    return _G.TheWorld
end

local function Sessions()
    local world = World()
    if world == nil then return nil end
    world._my_friend_possessions = world._my_friend_possessions or {}
    return world._my_friend_possessions
end

local function ClearInventory(inv)
    if inv == nil or inv.ForEachItem == nil then return end
    local items = {}
    inv:ForEachItem(function(item)
        items[#items + 1] = item
    end)
    for _, item in ipairs(items) do
        if item ~= nil and item:IsValid() then item:Remove() end
    end
end

local function SaveInventory(inst)
    local inv = inst ~= nil and inst.components ~= nil and inst.components.inventory or nil
    if inv == nil or inv.OnSave == nil then return nil end
    local data = inv:OnSave()
    ClearInventory(inv)
    return data
end

-- World saving must not clear a live player's inventory.  The possession
-- swap path uses SaveInventory because it immediately removes the old body;
-- this read-only variant is for an active session that will continue after a
-- save/reload.
local function CaptureInventory(inst)
    local inv = inst ~= nil and inst.components ~= nil and inst.components.inventory or nil
    if inv == nil or inv.OnSave == nil then return nil end
    return inv:OnSave()
end

local function LoadInventory(inst, data)
    local inv = inst ~= nil and inst.components ~= nil and inst.components.inventory or nil
    if inv == nil then return end
    ClearInventory(inv)
    if data ~= nil and inv.OnLoad ~= nil then inv:OnLoad(data, {}) end
end

local function DetachCompanionPets(inst)
    local pets = {}
    local leash = inst ~= nil and inst.components ~= nil and inst.components.petleash or nil
    if leash == nil then return pets end
    for pet in pairs(leash:GetPets() or {}) do
        if pet ~= nil and pet:IsValid() then
            pets[#pets + 1] = pet
            leash:DetachPet(pet)
            pet.persists = true
            if inst.components.leader ~= nil and inst.components.leader:IsFollower(pet) then
                inst.components.leader:RemoveFollower(pet)
            end
        end
    end
    return pets
end

local function AttachCompanionPets(inst, pets)
    local leash = inst ~= nil and inst.components ~= nil and inst.components.petleash or nil
    if leash == nil or type(pets) ~= "table" then return end
    for _, pet in ipairs(pets) do
        if pet ~= nil and pet:IsValid() and leash:AttachPet(pet)
            and pet.components ~= nil and pet.components.follower ~= nil
            and pet.components.follower:GetLeader() ~= inst then
            pet.components.follower:SetLeader(inst)
        end
    end
end

local function RestoreCompanionPets(inst, sess)
    if inst == nil or not inst:IsValid() then return end
    if sess.companion_pets ~= nil then
        AttachCompanionPets(inst, sess.companion_pets)
        sess.companion_pets = nil
    elseif sess.companion_pet_data ~= nil and inst.components.petleash ~= nil then
        inst.components.petleash:OnLoad(sess.companion_pet_data)
    end
    sess.companion_pet_data = nil
end

local function SaveMeters(inst)
    local c = inst ~= nil and inst.components or nil
    return {
        health = c ~= nil and c.health ~= nil and c.health:GetPercent() or nil,
        hunger = c ~= nil and c.hunger ~= nil and c.hunger:GetPercent() or nil,
        sanity = c ~= nil and c.sanity ~= nil and c.sanity:GetPercent() or nil,
        oldage = c ~= nil and c.oldager ~= nil and {
            year_timer = c.oldager.year_timer,
            damage_remaining = c.oldager.damage_remaining,
            damage_per_second = c.oldager.damage_per_second,
        } or nil,
    }
end

local function LoadMeters(inst, data)
    if inst == nil or data == nil or inst.components == nil then return end
    if data.health ~= nil and inst.components.health ~= nil then
        inst.components.health:SetPercent(data.health)
    end
    if data.hunger ~= nil and inst.components.hunger ~= nil then
        inst.components.hunger:SetPercent(data.hunger)
    end
    if data.sanity ~= nil and inst.components.sanity ~= nil then
        inst.components.sanity:SetPercent(data.sanity)
    end
    if data.oldage ~= nil and inst.components.oldager ~= nil then
        local age = inst.components.oldager
        age.year_timer = data.oldage.year_timer or 0
        age.damage_remaining = data.oldage.damage_remaining or 0
        age.damage_per_second = data.oldage.damage_per_second or 0
        if inst.player_classified ~= nil then
            inst.player_classified.oldager_yearpercent:set(age.year_timer)
        end
    end
end

-- Skill-tree state is tied to the character prefab.  Seamless swaps transfer
-- the player's tree automatically, so possession must explicitly apply the
-- companion's compact vanilla skill blob to the controlled body.
local SaveSkillTree = require("my_friend_skills").Save
local ApplySkillTree = require("my_friend_skills").Apply

local function SaveSkin(inst)
    local skinner = inst.components.skinner
    if skinner == nil then return end
    return {skin_name = skinner.skin_name, clothing = skinner:GetClothing(),
        skin_mode = skinner.skintype, owner = inst._my_friend_skin_owner or inst.userid}
end

local function SaveAffinity(inst)
    local affinity = inst ~= nil and inst.components ~= nil
        and inst.components.my_friend_affinity or nil
    return affinity ~= nil and affinity.OnSave ~= nil and affinity:OnSave() or nil
end

local function LoadAffinity(inst, data)
    local affinity = inst ~= nil and inst.components ~= nil
        and inst.components.my_friend_affinity or nil
    if affinity ~= nil and data ~= nil and affinity.OnLoad ~= nil then
        affinity:OnLoad(data)
    end
end

local function StartSwap(player, prefab, skin, trusted)
    local sw = player ~= nil and player.components ~= nil
        and player.components.seamlessplayerswapper or nil
    if sw == nil or sw._my_friend_swap_in_progress
        or type(sw._StartSwap) ~= "function" then return false end
    if prefab ~= nil and not Characters.IsCharacter(prefab) then return false end
    if player.userid == nil or player.userid == "" then return false end
    if not trusted and prefab ~= nil and not PlayerOwnsCharacter(player, prefab) then return false end
    sw._my_friend_swap_in_progress = true
    if prefab ~= nil then
        sw.swap_data = sw.swap_data or {}
        sw.swap_data[prefab] = {
            skin_base = SafeSkinForPlayer(player, prefab, skin),
        }
    end
    -- Finish a spawn fade while its controller still exists. Native swapping
    -- removes that controller before the old body is actually removed.
    local tween = player.components.colourtweener
    if tween ~= nil and tween:IsTweening() and tween.t_colour_r == 1
        and tween.t_colour_g == 1 and tween.t_colour_b == 1 then
        tween:EndTween()
    end
    local ok = _G.pcall(function()
        sw:_StartSwap(prefab)
    end)
    if not ok then
        sw._my_friend_swap_in_progress = nil
        return false
    end
    return true
end

local function SessionFor(player)
    local sessions = Sessions()
    return sessions ~= nil and player ~= nil and player.userid ~= nil
        and sessions[player.userid] or nil
end

local function FindOnlinePlayer(userid, excluded)
    if userid == nil then return nil end
    for _, player in ipairs(_G.AllPlayers or {}) do
        if player ~= nil and player ~= excluded and player:IsValid()
            and not player._despawning and player.userid == userid then
            return player
        end
    end
    return nil
end

local function FindPossessingPlayer(userid)
    if userid == nil then return nil end
    for _, player in ipairs(_G.AllPlayers or {}) do
        if player ~= nil and player:IsValid() and not player._despawning
            and player.userid == userid and player:HasTag("my_friend_possessing") then
            return player
        end
    end
    return FindOnlinePlayer(userid)
end

local function CaptureActiveSession(sess, player)
    if sess == nil or player == nil or not player:IsValid()
        or sess.phase ~= nil then return end
    if SessionFor(player) ~= sess then return end
    local x, _, z = player.Transform:GetWorldPosition()
    local skinner = player.components ~= nil and player.components.skinner or nil
    sess.active_body = {
        inv = CaptureInventory(player),
        meters = SaveMeters(player),
        skill_data = SaveSkillTree(player),
    }
    sess.active_position = {x = x, z = z}
    sess.active_prefab = player.prefab
    sess.active_skin_data = skinner ~= nil and {
        owner = player._my_friend_skin_owner or player.userid,
        skin_name = skinner.skin_name,
        clothing = skinner:GetClothing(),
        skin_mode = skinner.skintype,
    } or nil
end

-- A seamless character change replaces the player entity.  Keep the
-- possession marker and the parked companion attached to the replacement so
-- the center wheel can release or continue the same session.
local function MarkPossessedPlayer(player, sess)
    if player == nil or not player:IsValid() or sess == nil then return end
    player:AddTag("my_friend_possessing")
    player:AddTag("my_friend_possessed")
    player._my_friend_id = sess.companion_id
    player._my_friend_custom_name = sess.companion_custom_name
    player._my_friend_possessed_name = sess.companion_name
    player._my_friend_possessed_prefab = sess.companion_prefab
    if player.components ~= nil and player.components.named ~= nil
        and sess.companion_name ~= nil then
        player.components.named:SetName(sess.companion_name)
    end
    require("my_friend_wortox").RefreshLinkedHearts(player)
    if sess.temporary_companion ~= nil and sess.temporary_companion:IsValid()
        and sess.was_following and sess.temporary_companion.components ~= nil
        and sess.temporary_companion.components.follower ~= nil then
        sess.temporary_companion.components.follower:SetLeader(player)
    end
end

function M.IsPossessing(player)
    return SessionFor(player) ~= nil
end

function M.CanUseCompanionCharacter(player, prefab)
    return PlayerOwnsCharacter(player, prefab)
end

function M.Rebind(player)
    local sess = SessionFor(player)
    if sess == nil or player == nil or not player:IsValid() then return false end
    if sess.portal_reroll and sess.phase == nil and not player._despawning then
        sess.companion_prefab = player.prefab
        sess.companion_skin_data = SaveSkin(player)
        sess.portal_reroll = nil
    end
    if sess.phase ~= "enter" and sess.phase ~= "exit" then
        MarkPossessedPlayer(player, sess)
    end
    return true
end

function M.Recover(player)
    local sess = SessionFor(player)
    if sess == nil or not sess._needs_restore or sess.active_body == nil or sess._restore_pending
        or sess.phase ~= nil then return false end
    return RestoreActiveSession(sess, player)
end

function M.GetCommandTarget(player)
    local sess = SessionFor(player)
    local target = sess ~= nil and sess.temporary_companion or nil
    return target ~= nil and target:IsValid() and target or nil
end

function M.SaveWorld(world, data)
    local sessions = world ~= nil and world._my_friend_possessions or nil
    if data == nil then return end
    local saved = {}
    for userid, sess in pairs(sessions or {}) do
        CaptureActiveSession(sess, FindPossessingPlayer(userid))
        local friend = sess.temporary_companion
        if friend ~= nil and friend:IsValid() then
            sess.player_skin_data = SaveSkin(friend)
            sess.player_body.inv = CaptureInventory(friend)
            sess.player_body.meters = SaveMeters(friend)
            sess.player_body.skill_data = SaveSkillTree(friend)
            sess.companion_pet_data = friend.components.petleash ~= nil
                and friend.components.petleash:OnSave() or nil
        end
        local copy = {}
        for key, value in pairs(sess) do
            if key ~= "temporary_companion" and key ~= "restored_companion"
                and key ~= "companion_pets" and key ~= "_despawn_task"
                and key ~= "_restore_pending" and key ~= "_needs_restore"
                and key ~= "parked_friend" then
                copy[key] = value
            end
        end
        saved[userid] = copy
    end
    data.my_friend_possessions = saved
end

function M.LoadWorld(world, data)
    world._my_friend_possessions = data ~= nil and data.my_friend_possessions or {}
    for _, sess in pairs(world._my_friend_possessions) do
        sess._needs_restore = sess.active_body ~= nil or nil
    end
end

function M.OnCharacterReroll(player)
    local sess = SessionFor(player)
    if sess == nil or sess.phase ~= nil then return end
    -- A portal character choice must not restore a stale autosave snapshot.
    sess.active_body, sess.active_position = nil, nil
    sess.active_prefab, sess.active_skin_data = nil, nil
    sess._needs_restore = nil
    sess.portal_reroll = true
    sess.was_following = false
    sess.friend_staying = true
    local friend = sess.temporary_companion
    if friend ~= nil and friend:IsValid() then
        sess.friend_home = friend._my_friend_home
    end
end

local function RecoverSavedSessions(world)
    local sessions = world ~= nil and world._my_friend_possessions or nil
    if sessions == nil then return end
    for userid, sess in pairs(sessions) do
        local player = FindOnlinePlayer(userid)
        if sess ~= nil and sess._needs_restore and sess.active_body ~= nil and player ~= nil then
            -- The session was saved while the player was controlling the
            -- companion. Keep that body and its inventory instead of
            -- unwinding the possession back to the original character.
            player:DoStaticTaskInTime(1, function(inst) M.Recover(inst) end)
        elseif sess ~= nil and (sess.companion_record ~= nil or sess.record ~= nil
            or sess.companion_prefab ~= nil) and sess.active_body == nil then
            -- Compatibility for saves made before active possession state
            -- was persisted: safely return the parked companion once.
            RestoreCompanion(sess, sess.companion_body,
                sess.position ~= nil and sess.position.x or 0,
                sess.position ~= nil and sess.position.z or 0,
                sess.companion_record or sess.record, false)
            sessions[userid] = nil
            if player ~= nil and player.components ~= nil
                and player.components.seamlessplayerswapper ~= nil then
                _G.pcall(function()
                    player.components.seamlessplayerswapper:SwapBackToMainCharacter()
                end)
            end
        end
    end
end

RestoreCompanion = function(sess, body, x, z, record, is_player_body)
    record = record or (sess ~= nil and (sess.companion_record or sess.record) or nil)
    if sess == nil then return nil end
    local friend
    if is_player_body and _G.SpawnPrefab ~= nil then
        friend = _G.SpawnPrefab(sess.player_prefab)
    elseif _G.SpawnSaveRecord ~= nil then
        -- Older sessions contain a full save record.  New sessions use the
        -- much cheaper prefab path below, because serializing a live
        -- companion's entire entity graph is what made possession hitch.
        if record ~= nil then friend = _G.SpawnSaveRecord(record) end
        if friend == nil and sess.companion_prefab ~= nil then
            friend = _G.SpawnPrefab(sess.companion_prefab)
        end
    elseif _G.SpawnPrefab ~= nil and sess.companion_prefab ~= nil then
        friend = _G.SpawnPrefab(sess.companion_prefab)
    end
    if friend == nil then return nil end
    if sess.companion_id ~= nil then
        friend._my_friend_id = sess.companion_id
    end
    if friend.Physics ~= nil then
        friend.Physics:Teleport(x, 0, z)
    elseif friend.Transform ~= nil then
        friend.Transform:SetPosition(x, 0, z)
    end
    LoadInventory(friend, body ~= nil and body.inv or nil)
    LoadMeters(friend, body ~= nil and body.meters or nil)
    if M.ConfigureCompanion ~= nil then
        friend._my_friend_custom_name = body ~= nil and body.custom_name or nil
        M.ConfigureCompanion(friend)
    end
    ApplySkillTree(friend, body ~= nil and body.skill_data or nil)
    LoadAffinity(friend, sess.restore_affinity or sess.companion_affinity)
    if is_player_body and sess.player_skin_data ~= nil then
        require("my_friend_replication").RestoreSkin(friend, {
            my_friend_skin = sess.player_skin_data,
        })
    elseif not is_player_body and sess.companion_skin_data ~= nil then
        require("my_friend_replication").RestoreSkin(friend, {
            my_friend_skin = sess.companion_skin_data,
        })
    end
    local world = World()
    if world ~= nil then world._my_friend = friend end
    if sess.friend_home ~= nil then
        friend._my_friend_home = {
            x = sess.friend_home.x,
            z = sess.friend_home.z,
            mode = sess.friend_home.mode,
        }
        require("my_friend_home").Apply(friend)
    end
    if sess.friend_staying ~= nil then
        local affinity = friend.components ~= nil and friend.components.my_friend_affinity or nil
        local follower = friend.components ~= nil and friend.components.follower or nil
        if affinity ~= nil then
            affinity.staying = sess.friend_staying == true
            affinity.requests = affinity.requests or {}
        end
        if follower ~= nil and affinity ~= nil and affinity.staying then
            follower:SetLeader(nil)
        end
        friend._my_friend_replan_requested = true
    end
    return friend
end

local function FinishRestoredSession(sess, player)
    if sess == nil or player == nil or not player:IsValid()
        or sess.active_body == nil then return end
    local world = World()
    local body = sess.active_body
    LoadInventory(player, body.inv)
    LoadMeters(player, body.meters)
    ApplySkillTree(player, body.skill_data)
    if sess.active_position ~= nil and player.Physics ~= nil then
        player.Physics:Teleport(sess.active_position.x, 0, sess.active_position.z)
    end
    if sess.active_skin_data ~= nil then
        require("my_friend_replication").RestoreSkin(player, {
            my_friend_skin = sess.active_skin_data,
        })
    end
    MarkPossessedPlayer(player, sess)
    sess._restore_pending = true
    if world ~= nil then world._my_friend_possession_active = true end
    player:DoTaskInTime(.1, function(inst)
        if not inst:IsValid() or SessionFor(inst) ~= sess then return end
        sess.phase = nil
        local currentx, _, currentz = inst.Transform:GetWorldPosition()
        local px = sess.player_position ~= nil and sess.player_position.x or currentx
        local pz = sess.player_position ~= nil and sess.player_position.z or currentz
        sess.temporary_companion = RestoreCompanion(sess, sess.player_body,
            px, pz,
            nil, true)
        if sess.temporary_companion ~= nil then
            RestoreCompanionPets(sess.temporary_companion, sess)
            sess.temporary_companion.persists = false
            if sess.was_following and sess.temporary_companion.components ~= nil
                and sess.temporary_companion.components.follower ~= nil then
                sess.temporary_companion.components.follower:SetLeader(inst)
            end
        end
        sess.active_body = nil
        sess.active_position = nil
        sess.active_prefab = nil
        sess.active_skin_data = nil
        sess._restore_pending = nil
        sess._needs_restore = nil
        if world ~= nil then world._my_friend_possession_active = nil end
    end)
end

RestoreActiveSession = function(sess, player)
    if sess == nil or player == nil or not player:IsValid()
        or sess.active_body == nil or sess._restore_pending
        or sess.phase ~= nil then return false end
    local prefab = sess.active_prefab or sess.companion_prefab
    if prefab == nil then return false end
    if player.prefab == prefab then
        FinishRestoredSession(sess, player)
        return true
    end
    sess.phase = "reload_enter"
    local skin = sess.active_skin_data ~= nil
        and sess.active_skin_data.skin_name or sess.companion_skin
    if not StartSwap(player, prefab, skin, true) then
        sess.phase = nil
        return false
    end
    sess._restore_pending = true
    return true
end

local function FinishSwap(_, player)
    if player == nil or player.userid == nil then return end
    local sess = SessionFor(player)
    if sess == nil then return end
    local sw = player.components ~= nil and player.components.seamlessplayerswapper or nil
    if sw ~= nil then sw._my_friend_swap_in_progress = nil end

    if sess.phase == "reload_enter" then
        FinishRestoredSession(sess, player)
    elseif sess.phase == "enter" then
        sess.phase = "enter_ready"
        LoadInventory(player, sess.companion_body ~= nil and sess.companion_body.inv or nil)
        LoadMeters(player, sess.companion_body ~= nil and sess.companion_body.meters or nil)
        ApplySkillTree(player, sess.companion_skill_data)
        if sess.companion_skin_data ~= nil then
            require("my_friend_replication").RestoreSkin(player, {
                my_friend_skin = sess.companion_skin_data,
            })
        end
        MarkPossessedPlayer(player, sess)
        local world = World()
        if world ~= nil then world._my_friend_possession_active = true end
        player:DoTaskInTime(.1, function(inst)
            if not inst:IsValid() or SessionFor(inst) ~= sess then return end
            sess.phase = nil
            sess.temporary_companion = RestoreCompanion(sess, sess.player_body,
                sess.player_position.x, sess.player_position.z, nil, true)
            if sess.temporary_companion ~= nil then
                RestoreCompanionPets(sess.temporary_companion, sess)
                require("my_friend_dialogue").RandomReply(sess.temporary_companion, "body_exchanged")
                sess.temporary_companion.persists = false
                if sess.was_following and sess.temporary_companion.components ~= nil
                    and sess.temporary_companion.components.follower ~= nil then
                    sess.temporary_companion.components.follower:SetLeader(inst)
                end
            end
            if sess.parked_friend ~= nil and sess.parked_friend:IsValid() then
                sess.parked_friend.persists = false
                sess.parked_friend:Remove()
                sess.parked_friend = nil
            end
            if world ~= nil then
                world._my_friend_possession_active = nil
            end
        end)
    elseif sess.phase == "exit" then
        sess.phase = "exit_ready"
        player:DoTaskInTime(.1, function(inst)
            if not inst:IsValid() or SessionFor(inst) ~= sess then return end
            LoadInventory(inst, sess.player_body ~= nil and sess.player_body.inv or nil)
            LoadMeters(inst, sess.player_body ~= nil and sess.player_body.meters or nil)
            require("my_friend_replication").RestoreSkin(inst, {my_friend_skin = sess.player_skin_data})
            ApplySkillTree(inst, sess.player_body ~= nil and sess.player_body.skill_data or nil)
            if sess.release_position ~= nil and inst.Physics ~= nil then
                inst.Physics:Teleport(sess.release_position.x, 0, sess.release_position.z)
            end
            if inst.components ~= nil and inst.components.named ~= nil
                and sess.player_name ~= nil then
                inst.components.named:SetName(sess.player_name)
            end
            sess.restored_companion = RestoreCompanion(sess, sess.release_body,
                sess.release_position ~= nil and sess.release_position.x or
                    sess.player_position.x,
                sess.release_position ~= nil and sess.release_position.z or
                    sess.player_position.z,
                sess.companion_record, false)
            RestoreCompanionPets(sess.restored_companion, sess)
            if sess.restored_companion ~= nil then
                require("my_friend_dialogue").RandomReply(sess.restored_companion, "body_exchanged")
            end
            if sess.restored_companion ~= nil and sess.restored_companion:IsValid()
                and sess.was_following and sess.restored_companion.components ~= nil
                and sess.restored_companion.components.follower ~= nil then
                sess.restored_companion.components.follower:SetLeader(inst)
            end
            inst:RemoveTag("my_friend_possessing")
            inst:RemoveTag("my_friend_possessed")
            inst._my_friend_id = nil
            require("my_friend_wortox").RefreshLinkedHearts(sess.restored_companion)
            inst._my_friend_custom_name = nil
            inst._my_friend_possessed_name = nil
            inst._my_friend_possessed_prefab = nil
            local sessions = Sessions()
            if sessions ~= nil then sessions[inst.userid] = nil end
        end)
    else
        -- A normal character change while possessing creates another player
        -- entity. Keep the possession marker and reconnect the parked AI body
        -- so the player can still release or issue companion commands.
        MarkPossessedPlayer(player, sess)
    end
end

function M.Init(world)
    if world == nil or not world.ismastersim or world._my_friend_possess_init then return end
    world._my_friend_possess_init = true
    world._my_friend_possessions = world._my_friend_possessions or {}
    world:ListenForEvent("ms_seamlesscharacterspawned", FinishSwap)
    world:ListenForEvent("ms_playerdespawn", function(_, player)
        local sess = SessionFor(player)
        if sess == nil or sess._despawn_task ~= nil then return end
        -- Character changes can briefly despawn the old player entity before
        -- the replacement is present.  Defer cleanup and keep the session if
        -- the same userid appears again.
        sess._despawn_task = world:DoTaskInTime(.5, function()
            sess._despawn_task = nil
            if Sessions() == nil or Sessions()[player.userid] ~= sess then return end
            local replacement = FindOnlinePlayer(player.userid, player)
            if replacement ~= nil then
                MarkPossessedPlayer(replacement, sess)
                return
            end
            local x, z = sess.position.x, sess.position.z
            if player ~= nil and player:IsValid() and player.Transform ~= nil then
                local px, _, pz = player.Transform:GetWorldPosition()
                x, z = px, pz
            end
            if player ~= nil and player:IsValid() then
                sess.companion_skill_data = SaveSkillTree(player)
            end
            local body = (player ~= nil and player:IsValid())
                and {inv = SaveInventory(player),
                    meters = SaveMeters(player),
                    custom_name = sess.companion_custom_name,
                    skill_data = SaveSkillTree(player)}
                or sess.companion_body
            if sess.temporary_companion ~= nil and sess.temporary_companion:IsValid() then
                sess.temporary_companion.persists = false
                sess.temporary_companion:Remove()
            end
            RestoreCompanion(sess, body, x, z, sess.companion_record, false)
            local sessions = Sessions()
            if sessions ~= nil then sessions[player.userid] = nil end
        end)
    end)
    world:DoTaskInTime(1, function()
        RecoverSavedSessions(world)
    end)
end

function M.Possess(player, friend)
    if player == nil or not player:IsValid() or player.userid == nil
        or friend == nil or not friend:IsValid() then return false end
    if M.IsPossessing(player) or player:HasTag("my_friend_possessing") then return false end
    if player.components == nil or player.components.seamlessplayerswapper == nil
        or not friend:HasTag("my_friend") or friend:HasTag("playerghost")
        or friend.components == nil then return false end
    if not PlayerOwnsCharacter(player, friend.prefab) then return false end
    local world = World()
    if world == nil or not world.ismastersim then return false end
    local follower = friend.components.follower
    if follower ~= nil and follower:GetLeader() ~= nil and follower:GetLeader() ~= player then
        return false
    end

    local x, _, z = friend.Transform:GetWorldPosition()
    local px, _, pz = player.Transform:GetWorldPosition()
    local skinner = friend.components.skinner
    local was_following = follower ~= nil and follower:GetLeader() == player
    local affinity = friend.components.my_friend_affinity
    local clothing = skinner ~= nil and skinner:GetClothing() or nil
    local safe_companion_skin = SafeSkinForPlayer(player, friend.prefab,
        skinner ~= nil and skinner.skin_name or nil)
    local companion_pets = DetachCompanionPets(friend)
    local sessions = Sessions()
    if sessions == nil then return false end

    require("my_friend_commands").Clear(friend)
    if follower ~= nil then follower:SetLeader(nil) end

    local session = {
        phase = "enter",
        companion_name = friend:GetDisplayName(),
        companion_custom_name = friend._my_friend_custom_name,
        friend_staying = affinity ~= nil and affinity.staying == true or false,
        companion_prefab = friend.prefab,
        companion_id = friend._my_friend_id,
        companion_skin = safe_companion_skin,
        companion_skin_data = {
            owner = friend._my_friend_skin_owner or player.userid,
            skin_name = safe_companion_skin,
            clothing = SafeClothingForPlayer(player, clothing),
            skin_mode = skinner ~= nil and skinner.skintype or nil,
        },
        companion_body = {
            inv = SaveInventory(friend),
            meters = SaveMeters(friend),
            custom_name = friend._my_friend_custom_name,
            skill_data = SaveSkillTree(friend),
        },
        companion_affinity = SaveAffinity(friend),
        player_body = {
            inv = SaveInventory(player),
            meters = SaveMeters(player),
            -- The autonomous body represents the companion while the player
            -- is controlling the companion body, so keep the companion name
            -- on that entity instead of leaking the player's name into it.
            custom_name = friend._my_friend_custom_name or friend:GetDisplayName(),
            skill_data = SaveSkillTree(player),
        },
        companion_skill_data = SaveSkillTree(friend),
        player_prefab = player.prefab,
        player_name = player.name,
        was_following = was_following,
        -- Keep the swap snapshot lightweight.  A full GetSaveRecord() of a
        -- live companion serializes a large entity graph and causes a visible
        -- server hitch.  Inventory, meters, affinity, skin and home state are
        -- already captured explicitly above.
        companion_record = nil,
        companion_position = {x = x, z = z},
        friend_home = friend._my_friend_home ~= nil and {
            x = friend._my_friend_home.x,
            z = friend._my_friend_home.z,
            mode = friend._my_friend_home.mode,
        } or nil,
        player_skin_data = player.components.skinner ~= nil and {
            owner = player._my_friend_skin_owner or player.userid,
            skin_name = player.components.skinner.skin_name,
            clothing = player.components.skinner:GetClothing(),
            skin_mode = player.components.skinner.skintype,
        } or nil,
        player_position = {x = px, z = pz},
        position = {x = x, z = z},
        companion_pets = companion_pets,
    }
    sessions[player.userid] = session
    world._my_friend_possession_active = true
    -- Keep the old body valid until the native replacement event arrives.
    -- Removing it first leaves remote clients with a target they can still
    -- have selected for one or two frames.
    friend.persists = false
    friend._my_friend_possess_parked = true
    if friend.Physics ~= nil then friend.Physics:SetActive(false) end
    if friend.DynamicShadow ~= nil then friend.DynamicShadow:Enable(false) end
    if friend.MiniMapEntity ~= nil then friend.MiniMapEntity:SetEnabled(false) end
    if friend.Hide ~= nil then friend:Hide() end
    session.parked_friend = friend
    world._my_friend = nil
    if player.Physics ~= nil then player.Physics:Teleport(x, 0, z) end
    if not StartSwap(player, session.companion_prefab, session.companion_skin) then
        if session.parked_friend ~= nil and session.parked_friend:IsValid() then
            session.parked_friend.persists = false
            session.parked_friend:Remove()
            session.parked_friend = nil
        end
        local restored = RestoreCompanion(session, session.companion_body, x, z,
            session.companion_record, false)
        AttachCompanionPets(restored, session.companion_pets)
        if restored ~= nil and session.was_following
            and restored.components ~= nil and restored.components.follower ~= nil then
            restored.components.follower:SetLeader(player)
        end
        LoadInventory(player, session.player_body.inv)
        LoadMeters(player, session.player_body.meters)
        world._my_friend_possession_active = nil
        sessions[player.userid] = nil
        return false
    end
    return true
end

function M.Release(player)
    local sess = SessionFor(player)
    if sess == nil or sess.phase ~= nil or player == nil or not player:IsValid() then
        return false
    end
    local x, _, z = player.Transform:GetWorldPosition()
    sess.companion_skill_data = SaveSkillTree(player)
    sess.companion_skin_data = SaveSkin(player)
    sess.companion_prefab = player.prefab
    local body = {inv = SaveInventory(player), meters = SaveMeters(player),
        skill_data = sess.companion_skill_data}
    local temporary = sess.temporary_companion
    local affinity = temporary ~= nil and temporary.components ~= nil
        and temporary.components.my_friend_affinity or nil
    if affinity ~= nil then
        sess.restore_affinity = SaveAffinity(temporary)
        sess.friend_staying = affinity.staying == true
    end
    if temporary ~= nil and temporary.components ~= nil
        and temporary.components.follower ~= nil then
        sess.was_following = temporary.components.follower:GetLeader() == player
    end
    if temporary ~= nil and temporary._my_friend_home ~= nil then
        sess.friend_home = {
            x = temporary._my_friend_home.x,
            z = temporary._my_friend_home.z,
            mode = temporary._my_friend_home.mode,
        }
    end
    if temporary ~= nil and temporary:IsValid() then
        sess.player_skin_data = SaveSkin(temporary)
        sess.player_body.inv = SaveInventory(temporary)
        sess.player_body.meters = SaveMeters(temporary)
        sess.player_body.skill_data = SaveSkillTree(temporary)
        sess.companion_pets = DetachCompanionPets(temporary)
        temporary.persists = false
        temporary:Remove()
    end
    body.custom_name = sess.companion_custom_name
    sess.release_body = body
    sess.release_position = {x = x, z = z}
    sess.phase = "exit"
    -- A character change made while possessing can overwrite the vanilla
    -- swapper's main_data with the companion prefab. Restore the original
    -- player's identity before requesting the return swap.
    local sw = player.components ~= nil and player.components.seamlessplayerswapper or nil
    if sw ~= nil then
        sw.main_data = sw.main_data or {}
        sw.main_data.prefab = sess.player_prefab
        sw.main_data.skin_base = sess.player_skin_data ~= nil
            and sess.player_skin_data.skin_name or nil
    end
    if not StartSwap(player, nil, nil) then
        sess.phase = nil
        return false
    end
    return true
end

return M
