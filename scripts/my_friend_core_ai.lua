local BehaviourAI = require("my_friend_behavior_ai")
local InventoryAI = require("my_friend_inventory")
local Policy = require("my_friend_policy")

local M = {}

M.OPPORTUNITY_BATCH_SIZE = 6
M.OPPORTUNITY_PAUSE = 3
M.STACK_MERGE_INTERVAL = .75
M.GREETING_RANGE = 8
M.GREETING_COOLDOWN = 240
M.GREETING_INTERVAL = 1.5
M.GREETING_PAUSE = 5

local function CanMaintainInventory(inst)
    return inst ~= nil and inst:IsValid() and not inst:HasTag("playerghost")
        and inst.components ~= nil and inst.components.inventory ~= nil
        and not inst._my_friend_backpack_action
        and inst._my_friend_backpack_target == nil
        and not inst._my_friend_container_action
        and not inst._my_friend_storage_action
        and (inst.sg == nil or not inst.sg:HasStateTag("busy"))
end

local function GetCarriedSlots(inst)
    local inventory = inst.components.inventory
    local slots = {}
    for index = 1, inventory.maxslots do
        local item = inventory:GetItemInSlot(index)
        if item ~= nil then
            slots[#slots + 1] = { storage = inventory, slot = index, item = item }
        end
    end
    local overflow = inventory:GetOverflowContainer()
    if overflow ~= nil then
        for index = 1, overflow:GetNumSlots() do
            local item = overflow:GetItemInSlot(index)
            if item ~= nil then
                slots[#slots + 1] = { storage = overflow, slot = index, item = item }
            end
        end
    end
    return slots
end

function M.CanMergeStacks(target, source)
    return InventoryAI.CanMerge(target, source)
end

function M.MergeOneStack(inst)
    if not CanMaintainInventory(inst) then return false end
    if inst._my_friend_chest_transfer ~= nil then return false end
    local now = GetTime()
    if now < (inst._my_friend_next_stack_merge or 0) then return false end
    inst._my_friend_next_stack_merge = now + M.STACK_MERGE_INTERVAL

    local root = inst.brain ~= nil and inst.brain.bt ~= nil and inst.brain.bt.root or nil
    local node = root ~= nil and root.active ~= nil and root.active.node or nil
    local action = node ~= nil and node.action or inst:GetBufferedAction()
    local excluded = action ~= nil and action.invobject or nil
    if require("my_friend_food_storage").StoreOnePrepared(inst, excluded) then return true end
    local merged = false
    for _ = 1, 6 do
        if not InventoryAI.Merge(GetCarriedSlots(inst), inst:GetPosition(), excluded) then break end
        merged = true
    end
    return merged
end

function M.GetOpportunityAction(inst)
    if not CanMaintainInventory(inst) then return end
    M.MergeOneStack(inst)

    local action = BehaviourAI.GetFoodOrResourceAction(inst)
    if action == nil then
        inst._my_friend_opportunity_batch = 0
        return
    end
    return action
end

function M.IsGreetingReady(now, cooldown_until)
    return cooldown_until == nil or now >= cooldown_until
end

function M.IsGreetingPauseActive(inst, now)
    return inst ~= nil and (now or GetTime())
        < (inst._my_friend_greeting_pause_until or 0)
end

function M.CanPauseForGreeting(inst)
    local root = inst.brain ~= nil and inst.brain.bt ~= nil and inst.brain.bt.root or nil
    local active = root ~= nil and root.active or nil
    -- Action ownership includes approaching the site and the gap between two
    -- plants. An idle SG tag alone does not mean the work can be interrupted.
    return not Policy.IsBusy(inst) and inst:GetBufferedAction() == nil
        and (active == nil or active.passive == true)
end

local function IsGreetingPlayer(inst, player, now)
    if player == nil or player == inst or not player:IsValid()
        or player:HasAnyTag("playerghost", "INLIMBO", "my_friend") then return false end
    -- The leader already has a continuous follow interaction. Greeting them
    -- here would make the companion stop in place and interrupt following.
    if Policy.GetLeader(inst) == player then return false end
    local health = player.components ~= nil and player.components.health or nil
    if inst.components.my_friend_affinity ~= nil
        and inst.components.my_friend_affinity:Get(player) < -20 then return false end
    if health ~= nil and health:IsDead() then return false end
    local key = player.userid or player.GUID
    if not M.IsGreetingReady(now, inst._my_friend_greeting_cooldowns[key]) then
        return false
    end
    local x, _, z = inst.Transform:GetWorldPosition()
    local px, _, pz = player.Transform:GetWorldPosition()
    return (px - x) * (px - x) + (pz - z) * (pz - z)
        <= M.GREETING_RANGE * M.GREETING_RANGE
end

function M.UpdateGreetings(inst)
    if inst == nil or not inst:IsValid() or inst:HasTag("playerghost")
        or inst.components == nil or inst.components.talker == nil then return false end
    local health = inst.components.health
    if health ~= nil and health:IsDead() then return false end
    if inst._my_friend_under_threat or Policy.IsBusy(inst)
        or inst.components.combat ~= nil and inst.components.combat.target ~= nil
        or M.IsGreetingPauseActive(inst) then return false end
    local now = GetTime()
    if now < (inst._my_friend_next_greeting or 0) then return false end
    inst._my_friend_greeting_cooldowns = inst._my_friend_greeting_cooldowns or {}

    local players = AllPlayers or {}
    local count = #players
    if count == 0 then
        inst._my_friend_next_greeting = now + .5
        return false
    end
    local start = (inst._my_friend_greeting_index or 0) % count + 1
    for offset = 0, count - 1 do
        local index = (start + offset - 1) % count + 1
        local player = players[index]
        if IsGreetingPlayer(inst, player, now) then
            local key = player.userid or player.GUID
            local name = player.name ~= nil and player.name ~= "" and player.name
                or require("my_friend_strings").Text("朋友", "friend")
            inst._my_friend_greeting_cooldowns[key] = now + M.GREETING_COOLDOWN
            inst._my_friend_greeting_index = index
            inst._my_friend_next_greeting = now + M.GREETING_INTERVAL
            inst._my_friend_greeting_pause_until = M.CanPauseForGreeting(inst)
                and now + M.GREETING_PAUSE or nil
            require("my_friend_speech").Random(inst, "greeting", 4, name, true)
            return true
        end
    end
    inst._my_friend_next_greeting = now + .5
    return false
end

return M
