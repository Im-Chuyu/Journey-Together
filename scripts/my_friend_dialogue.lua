local Speech = require("my_friend_speech")
local M = {}
local PERSONAL = {fed = true, fed_careful = true, gift = true,
    gift_food = true, gift_food_settled = true, gift_sack = true, pickup_allowed = true,
    ask_pickup = true, revived_thanks = true, revive_player = true, skin_changed = true,
    revive_drop = true, player_attack = true, player_takes_food = true, player_takes_sack = true}

local function Alive(inst)
    return inst:IsValid() and inst:HasTag("my_friend") and not inst:HasTag("playerghost")
        and inst.components.talker ~= nil and inst.components.health ~= nil
        and not inst.components.health:IsDead()
end

local function State(inst)
    if inst._my_friend_dialogue == nil then
        inst._my_friend_dialogue = {last = {}, after = {}, queue = {}, ambient_after = 0, speech_after = 0}
    end
    return inst._my_friend_dialogue
end

local Pump
local function Schedule(inst, state)
    if state.task == nil and #state.queue > 0 then
        state.task = inst:DoTaskInTime(.5, Pump)
    end
end

Pump = function(inst)
    local state = State(inst)
    state.task = nil
    if not Alive(inst) then state.queue = {} return end
    local now = GetTime()
    while state.queue[1] ~= nil and state.queue[1].expires <= now do table.remove(state.queue, 1) end
    local message = state.queue[1]
    if message == nil then return end
    local talker = inst.components.talker
    if talker:IsTalking() or talker.ignoring ~= nil or TheWorld.speechdisabled
        or now < state.speech_after
        or inst.sg ~= nil and inst.sg:HasStateTag("sleeping") then
        Schedule(inst, state)
        return
    end
    local count = Speech.CountFor(inst, message.kind)
    if count == 0 then
        table.remove(state.queue, 1)
        Schedule(inst, state)
        return
    end
    table.remove(state.queue, 1)
    local index = count > 1 and math.random(count - 1) or 1
    if count > 1 then
        if state.last[message.kind] ~= nil and index >= state.last[message.kind] then
            index = index + 1
        elseif state.last[message.kind] == nil then
            index = math.random(count)
        end
    end
    -- quiet keeps movement, eating and work animations untouched. This queue
    -- never issues movement or brain commands.
    Speech.Say(inst, message.kind, index, 4, message.name, true)
    state.last[message.kind] = index
    state.after[message.kind] = now + (PERSONAL[message.kind] and 6 or message.kind == "hurt" and 15 or 45)
    state.speech_after, state.ambient_after = now + 4, now + 18
    Schedule(inst, state)
end

function M.Say(inst, kind, player)
    if Speech.CountFor(inst, kind) == 0 or not Alive(inst) then return false end
    local state, now = State(inst), GetTime()
    if now < (state.after[kind] or 0) then return false end
    local personal = PERSONAL[kind]
    if not personal and (now < state.ambient_after or #state.queue > 0
        or inst.components.talker:IsTalking()) then return false end
    for _, pending in ipairs(state.queue) do if pending.kind == kind then return false end end
    if #state.queue >= 4 then return false end
    local message = {kind = kind, expires = now + (personal and 25 or 6),
        name = personal and player ~= nil and player:IsValid() and player:GetDisplayName() or nil}
    if personal then
        -- Direct player interactions take precedence over incidental work lines.
        for i = #state.queue, 1, -1 do
            if not PERSONAL[state.queue[i].kind] then table.remove(state.queue, i) end
        end
    end
    state.queue[#state.queue + 1] = message
    Schedule(inst, state)
    return true
end

-- Immediate, guaranteed reply to a chat command. Bypasses the ambient queue.
function M.Reply(inst, key, argument)
    if inst == nil or not inst:IsValid() or inst.components.talker == nil then return false end
    local state = State(inst)
    state.speech_after = GetTime() + 4
    return Speech.Reply(inst, key, argument)
end

local function HasText(text, value)
    return type(text) == "string" and text:find(value, 1, true) ~= nil
end

local function ActivityKey(inst)
    local task = inst._my_friend_current_task or ""
    local command = inst._my_friend_command
    local decision = inst._my_friend_decision
    if HasText(task, "砍树") then return "activity_chop"
    elseif HasText(task, "采矿") then return "activity_mine"
    elseif HasText(task, "挖") or HasText(task, "移植") then return "activity_dig"
    elseif HasText(task, "钓鱼") then return "activity_fish"
    elseif HasText(task, "探索") or HasText(task, "探路") then return "activity_explore"
    elseif HasText(task, "战斗") or HasText(task, "攻击") then return "activity_fight"
    elseif HasText(task, "喂") then return "activity_feed"
    elseif HasText(task, "整理") or HasText(task, "物资") or HasText(task, "箱子") then return "activity_tidy"
    elseif HasText(task, "烹饪") or HasText(task, "料理") or HasText(task, "做饭") then return "activity_cook"
    elseif HasText(task, "进食") or HasText(task, "吃饭") then return "activity_eat"
    elseif HasText(task, "制作") or HasText(task, "建造") then return "activity_build"
    elseif HasText(task, "跟随") then return "activity_follow"
    elseif HasText(task, "骑牛") then return "activity_ride"
    elseif HasText(task, "椅子") or HasText(task, "坐") then return "activity_sit"
    end
    if command ~= nil then
        local ids = {
            chop = "activity_chop", mine = "activity_mine", dig_grass = "activity_dig",
            dig_sapling = "activity_dig", dig_stump = "activity_dig", fish = "activity_fish",
            explore = "activity_explore", butterfly = "activity_fight", tidy = "activity_tidy",
            food = "activity_eat", cook = "activity_cook",
        }
        if ids[command.id] ~= nil then return ids[command.id] end
    end
    if decision ~= nil then
        local ids = {combat = "activity_fight", assist = "activity_fight",
            catch_up_mount = "activity_ride", catch_up = "activity_follow",
            follow = "activity_follow", sit = "activity_sit"}
        if ids[decision.task] ~= nil then return ids[decision.task] end
    end
    if inst.components ~= nil and inst.components.rider ~= nil
        and inst.components.rider:IsRiding() then return "activity_ride" end
    if inst.components ~= nil and inst.components.combat ~= nil
        and inst.components.combat.target ~= nil then return "activity_fight" end
    return "activity_idle"
end

function M.AnswerActivity(inst)
    if not Alive(inst) then return false end
    local state = State(inst)
    state.speech_after = GetTime() + 4
    return Speech.Random(inst, ActivityKey(inst), 7)
end

-- Arrivals, departures and ghost rescue calls use the world announcement
-- channel; ordinary chatter stays local.
function M.PublicSay(inst, kind, argument)
    if inst == nil or not inst:IsValid() or TheNet == nil
        or TheNet.Announce == nil then return M.Say(inst, kind) end
    local count = Speech.CountFor(inst, kind)
    if count == 0 then return false end
    local index = math.random(count)
    local text = Speech.Text(Speech.Key(inst, kind), index, argument)
    if text == nil then return false end
    TheNet:Announce(text)
    require("my_friend_voice").Play(inst, {duration = 2})
    return true
end

function M.OnAction(inst, action)
    if action._my_friend_fertilizer_wait then return end
    local names = {
        CHOP = "chop", MINE = "mine", PICK = "gather", PICKUP = "gather",
        HARVEST = "gather", DIG = "work", HAMMER = "work", TILL = "plant",
        DEPLOY = "plant", PLANT = "plant", FERTILIZE = "fertilize",
        POUR_WATER_GROUNDTILE = "plant", COOK = "cook",
        MY_FRIEND_STORE = "store", MY_FRIEND_ORGANIZE = "store",
        MY_FRIEND_WITHDRAW = "store", MY_FRIEND_HANDOVER = "store",
        MY_FRIEND_POCKET_RUMMAGE = "meal_open", MY_FRIEND_RETURN_FOOD = "meal_return",
        FEEDPLAYER = "feed_player",
        MY_FRIEND_COOKPOT_ADD = "beefalo_cook",
        MOUNT = "ride_mount", DISMOUNT = "ride_dismount",
    }
    local kind = action._my_friend_dialogue_kind or (action.action ~= nil and names[action.action.id] or nil)
    if action.target ~= nil and action.target.prefab == "gelblob_storage"
        and (action.action == ACTIONS.TAKEITEM or action.action == ACTIONS.TAKESINGLEITEM) then
        kind = "meal_take"
    end
    if kind == "plant" or kind == "fertilize" then
        if not action._my_friend_garden_dialogue then
            action._my_friend_garden_dialogue = true
            action:AddSuccessAction(function() M.Say(inst, kind) end)
        end
    elseif kind ~= nil then
        M.Say(inst, kind)
    end
end

function M.OnDecision(inst, task)
    local kinds = {follow = "follow", catch_up = "follow", catch_up_mount = "ride_chase", free = "idle",
        construction_wait = "idle", light_wait = "idle", combat = "fight",
        assist = "fight", escape = "flee", vigil = "vigil"}
    local kind = kinds[task]
    -- No dedicated vigil lines yet: fall back to the quiet idle chatter.
    if kind == "vigil" and Speech.CountFor(inst, "vigil") == 0 then kind = "idle" end
    if kind == "idle" then
        -- Idle chatter reflects where the companion is actually living.
        local Home = require("my_friend_home")
        local mode = Home.Mode(inst)
        if mode == "hold" then kind = "hold_idle"
        elseif mode == "base" then kind = "base_idle"
        elseif Home.IsLateJoin(inst) then
            kind = math.random() < .35 and "late_join" or "wander"
        end
    end
    if kind ~= nil then M.Say(inst, kind) end
end

function M.Gift(inst, player, item)
    if item ~= nil and item:IsValid() and item.components.equippable ~= nil
        and item.components.inventoryitem ~= nil
        and item.components.inventoryitem:GetGrandOwner() == inst then
        M.Say(inst, "gift", player)
    end
end

function M.Configure(inst)
    if inst._my_friend_dialogue_configured then return end
    inst._my_friend_dialogue_configured = true
    inst:ListenForEvent("oneat", function(_, data)
        local feeder = data ~= nil and data.feeder or nil
        if feeder ~= nil and feeder ~= inst and feeder.userid ~= nil then
            local unsafe = require("my_friend_feeding").IsUnsafe(data.food, inst)
            M.Say(inst, unsafe and "fed_careful" or "fed", feeder)
        else M.Say(inst, "eat") end
    end)
    inst:ListenForEvent("attacked", function(_, data)
        local attacker = data ~= nil and data.attacker or nil
        if attacker ~= nil and attacker:IsValid() and attacker:HasTag("player")
            and not attacker:HasTag("my_friend") then
            M.Say(inst, "player_attack", attacker)
        else
            M.Say(inst, "hurt")
        end
    end)
    inst:ListenForEvent("onattackother", function(_, data)
        local target = data ~= nil and (data.target or data.attacked) or nil
        local boss = target ~= nil and target.HasAnyTag ~= nil
            and target:HasAnyTag("epic", "largecreature", "boss")
        M.Say(inst, boss and "fight_boss" or "fight")
    end)
    inst:ListenForEvent("builditem", function() M.Say(inst, "build") end)
    inst:ListenForEvent("buildstructure", function() M.Say(inst, "build") end)
end

function M.ProtectStategraph(sg)
    local function Wrap(events)
        local handler = events ~= nil and events.ontalk or nil
        if handler == nil or handler._my_friend_dialogue_wrapped then return end
        handler._my_friend_dialogue_wrapped = true
        local fn = handler.fn
        handler.fn = function(inst, data, ...)
            -- Companion speech plays its voice independently, preserving the
            -- work/movement state and avoiding the SG's second sound loop.
            if inst:HasTag("my_friend") then return end
            return fn(inst, data, ...)
        end
    end
    Wrap(sg.events)
    for _, state in pairs(sg.states) do Wrap(state.events) end
end

return M
