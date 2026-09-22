-- Reviving nearby dead players and thanking whoever revives the companion.
local Policy = require("my_friend_policy")

local M = {}

M.RANGE = 20
M.SCORE = 116
M.RETRY_DELAY = 15
M.DROP_SPACING = 3

local GHOST_CANT_TAGS = { "INLIMBO", "my_friend" }

local function IsAlive(inst)
    return inst ~= nil and inst:IsValid() and not inst:HasTag("playerghost")
        and inst.components.health ~= nil and not inst.components.health:IsDead()
end

local function CanAct(inst)
    return IsAlive(inst) and inst.components.inventory ~= nil
        and not inst._my_friend_under_threat
        and not inst._my_friend_backpack_action
        and not inst._my_friend_container_action
        and not inst._my_friend_storage_action
        and not Policy.IsBusy(inst)
end

-- A telltale heart is handed straight to the ghost. Anything else that
-- resurrects when haunted (life giving amulet and the like) is dropped next
-- to the ghost for the player to haunt.
local function IsHeart(item)
    return item ~= nil and item:IsValid() and item:HasTag("reviver")
end

local function IsHauntRevival(item)
    return item ~= nil and item:IsValid() and not IsHeart(item)
        and item.components ~= nil and item.components.hauntable ~= nil
        and item.components.inventoryitem ~= nil
        and (item:HasTag("resurrector") or item.prefab == "amulet")
end

local function FindItem(inst, test)
    local inventory = inst.components.inventory
    if inventory == nil or inventory.ReferenceAllItems == nil then return end
    for _, item in ipairs(inventory:ReferenceAllItems()) do
        if test(item) then return item end
    end
end

local function GhostPlayers(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local ghosts = {}
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, M.RANGE,
        { "playerghost" }, GHOST_CANT_TAGS)) do
        if Policy.IsLocalPlayer(entity) and entity.userid ~= nil
            and entity.components.trader ~= nil then
            ghosts[#ghosts + 1] = entity
        end
    end
    table.sort(ghosts, function(a, b)
        return inst:GetDistanceSqToInst(a) < inst:GetDistanceSqToInst(b)
    end)
    return ghosts
end

local function HasRevivalNearby(ghost)
    local x, y, z = ghost.Transform:GetWorldPosition()
    for _, entity in ipairs(TheSim:FindEntities(x, y, z, M.DROP_SPACING,
        nil, { "INLIMBO" })) do
        if IsHauntRevival(entity) and entity.components.inventoryitem.owner == nil then
            return true
        end
    end
    return false
end

local function Retry(inst)
    inst._my_friend_rescue_retry = inst._my_friend_rescue_retry or {}
    return inst._my_friend_rescue_retry
end

function M.Score(inst)
    if not CanAct(inst) or GetTime() < (inst._my_friend_rescue_check_after or 0) then return 0 end
    -- Scanning every tick is wasteful; the answer rarely changes within a second.
    inst._my_friend_rescue_check_after = GetTime() + 1
    local has_heart = FindItem(inst, IsHeart) ~= nil
    local has_haunt = FindItem(inst, IsHauntRevival) ~= nil
    if not has_heart and not has_haunt then return 0 end
    local retry = Retry(inst)
    for _, ghost in ipairs(GhostPlayers(inst)) do
        if GetTime() >= (retry[ghost.userid] or 0)
            and (has_heart or not HasRevivalNearby(ghost)) then
            inst._my_friend_rescue_check_after = nil
            return M.SCORE
        end
    end
    return 0
end

function M.GetAction(inst)
    if not CanAct(inst) then return end
    local retry = Retry(inst)
    local heart = FindItem(inst, IsHeart)
    local haunt = heart == nil and FindItem(inst, IsHauntRevival) or nil
    if heart == nil and haunt == nil then return end
    for _, ghost in ipairs(GhostPlayers(inst)) do
        if GetTime() >= (retry[ghost.userid] or 0) then
            local action
            if heart ~= nil then
                -- Same as a player pressing the heart on the ghost.
                action = BufferedAction(inst, ghost, ACTIONS.GIVE, heart)
                action.validfn = function()
                    return IsHeart(heart) and ghost:IsValid() and ghost:HasTag("playerghost")
                        and heart.components.inventoryitem:GetGrandOwner() == inst
                        and ghost.components.trader ~= nil
                        and ghost.components.trader:AbleToAccept(heart, inst) == true
                end
                action:AddSuccessAction(function()
                    require("my_friend_dialogue").Say(inst, "revive_player", ghost)
                end)
            elseif not HasRevivalNearby(ghost) then
                -- One haunt revival item per ghost, dropped within reach.
                local point = ghost:GetPosition()
                local offset = FindWalkableOffset(point, math.random() * PI2, 1.5, 8, true, false)
                if offset ~= nil then point = point + offset end
                if inst:GetDistanceSqToPoint(point) > 2^2 then
                    action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, point)
                    action.arrivedist = 1.5
                else
                    action = BufferedAction(inst, nil, ACTIONS.DROP, haunt, point)
                    action.options.wholestack = false
                    action:AddSuccessAction(function()
                        require("my_friend_dialogue").Say(inst, "revive_drop", ghost)
                        retry[ghost.userid] = GetTime() + 60
                    end)
                end
            end
            if action ~= nil then
                action:AddFailAction(function()
                    if not action._my_friend_cancelled then
                        retry[ghost.userid] = GetTime() + M.RETRY_DELAY
                    end
                end)
                return Policy.GuardAction(inst, action, M.RANGE + 8)
            end
        end
    end
end

-- Whoever brought the companion back gets thanked, once per revival.
function M.Configure(inst)
    if inst._my_friend_rescue_configured then return end
    inst._my_friend_rescue_configured = true
    -- A telltale heart carries the giver; a revived corpse carries the reviver.
    -- Haunting the portal on its own has nobody to thank.
    inst:ListenForEvent("respawnfromghost", function(_, data)
        local user = data ~= nil and data.user or nil
        inst._my_friend_reviver = Policy.IsLocalPlayer(user) and user or nil
    end)
    inst:ListenForEvent("ms_respawnedfromghost", function(_, data)
        local reviver = inst._my_friend_reviver
        if reviver == nil and data ~= nil and Policy.IsLocalPlayer(data.reviver) then
            reviver = data.reviver
        end
        inst._my_friend_reviver = nil
        if reviver == nil then return end
        inst:DoTaskInTime(1.5, function()
            if not inst:IsValid() or inst:HasTag("playerghost")
                or not reviver:IsValid() then return end
            require("my_friend_dialogue").Say(inst, "revived_thanks", reviver)
            if inst.components.my_friend_affinity ~= nil then
                inst.components.my_friend_affinity:DoDelta(reviver, 5, "revive")
            end
        end)
    end)
end

return M
