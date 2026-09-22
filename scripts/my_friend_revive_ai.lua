local Backpacks = require("my_friend_backpacks")
local Policy = require("my_friend_policy")
local Safety = require("my_friend_recovery_safety")

local M = {}
local EquipSlots = require("my_friend_equip_slots")

M.DEATH_DROP_TAG = "my_friend_death_drop"
M.DEATH_DROP_RADIUS = 18
M.DEATH_POINT_ARRIVE_DISTANCE = 3
M.PORTAL_ACTION_TIMEOUT = 300

local VALID_PORTALS = {
    multiplayer_portal = true,
    multiplayer_portal_moonrock = true,
}

local function IsValid(inst)
    return inst ~= nil and inst:IsValid()
end

local function IsGhost(inst)
    return IsValid(inst) and inst:HasTag("playerghost")
end

local function IsAlive(inst)
    return IsValid(inst) and not inst:HasTag("playerghost")
        and inst.components ~= nil and inst.components.health ~= nil
        and not inst.components.health:IsDead()
end

function M.IsPortalPrefab(prefab)
    return VALID_PORTALS[prefab] == true
end

function M.ShouldRecover(isghost, isdead, pending)
    return pending == true and not isghost and not isdead
end

local function SetDeathDrop(item, value)
    if not IsValid(item) then return end
    if value then
        if item.components.my_friend_death_drop == nil then
            item:AddComponent("my_friend_death_drop")
        end
    elseif item.components.my_friend_death_drop ~= nil then
        item:RemoveComponent("my_friend_death_drop")
    end
end

local function MarkInventory(inst)
    local inventory = inst.components ~= nil and inst.components.inventory or nil
    if inventory == nil then return end
    for _, item in ipairs(inventory:ReferenceAllItems()) do
        SetDeathDrop(item, true)
    end
    local backpack = EquipSlots.GetBackpack(inventory)
    if backpack ~= nil and backpack:HasTag("backpack") then Backpacks.MarkOwned(inst, backpack) end
    SetDeathDrop(inventory:GetActiveItem(), true)
end

local function ClearRecoveredInventory(inst)
    local inventory = inst.components ~= nil and inst.components.inventory or nil
    if inventory == nil then return end
    for _, item in ipairs(inventory:ReferenceAllItems()) do
        if item._my_friend_death_drop then SetDeathDrop(item, false) end
    end
end

function M.ReleaseBelongings(inst)
    -- The world has one companion. These persisted markers predate owner IDs,
    -- so clear them globally when that companion leaves, including older graves.
    for _, item in pairs(Ents or {}) do
        if item:IsValid() then
            if Backpacks.IsOwned(item) then Backpacks.ClearOwned(item) end
            SetDeathDrop(item, false)
            if item.components.my_friend_remains ~= nil then
                item:RemoveComponent("my_friend_remains")
            end
        end
    end
    inst._my_friend_owned_backpack = nil
    inst._my_friend_recover_death_drops = nil
    inst._my_friend_death_sites = nil
    inst._my_friend_auto_recovery_point = nil
end

-- Dying and being revived both cut whatever interaction was in flight without
-- ever running its success or fail callback, so the latches those callbacks
-- were supposed to lower have to be released by hand. Every one of these is
-- read by CanAct(), which gates nearly every behaviour the companion has.
local function ReleasePendingWork(inst)
    local navigation = require("my_friend_navigation")
    navigation.CancelSteering(inst)
    navigation.ClearStuck(inst)
    inst._my_friend_steering_cache, inst._my_friend_last_move = nil, nil
    inst._my_friend_pending_emote = nil
    require("my_friend_butterfly").Cancel(inst)
    -- A cooking order can wait indefinitely while low revival health prevents
    -- planning. Retire the old order before the brain can select command_wait.
    require("my_friend_commands").Clear(inst)
    require("my_friend_container_ai").Cancel(inst)
    inst._my_friend_storage_action = nil
    inst._my_friend_chest_transfer = nil
    inst._my_friend_backpack_action = nil
    inst._my_friend_backpack_action_since = nil
    inst._my_friend_backpack_target = nil
    inst._my_friend_backpack_pending_index = nil
    inst._my_friend_backpack_commanded = nil
    inst._my_friend_backpack_switch_prepared = nil
    inst._my_friend_backpack_no_craft_until = nil
    inst._my_friend_abandoned_backpack = nil
    inst._my_friend_backpack_retry = nil
    inst._my_friend_backpack_recover_after = nil
    inst._my_friend_work_target = nil
    inst._my_friend_work_action = nil
    inst._my_friend_tool_action = nil
    inst._my_friend_hand_tool_lock_until = nil
    inst._my_friend_under_threat = nil
    if inst.components.combat ~= nil then
        inst.components.combat:SetTarget(nil)
    end
    inst._my_friend_combat_hand_item = nil
    inst._my_friend_combat_hand_until = nil
    inst._my_friend_combat_equipment_target = nil
    inst._my_friend_light_refuge = nil
    inst._my_friend_external_light_since = nil
    inst._my_friend_dark_state = nil
    -- A bag the player pulled off shortly before the death must not keep its
    -- 30 second "leave it alone" hold once the companion is back on its feet.
    if inst._my_friend_equip_after ~= nil then
        local bag = Backpacks.FindOwned(inst)
        if bag ~= nil then inst._my_friend_equip_after[bag.components.equippable.equipslot] = nil end
    end
    inst._my_friend_replan_requested = true
end

local function OnDeath(inst)
    if inst._my_friend_death_handled then return end
    inst._my_friend_death_handled = true
    require("my_friend_ghost_help").Stop(inst)
    inst._my_friend_auto_recovery_point = nil
    require("my_friend_ghost_commands").Cancel(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    inst._my_friend_death_point = { x = x, y = y, z = z, name = inst:GetDisplayName() }
    -- There is only one active companion. Keep the current death site as the
    -- recovery job instead of appending an unbounded history after repeated
    -- deaths before the previous drops were recovered.
    inst._my_friend_death_sites = {inst._my_friend_death_point}
    inst._my_friend_death_name = inst:GetDisplayName()
    local combat = inst.components.combat
    inst._my_friend_death_attacker = combat ~= nil and combat.lastattacker or nil
    inst._my_friend_death_attacker_prefab = IsValid(inst._my_friend_death_attacker)
        and inst._my_friend_death_attacker.prefab or nil
    inst._my_friend_existing_remains = {}
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, 3, nil, {"INLIMBO"})) do
        if entity.SetSkeletonDescription ~= nil then inst._my_friend_existing_remains[entity.GUID] = true end
    end
    ReleasePendingWork(inst)
    inst._my_friend_portal_revive_requested = nil
    inst._my_friend_portal_target = nil
    inst._my_friend_recover_death_drops = nil
    inst._my_friend_recovery_delivery = nil
    MarkInventory(inst)
    if inst.components.inventory ~= nil then
        inst.components.inventory:DropEverything(true)
    end
end

local function MarkOwnRemains(inst, point)
    point = point or inst._my_friend_death_point
    if point == nil then return end
    for _, entity in ipairs(TheSim:FindEntities(point.x, 0, point.z, 2, nil, {"INLIMBO"})) do
        if entity.SetSkeletonDescription ~= nil
            and entity.char == inst.prefab and entity.userid == inst.userid
            and entity.playername == (point.name or inst._my_friend_death_name or inst:GetDisplayName())
            and not (inst._my_friend_existing_remains or {})[entity.GUID]
            and entity.components.my_friend_remains == nil then
            entity:AddComponent("my_friend_remains")
        end
    end
end

local function OnRespawned(inst)
    -- Being revived by another player re-runs the whole player spawn path
    -- (new stategraph, new physics, hidden inventory) underneath any action the
    -- companion still had queued, so clear the latches again on the way back up
    -- rather than trusting that nothing was left behind at death.
    require("my_friend_ghost_help").Stop(inst)
    ReleasePendingWork(inst)
    require("my_friend_ghost_commands").OnRespawned(inst)
    -- Player revives do not pass through GhostCommands.OnRespawned's
    -- automatic-portal branch, but they still need the same independent
    -- return-to-death-site phase to recover dropped lighting and equipment.
    local point = inst._my_friend_death_point
    if point ~= nil then
        inst._my_friend_auto_recovery_point = Vector3(point.x, 0, point.z)
    end
    if inst.components.combat ~= nil then
        inst.components.combat:SetTarget(nil)
    end
    inst._my_friend_combat_hand_item = nil
    inst._my_friend_combat_hand_until = nil
    inst._my_friend_combat_equipment_target = nil
    inst._my_friend_light_refuge = nil
    inst._my_friend_external_light_since = nil
    inst._my_friend_dark_state = nil
    inst._my_friend_death_handled = nil
    inst._my_friend_portal_revive_requested = nil
    inst._my_friend_portal_target = nil
    inst._my_friend_recover_death_drops = inst._my_friend_death_point ~= nil
    inst._my_friend_recover_arrived = nil
    inst._my_friend_recover_target = nil
    inst._my_friend_recovery_retry = {}
    inst._my_friend_recovery_empty_since = nil
    MarkOwnRemains(inst)
end

function M.Configure(inst)
    if not IsValid(inst) or inst._my_friend_revive_configured then return end
    inst._my_friend_revive_configured = true
    local inventory = inst.components ~= nil and inst.components.inventory or nil
    if inventory ~= nil then inventory:DisableDropOnDeath() end
    inst:ListenForEvent("death", OnDeath)
    inst:ListenForEvent("ms_becameghost", function()
        MarkOwnRemains(inst)
        require("my_friend_ghost_help").Start(inst)
    end)
    inst:ListenForEvent("ms_respawnedfromghost", OnRespawned)
    inst:ListenForEvent("onremove", function() require("my_friend_ghost_help").Stop(inst) end)
end

local function IsUsablePortal(portal)
    return IsValid(portal) and M.IsPortalPrefab(portal.prefab)
        and not portal:IsInLimbo() and portal.components ~= nil
        and portal.components.hauntable ~= nil and portal:HasTag("resurrector")
end

local function DistanceSq(inst, target)
    local x, _, z = inst.Transform:GetWorldPosition()
    local tx, _, tz = target.Transform:GetWorldPosition()
    local dx, dz = tx - x, tz - z
    return dx * dx + dz * dz
end

local function FindPortal(inst)
    local closest, closest_distance
    for _, portal in pairs(Ents or {}) do
        if IsUsablePortal(portal) then
            local distance = DistanceSq(inst, portal)
            if closest_distance == nil or distance < closest_distance then
                closest, closest_distance = portal, distance
            end
        end
    end
    return closest
end

function M.RequestPortalRevive(inst)
    if not IsGhost(inst) then return false end
    inst._my_friend_portal_revive_requested = true
    inst._my_friend_portal_target = nil
    return true
end

function M.GetPortalAction(inst)
    if not IsGhost(inst) or not inst._my_friend_portal_revive_requested
        or inst.sg ~= nil and inst.sg:HasStateTag("busy") then return end
    local target = inst._my_friend_portal_target
    if not IsUsablePortal(target) then
        target = FindPortal(inst)
        inst._my_friend_portal_target = target
    end
    if target == nil then return end
    local action = BufferedAction(inst, target, ACTIONS.HAUNT)
    action.validfn = function()
        return IsGhost(inst) and inst._my_friend_portal_revive_requested == true
            and IsUsablePortal(target)
    end
    action:AddSuccessAction(function()
        inst._my_friend_portal_revive_requested = nil
        inst._my_friend_portal_target = nil
    end)
    action:AddFailAction(function()
        inst._my_friend_portal_target = nil
    end)
    return action
end

local function IsRecoverableDrop(item)
    return IsValid(item) and item._my_friend_death_drop == true
        and item:HasTag(M.DEATH_DROP_TAG) and not item:IsInLimbo()
        and item.components ~= nil and item.components.inventoryitem ~= nil
        and item.components.inventoryitem.owner == nil
        and item.components.inventoryitem.canbepickedup
end

local function FinishRecovery(inst)
    ClearRecoveredInventory(inst)
    inst._my_friend_recover_death_drops = nil
    inst._my_friend_auto_recovery_point = nil
    inst._my_friend_recover_arrived = nil
    inst._my_friend_recover_target = nil
    inst._my_friend_death_sites = {}
    inst._my_friend_recovery_delivery = true
    inst._my_friend_recovery_retry = nil
    inst._my_friend_existing_remains = nil
    inst._my_friend_death_point = nil
    inst._my_friend_death_name = nil
    inst._my_friend_death_attacker = nil
    inst._my_friend_death_attacker_prefab = nil
end

function M.GetRecoveryAction(inst)
    local health = inst ~= nil and inst.components ~= nil and inst.components.health or nil
    if not M.ShouldRecover(IsGhost(inst), health ~= nil and health:IsDead(),
        inst ~= nil and inst._my_friend_recover_death_drops)
        or Policy.IsBusy(inst) or inst._my_friend_storage_action
        or inst._my_friend_container_action then return end
    local leader = Policy.GetLeader(inst)
    if leader ~= nil and not Policy.InRange(inst, inst) then return end
    ClearRecoveredInventory(inst)
    local now, candidates, outstanding = GetTime(), {}, false
    local retry = inst._my_friend_recovery_retry or {}
    inst._my_friend_recovery_retry = retry
    for _, entity in pairs(Ents or {}) do
        local remains = entity:IsValid() and entity:HasTag("my_friend_remains")
            and entity.components.workable ~= nil and entity.components.workable:CanBeWorked()
            and entity.components.workable:GetWorkAction() == ACTIONS.HAMMER
        local pending_drop = IsValid(entity) and entity._my_friend_death_drop
            and entity.components.inventoryitem ~= nil
            and entity.components.inventoryitem.owner == nil
        if pending_drop or remains then outstanding = true end
        if IsRecoverableDrop(entity) or remains then
            outstanding = true
            if Policy.InRange(inst, entity) and now >= (retry[entity.GUID] or 0) then
                local fits = remains or Backpacks.IsOwned(entity)
                    or inst.components.inventory:CanAcceptCount(entity, 1) > 0
                if fits then
                    candidates[#candidates + 1] = {target = entity, remains = remains,
                        priority = Backpacks.IsOwned(entity) and 0 or remains and 2 or 1}
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        return a.priority == b.priority and DistanceSq(inst, a.target) < DistanceSq(inst, b.target)
            or a.priority < b.priority
    end)
    for _, candidate in ipairs(candidates) do
        local target = candidate.target
        if not Safety.IsSafe(inst, target:GetPosition()) then
            retry[target.GUID] = now + 20
        else
            inst._my_friend_recover_target = target
            local action
            if candidate.remains then
                action = require("my_friend_base_ai").GetRemainsAction(inst, target)
            elseif Backpacks.IsOwned(target) then
                require("my_friend_base_ai").SetTask(inst, "正在安全地找回自己的背包")
                action = Backpacks.GetOwnedRecoveryAction(inst, target)
            else
                require("my_friend_base_ai").SetTask(inst, "正在找回自己的死亡掉落物")
                action = BufferedAction(inst, target, ACTIONS.PICKUP)
                action:AddSuccessAction(function()
                    -- A partial pickup may leave a stack on the ground.
                    if IsValid(target) and target.components.inventoryitem:GetGrandOwner() == inst then
                        SetDeathDrop(target, false)
                    end
                end)
            end
            if action ~= nil then
                action._my_friend_death_recovery = inst._my_friend_auto_recovery_point or true
                local previous = action.validfn
                action.validfn = function(act)
                    return IsAlive(inst) and Policy.GetLeader(inst) == leader
                        and (leader == nil or Policy.InRange(inst, inst))
                        and target:IsValid() and Policy.InRange(inst, target)
                        and Safety.IsSafe(inst, target:GetPosition())
                        and (previous == nil or previous(act))
                end
                action:AddSuccessAction(function() inst._my_friend_recover_target = nil end)
                action:AddFailAction(function()
                    inst._my_friend_recover_target = nil
                    if not action._my_friend_cancelled then
                        -- Breaking our own skeleton takes many swings and is
                        -- interrupted by anything that moves us, so a long
                        -- backoff reads as "it gave up". Loose drops keep the
                        -- patient retry; the skeleton gets straight back to it.
                        retry[target.GUID] = GetTime() + (candidate.remains and 2 or 15)
                    end
                end)
                return Policy.GuardAction(inst, action)
            end
        end
    end
    inst._my_friend_recover_target = nil
    if outstanding then
        inst._my_friend_recovery_empty_since = nil
        if leader == nil then return require("my_friend_base_ai").GetRecoveryStoreAction(inst) end
        return
    end
    -- Visit remembered sites once before retiring the job; old saves may not
    -- have had their skeleton marked when the ghost was created.
    local sites = inst._my_friend_death_sites or {inst._my_friend_death_point}
    local unvisited = false
    for _, point in ipairs(sites) do
        if not point.visited then
            unvisited = true
            local x, _, z = inst.Transform:GetWorldPosition()
            if (point.x - x)^2 + (point.z - z)^2 <= 4^2 then
                point.visited = true
                MarkOwnRemains(inst, point)
                return
            end
            local p = Vector3(point.x, 0, point.z)
            if inst._my_friend_auto_recovery_point ~= nil or leader == nil
                or (p - leader:GetPosition()):LengthSq() <= Policy.ACTIVITY_RANGE^2 then
                if now >= (point.retry or 0) and Safety.IsSafe(inst, p) then
                    local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, p)
                    action._my_friend_death_recovery = inst._my_friend_auto_recovery_point or true
                    action.arrivedist = 3
                    action.validfn = function()
                        return IsAlive(inst) and Safety.IsSafe(inst, p)
                            and Policy.GetLeader(inst) == leader
                            and (leader == nil or Policy.InRange(inst, inst))
                    end
                    action:AddFailAction(function()
                        if not action._my_friend_cancelled then point.retry = GetTime() + 20 end
                    end)
                    return Policy.GuardAction(inst, action)
                end
            end
        end
    end
    if unvisited then return end
    inst._my_friend_recovery_empty_since = inst._my_friend_recovery_empty_since or now
    if now - inst._my_friend_recovery_empty_since < 2 then return end
    FinishRecovery(inst)
end

function M.OnSave(inst, data)
    require("my_friend_ghost_help").OnSave(inst, data)
    local point = inst._my_friend_death_point
    if point ~= nil then
        data.my_friend_revive = {
            death_x = point.x,
            death_y = point.y,
            death_z = point.z,
            portal_requested = inst._my_friend_portal_revive_requested == true,
            recover_drops = inst._my_friend_recover_death_drops == true,
            auto_recovery = inst._my_friend_auto_recovery_point ~= nil,
            sites = inst._my_friend_death_sites,
            death_name = inst._my_friend_death_name,
            attacker_prefab = inst._my_friend_death_attacker_prefab,
            delivery = inst._my_friend_recovery_delivery,
        }
    end
end

function M.OnLoad(inst, data)
    local saved = data ~= nil and data.my_friend_revive or nil
    if saved ~= nil and type(saved.death_x) == "number"
        and type(saved.death_z) == "number" then
        inst._my_friend_death_point = {
            x = saved.death_x,
            y = saved.death_y or 0,
            z = saved.death_z,
        }
        inst._my_friend_portal_revive_requested = saved.portal_requested and true or nil
        inst._my_friend_recover_death_drops = saved.recover_drops and true or nil
        inst._my_friend_auto_recovery_point = saved.auto_recovery and saved.recover_drops
            and Vector3(saved.death_x, 0, saved.death_z) or nil
        inst._my_friend_death_sites = {}
        for _, point in ipairs(type(saved.sites) == "table" and saved.sites or {inst._my_friend_death_point}) do
            if type(point) == "table" and type(point.x) == "number" and type(point.z) == "number"
                and point.x == point.x and point.z == point.z
                and math.abs(point.x) < 10000000 and math.abs(point.z) < 10000000 then
                inst._my_friend_death_sites[#inst._my_friend_death_sites + 1] = {
                    x = point.x, z = point.z, y = 0, name = point.name, visited = point.visited == true,
                }
            end
        end
        inst._my_friend_death_name = saved.death_name
        inst._my_friend_death_attacker_prefab = saved.attacker_prefab
        inst._my_friend_recovery_delivery = saved.delivery
    end
    require("my_friend_ghost_help").OnLoad(inst, data)
end

return M
