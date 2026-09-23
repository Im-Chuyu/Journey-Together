-- A backpack displaced by heavy lifting requires permission to retrieve.
-- Keep this trip separate from ordinary dropped/death backpack recovery.
local M = {}
local Slots = require("my_friend_equip_slots")
local Policy = require("my_friend_policy")
local Riding = require("my_friend_riding")
local Dialogue = require("my_friend_dialogue")
local Safety = require("my_friend_recovery_safety")

local function Held(inst, bag)
    return bag:IsValid() and bag.components.inventoryitem:GetGrandOwner() == inst
end

local function RidingNow(inst)
    return inst.components.rider ~= nil and inst.components.rider:IsRiding()
end

local function TripBeefalo(inst, bag)
    local beefalo = Riding.GetBeefalo(inst)
    if beefalo ~= nil then return beefalo end
    local container = bag.components.container
    for _, bell in pairs(container ~= nil and container.slots or {}) do
        if bell:HasTag("bell") and bell.GetBeefalo ~= nil then
            local ok, mount = pcall(bell.GetBeefalo, bell)
            if ok and Riding.IsAvailableBeefalo(inst, mount) then return mount end
        end
    end
end

local function Waiting(state)
    state.phase, state.empty_since, state.asked = "wait", nil, nil
    state.deadline, state.mount_tried = nil, nil
    state.trip = nil
end

function M.Cancel(inst)
    local state = inst._my_friend_carry_backpack
    if state ~= nil then Waiting(state) end
end

function M.Record(inst, bag)
    if bag == nil or not bag:IsValid() or Held(inst, bag)
        or Slots.IsEquipped(inst.components.inventory, bag)
        or Slots.GetHeavy(inst.components.inventory) == nil
        or bag.components.inventoryitem.owner ~= nil then return end
    require("my_friend_backpacks").MarkOwned(inst, bag)
    bag._my_friend_heavy_left = true
    inst._my_friend_carry_backpack = {bag = bag, phase = "wait"}
    inst._my_friend_backpack_target, inst._my_friend_backpack_action = nil, nil
    inst._my_friend_backpack_switch_prepared = nil
end

function M.Configure(inst)
    if inst._my_friend_carry_backpack_configured then return end
    inst._my_friend_carry_backpack_configured = true
    inst:ListenForEvent("onpickupitem", function(_, data)
        local item = data ~= nil and data.item or nil
        local bag = Slots.GetBackpack(inst.components.inventory)
        if bag == nil or item == nil or not item:HasTag("heavy") then return end
        -- PICKUP fires this before changing equipment. Check the actual result
        -- next tick: extra equipment slots may have kept the backpack on.
        inst:DoTaskInTime(0, function()
            if inst:IsValid() and item:IsValid()
                and Slots.IsEquipped(inst.components.inventory, item) then M.Record(inst, bag) end
        end)
    end)
    inst:ListenForEvent("equip", function(_, data)
        if data ~= nil and data.item ~= nil and data.item:HasTag("heavy") then M.Cancel(inst) end
    end)
end

local function State(inst)
    if inst == nil or not inst:IsValid() or inst.components == nil
        or inst.components.inventory == nil then return end
    local state = inst._my_friend_carry_backpack
    if state == nil then
        local bag = require("my_friend_backpacks").FindOwned(inst)
        if bag ~= nil and bag._my_friend_heavy_left then
            state = {bag = bag, phase = "wait"}
            inst._my_friend_carry_backpack = state
        end
    end
    return state
end

function M.BlocksRecovery(inst)
    local state = State(inst)
    return state ~= nil and state.bag:IsValid()
end

function M.Update(inst)
    local state = State(inst)
    if state == nil then return end
    local bag, leader = state.bag, Policy.GetLeader(inst)
    if not bag:IsValid() or not require("my_friend_backpacks").IsOwned(bag)
        or bag.components.inventoryitem.owner ~= nil and not Held(inst, bag) then
        if bag:IsValid() then bag._my_friend_heavy_left = nil end
        inst._my_friend_carry_backpack = nil
        return
    end
    if Held(inst, bag) and state.phase == "wait" then
        bag._my_friend_heavy_left = nil
        inst._my_friend_carry_backpack = nil
        return
    end
    if leader == nil or not leader:IsValid() or inst:HasTag("playerghost")
        or inst.components.health:IsDead() or Slots.GetHeavy(inst.components.inventory) ~= nil then
        Waiting(state)
        return state
    end
    if state.player ~= leader then Waiting(state) state.player = leader end
    local now = GetTime()
    if state.phase == "wait" then
        state.empty_since = state.empty_since or now
        if not state.asked and now - state.empty_since > 5 and not Policy.IsBusy(inst)
            and not inst._my_friend_under_threat then
            state.asked = true
            Dialogue.RandomReply(inst, "carry_backpack_ask")
        end
    elseif now > state.deadline then
        Waiting(state)
        -- Leave it pending without repeated requests after an unreachable trip.
        state.asked = true
        Dialogue.RandomReply(inst, "carry_backpack_failed")
    elseif Held(inst, bag) then
        state.phase = "return"
        bag._my_friend_heavy_left = nil
        if inst:GetDistanceSqToInst(leader) <= 4^2 then
            inst._my_friend_carry_backpack = nil
            Dialogue.RandomReply(inst, "carry_backpack_done")
            return
        end
    end
    return state
end

local YES = { ["可以"] = true, ["行"] = true, ["没问题"] = true, ["好"] = true,
    ["好的"] = true, yes = true, sure = true, ["go ahead"] = true, ok = true,
    okay = true, ["no problem"] = true }

function M.Answer(inst, player, message)
    local pending = inst._my_friend_carry_backpack
    if pending == nil or not pending.asked then return false end
    local state = M.Update(inst)
    if state == nil or state.phase ~= "wait" or not state.asked
        or state.empty_since == nil or GetTime() - state.empty_since <= 5
        or state.player ~= player or Policy.GetLeader(inst) ~= player
        or Slots.GetHeavy(inst.components.inventory) ~= nil then return false end
    local answer = message:lower():gsub("[,%.!?:;]", "")
        :gsub("。", ""):gsub("！", ""):gsub("？", ""):gsub("，", ""):gsub("：", "")
        :match("^%s*(.-)%s*$")
    if not YES[answer] then return false end
    require("my_friend_commands").Clear(inst)
    state.phase, state.deadline, state.mount_tried = "fetch", GetTime() + 180, nil
    state.trip = {}
    local slot = state.bag.components.equippable.equipslot
    if inst._my_friend_equip_after ~= nil then inst._my_friend_equip_after[slot] = nil end
    Dialogue.RandomReply(inst, "carry_backpack_yes")
    inst._my_friend_replan_requested = true
    return true
end

function M.Score(inst)
    local state = M.Update(inst)
    return state ~= nil and state.phase ~= "wait" and 117 or 0
end

function M.IsTravelAction(inst, action)
    local state = inst._my_friend_carry_backpack
    return state ~= nil and action._my_friend_carry_backpack == state
        and action._my_friend_carry_backpack_trip == state.trip and state.trip ~= nil
        and state.phase ~= "wait" and GetTime() <= state.deadline
        and Policy.GetLeader(inst) == state.player
        and Slots.GetHeavy(inst.components.inventory) == nil
end

local function Track(inst, state, action)
    if action == nil then return end
    action._my_friend_carry_backpack = state
    action._my_friend_carry_backpack_trip = state.trip
    local valid = action.validfn
    action.validfn = function(act)
        return M.IsTravelAction(inst, act) and (valid == nil or valid(act))
    end
    action:AddFailAction(function()
        if not action._my_friend_cancelled and M.IsTravelAction(inst, action) then
            -- A mount can clear its buffered action while successfully mounting.
            if action.action == ACTIONS.MOUNT then state.mount_tried = true return end
            Waiting(state)
            state.asked = true
            Dialogue.RandomReply(inst, "carry_backpack_failed")
        end
    end)
    return action
end

function M.GetAction(inst)
    local state = M.Update(inst)
    if state == nil or state.phase == "wait" or Policy.IsBusy(inst)
        or inst._my_friend_under_threat then return end
    if not RidingNow(inst) and not state.mount_tried then
        local beefalo = TripBeefalo(inst, state.bag)
        if beefalo ~= nil and Safety.IsSafe(inst, beefalo:GetPosition()) then
            local action = Riding.GetMountAction(inst, beefalo)
            if action ~= nil then
                action:AddSuccessAction(function() state.mount_tried = true end)
                return Track(inst, state, action)
            end
        end
    end
    if state.phase == "return" then
        local action = BufferedAction(inst, state.player, ACTIONS.WALKTO)
        action.arrivedist = 3
        return Track(inst, state, action)
    end
    local bag = state.bag
    local action = BufferedAction(inst, bag, ACTIONS.PICKUP)
    action.validfn = function()
        if not bag:IsValid() then return false end
        local item, equip = bag.components.inventoryitem, bag.components.equippable
        local current = inst.components.inventory:GetEquippedItem(equip.equipslot)
        return not bag:IsInLimbo() and item.owner == nil and item.canbepickedup
            and not equip:IsRestricted(inst)
            and (current == nil or not current.components.equippable:ShouldPreventUnequipping())
            and require("my_friend_equipment").Allowed(inst, equip.equipslot)
            and Safety.IsSafe(inst, bag:GetPosition())
    end
    action:AddSuccessAction(function()
        if Held(inst, bag) then
            if not Slots.IsEquipped(inst.components.inventory, bag) then
                inst.components.inventory:Equip(bag)
            end
            bag._my_friend_heavy_left = nil
            state.phase, state.deadline = "return", GetTime() + 180
        end
    end)
    return Track(inst, state, action)
end

return M
