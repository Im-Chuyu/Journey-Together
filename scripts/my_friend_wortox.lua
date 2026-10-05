local M = {}
local Policy = require("my_friend_policy")
local Dialogue = require("my_friend_dialogue")

M.HEAL_START = .5
M.HEAL_STOP = .8
M.HEAL_RANGE = 20
M.HEAL_DISTANCE = 4
M.HEART_SOUL_COST = 10

-- Native wortox hearts are normally linked during the player's skill-tree
-- handshake. A companion does not have that login handshake, so keep the
-- companion-owned link registry available before MakeHeart can run.
local linked_hearts = setmetatable({}, {__mode = "k"})
local RefreshHeart

function M.CanMakeHeart(inst)
    return inst.prefab == "wortox" and inst:HasTag("my_friend")
        and not (TheWorld ~= nil and TheWorld._my_friend_possession_active)
        and not inst._my_friend_possess_parked
        and not inst:HasTag("playerghost") and inst.components.health ~= nil
        and not inst.components.health:IsDead() and inst.components.inventory ~= nil
        and inst.components.inventory:Has("wortox_soul", M.HEART_SOUL_COST) == true
end

function M.MakeHeart(inst)
    if not M.CanMakeHeart(inst) then return false end
    local heart = SpawnPrefab("wortox_reviver")
    if heart == nil then return false end
    local inventory = inst.components.inventory
    local _, souls = inventory:Has("wortox_soul", M.HEART_SOUL_COST)
    if inventory:CanAcceptCount(heart, 1) < 1 and inventory:GetActiveItem() ~= nil
        and souls > M.HEART_SOUL_COST then
        heart:Remove()
        return false
    end
    -- Has/ConsumeByName use the same carried slots and overflow bag. An open
    -- chest must never count as souls carried by the companion.
    inst.components.inventory:ConsumeByName("wortox_soul", M.HEART_SOUL_COST)
    inst.components.inventory:GiveItem(heart, nil, inst:GetPosition())
    heart:OnBuilt(inst)
    -- OnBuilt can only attach a native owner when the vanilla player skill
    -- handshake has already run. Companions are ordinary entities, so make
    -- the owner link explicit and keep it tied to the companion body ID.
    if heart.components.linkeditem ~= nil and inst._my_friend_id ~= nil then
        heart._my_friend_heart_owner_id = inst._my_friend_id
        linked_hearts[heart] = true
        RefreshHeart(heart, inst)
    end
    inst:PushEvent("builditem", {item = heart, recipe = GetValidRecipe("wortox_reviver")})
    Dialogue.Say(inst, "heart_made")
    return true
end

function M.GetMakeHeartAction(inst, ghost)
    if not M.CanMakeHeart(inst) or Policy.IsBusy(inst) then return end
    local Commands = require("my_friend_commands")
    local command = ghost == nil and Commands.Get(inst) or nil
    if ghost == nil and (command == nil or command.id ~= "make_heart") then return end
    local action = BufferedAction(inst, nil, ACTIONS.MY_FRIEND_MAKE_HEART)
    action.validfn = function()
        return M.CanMakeHeart(inst) and (ghost ~= nil
            and ghost:IsValid() and ghost:HasTag("playerghost")
            or ghost == nil and inst._my_friend_command == command)
    end
    if command ~= nil then
        action:AddSuccessAction(function()
            if inst._my_friend_command == command then Commands.Clear(inst) end
        end)
        action:AddFailAction(function()
            if not action._my_friend_cancelled
                and not (TheWorld ~= nil and TheWorld._my_friend_possession_active)
                and not inst._my_friend_possess_parked
                and inst._my_friend_command == command then
                Commands.Clear(inst)
                Dialogue.Say(inst, "heart_make_failed")
            end
        end)
    end
    return action
end

function M.GetMakeHeartCommandAction(inst)
    if TheWorld ~= nil and TheWorld._my_friend_possession_active then return end
    local Commands = require("my_friend_commands")
    local command = Commands.Get(inst)
    if command == nil or command.id ~= "make_heart" or Policy.IsBusy(inst) then return end
    if not M.CanMakeHeart(inst) then
        Commands.Clear(inst)
        Dialogue.Say(inst, "heart_make_failed")
        return
    end
    return M.GetMakeHeartAction(inst)
end

-- Native hearts link to a user's login ID. NPC-made hearts instead keep the
-- existing companion body ID; actual player-made hearts retain native links.
local function EnsureOwnerEvents(owner)
    if owner._my_friend_heart_events then return end
    owner._my_friend_heart_events = true
    local function Refresh() M.RefreshLinkedHearts(owner) end
    for _, event in ipairs({"ms_skilltreeinitialized", "onsetskillselection_server",
        "onactivateskill_server", "ondeactivateskill_server"}) do
        owner:ListenForEvent(event, Refresh)
    end
end

local function FindHeartOwner(id)
    -- While possessing, the original companion body is controlled by this
    -- player. The parked AI body shares the session ID and must not win.
    for _, player in ipairs(AllPlayers) do
        if player:IsValid() and player._my_friend_id == id
            and player:HasTag("my_friend_possessed")
            and player.prefab == "wortox" then
            return player
        end
    end
    local friend = TheWorld._my_friend
    if friend ~= nil and friend:IsValid() and friend._my_friend_id == id
        and friend.prefab == "wortox" then return friend end
end

local function HasSqueezeSkill(inst)
    return inst ~= nil and inst:IsValid()
        and inst.components ~= nil and inst.components.skilltreeupdater ~= nil
        and inst.components.skilltreeupdater:IsActivated("wortox_lifebringer_3") == true
end

local function FindSessionSkillOwner(id)
    if id == nil then return end
    for _, player in ipairs(AllPlayers or {}) do
        if player ~= nil and player:IsValid() and player._my_friend_id == id
            and HasSqueezeSkill(player) then
            return player
        end
    end
    local friend = TheWorld ~= nil and TheWorld._my_friend or nil
    if friend ~= nil and friend:IsValid() and friend._my_friend_id == id
        and HasSqueezeSkill(friend) then
        return friend
    end
end

function M.RefreshLinkedHearts(owner)
    if owner == nil or not owner:IsValid() or owner._my_friend_id == nil then return end
    EnsureOwnerEvents(owner)
    for heart in pairs(linked_hearts) do
        if heart:IsValid() and heart._my_friend_heart_owner_id == owner._my_friend_id then
            RefreshHeart(heart)
        end
    end
end

RefreshHeart = function(heart, owner)
    local linked = heart.components.linkeditem
    if heart._my_friend_heart_owner_id == nil then return linked.owner_inst end
    local old = heart._my_friend_heart_owner
    if owner == nil and old ~= nil and old:IsValid()
        and not old._my_friend_possess_parked
        and old.prefab == "wortox"
        and old._my_friend_id == heart._my_friend_heart_owner_id then
        owner = old
    end
    owner = owner or FindHeartOwner(heart._my_friend_heart_owner_id)
    if old ~= owner then
        if old ~= nil then
            heart:RemoveEventCallback("onremove", heart._my_friend_heart_removed, old)
        end
        heart._my_friend_heart_owner = owner
        heart._my_friend_heart_removed = function()
            linked:SetOwnerInst(nil)
            heart._my_friend_heart_owner = nil
            heart:SetAllowConsumption(false)
            heart._my_friend_heart_consumable = false
        end
        if owner ~= nil then heart:ListenForEvent("onremove", heart._my_friend_heart_removed, owner) end
        linked:SetOwnerInst(owner)
        -- SetOwnerInst invokes the native removal callback, which locks the
        -- spell even if both the previous and new owners have the same skill.
        heart._my_friend_heart_consumable = nil
    end
    -- A removed/reset skill must lock squeezing again, just as a missing
    -- owner does. All effects of the spell remain the native heart's code.
    local can_squeeze = owner ~= nil and owner.components.skilltreeupdater ~= nil
        and owner.components.skilltreeupdater:IsActivated("wortox_lifebringer_3") == true
    if heart._my_friend_heart_consumable ~= can_squeeze then
        heart._my_friend_heart_consumable = can_squeeze
        if can_squeeze then
            -- OnSkillTreeInitialized only runs the native owner callback. A
            -- companion has no player login handshake, so explicitly clear
            -- the native WORTOX_REVIVER_LOCK as well.
            if heart.SetAllowConsumption ~= nil then
                heart:SetAllowConsumption(true)
            end
            linked:OnSkillTreeInitialized()
        else heart:SetAllowConsumption(false) end
    end
    if owner ~= nil then
        if linked.netownername:value() ~= owner:GetDisplayName() then
            linked.netownername:set(owner:GetDisplayName())
        end
        EnsureOwnerEvents(owner)
    end
    return owner
end

function M.RefreshHeartFor(inst, heart)
    if inst == nil or heart == nil or not heart:IsValid()
        or inst._my_friend_id == nil then return false end
    -- After an entity exchange the active player body carries the companion
    -- session id, but it is marked `my_friend_possessed` instead of
    -- `my_friend`.  A heart crafted from that body therefore keeps the
    -- native player owner and would otherwise look like somebody else's
    -- heart when the parked companion tries to squeeze it.  The session id
    -- is the stable identity across both bodies, so adopt that link before
    -- refreshing the owner and skill-tree state.
    local linked = heart.components ~= nil and heart.components.linkeditem or nil
    local native_owner = heart._my_friend_heart_owner
        or linked ~= nil and linked:GetOwnerInst() or nil
    if heart._my_friend_heart_owner_id == nil and native_owner ~= nil
        and native_owner ~= inst and native_owner._my_friend_id == inst._my_friend_id then
        heart._my_friend_heart_owner_id = inst._my_friend_id
        linked_hearts[heart] = true
    end
    if heart._my_friend_heart_owner_id ~= inst._my_friend_id then return false end
    RefreshHeart(heart, inst)
    local owner = heart._my_friend_heart_owner or linked ~= nil and linked:GetOwnerInst() or nil
    -- The skill can remain on the currently controlled body while the heart
    -- is inside the restored companion body (or the reverse). The session ID
    -- is stable across that exchange, so either body can provide the skill.
    local skill_owner = HasSqueezeSkill(inst)
        and inst or FindSessionSkillOwner(inst._my_friend_id)
    local allowed = (owner == inst
        or heart._my_friend_heart_owner_id == inst._my_friend_id)
        and skill_owner ~= nil
    if allowed and heart.SetAllowConsumption ~= nil then
        heart._my_friend_heart_consumable = true
        heart:SetAllowConsumption(true)
        if linked ~= nil and linked.OnSkillTreeInitialized ~= nil then
            linked:OnSkillTreeInitialized()
        end
    end
    return allowed
end

function M.ConfigureHeart(heart)
    if not TheWorld.ismastersim or heart.components.linkeditem == nil then return end
    local linked = heart.components.linkeditem
    local attach = heart.TryToAttachWortoxID
    heart.TryToAttachWortoxID = function(self, owner)
        if self._my_friend_heart_owner_id ~= nil then
            RefreshHeart(self)
            return
        end
        -- A heart made while the player is controlling the companion body
        -- must keep the companion session identity even though the native
        -- linkeditem component only knows the player's userid. Do this before
        -- the vanilla skill check; otherwise a heart made after an entity
        -- exchange can lose its companion owner as soon as it is moved into
        -- the parked companion's inventory.
        local companion_owner = owner ~= nil
            and (owner:HasTag("my_friend") or owner:HasTag("my_friend_possessed"))
            and owner.prefab == "wortox" and owner._my_friend_id ~= nil
        local linked_user = linked:GetOwnerUserID()
        if companion_owner and (linked_user == nil or linked_user == owner.userid) then
            self._my_friend_heart_owner_id = owner._my_friend_id
            linked_hearts[self] = true
            RefreshHeart(self, owner)
            return
        end
        return attach(self, owner)
    end
    local getowner = linked.GetOwnerInst
    linked.GetOwnerInst = function(self)
        if heart._my_friend_heart_owner_id ~= nil then return RefreshHeart(heart) end
        return getowner(self)
    end
    local save, load = heart.OnSave, heart.OnLoad
    heart.OnSave = function(self, data)
        data.my_friend_heart_owner_id = self._my_friend_heart_owner_id
        if save ~= nil then return save(self, data) end
    end
    heart.OnLoad = function(self, data, ...)
        self._my_friend_heart_owner_id = data ~= nil and data.my_friend_heart_owner_id or nil
        if self._my_friend_heart_owner_id ~= nil then
            linked_hearts[self] = true
            self:DoTaskInTime(0, function() RefreshHeart(self) end)
        end
        if load ~= nil then return load(self, data, ...) end
    end
end

local function NeedsHealing(player, threshold)
    return Policy.IsLocalPlayer(player) and player.entity:IsVisible()
        and not player:HasAnyTag("playerghost", "health_as_oldage")
        and player.components.health ~= nil and not player.components.health:IsDead()
        and player.components.health:GetPercent() < threshold
end

local function CarriedSoul(inst, soul)
    local ii = soul ~= nil and soul:IsValid() and soul.components.inventoryitem or nil
    return soul ~= nil and soul.prefab == "wortox_soul" and ii ~= nil
        and not ii.islockedinslot and ii:GetGrandOwner() == inst
end

local function FindPatient(inst)
    local patient = inst._my_friend_soul_patient
    if NeedsHealing(patient, M.HEAL_STOP)
        and inst:GetDistanceSqToInst(patient) <= M.HEAL_RANGE^2
        and Policy.InRange(inst, patient) then return patient end
    inst._my_friend_soul_patient = nil
    local leader = Policy.GetLeader(inst)
    if NeedsHealing(leader, M.HEAL_START)
        and inst:GetDistanceSqToInst(leader) <= M.HEAL_RANGE^2 then
        inst._my_friend_soul_patient = leader
        return leader
    end
    local lowest = M.HEAL_START
    for _, player in ipairs(AllPlayers) do
        if NeedsHealing(player, lowest) and Policy.InRange(inst, player)
            and inst:GetDistanceSqToInst(player) <= M.HEAL_RANGE^2 then
            patient, lowest = player, player.components.health:GetPercent()
            inst._my_friend_soul_patient = player
        end
    end
    return inst._my_friend_soul_patient
end

function M.GetHealPlayerAction(inst)
    if inst.prefab ~= "wortox" or Policy.IsBusy(inst) or inst._my_friend_under_threat
        or inst._my_friend_command ~= nil or inst._my_friend_storage_action
        or inst._my_friend_container_action or inst._my_friend_backpack_action
        or GetTime() < (inst._my_friend_soul_heal_after or 0) then return end
    local patient = FindPatient(inst)
    if patient == nil then return end
    local soul
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if CarriedSoul(inst, item) then soul = item break end
    end
    if soul == nil then return end
    -- Drop the soul at the companion's current position. Dropping it on the
    -- player's exact position can push the player and is unnecessary: the
    -- native soul seek/heal code already finds nearby players.
    local point = inst:GetPosition()
    local action
    if inst:GetDistanceSqToInst(patient) > M.HEAL_DISTANCE^2 then
        action = BufferedAction(inst, patient, ACTIONS.WALKTO)
        action.arrivedist = M.HEAL_DISTANCE
    else
        action = BufferedAction(inst, nil, ACTIONS.DROP, soul, point)
        action.options.wholestack = false
        action:AddSuccessAction(function()
            -- Wait for vanilla delayed healing before spending the next soul.
            inst._my_friend_soul_heal_after = GetTime() + TUNING.WORTOX_SOUL_HEAL_DELAY + .5
            Dialogue.Say(inst, "activity_wortox_heal", patient)
        end)
    end
    action.validfn = function()
        return inst._my_friend_command == nil and not inst._my_friend_under_threat
            and NeedsHealing(patient, M.HEAL_STOP) and CarriedSoul(inst, soul)
            and Policy.InRange(inst, patient)
            and inst:GetDistanceSqToInst(patient) <= M.HEAL_RANGE^2
            and (action.action ~= ACTIONS.DROP
                or patient:GetDistanceSqToPoint(point) <= (M.HEAL_DISTANCE + 1)^2)
    end
    action:AddFailAction(function()
        if not action._my_friend_cancelled then inst._my_friend_soul_heal_after = GetTime() + 5 end
    end)
    return action
end

-- Both native functions select real players from AllPlayers. Use a temporary
-- function environment during that call; leave the real registry untouched.
local function WithCompanion(fn, ...)
    local friend = TheWorld._my_friend
    if friend == nil or not friend:IsValid() or not friend:HasTag("my_friend") then return fn(...) end
    local targets = {}
    for _, player in ipairs(AllPlayers) do
        if player == friend then return fn(...) end
        targets[#targets + 1] = player
    end
    targets[#targets + 1] = friend
    local env = getfenv(fn)
    setfenv(fn, setmetatable({AllPlayers = targets}, {__index = env}))
    local ok, result = pcall(fn, ...)
    setfenv(fn, env)
    if not ok then error(result) end
    return result
end

function M.InstallSoulAttraction(soul)
    if not TheWorld.ismastersim or soul._seektask == nil then return end
    local task = soul._seektask
    local seek = task.fn
    task.fn = function(inst, ...)
        local friend = TheWorld._my_friend
        if friend == nil or not friend:IsValid() or friend.prefab ~= "wortox"
            or not friend:HasTag("soulstealer") or friend:HasTag("playerghost")
            or friend.components.health == nil or friend.components.health:IsDead()
            or not friend.entity:IsVisible() then return seek(inst, ...) end
        local range = TUNING.WORTOX_SOULSTEALER_RANGE
        local skills = friend.components.skilltreeupdater
        if skills ~= nil and skills:IsActivated("wortox_thief_1") then
            range = range + TUNING.SKILLS.WORTOX.SOULSTEALER_RANGE_BONUS
        end
        if inst:GetDistanceSqToInst(friend) >= range^2 then return seek(inst, ...) end
        return WithCompanion(seek, inst, ...)
    end
end

function M.InstallSoulHealing()
    local common = require("prefabs/wortox_soul_common")
    local original = common.DoHeal
    common.DoHeal = function(soul, ...)
        local friend = TheWorld._my_friend
        if friend == nil or not friend:IsValid() or friend.components.health == nil
            or friend.components.health:IsDead() or friend:HasTag("playerghost")
            or not friend.entity:IsVisible()
            or soul:GetDistanceSqToInst(friend) >= (TUNING.WORTOX_SOULHEAL_RANGE
                + (soul.soul_heal_range_modifier or 0))^2 then return original(soul, ...) end
        return WithCompanion(original, soul, ...)
    end
end

return M
