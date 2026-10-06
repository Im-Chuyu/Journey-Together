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
local WX78 = require("my_friend_wx78")
local Abigail = require("my_friend_abigail")
local InventoryTransfer = require("my_friend_inventory_transfer")

local function DefaultSkin(prefab)
    -- Vanilla characters have a registered prefab skin table and accept the
    -- explicit <prefab>_none identifier. Mod characters may not, so preserve
    -- the old nil behaviour for them.
    if type(prefab) ~= "string" or Characters.IsModCharacter(prefab) then return nil end
    return (PREFAB_SKINS == nil or PREFAB_SKINS[prefab] ~= nil)
        and prefab .. "_none" or nil
end

local function PlayerOwnsCharacter(player, prefab)
    if player == nil or type(prefab) ~= "string" then return false end
    if player.prefab == prefab or not Characters.IsPaid(prefab) then return true end
    local reported = _G.MyFriendOwnedCharacters ~= nil
        and _G.MyFriendOwnedCharacters[player.userid] or nil
    return reported ~= nil and reported[prefab] == true
end

local function SafeSkinForPlayer(player, prefab, skin)
    local default = DefaultSkin(prefab)
    if type(skin) ~= "string" or skin == "" or skin == prefab
        or skin == prefab .. "_none" then return default end
    local owned = _G.MyFriendSkinNames ~= nil
        and _G.MyFriendSkinNames[player.userid] or nil
    return owned ~= nil and owned[skin] == true and skin or default
end

-- Skin data captured from an entity has already passed the server-side
-- wardrobe validation. Do not require the asynchronous client ownership
-- report again during a body exchange; it may not have arrived yet after
-- joining or reopening the wardrobe. Reject only a skin for another prefab.
local function SkinBelongsToCharacter(prefab, skin)
    if type(prefab) ~= "string" or type(skin) ~= "string" or skin == "" then return false end
    if skin == prefab or skin == prefab .. "_none" then return true end
    local data = type(GetSkinData) == "function" and GetSkinData(skin) or nil
    if type(data) == "table" and type(data.base_prefab) == "string" then
        return data.base_prefab == prefab
    end
    return skin:sub(1, #prefab + 1) == prefab .. "_"
end

local function SkinForBody(player, prefab, skin)
    return SkinBelongsToCharacter(prefab, skin)
        and skin or SafeSkinForPlayer(player, prefab, skin)
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

function M.HasSessions()
    return next(Sessions() or {}) ~= nil
end

function M.SessionOwner(friend)
    if friend == nil then return end
    for userid, sess in pairs(Sessions() or {}) do
        if sess.temporary_companion == friend or sess.parked_friend == friend then
            return userid
        end
    end
end

local function IsLiving(inst)
    return inst ~= nil and inst:IsValid() and not inst._despawning
        and not inst.is_snapshot_user_session
        and not inst:HasTag("playerghost") and not inst:HasTag("corpse")
        and inst.components ~= nil and inst.components.health ~= nil
        and not inst.components.health:IsDead()
end

local function CanStartSwap(player, prefab, trusted)
    local sw = player ~= nil and player.components ~= nil
        and player.components.seamlessplayerswapper or nil
    return IsLiving(player) and player.userid ~= nil and player.userid ~= ""
        and player.components.skinner ~= nil and player.components.inventory ~= nil
        and sw ~= nil and not sw._my_friend_swap_in_progress
        and type(sw._StartSwap) == "function"
        and (prefab == nil or Characters.IsCharacter(prefab)
            and (trusted or PlayerOwnsCharacter(player, prefab)))
end

local SaveAndClearInventory = InventoryTransfer.SaveAndClear
local CaptureInventory = InventoryTransfer.Capture
local LoadInventory = InventoryTransfer.Load

local function DetachCompanionPets(inst)
    local pets = {}
    local leash = inst ~= nil and inst.components ~= nil and inst.components.petleash or nil
    if leash == nil then return pets end
    for pet in pairs(leash:GetPets() or {}) do
        if pet ~= nil and pet:IsValid() then
            pets[#pets + 1] = pet
            leash:DetachPet(pet)
            -- The session owns the saved pet record during the handover.
            -- Saving it independently too would duplicate it after a reload.
            pet.persists = false
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
        ghost = inst ~= nil and (inst:HasTag("playerghost")
            or c ~= nil and c.health ~= nil and c.health:IsDead()) or nil,
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
    if data.ghost and not inst:HasTag("playerghost") then
        inst:PushEvent("makeplayerghost", {loading = true})
    end
    if not data.ghost and data.health ~= nil and inst.components.health ~= nil then
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

local function LoadBodyTraits(inst, body, skill_data)
    if body ~= nil and body.wx78 ~= nil and inst.prefab == "wx78" then
        LoadMeters(inst, body.meters)
        if body.wx78.sockets ~= nil then WX78.TakeSockets(inst) end
        ApplySkillTree(inst, skill_data or body.skill_data)
        WX78.Load(inst, body.wx78, function() LoadMeters(inst, body.meters) end)
    else
        LoadMeters(inst, body ~= nil and body.meters or nil)
        ApplySkillTree(inst, skill_data or body ~= nil and body.skill_data or nil)
    end
    Abigail.LoadBody(inst, body ~= nil and body.abigail or nil)
end

local function SaveSkin(inst)
    local skinner = inst.components.skinner
    if skinner == nil then return end
    local clothing = skinner:GetClothing()
    local skin_name = skinner.skin_name
    if (type(skin_name) ~= "string" or skin_name == "") and clothing ~= nil then
        skin_name = clothing.base
    end
    return {skin_name = skin_name, clothing = clothing,
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

-- Only serializable memory, never live entity references. The base module
-- includes manual homes, automatic sites and temporary waiting memory.
local function CaptureCompanionState(sess, friend)
    if friend == nil or not friend:IsValid() then return end
    local memory = {}
    require("my_friend_base_ai").OnSave(friend, memory)
    sess.friend_memory = deepcopy(memory)
    sess.friend_home = sess.friend_memory.my_friend_home -- old-save compatibility
    sess.friend_shard_homes = deepcopy(friend._my_friend_shard_homes)
    sess.friend_switch_used = friend._my_friend_switch_used
    sess.restore_affinity = deepcopy(SaveAffinity(friend))
    local affinity = friend.components.my_friend_affinity
    sess.friend_staying = affinity ~= nil and affinity.staying == true or false
    local follower = friend.components.follower
    local leader = follower ~= nil and follower:GetLeader() or nil
    sess.friend_leader_userid = leader ~= nil and leader:IsValid() and leader.userid or nil
    sess.was_following = sess.friend_leader_userid ~= nil
        and sess.friend_leader_userid == sess.userid
    sess.companion_custom_name = friend._my_friend_custom_name
    sess.companion_name = friend:GetDisplayName()
end

local function CaptureTemporary(sess)
    local friend = sess.temporary_companion
    if friend == nil or not friend:IsValid() then return end
    CaptureCompanionState(sess, friend)
    local x, _, z = friend.Transform:GetWorldPosition()
    sess.player_position = {x = x, z = z}
    sess.player_prefab = friend.prefab
    sess.temporary_companion_id = friend._my_friend_id
    sess.player_skin_data = SaveSkin(friend)
    sess.player_body = {
        inv = CaptureInventory(friend), meters = SaveMeters(friend),
        skill_data = SaveSkillTree(friend), custom_name = friend._my_friend_custom_name,
        wx78 = WX78.Save(friend),
        abigail = Abigail.SaveBody(friend),
    }
    sess.companion_pet_data = friend.components.petleash ~= nil
        and friend.components.petleash:OnSave() or nil
end

local function CopySession(sess)
    local copy = {}
    for key, value in pairs(sess) do
        if key ~= "temporary_companion" and key ~= "restored_companion"
            and key ~= "companion_pets" and key ~= "_despawn_task"
            and key ~= "_restore_pending" and key ~= "_needs_restore"
            and key ~= "_from_save"
            and key ~= "parked_friend" then
            copy[key] = value
        end
    end
    if sess.phase ~= nil and sess.phase ~= "reload_enter" then
        copy.active_body = sess.release_body or sess.companion_body
        copy.active_prefab = sess.companion_prefab
        copy.active_position = sess.release_position or sess.companion_position
        copy.active_skin_data = sess.companion_skin_data
    end
    copy.phase = nil
    return copy
end

local function StartSwap(player, prefab, skin, trusted)
    if not CanStartSwap(player, prefab, trusted) then return false end
    local sw = player.components.seamlessplayerswapper
    local old_main, old_swap = deepcopy(sw.main_data), deepcopy(sw.swap_data)
    sw._my_friend_swap_in_progress = true
    if prefab ~= nil then
        sw.swap_data = sw.swap_data or {}
        -- SeamlessPlayerSwapper treats nil as "reuse whatever the current
        -- body reports". Always send an explicit target-character skin so a
        -- body exchange cannot inherit the previous body's default build.
        local target_skin = SkinForBody(player, prefab, skin)
        sw.swap_data[prefab] = {
            skin_base = target_skin or DefaultSkin(prefab),
        }
    end
    -- Finish a spawn fade while its controller still exists. Native swapping
    -- removes that controller before the old body is actually removed.
    local tween = player.components.colourtweener
    if tween ~= nil and tween:IsTweening() and tween.t_colour_r == 1
        and tween.t_colour_g == 1 and tween.t_colour_b == 1 then
        tween:EndTween()
    end
    -- Native player reroll ejects socketed implants. Their body snapshot
    -- already owns the records, so remove them before that callback can drop
    -- a second copy into the world.
    local sockets = WX78.TakeSockets(player)
    local ok, err = _G.pcall(function()
        sw:_StartSwap(prefab)
    end)
    if not ok then
        print("[MyFriends] Body exchange request failed: " .. tostring(err))
        sw.main_data, sw.swap_data = old_main, old_swap
        sw._my_friend_swap_in_progress = nil
        WX78.LoadSockets(player, sockets)
        return false
    end
    Abigail.RemoveSource(player)
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
            and not player._despawning and not player.is_snapshot_user_session
            and not player:HasTag("my_friend") and player.userid == userid then
            return player
        end
    end
    return nil
end

local function RestoreLeader(friend, sess, player)
    if friend == nil or not friend:IsValid() or sess.friend_staying then return end
    local leader = sess.was_following and player
        or FindOnlinePlayer(sess.friend_leader_userid)
    if leader ~= nil and leader:IsValid() and friend.components.follower ~= nil then
        friend.components.follower:SetLeader(leader)
    end
end

local function FindPossessingPlayer(userid)
    if userid == nil then return nil end
    for _, player in ipairs(_G.AllPlayers or {}) do
        if player ~= nil and player:IsValid() and not player._despawning
            and not player.is_snapshot_user_session
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
    sess.active_body = {
        inv = CaptureInventory(player),
        meters = SaveMeters(player),
        skill_data = SaveSkillTree(player),
        wx78 = WX78.Save(player),
        abigail = Abigail.SaveBody(player),
    }
    sess.active_position = {x = x, z = z}
    sess.active_prefab = player.prefab
    sess.active_skin_data = SaveSkin(player)
end

-- A seamless character change replaces the player entity.  Keep the
-- possession marker and the parked companion attached to the replacement so
-- the center wheel can release or continue the same session.
local function UseBodySpeech(player)
    local talker = player.components ~= nil and player.components.talker or nil
    if talker ~= nil and Characters.IsCharacter(player.prefab) then
        -- Native swapping keeps the original character's dialogue for Wonkey.
        -- A full body exchange needs the new character's exclusive lines;
        -- the old table contains only_used_by_* placeholders for those skills.
        talker.speechproxy = nil
    end
end

local function MarkPossessedPlayer(player, sess)
    if player == nil or not player:IsValid() or sess == nil then return end
    UseBodySpeech(player)
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
    RestoreLeader(sess.temporary_companion, sess, player)
end

function M.IsPossessing(player)
    return SessionFor(player) ~= nil
end

function M.CanUseCompanionCharacter(player, prefab)
    return PlayerOwnsCharacter(player, prefab)
end

function M.Rebind(player)
    local sess = SessionFor(player)
    if sess == nil or player == nil or not player:IsValid()
        or player._despawning or player.is_snapshot_user_session then return false end
    if sess.phase == nil then CaptureTemporary(sess) end
    if (sess.portal_reroll or sess.player_migrated) and sess.phase == nil and not player._despawning then
        -- A player returning alone from another shard brings the current body
        -- and inventory in their native save. Do not apply the departure copy.
        sess.active_body, sess.active_position = nil, nil
        sess.active_prefab, sess.active_skin_data = nil, nil
        sess._needs_restore = nil
        sess.companion_prefab = player.prefab
        sess.companion_skin_data = SaveSkin(player)
        sess.portal_reroll, sess.player_migrated = nil, nil
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

-- Character changes can be requested for the autonomous body while the
-- player is controlling the companion.  The farewell code removes that body
-- and creates its replacement, so keep the possession session pointed at the
-- replacement.  Otherwise Release() cannot remove it and creates a second
-- companion from the controlled body.
function M.ReplaceTemporaryCompanion(old, replacement)
    if old == nil or replacement == nil or not replacement:IsValid() then return false end
    for _, sess in pairs(Sessions() or {}) do
        if sess ~= nil and sess.temporary_companion == old then
            sess.temporary_companion = replacement
            -- Possession owns this body until Release() completes.  It must
            -- not be persisted as an independent main companion.
            replacement.persists = false
            CaptureTemporary(sess)
            return true
        end
    end
    return false
end

function M.SaveWorld(world, data)
    local sessions = world ~= nil and world._my_friend_possessions or nil
    if data == nil then return end
    local saved = {}
    for userid, sess in pairs(sessions or {}) do
        CaptureActiveSession(sess, FindPossessingPlayer(userid))
        CaptureTemporary(sess)
        -- A save can land inside the native asynchronous handover. Persist
        -- both bodies as a recoverable active session, never a stranded phase.
        saved[userid] = CopySession(sess)
    end
    data.my_friend_possessions = saved
end

function M.LoadWorld(world, data)
    world._my_friend_possessions = data ~= nil and data.my_friend_possessions or {}
    for userid, sess in pairs(world._my_friend_possessions) do
        sess.userid = userid
        sess._from_save = true
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
        CaptureTemporary(sess)
    end
end

-- Follow the travelling AI body through the player's existing migration
-- component. Leaving its session on the source shard would later recreate a
-- duplicate there and leave the destination unable to release the exchange.
function M.CaptureMigration(player, friend)
    local sess = SessionFor(player)
    if sess == nil or sess.phase ~= nil or sess.temporary_companion ~= friend then return end
    CaptureActiveSession(sess, player)
    CaptureTemporary(sess)
    local saved = deepcopy(CopySession(sess))
    Sessions()[player.userid] = nil
    return saved
end

function M.RestoreMigration(player, saved, friend)
    if saved == nil or player == nil or not player:IsValid()
        or saved.userid ~= player.userid or friend == nil or not friend:IsValid()
        or (saved.temporary_companion_id or saved.companion_id) ~= friend._my_friend_id then return false end
    local sessions = Sessions()
    if sessions == nil or next(sessions) ~= nil and sessions[player.userid] == nil then return false end
    saved.phase, saved._needs_restore, saved._restore_pending = nil, nil, nil
    saved.active_body, saved.active_position = nil, nil
    saved.active_prefab, saved.active_skin_data = nil, nil
    saved.temporary_companion = friend
    sessions[player.userid] = saved
    friend.persists = false
    CaptureTemporary(saved) -- use the destination shard's base memory
    MarkPossessedPlayer(player, saved)
    return true
end

local function RestoreTemporary(sess, player)
    local friend = sess.temporary_companion
    if friend ~= nil and friend:IsValid() then
        RestoreLeader(friend, sess, player)
        return friend
    end
    local point = sess.player_position or sess.position or {x = 0, z = 0}
    friend = RestoreCompanion(sess, sess.player_body, point.x, point.z, nil, true)
    sess.temporary_companion = friend
    if friend ~= nil then
        friend.persists = false
        RestoreCompanionPets(friend, sess)
        RestoreLeader(friend, sess, player)
    end
    return friend
end

local function AfterSwap(sess, player, callback)
    -- An entity-owned task is cancelled if the player disconnects during the
    -- 0.1s handover. Use the world so session locks always get cleaned up.
    local world = World()
    world:DoTaskInTime(.1, function()
        if Sessions()[sess.userid or player.userid] ~= sess then return end
        if not player:IsValid() or player._despawning then
            local saved = CopySession(sess)
            sess.active_body = saved.active_body
            sess.active_position = saved.active_position
            sess.active_prefab = saved.active_prefab
            sess.active_skin_data = saved.active_skin_data
            sess.phase, sess._restore_pending = nil, nil
            sess._needs_restore = true
            RestoreTemporary(sess)
            if sess.parked_friend ~= nil and sess.parked_friend:IsValid() then
                sess.parked_friend:Remove()
            end
            sess.parked_friend = nil
            world._my_friend_possession_active = nil
            return
        end
        callback(player)
    end)
end

local function RecoverSavedSessions(world)
    local sessions = world ~= nil and world._my_friend_possessions or nil
    if sessions == nil then return end
    for userid, sess in pairs(sessions) do
        local player = FindOnlinePlayer(userid)
        if sess ~= nil and sess._from_save and (sess.active_body ~= nil or sess.portal_reroll) then
            RestoreTemporary(sess, player)
            -- The session was saved while the player was controlling the
            -- companion. Keep that body and its inventory instead of
            -- unwinding the possession back to the original character.
            if player ~= nil and sess._needs_restore then
                player:DoStaticTaskInTime(1, function(inst) M.Recover(inst) end)
            end
        elseif sess ~= nil and sess._from_save and (sess.companion_record ~= nil or sess.record ~= nil
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
        if sess ~= nil then sess._from_save = nil end
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
    local friend_id = is_player_body and sess.temporary_companion_id or sess.companion_id
    friend_id = friend_id or sess.companion_id
    if friend_id ~= nil then
        friend._my_friend_id = friend_id
    end
    require("my_friend_replication").ApplyDefaultAppearance(friend)
    if friend.Physics ~= nil then
        friend.Physics:Teleport(x, 0, z)
    elseif friend.Transform ~= nil then
        friend.Transform:SetPosition(x, 0, z)
    end
    LoadInventory(friend, body ~= nil and body.inv or nil)
    if M.ConfigureCompanion ~= nil then
        friend._my_friend_custom_name = body ~= nil and body.custom_name or nil
        M.ConfigureCompanion(friend)
    end
    LoadBodyTraits(friend, body)
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
    if sess.friend_memory ~= nil then
        require("my_friend_base_ai").OnLoad(friend, deepcopy(sess.friend_memory))
    elseif sess.friend_home ~= nil then
        friend._my_friend_home = {
            x = sess.friend_home.x,
            z = sess.friend_home.z,
            mode = sess.friend_home.mode,
        }
        require("my_friend_home").Apply(friend)
    end
    if sess.friend_memory ~= nil or sess.friend_shard_homes ~= nil then
        friend._my_friend_shard_homes = deepcopy(sess.friend_shard_homes)
        friend._my_friend_switch_used = sess.friend_switch_used
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
    LoadBodyTraits(player, body)
    if sess.active_position ~= nil and player.Physics ~= nil then
        player.Physics:Teleport(sess.active_position.x, 0, sess.active_position.z)
    end
    Abigail.Place(player)
    if sess.active_skin_data ~= nil then
        require("my_friend_replication").RestoreSkin(player, {
            my_friend_skin = sess.active_skin_data,
        })
    end
    MarkPossessedPlayer(player, sess)
    sess._restore_pending = true
    if world ~= nil then world._my_friend_possession_active = true end
    AfterSwap(sess, player, function(inst)
        if not inst:IsValid() or SessionFor(inst) ~= sess then return end
        RestoreTemporary(sess, inst)
        sess.phase = nil
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
    if player == nil or not player:IsValid() or player.userid == nil then return end
    local sess = SessionFor(player)
    if sess == nil then return end
    local sw = player.components ~= nil and player.components.seamlessplayerswapper or nil
    if sw ~= nil then sw._my_friend_swap_in_progress = nil end

    if sess.phase == "reload_enter" then
        FinishRestoredSession(sess, player)
    elseif sess.phase == "enter" then
        sess.phase = "enter_ready"
        LoadInventory(player, sess.companion_body ~= nil and sess.companion_body.inv or nil)
        LoadBodyTraits(player, sess.companion_body, sess.companion_skill_data)
        if sess.companion_skin_data ~= nil then
            require("my_friend_replication").RestoreSkin(player, {
                my_friend_skin = sess.companion_skin_data,
            })
        end
        MarkPossessedPlayer(player, sess)
        local world = World()
        if world ~= nil then world._my_friend_possession_active = true end
        AfterSwap(sess, player, function(inst)
            if not inst:IsValid() or SessionFor(inst) ~= sess then return end
            RestoreTemporary(sess, inst)
            if sess.temporary_companion ~= nil then
                require("my_friend_dialogue").RandomReply(sess.temporary_companion, "body_exchanged")
            end
            if sess.parked_friend ~= nil and sess.parked_friend:IsValid() then
                sess.parked_friend.persists = false
                sess.parked_friend:Remove()
                sess.parked_friend = nil
            end
            sess.phase = nil
            if world ~= nil then
                world._my_friend_possession_active = nil
            end
        end)
    elseif sess.phase == "exit" then
        sess.phase = "exit_ready"
        UseBodySpeech(player)
        AfterSwap(sess, player, function(inst)
            if not inst:IsValid() or SessionFor(inst) ~= sess then return end
            LoadInventory(inst, sess.player_body ~= nil and sess.player_body.inv or nil)
            local body = sess.player_body
            local robot = body ~= nil and body.wx78 ~= nil and inst.prefab == "wx78"
            if not robot then LoadMeters(inst, body ~= nil and body.meters or nil) end
            local skin = sess.player_skin_data
            require("my_friend_replication").RestoreSkin(inst, {my_friend_skin = {
                owner = inst.userid,
                skin_name = SkinForBody(inst, inst.prefab, skin ~= nil and skin.skin_name),
                clothing = skin ~= nil and skin.clothing or {},
                skin_mode = skin ~= nil and skin.skin_mode or nil,
            }})
            if robot then
                LoadBodyTraits(inst, body)
            else
                ApplySkillTree(inst, body ~= nil and body.skill_data or nil)
                Abigail.LoadBody(inst, body ~= nil and body.abigail or nil)
            end
            if sess.release_position ~= nil and inst.Physics ~= nil then
                inst.Physics:Teleport(sess.release_position.x, 0, sess.release_position.z)
            end
            Abigail.Place(inst)
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
            RestoreLeader(sess.restored_companion, sess, inst)
            inst:RemoveTag("my_friend_possessing")
            inst:RemoveTag("my_friend_possessed")
            inst._my_friend_id = nil
            require("my_friend_wortox").RefreshLinkedHearts(sess.restored_companion)
            inst._my_friend_custom_name = nil
            inst._my_friend_possessed_name = nil
            inst._my_friend_possessed_prefab = nil
            local sessions = Sessions()
            if sessions ~= nil then sessions[inst.userid] = nil end
            if World() ~= nil then World()._my_friend_possession_active = nil end
        end)
    else
        -- A normal character change while possessing creates another player
        -- entity. Keep the possession marker and reconnect the parked AI body
        -- so the player can still release or issue companion commands.
        MarkPossessedPlayer(player, sess)
    end
end

function M.OnPlayerDespawn(player)
    local world = World()
    if world == nil or world._my_friend_loading or player == nil
        or not player:IsValid() or player.is_snapshot_user_session then return end
    local sess = SessionFor(player)
    if sess == nil or sess.phase ~= nil then return end
    CaptureTemporary(sess)
    if not sess.portal_reroll then
        CaptureActiveSession(sess, player)
        sess._needs_restore = sess.active_body ~= nil or nil
    end
    sess.player_migrated = player._my_friend_migrating or sess.player_migrated
    -- Keep the autonomous body and its current memory. Rebuilding from the
    -- entry snapshot here duplicated items already saved in the user session
    -- and discarded everything the companion changed while being controlled.
end

function M.Init(world)
    if world == nil or not world.ismastersim or world._my_friend_possess_init then return end
    world._my_friend_possess_init = true
    world._my_friend_possessions = world._my_friend_possessions or {}
    world:ListenForEvent("ms_seamlesscharacterspawned", FinishSwap)
    world:ListenForEvent("ms_playerdespawn", function(_, player)
        M.OnPlayerDespawn(player)
    end)
    world:DoTaskInTime(1, function()
        RecoverSavedSessions(world)
    end)
end

function M.CanPossess(player, friend)
    local world = World()
    if world == nil or not world.ismastersim or world._my_friend_loading
        or world._my_friend_possession_active or M.HasSessions()
        or not IsLiving(friend) or not friend:HasTag("my_friend")
        or friend._my_friend_possess_parked or friend._my_friend_departing
        or friend.components.inventory == nil
        or not CanStartSwap(player, friend.prefab)
        or player:HasTag("my_friend_possessing")
        or not require("my_friend_policy").IsLocalPlayer(player) then return false end
    local affinity = friend.components.my_friend_affinity
    return affinity ~= nil and affinity:Get(player) >= 25
end

function M.Possess(player, friend)
    if not M.CanPossess(player, friend) then return false end
    local world = World()
    local follower = friend.components.follower

    local x, _, z = friend.Transform:GetWorldPosition()
    local px, _, pz = player.Transform:GetWorldPosition()
    local was_following = follower ~= nil and follower:GetLeader() == player
    local affinity = friend.components.my_friend_affinity
    local companion_skin_data = SaveSkin(friend)
    local companion_abigail = Abigail.SaveBody(friend)
    local player_abigail = Abigail.SaveBody(player)
    local safe_companion_skin = SkinForBody(player, friend.prefab,
        companion_skin_data ~= nil and companion_skin_data.skin_name or nil)
    local leash = friend.components.petleash
    local companion_pet_data = leash ~= nil and leash:OnSave() or nil
    local companion_pets = DetachCompanionPets(friend)
    local sessions = Sessions()
    if sessions == nil then return false end
    world._my_friend_possession_active = true
    require("my_friend_commands").Clear(friend)

    local session = {
        userid = player.userid,
        phase = "enter",
        companion_name = friend:GetDisplayName(),
        companion_custom_name = friend._my_friend_custom_name,
        friend_staying = affinity ~= nil and affinity.staying == true or false,
        companion_prefab = friend.prefab,
        companion_id = friend._my_friend_id,
        companion_skin = safe_companion_skin,
        companion_skin_data = companion_skin_data,
        companion_body = {
            inv = SaveAndClearInventory(friend),
            meters = SaveMeters(friend),
            custom_name = friend._my_friend_custom_name,
            skill_data = SaveSkillTree(friend),
            wx78 = WX78.Save(friend),
            abigail = companion_abigail,
        },
        companion_affinity = SaveAffinity(friend),
        player_body = {
            inv = SaveAndClearInventory(player),
            meters = SaveMeters(player),
            -- The autonomous body represents the companion while the player
            -- is controlling the companion body, so keep the companion name
            -- on that entity instead of leaking the player's name into it.
            custom_name = friend._my_friend_custom_name or friend:GetDisplayName(),
            skill_data = SaveSkillTree(player),
            wx78 = WX78.Save(player),
            abigail = player_abigail,
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
        player_skin_data = SaveSkin(player),
        player_position = {x = px, z = pz},
        position = {x = x, z = z},
        companion_pets = companion_pets,
        companion_pet_data = companion_pet_data,
    }
    CaptureCompanionState(session, friend)
    sessions[player.userid] = session
    if follower ~= nil then follower:SetLeader(nil) end
    if friend.StopBrain ~= nil then friend:StopBrain("my_friend_possess") end
    friend:ClearBufferedAction()
    if friend.components.locomotor ~= nil then
        friend.components.locomotor:Clear()
        friend.components.locomotor:Stop()
    end
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
        friend._my_friend_possess_parked = nil
        friend.persists = true
        if friend.Physics ~= nil then friend.Physics:SetActive(true) end
        if friend.DynamicShadow ~= nil then friend.DynamicShadow:Enable(true) end
        if friend.MiniMapEntity ~= nil then friend.MiniMapEntity:SetEnabled(true) end
        friend:Show()
        LoadInventory(friend, session.companion_body.inv)
        LoadMeters(friend, session.companion_body.meters)
        AttachCompanionPets(friend, session.companion_pets)
        RestoreLeader(friend, session, player)
        if friend.RestartBrain ~= nil then friend:RestartBrain("my_friend_possess") end
        world._my_friend = friend
        LoadInventory(player, session.player_body.inv)
        LoadMeters(player, session.player_body.meters)
        if player.Physics ~= nil then player.Physics:Teleport(px, 0, pz) end
        world._my_friend_possession_active = nil
        sessions[player.userid] = nil
        return false
    end
    Abigail.RemoveSource(friend)
    return true
end

function M.Release(player)
    local sess = SessionFor(player)
    local temporary = sess ~= nil and sess.temporary_companion or nil
    if sess == nil or sess.phase ~= nil or sess._restore_pending
        or not IsLiving(temporary) or temporary._my_friend_departing
        or temporary._my_friend_possess_parked
        or not CanStartSwap(player, temporary.prefab) then
        return false
    end
    CaptureTemporary(sess)
    local x, _, z = player.Transform:GetWorldPosition()
    sess.companion_skill_data = SaveSkillTree(player)
    sess.companion_skin_data = SaveSkin(player)
    sess.companion_prefab = player.prefab
    local abigail = Abigail.SaveBody(player)
    local body = {inv = SaveAndClearInventory(player), meters = SaveMeters(player),
        skill_data = sess.companion_skill_data, wx78 = WX78.Save(player),
        abigail = abigail}
    body.custom_name = sess.companion_custom_name
    sess.release_body = body
    sess.release_position = {x = x, z = z}
    sess.phase = "exit"
    -- A character change made while possessing can overwrite the vanilla
    -- swapper's main_data with the companion prefab. Restore the original
    -- player's identity before requesting the return swap.
    local sw = player.components ~= nil and player.components.seamlessplayerswapper or nil
    local previous_main = deepcopy(sw.main_data)
    if sw ~= nil then
        sw.main_data = sw.main_data or {}
        sw.main_data.prefab = sess.player_prefab
        sw.main_data.skin_base = SkinForBody(player, sess.player_prefab,
            sess.player_skin_data ~= nil and sess.player_skin_data.skin_name or nil)
    end
    if not StartSwap(player, nil, nil) then
        sw.main_data = previous_main
        LoadInventory(player, body.inv)
        sess.phase = nil
        sess.release_body, sess.release_position = nil, nil
        return false
    end
    -- The native request has been accepted. Until this point the AI body,
    -- inventory and pets remain intact so a failed request is reversible.
    if World() ~= nil then World()._my_friend_possession_active = true end
    sess.companion_pets = DetachCompanionPets(temporary)
    InventoryTransfer.Clear(temporary)
    temporary.persists = false
    temporary:Remove()
    sess.temporary_companion = nil
    return true
end

return M
