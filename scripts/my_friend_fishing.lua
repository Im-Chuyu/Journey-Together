local Policy = require("my_friend_policy")
local Inventory = require("my_friend_inventory")
local Navigation = require("my_friend_navigation")
local Work = require("my_friend_command_work")
local Dialogue = require("my_friend_dialogue")
local M = {}

local function Command(inst)
    local command = inst._my_friend_command
    return Policy.IsRoaming(inst) and command.id == "fish" and command or nil
end

local function RodComponent(command)
    local rod = command ~= nil and command.fishing_rod or nil
    return rod ~= nil and rod:IsValid() and rod.components.fishingrod or nil
end

local function UsablePond(inst, pond, command)
    local fishable = pond ~= nil and pond:IsValid() and pond.components.fishable or nil
    return fishable ~= nil and not fishable:IsFrozenOver() and fishable:GetFishPercent() > 0
        and not pond:HasAnyTag("INLIMBO", "NOCLICK", "fire")
        and pond:GetCurrentPlatform() == inst:GetCurrentPlatform()
        and GetTime() >= ((command.pond_retry or {})[pond.GUID] or 0)
        and not Navigation.IsBlocked(inst, pond:GetPosition())
        and not require("my_friend_behavior_ai").IsTargetUnsafe(inst, pond)
end

function M.Cancel(inst, command)
    local rod = RodComponent(command)
    if rod ~= nil and rod.fisherman == inst then
        if rod:HasCaughtFish() then rod:Collect()
        elseif rod:HasHookedFish() then rod:Release()
        else rod:StopFishing() end
    end
    if inst.sg ~= nil and inst.sg:HasStateTag("fishing") and not inst.sg:HasStateTag("busy") then
        inst:PushEvent("fishingcancel")
    end
end

function M.Configure(inst)
    if inst._my_friend_fishing_configured then return end
    inst._my_friend_fishing_configured = true
    inst:ListenForEvent("fishingcollect", function(_, data)
        local command = Command(inst)
        local fish = data ~= nil and data.fish or nil
        if command == nil or fish == nil or not fish:IsValid() then return end
        -- The vanilla catch animation has already landed and revealed the fish.
        -- Defer the inventory move until FishingRod:Collect finishes its events.
        inst:DoTaskInTime(0, function()
            if not inst:IsValid() or not fish:IsValid() or fish.components.inventoryitem == nil
                or fish.components.inventoryitem.owner ~= nil then return end
            if not inst:HasTag("playerghost") and not inst.components.health:IsDead()
                and inst.components.inventory:CanAcceptCount(fish, 1) > 0 then
                Inventory.GiveCarried(inst, fish, inst:GetPosition())
                Dialogue.Say(inst, "fish_caught")
            else
                Dialogue.Say(inst, "fish_full")
            end
        end)
    end)
end

function M.IsWaiting(inst)
    local command = Command(inst)
    local rod = RodComponent(command)
    -- Keep the cast action alive until SGwilson performs FISH at frame 15.
    return command ~= nil and rod ~= nil and inst.sg ~= nil
        and (rod:IsFishing() or not inst.sg:HasStateTag("prefish"))
        and (inst.sg:HasStateTag("fishing") or inst.sg:HasStateTag("catchfish"))
end

function M.PrepareCast(inst, action)
    local command = Command(inst)
    local rod = action.invobject
    if command == nil or command.fishing_rod ~= rod or not rod:IsValid()
        or rod.components.inventoryitem:GetGrandOwner() ~= inst
        or not UsablePond(inst, action.target, command)
        or not require("my_friend_base_ai").CanUseHandToolInCurrentLight(inst) then return false end
    local inventory = inst.components.inventory
    if inventory:GetEquippedItem(EQUIPSLOTS.HANDS) ~= rod and not inventory:Equip(rod) then return false end
    inst._my_friend_hand_tool_lock_until = GetTime() + 3
    return true
end

local function Finish(inst, command, reply)
    if inst._my_friend_command == command then
        require("my_friend_commands").Clear(inst)
        Dialogue.Reply(inst, reply)
    end
end

function M.GetAction(inst)
    local command = Command(inst)
    if command == nil or Policy.IsBusy(inst) or M.IsWaiting(inst) then return end
    local rider = inst.components.rider
    if rider ~= nil and rider:IsRiding() then
        return BufferedAction(inst, nil, ACTIONS.DISMOUNT)
    end
    local rod = command.fishing_rod
    if rod ~= nil then
        if not rod:IsValid() or rod.components.finiteuses ~= nil and rod.components.finiteuses:GetUses() <= 0 then
            command.fishing_rod = nil
            command.fishing_replacing = true
            rod = nil
            Dialogue.Say(inst, "fish_replace")
        end
    end
    if rod ~= nil then
        local ii = rod.components.inventoryitem
        if ii == nil or ii:GetGrandOwner() ~= inst then
            if ii ~= nil and ii.owner == nil and ii.canbepickedup and Policy.InRange(inst, rod, 32)
                and inst.components.inventory:CanAcceptCount(rod, 1) > 0 then
                return BufferedAction(inst, rod, ACTIONS.PICKUP)
            end
            Finish(inst, command, "fish_rod_missing")
            return
        end
    else
        local preparation
        rod, preparation = Work.Tool(inst, command, ACTIONS.FISH, "fishingrod",
            not command.fishing_replacing, command.fishing_replacing)
        if preparation ~= nil then
            preparation._my_friend_dialogue_kind = "fish_prepare"
            return preparation
        end
        if rod == nil then
            Finish(inst, command, command.fishing_replacing and "fish_rod_done" or "fish_no_rod")
            return
        end
        command.fishing_rod = rod
    end
    if not require("my_friend_base_ai").CanUseHandToolInCurrentLight(inst) then return end
    local pond = command.pond
    if not UsablePond(inst, pond, command) then
        pond = nil
        local x, y, z = inst.Transform:GetWorldPosition()
        local distance
        for _, candidate in ipairs(TheSim:FindEntities(x, y, z, 40, {"fishable"}, {"INLIMBO"})) do
            if UsablePond(inst, candidate, command) then
                local d = inst:GetDistanceSqToInst(candidate)
                if distance == nil or d < distance then pond, distance = candidate, d end
            end
        end
        command.pond = pond
    end
    if pond == nil then return require("my_friend_exploration").GetAction(inst) end
    local action = BufferedAction(inst, pond, ACTIONS.FISH, rod)
    action._my_friend_roaming = command
    action._my_friend_dialogue_kind = "fish_cast"
    action.validfn = function()
        return inst._my_friend_command == command and rod:IsValid()
            and rod.components.inventoryitem:GetGrandOwner() == inst and UsablePond(inst, pond, command)
    end
    action:AddFailAction(function()
        M.Cancel(inst, command)
        if not action._my_friend_cancelled then
            command.pond_retry = command.pond_retry or {}
            command.pond_retry[pond.GUID] = GetTime() + 60
            command.pond = nil
        end
    end)
    return action
end

function M.UpdateWaiting(inst)
    local command = Command(inst)
    local rod = RodComponent(command)
    if rod == nil or not M.IsWaiting(inst) then return false end
    if not rod:IsFishing() then
        if inst.sg:HasStateTag("prefish") then return true end
        M.Cancel(inst, command)
        return false
    end
    -- REEL is the vanilla instant action: first hook a bite, then reel the fish.
    -- Catch animations finish through SGwilson and emit fishingcollect normally.
    if rod:HasHookedFish() or rod:FishIsBiting() then
        inst:PushBufferedAction(BufferedAction(inst, rod.target, ACTIONS.REEL, command.fishing_rod))
    elseif inst.sg.currentstate.name == "fishing" and not UsablePond(inst, rod.target, command) then
        M.Cancel(inst, command)
        return false
    end
    return true
end

return M
