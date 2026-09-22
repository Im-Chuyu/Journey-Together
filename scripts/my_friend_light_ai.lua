local M = {}
local EquipSlots = require("my_friend_equip_slots")
local Policy = require("my_friend_policy")
local ActiveArea = require("my_friend_active_area")

M.LIGHT_SEARCH_RANGE = 30
M.EXTERNAL_LIGHT_SCAN_RANGE = 12
M.MANUAL_LIGHT_MIN_TIME = 60
M.MANUAL_LIGHT_MAX_TIME = 300
-- Darkness is confirmed slowly and released quickly, so the companion neither
-- flickers its light nor keeps carrying one after reaching a campfire.
M.DARK_ENTER_DELAY = 1.5
M.DARK_EXIT_DELAY = .4
M.LIGHT_STORE_DELAY = .75

local LIGHT_PREFABS = {
    alterguardianhat = 8,
    minerhat = 7,
    lantern = 6,
    nightstick = 5,
    torch = 4,
    yellowamulet = 3,
    lighter = 2,
}

local LIGHT_CANT_TAGS = {
    "INLIMBO", "burnt", "invisible",
}

local THREAT_CANT_TAGS = {
    "INLIMBO", "NOCLICK", "ghost", "invisible", "noattack",
    "notarget", "playerghost",
}

local function DistanceSqToPoint(entity, x, z)
    local ex, _, ez = entity.Transform:GetWorldPosition()
    local dx, dz = ex - x, ez - z
    return dx * dx + dz * dz
end

local function IsAlive(inst)
    return inst ~= nil and inst:IsValid()
        and (inst.components.health == nil or not inst.components.health:IsDead())
end

local function CanAct(inst)
    return IsAlive(inst) and not inst:HasTag("playerghost")
        and inst.components.inventory ~= nil
        and (inst.sg == nil or not inst.sg:HasStateTag("busy"))
end

local function IsFuelUsable(item)
    local fueled = item.components ~= nil and item.components.fueled or nil
    return fueled == nil or not fueled:IsEmpty()
end

function M.IsLightEquipment(item)
    if item == nil or not item:IsValid() or item.components == nil
        or item.components.equippable == nil then
        return false
    end
    return (LIGHT_PREFABS[item.prefab] ~= nil
            or item:HasAnyTag("light", "nightvision"))
        and IsFuelUsable(item)
end

function M.CanEquipLight(inst, item)
    return M.IsLightEquipment(item)
        and not item.components.equippable:IsRestricted(inst)
end

function M.MarkPlayerEquipped(item)
    if M.IsLightEquipment(item) then
        item._my_friend_ai_light = nil
        item._my_friend_manual_light_until = GetTime()
            + math.random(M.MANUAL_LIGHT_MIN_TIME, M.MANUAL_LIGHT_MAX_TIME)
    end
end

function M.ClearLightOwnership(item)
    if item ~= nil then
        item._my_friend_ai_light = nil
        item._my_friend_manual_light_until = nil
    end
end

function M.ShouldHoldManualLight(now, deadline)
    return deadline ~= nil and now < deadline
end

function M.CanSeeInDark(inst)
    return CanEntitySeeInDark ~= nil and CanEntitySeeInDark(inst) == true
end

-- Only caves and real night are dark enough to need a carried light. Dusk
-- above ground dims the ambient light below the light watcher's threshold in
-- winter, which used to make the companion light a lantern in broad daylight.
function M.IsAmbientDarkPhase()
    if TheWorld == nil or TheWorld.state == nil then return false end
    -- Caves stay dark whatever the clock says, matching IsExternallyLit.
    if TheWorld:HasTag("cave") then return true end
    return TheWorld.state.isnight == true
end

-- Debounced so a single flicker of the light watcher never toggles equipment.
function M.IsEnvironmentDark(inst)
    if inst == nil or inst.IsInLight == nil then return false end
    local raw = M.IsAmbientDarkPhase() and not M.IsExternallyLit(inst)
    local now = GetTime()
    local state = inst._my_friend_dark_state
    if state == nil then
        state = {dark = raw, pending = nil, since = now}
        inst._my_friend_dark_state = state
        return state.dark
    end
    if raw == state.dark then
        state.pending = nil
        return state.dark
    end
    if state.pending ~= raw then state.pending, state.since = raw, now end
    if now - state.since >= (raw and M.DARK_ENTER_DELAY or M.DARK_EXIT_DELAY) then
        state.dark, state.pending = raw, nil
    end
    return state.dark
end

function M.IsDark(inst)
    return M.IsEnvironmentDark(inst)
        and not M.HasUsableEquippedLight(inst)
end

local function GetEquippedLights(inst, include_empty)
    local inventory = inst ~= nil and inst.components ~= nil
        and inst.components.inventory or nil
    local lights = {}
    if inventory == nil then return lights end
    for _, slot in ipairs(EquipSlots.All()) do
        local item = inventory:GetEquippedItem(slot)
        if M.IsLightEquipment(item) or include_empty and item ~= nil
            and LIGHT_PREFABS[item.prefab] ~= nil then
            table.insert(lights, item)
        end
    end
    return lights
end

function M.MarkEquippedAILights(inst)
    if inst.components.inventory == nil then return end
    for _, item in ipairs(GetEquippedLights(inst)) do
        if item._my_friend_manual_light_until == nil then
            item._my_friend_ai_light = true
        end
    end
end

function M.HasUsableEquippedLight(inst)
    return inst ~= nil and inst.components ~= nil
        and inst.components.inventory ~= nil and #GetEquippedLights(inst) > 0
end

local function EnsureEquippedLightActive(inst)
    local inventory = inst ~= nil and inst.components ~= nil
        and inst.components.inventory or nil
    if inventory == nil then return end
    for _, item in ipairs(GetEquippedLights(inst)) do
        local machine = item.components.machine
        if machine ~= nil and not machine:IsOn() and machine:CanInteract() then
            machine:TurnOn()
        else
            local needs_callback = item.prefab == "minerhat" and item._light == nil
                or (item.prefab == "torch" or item.prefab == "lighter") and item.fires == nil
                or item.prefab == "nightstick" and item.fire == nil
            local equip = item.components.equippable
            if needs_callback and equip ~= nil and equip.onequipfn ~= nil then
                equip.onequipfn(item, inst, false)
            end
        end
        -- Torch skins keep their real Light one level below the fire FX.
        -- Acquire only sleeping entities; the area releases them when left.
        local function KeepAwake(fx)
            if fx == nil then return end
            ActiveArea.KeepAwake(inst, fx)
            if fx._light ~= nil then ActiveArea.KeepAwake(inst, fx._light) end
        end
        KeepAwake(item._light)
        KeepAwake(item.fire)
        for _, fire in ipairs(item.fires or {}) do KeepAwake(fire) end
    end

end

local function LightScore(inst, item)
    local equippable = item.components.equippable
    local slot = equippable.equipslot
    local score = LIGHT_PREFABS[item.prefab] or 1
    if inst.components.inventory:GetEquippedItem(slot) == nil then
        score = score + 20
    end
    local current = inst.components.inventory:GetEquippedItem(slot)
    if current ~= nil and current:HasTag("backpack") then score = score - 30 end
    return score
end

function M.FindBestStoredLight(inst)
    local inventory = inst.components.inventory
    if inventory == nil then return end
    local best, bestscore
    for _, item in ipairs(inventory:ReferenceAllItems()) do
        if M.CanEquipLight(inst, item)
            and not item.components.equippable:IsEquipped() then
            local score = LightScore(inst, item)
            if bestscore == nil or score > bestscore then
                best, bestscore = item, score
            end
        end
    end
    return best
end

function M.EquipLight(inst, item)
    if not M.CanEquipLight(inst, item) then return false end
    -- A hand tool may have been equipped moments before a teleport. The
    -- ordinary loadout cooldown prevents cosmetic churn, but darkness while
    -- travelling is an actual survival emergency and must be allowed to
    -- replace that tool with a light.
    inst._my_friend_light_equip_override = true
    local equipped = inst.components.inventory:Equip(item)
    inst._my_friend_light_equip_override = nil
    if equipped == true then
        local actual = inst.components.inventory:GetEquippedItem(
            item.components.equippable.equipslot)
        if actual ~= nil then
            actual._my_friend_manual_light_until = nil
            actual._my_friend_ai_light = true
        end
        return true
    end
    return false
end

function M.EquipBestStoredLight(inst)
    local item = M.FindBestStoredLight(inst)
    return item ~= nil and M.EquipLight(inst, item) or false
end

local function GetTorchRecipe()
    return GetValidRecipe ~= nil and GetValidRecipe("torch") or nil
end

function M.CanCraftTorch(inst)
    local builder = inst.components.builder
    local recipe = GetTorchRecipe()
    return builder ~= nil and recipe ~= nil and builder:KnowsRecipe(recipe)
        and builder:HasIngredients(recipe)
end

function M.GetMissingTorchMaterials(inst)
    local inventory = inst.components.inventory
    local builder = inst.components.builder
    local recipe = GetTorchRecipe()
    if inventory == nil or builder == nil or recipe == nil
        or not builder:KnowsRecipe(recipe) then return end
    local missing = {}
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        if ingredient.type ~= nil and ingredient.amount ~= nil then
            local _, count = inventory:Has(ingredient.type, ingredient.amount)
            local needed = math.max(0, ingredient.amount - (count or 0))
            if needed > 0 then missing[ingredient.type] = needed end
        end
    end
    return next(missing) ~= nil and missing or nil
end

function M.HasLightReserve(inst)
    return M.HasUsableEquippedLight(inst)
        or M.FindBestStoredLight(inst) ~= nil
        or M.HasMaterialReserve(inst)
end

function M.HasMaterialReserve(inst)
    local inventory = inst.components.inventory
    if inventory == nil then return false end
    for _, prefab in ipairs({"cutgrass", "twigs", "log"}) do
        local has = inventory:Has(prefab, 10, true)
        if not has then return false end
    end
    return true
end

local function IsOwnedLight(inst, light)
    local source = light._lantern or light._owner
    if source == inst then return true end
    if type(source) == "table" and source.components ~= nil
        and source.components.inventoryitem ~= nil
        and source.components.inventoryitem:GetGrandOwner() == inst then return true end
    for _, item in ipairs(GetEquippedLights(inst)) do
        if light == item or light == item._light then return true end
    end
    local current = light
    for _ = 1, 5 do
        if current == inst then return true end
        current = current.entity ~= nil and current.entity:GetParent() or nil
        if current == nil then return false end
    end
    return false
end

local function LightReachesPoint(light, x, z)
    if light.Light == nil or not light.Light:IsEnabled() then return false end
    local radius = light.Light:GetRadius()
    return radius ~= nil and DistanceSqToPoint(light, x, z) <= (radius + .75) ^ 2
end

function M.IsPointExternallyLit(inst, point)
    if TheWorld.state.isday and not TheWorld:HasTag("cave") then return true end
    for _, light in ipairs(TheSim:FindEntities(point.x, 0, point.z,
        M.EXTERNAL_LIGHT_SCAN_RANGE, nil, LIGHT_CANT_TAGS)) do
        if not IsOwnedLight(inst, light) and LightReachesPoint(light, point.x, point.z) then return true end
    end
    return false
end

function M.IsExternallyLit(inst)
    if TheWorld ~= nil and TheWorld.state ~= nil and TheWorld.state.isday
        and not TheWorld:HasTag("cave") then
        return true
    end
    if M.CanSeeInDark(inst) then
        local supplied_by_equipment = false
        for _, item in ipairs(GetEquippedLights(inst)) do
            if item:HasTag("nightvision") then
                supplied_by_equipment = true
                break
            end
        end
        if not supplied_by_equipment then return true end
    end
    if TheSim == nil then return true end

    local x, y, z = inst.Transform:GetWorldPosition()
    local self_lit = M.HasUsableEquippedLight(inst)
    for _, light in ipairs(TheSim:FindEntities(x, y, z,
        M.EXTERNAL_LIGHT_SCAN_RANGE, nil, LIGHT_CANT_TAGS)) do
        if LightReachesPoint(light, x, z) then
            if IsOwnedLight(inst, light) then self_lit = true else return true end
        end
    end
    -- The light watcher can remain stale while a follower is outside the
    -- player's active area.  The nearby-light scan above is authoritative in
    -- that case: if no external light reaches this point, it is dark here.
    return false
end

local function StoreEquippedLight(inst, item)
    local inventory = inst.components.inventory
    local equippable = item.components.equippable
    if equippable.equipslot == EQUIPSLOTS.HEAD
        and GetTime() < (item._my_friend_player_equipped_until or 0) then return false end
    if equippable:ShouldPreventUnequipping() then return false end
    if inventory:CanAcceptCount(item, 1) < 1 then
        -- Swap with an already carried tool/hat: its slot can hold the light.
        for _, replacement in ipairs(inventory:ReferenceAllItems()) do
            local equip = replacement.components.equippable
            if replacement ~= item and equip ~= nil and not equip:IsEquipped()
                and equip.equipslot == equippable.equipslot and not equip:IsRestricted(inst)
                and not M.IsLightEquipment(replacement) then
                return inventory:Equip(replacement) == true
            end
        end
        return false
    end
    local removed = inventory:Unequip(equippable.equipslot)
    if removed == nil then return false end
    M.ClearLightOwnership(removed)
    inventory:GiveItem(removed, nil, inst:GetPosition())
    return true
end

function M.OnBuildItem(inst, item)
    if not M.IsLightEquipment(item) then return end
    item._my_friend_ai_light = true
    item._my_friend_manual_light_until = nil
    -- builditem fires before vanilla gives/equips the result.
    inst:DoTaskInTime(0, function()
        if not inst:IsValid() or not item:IsValid() then return end
        local inventory = inst.components.inventory
        local slot = item.components.equippable.equipslot
        if inventory ~= nil and inventory:GetEquippedItem(slot) == item
            and M.IsExternallyLit(inst) then StoreEquippedLight(inst, item) end
    end)
end

function M.UpdateEquipment(inst)
    if not IsAlive(inst) or inst:HasTag("playerghost") then return false end
    EnsureEquippedLightActive(inst)
    if not CanAct(inst) then return false end
    local dark = M.IsDark(inst)
    if Policy.IsBusy(inst) and not dark then return false end
    -- Combat owns the hand slot. Without this guard a rain umbrella or a
    -- light can replace the weapon between attack actions and then be
    -- replaced again on the next combat evaluation.
    if inst._my_friend_under_threat
        or inst.components.combat ~= nil and inst.components.combat.target ~= nil
        or GetTime() < (inst._my_friend_combat_hand_until or 0) then return end
    if dark then
        inst._my_friend_external_light_since = nil
        if M.EquipBestStoredLight(inst) then
            require("my_friend_dialogue").Say(inst, "dark")
            return true
        end
    elseif M.IsExternallyLit(inst) then
        inst._my_friend_external_light_since = inst._my_friend_external_light_since or GetTime()
        if GetTime() - inst._my_friend_external_light_since < M.LIGHT_STORE_DELAY then return end
        local daylight = TheWorld.state.isday and not TheWorld:HasTag("cave")
        for _, item in ipairs(GetEquippedLights(inst, true)) do
            if daylight or item._my_friend_ai_light
                or not M.ShouldHoldManualLight(GetTime(), item._my_friend_manual_light_until) then
                StoreEquippedLight(inst, item)
            end
        end
    else inst._my_friend_external_light_since = nil end
    return false
end

local function RememberUnmarkedPlayerLights(inst, now)
    for _, item in ipairs(GetEquippedLights(inst)) do
        if not item._my_friend_ai_light
            and item._my_friend_manual_light_until == nil then
            item._my_friend_manual_light_until = now
                + math.random(M.MANUAL_LIGHT_MIN_TIME, M.MANUAL_LIGHT_MAX_TIME)
        end
    end
end

function M.GetLightAction(inst)
    if not CanAct(inst) then return end
    local dark = M.IsDark(inst)
    if Policy.IsBusy(inst) and not dark then return end
    local now = GetTime()
    RememberUnmarkedPlayerLights(inst, now)

    if dark then
        if M.HasUsableEquippedLight(inst) or M.EquipBestStoredLight(inst) then return end
        if not M.CanCraftTorch(inst) then return end
        local action = BufferedAction(inst, nil,
            ACTIONS.MY_FRIEND_BUILD or ACTIONS.BUILD, nil,
            inst:GetPosition(), "torch")
        action:AddSuccessAction(function()
            if inst:IsValid() then
                M.MarkEquippedAILights(inst)
                if M.IsDark(inst) then M.EquipBestStoredLight(inst) end
            end
        end)
        return action
    end

    if not M.IsExternallyLit(inst) then
        inst._my_friend_external_light_since = nil
        return
    end
    inst._my_friend_external_light_since = inst._my_friend_external_light_since or now
    if now - inst._my_friend_external_light_since < M.LIGHT_STORE_DELAY then return end
    for _, item in ipairs(GetEquippedLights(inst, true)) do
        local should_store = TheWorld.state.isday and not TheWorld:HasTag("cave")
            or item._my_friend_ai_light
            or not item._my_friend_ai_light
                and not M.ShouldHoldManualLight(now, item._my_friend_manual_light_until)
        if should_store then
            if StoreEquippedLight(inst, item) then return end
        end
    end
end

local function IsThreat(inst, entity)
    local combat = entity ~= nil and entity.components ~= nil and entity.components.combat or nil
    return entity ~= inst and IsAlive(entity) and combat ~= nil and combat.target == inst
end

local function SegmentDistanceSq(px, pz, ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az
    local length = dx * dx + dz * dz
    if length <= .001 then
        dx, dz = px - ax, pz - az
        return dx * dx + dz * dz
    end
    local t = math.max(0, math.min(1,
        ((px - ax) * dx + (pz - az) * dz) / length))
    local qx, qz = ax + dx * t, az + dz * t
    dx, dz = px - qx, pz - qz
    return dx * dx + dz * dz
end

local function GetThreatPenalty(inst, x, z)
    local ix, iy, iz = inst.Transform:GetWorldPosition()
    local penalty = 0
    for _, entity in ipairs(TheSim:FindEntities(ix, iy, iz, 24,
        { "_combat" }, THREAT_CANT_TAGS)) do
        if IsThreat(inst, entity) then
            local tx, _, tz = entity.Transform:GetWorldPosition()
            local endpoint = math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2)
            local route = math.sqrt(SegmentDistanceSq(tx, tz, ix, iz, x, z))
            if route < 8 then
                penalty = penalty + (8 - route) * 250
            end
            if endpoint < 16 then
                penalty = penalty + (16 - endpoint) * 6
            end
        end
    end
    return penalty
end

local function GetApproachPoint(inst, light)
    local x, y, z = inst.Transform:GetWorldPosition()
    local lx, ly, lz = light.Transform:GetWorldPosition()
    local dx, dz = x - lx, z - lz
    local distance = math.sqrt(dx * dx + dz * dz)
    local radius = light.Light ~= nil and light.Light:GetRadius() or 4
    local clearance = math.max(.75, math.min((radius or 4) * .75, 4))
    if distance > .01 then
        lx = lx + dx / distance * clearance
        lz = lz + dz / distance * clearance
    end
    return Vector3(lx, ly, lz), clearance
end

function M.GetSeekLightAction(inst)
    if not CanAct(inst) or not M.IsDark(inst) then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    local bestlight, bestdistance, bestscore
    local range = Policy.GetLeader(inst) ~= nil and 20 or M.LIGHT_SEARCH_RANGE
    for _, light in ipairs(TheSim:FindEntities(x, y, z, range,
        nil, LIGHT_CANT_TAGS)) do
        if not IsOwnedLight(inst, light)
            and light.Light ~= nil and light.Light:IsEnabled() then
            local point, distance = GetApproachPoint(inst, light)
            local dx, dz = point.x - x, point.z - z
            local score = dx * dx + dz * dz
                + GetThreatPenalty(inst, point.x, point.z)
            if bestscore == nil or score < bestscore then
                bestlight, bestdistance, bestscore = light, distance, score
            end
        end
    end
    if bestlight == nil then return end
    inst._my_friend_light_refuge = bestlight
    local leader = Policy.GetLeader(inst)
    local action = BufferedAction(inst, bestlight, ACTIONS.WALKTO, nil, nil, nil, bestdistance)
    action.validfn = function()
        return Policy.GetLeader(inst) == leader and bestlight:IsValid()
            and bestlight.Light ~= nil and bestlight.Light:IsEnabled()
            and DistanceSqToPoint(bestlight, x, z) <= range^2
    end
    action:AddFailAction(function() inst._my_friend_light_refuge = nil end)
    return action
end

function M.ShouldWaitInLight(inst)
    -- Dusk still has usable ambient light, but waiting here prevents the
    -- independent-life planner from planting, stocking or crafting. The
    -- actual dark-phase light action will take over after night begins.
    if TheWorld.state.isdusk and not TheWorld.state.isnight
        and not TheWorld:HasTag("cave") then
        inst._my_friend_light_refuge = nil
        return false
    end
    if TheWorld.state.isday and not TheWorld:HasTag("cave") then
        inst._my_friend_light_refuge = nil
        return false
    end
    if not M.IsExternallyLit(inst) then return false end
    local refuge = inst._my_friend_light_refuge
    if Policy.GetLeader(inst) ~= nil then
        return refuge ~= nil and refuge:IsValid() and not M.HasUsableEquippedLight(inst)
            and M.FindBestStoredLight(inst) == nil
    end
    return not M.HasUsableEquippedLight(inst) and M.FindBestStoredLight(inst) == nil
end

return M
