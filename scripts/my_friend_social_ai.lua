local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")
local M = {}
local EquipSlots = require("my_friend_equip_slots")

function M.SaveCare(inst)
    local result = {}
    local now = GetTime()
    for userid, cooldowns in pairs(inst._my_friend_care_cooldowns or {}) do
        local saved = {}
        for kind, deadline in pairs(cooldowns) do
            if deadline > now then saved[kind] = math.min(120, deadline - now) end
        end
        if next(saved) ~= nil then result[userid] = saved end
    end
    return result
end

function M.LoadCare(inst, data)
    inst._my_friend_care_cooldowns = {}
    if type(data) ~= "table" then return end
    for userid, saved in pairs(data) do
        if type(userid) == "string" and type(saved) == "table" then
            local cooldowns = {}
            for _, kind in ipairs({"health", "hunger", "sanity"}) do
                local remaining = saved[kind]
                if type(remaining) == "number" and remaining == remaining then
                    cooldowns[kind] = GetTime() + math.min(120, math.max(0, remaining))
                end
            end
            inst._my_friend_care_cooldowns[userid] = cooldowns
        end
    end
end

function M.UpdateCare(inst)
    local leader = Policy.GetLeader(inst)
    if leader == nil or not Policy.IsLocalPlayer(leader) or leader:HasTag("playerghost")
        or inst:HasTag("playerghost") or inst.components.health:IsDead()
        or Policy.IsBusy(inst) or inst._my_friend_under_threat
        or inst.components.talker == nil or inst:GetDistanceSqToInst(leader) > 20^2 then return end
    local now = GetTime()
    if now < (inst._my_friend_care_speech_after or 0)
        or now < (inst._my_friend_greeting_pause_until or 0) then return end
    inst._my_friend_care_cooldowns = inst._my_friend_care_cooldowns or {}
    local key = leader.userid
    if key == nil then return end
    local cooldowns = inst._my_friend_care_cooldowns[key] or {}
    inst._my_friend_care_cooldowns[key] = cooldowns
    for _, entry in ipairs({{"health", .5}, {"hunger", .3}, {"sanity", .3}}) do
        local kind, threshold = entry[1], entry[2]
        local component = leader.components[kind]
        if component ~= nil and component:GetPercent() < threshold
            and now >= (cooldowns[kind] or 0) then
            require("my_friend_speech").Random(inst, "care_" .. kind, 5,
                leader:GetDisplayName())
            cooldowns[kind] = now + 120
            inst._my_friend_care_speech_after = now + 8
            inst._my_friend_next_greeting = math.max(inst._my_friend_next_greeting or 0, now + 8)
            return
        end
    end
end

function M.GetAvoidAction(inst)
    local affinity = inst.components.my_friend_affinity
    if affinity == nil or inst._my_friend_under_threat or Policy.IsBusy(inst)
        or GetTime() < (inst._my_friend_social_retry or 0) then return end
    local position = inst:GetPosition()
    local unwanted, closest = {}, nil
    for _, player in ipairs(AllPlayers or {}) do
        if Policy.IsLocalPlayer(player) and not player:HasTag("playerghost")
            and affinity:Get(player) < -20 and inst:GetDistanceSqToInst(player) < 7^2 then
            unwanted[#unwanted + 1] = player
            if closest == nil or inst:GetDistanceSqToInst(player) < inst:GetDistanceSqToInst(closest) then
                closest = player
            end
        end
    end
    if closest == nil then return end
    local source = closest:GetPosition()
    local angle = math.atan2(position.z - source.z, position.x - source.x)
    local best, bestscore
    for index = 0, 11 do
        local a = angle + index * 2 * math.pi / 12
        local point = Vector3(position.x + math.cos(a) * 4, 0, position.z + math.sin(a) * 4)
        if Navigation.IsLand(point) and Navigation.InTravelRange(inst, point)
            and Navigation.IsWalkClear(inst, position, point, Navigation.Caps(inst)) then
            local score = math.huge
            for _, player in ipairs(unwanted) do
                score = math.min(score, (point - player:GetPosition()):LengthSq())
            end
            if score > inst:GetDistanceSqToInst(closest) + 1
                and (bestscore == nil or score > bestscore) then best, bestscore = point, score end
        end
    end
    if best == nil then inst._my_friend_social_retry = GetTime() + 2 return end
    local action = BufferedAction(inst, nil, ACTIONS.WALKTO, nil, best)
    action.arrivedist = .5
    action:AddFailAction(function() inst._my_friend_social_retry = GetTime() + 2 end)
    return Policy.GuardAction(inst, action)
end

function M.GetDropAction(inst)
    local leader = Policy.GetLeader(inst)
    local affinity = inst.components.my_friend_affinity
    if leader == nil or not affinity:CanTakeItems(leader) then
        inst._my_friend_drop_backpack, inst._my_friend_command_drop = nil, nil
        return
    end
    if inst._my_friend_drop_backpack then
        local bag = EquipSlots.GetBackpack(inst.components.inventory)
        if bag == nil or not bag:HasTag("backpack")
            or bag.components.equippable:ShouldPreventUnequipping() then
            inst._my_friend_drop_backpack = nil
            return
        end
        local action = BufferedAction(inst, nil, ACTIONS.DROP, bag, inst:GetPosition())
        action.options.wholestack = true
        action:AddSuccessAction(function()
            require("my_friend_backpacks").ClearOwned(bag)
            inst._my_friend_drop_backpack = nil
            inst._my_friend_backpack_craft_after = GetTime() + 60
        end)
        action:AddFailAction(function() inst._my_friend_drop_backpack = nil end)
        return action
    end
    -- Stop-work surplus disposal is handled one stack at a time; keep tools,
    -- food, equipment and twenty units of each basic resource.
    if inst._my_friend_command_drop then
        local counts = {}
        local reserves = {cutgrass = 20, twigs = 20, log = 20, rocks = 20, flint = 20, goldnugget = 20}
        local items = inst.components.inventory:ReferenceAllItems()
        for _, item in ipairs(items) do
            counts[item.prefab] = (counts[item.prefab] or 0)
                + (item.components.stackable ~= nil and item.components.stackable:StackSize() or 1)
        end
        for _, item in ipairs(items) do
            local keep = reserves[item.prefab]
            if keep ~= nil and counts[item.prefab] > keep then
                local action = BufferedAction(inst, nil, ACTIONS.MY_FRIEND_DROP_SURPLUS, item, inst:GetPosition())
                action._my_friend_drop_count = math.min(counts[item.prefab] - keep,
                    item.components.stackable ~= nil and item.components.stackable:StackSize() or 1)
                action:AddFailAction(function() inst._my_friend_command_drop = nil end)
                return action
            end
        end
        inst._my_friend_command_drop = nil
    end
end

return M
