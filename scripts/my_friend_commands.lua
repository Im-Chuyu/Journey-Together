local M = {}
local EquipSlots = require("my_friend_equip_slots")
local handlers = {}
local Backpacks = require("my_friend_backpacks")
local Policy = require("my_friend_policy")
local Home = require("my_friend_home")
local Dialogue = require("my_friend_dialogue")
local Riding = require("my_friend_beefalo").Riding
local SpecialCommands = require("my_friend_special_commands")
local Language = require("my_friend_strings")
local LanguageFiles = require("my_friend_language")

-- Keywords live in my_friend_command_words.lua, which is meant to be edited.
-- Anything malformed there is skipped with a log line rather than taking the
-- whole mod down, so a typo in the config never stops the world from loading.
local COMMANDS = {}
do
    local configured = LanguageFiles.CommandWords(Language.language)
    if type(configured) ~= "table" then
        print("[MyFriends] my_friend_command_words.lua could not be read: "
            .. tostring(configured))
        configured = {}
    end
    for _, entry in ipairs(configured) do
        if type(entry) == "table" and type(entry.id) == "string" then
            local words = {}
            for _, list in ipairs({entry.keywords, entry[Language.language], entry.zh, entry.en}) do
                for _, word in ipairs(type(list) == "table" and list or {}) do
                    if type(word) == "string" then
                        word = word:lower():match("^%s*(.-)%s*$")
                        if #word > 0 then words[#words + 1] = word end
                    end
                end
            end
            if #words > 0 then
            COMMANDS[#COMMANDS + 1] = {id = entry.id, words = words}
        end
    end
    local ok_packs, packs = pcall(require, "my_friend_command_word_packs")
    if ok_packs and type(packs) == "table" then
        for _, module_name in ipairs(packs) do
            if type(module_name) == "string" then
                local pack = LanguageFiles.Pack(Language.language, module_name)
                local loaded = type(pack) == "table"
                if loaded and type(pack) == "table" then
                    for _, entry in ipairs(pack) do
                        if type(entry) == "table" and type(entry.id) == "string" then
                            local words = {}
                            for _, list in ipairs({entry.keywords, entry[Language.language], entry.zh, entry.en}) do
                                for _, word in ipairs(type(list) == "table" and list or {}) do
                                    if type(word) == "string" then
                                        word = word:lower():match("^%s*(.-)%s*$")
                                        if #word > 0 then words[#words + 1] = word end
                                    end
                                end
                            end
                            if #words > 0 then
                                COMMANDS[#COMMANDS + 1] = {id = entry.id, words = words}
                            end
                        end
                    end
                end
            end
        end
    end
    end
    if #COMMANDS == 0 then
        print("[MyFriends] No usable chat keywords were configured.")
    end
end

-- Extra names players commonly type. Purely additive; the prefab name and
-- the character's own title are always accepted.
local ALIASES = {
    wendy = {"温蒂", "温迪"},
    wickerbottom = {"维克巴顿", "薇克巴顿", "奶奶", "奶"},
    warly = {"沃利", "大厨"},
}

local function Contains(text, word)
    if word:find("[a-z]") then
        local start = 1
        while true do
            local first, last = text:find(word, start, true)
            if first == nil then return false end
            if not text:sub(first - 1, first - 1):match("[%a%d_]")
                and not text:sub(last + 1, last + 1):match("[%a%d_]") then return true end
            start = last + 1
        end
    end
    return text:find(word, 1, true) ~= nil
end

function M.Get(friend)
    local command = friend ~= nil and friend._my_friend_command or nil
    if command ~= nil and (not Policy.IsLocalPlayer(command.player)
        or Policy.GetLeader(friend) ~= command.player or GetTime() >= command.deadline) then
        M.Clear(friend)
        return
    end
    return command
end

function M.Clear(friend)
    if friend == nil then return end
    local old = friend._my_friend_command
    if old ~= nil and old.id == "fish" then require("my_friend_fishing").Cancel(friend, old) end
    if old ~= nil and old.id == "butterfly" and friend.components.combat ~= nil
        and friend.components.combat.target == old.butterfly_target then
        friend.components.combat:SetTarget(nil)
    end
    if old ~= nil and old.special == "read" then require("my_friend_books").Close(friend, old) end
    if friend._my_friend_meal ~= nil and friend._my_friend_meal.command == old then
        require("my_friend_container_ai").Cancel(friend)
    end
    local container = old ~= nil and old.food_container or nil
    if container ~= nil and container:IsValid() and container.components.container ~= nil then
        container.components.container:Close(friend)
    end
    friend._my_friend_command = nil
    friend._my_friend_rockfruit_question = nil
    friend._my_friend_seat_request = nil
    friend._my_friend_follow_requested_until = nil
    friend._my_friend_follow_settle_until = nil
    friend._my_friend_replan_requested = true
    friend._my_friend_work_target, friend._my_friend_work_action = nil, nil
    friend._my_friend_work_left, friend._my_friend_work_stall_deadline = nil, nil
    friend._my_friend_hand_tool_lock_until = nil
    friend._my_friend_forest_clear_target = nil
    friend._my_friend_backpack_target, friend._my_friend_backpack_action = nil, nil
    friend._my_friend_backpack_switch_prepared = nil
    require("my_friend_recipe_cooking").Cancel(friend)
end

function M.Register(command, handler)
    assert(type(command) == "string" and type(handler) == "function")
    handlers[command:lower():match("^%s*(.-)%s*$")] = handler
end

local WORK = {chop = true, mine = true, harvest = true, hoe = true, water = true, tidy = true,
    seeds = true, equipment = true, dig_grass = true, dig_sapling = true, dig_stump = true,
    butterfly = true, fish = true, rockfruit = true, bullkelp = true, dry_meat = true,
    carry_statue = true}

-- Every reply line lives in my_friend_dialogue_lines.lua and is echoed into
-- the chat window of nearby players.
local function Reply(friend, key, argument)
    return Dialogue.Reply(friend, key, argument)
end

function M.Rename(friend, player, name)
    if type(name) ~= "string" or not Policy.IsLocalPlayer(player)
        or friend == nil or not friend:IsValid() or not friend:HasTag("my_friend")
        or friend:HasTag("playerghost") or friend.components.health == nil
        or friend.components.health:IsDead() then return false end
    local affinity = friend.components.my_friend_affinity
    if affinity == nil then return false end
    if affinity:Get(player) < 100 then
        Reply(friend, "affinity_name")
        return false
    end
    name = name:match("^%s*(.-)%s*$")
    if #name == 0 or #name > 48 or name:find("[%c<>|]") then
        Reply(friend, "name_invalid")
        return false
    end
    if friend.components.named == nil then friend:AddComponent("named") end
    friend._my_friend_custom_name = name
    friend.components.named:SetName(name, player.userid)
    Reply(friend, "name_ok", name)
    return true
end

local function AddressedMessage(friend, message)
    local text = message:lower()
    local names = {}
    if friend._my_friend_custom_name ~= nil and friend._my_friend_custom_name ~= "" then
        names[#names + 1] = friend._my_friend_custom_name:lower()
    end
    names[#names + 1] = friend:GetDisplayName():lower()
    names[#names + 1] = friend.prefab
    local title = STRINGS.CHARACTER_TITLES ~= nil
        and STRINGS.CHARACTER_TITLES[friend.prefab] or nil
    if type(title) == "string" and title ~= "" then names[#names + 1] = title:lower() end
    for _, alias in ipairs(ALIASES[friend.prefab] or {}) do names[#names + 1] = alias end
    if friend.prefab == "wickerbottom" then
        local current = friend._my_friend_custom_name or friend:GetDisplayName()
        if type(current) == "string" and current ~= "" then names[#names + 1] = "奶"..current:lower() end
    end
    local name_start, name_length
    for _, name in ipairs(names) do
        local first = name ~= "" and text:find(name, 1, true) or nil
        -- Prefer the address over names inside the command, and full names
        -- over prefixes at the same position.
        if first ~= nil and (name_start == nil or first < name_start
            or first == name_start and #name > name_length) then
            name_start, name_length = first, #name
        end
    end
    if name_start ~= nil then
        return message:sub(1, name_start - 1)..message:sub(name_start + name_length)
    end
end

local function FindCommand(friend, text)
    local id, length = nil, 0
    local answering = Home.IsAskPending(friend) or friend._my_friend_ghost_return_pending
    for _, command in ipairs(COMMANDS) do
        -- Answers only count while a question is pending. Longest keyword
        -- wins; configuration order breaks ties.
        if (command.id ~= "allow_pickup" or answering)
            and (command.id ~= "stop_fish" or friend._my_friend_command ~= nil
                and friend._my_friend_command.id == "fish")
            and (command.id ~= "revive" or friend:HasTag("playerghost")) then
            for _, word in ipairs(command.words) do
                if #word > length and Contains(text, word) then
                    id, length = command.id, #word
                end
            end
        end
    end
    return id
end

function M.Dispatch(friend, player, message)
    if type(message) ~= "string" or not Policy.IsLocalPlayer(player)
        or friend == nil or not friend:IsValid() or friend.components.health == nil then return false end
    message = message:match("^%s*(.-)%s*$")
    local addressed_message = AddressedMessage(friend, message)
    if addressed_message == nil then return false end
    local text = addressed_message:lower()
    -- The rock-fruit command has a short follow-up question. Handle it before
    -- normal keyword matching so "敲" cannot accidentally become "挖矿".
    local rock_question = friend._my_friend_rockfruit_question
    if rock_question ~= nil and rock_question.player == player
        and GetTime() < rock_question.deadline then
        if Contains(text, "不敲") or Contains(text, "别敲") or Contains(text, "不用敲")
            or Contains(text, "不要敲") then
            friend._my_friend_rockfruit_question = nil
            local command = friend._my_friend_command
            if command ~= nil and command.id == "rockfruit" then
                command.phase = "store"
                command.deadline = GetTime() + 180
            end
            Reply(friend, "rockfruit_store_answer")
            return true
        elseif Contains(text, "敲") or Contains(text, "要敲")
            or Contains(text, "继续") or Contains(text, "好") then
            friend._my_friend_rockfruit_question = nil
            local command = friend._my_friend_command
            if command ~= nil and command.id == "rockfruit" then
                -- Collected rock fruit is an inventory item, while the native
                -- MINE action only accepts the ground rock entity.  Let the
                -- command state drop the collected raw fruit first, then
                -- continue through the same native mining path used by a
                -- direct "敲石果" command.
                command.phase = "crack"
                command.deadline = GetTime() + 180
            end
            Reply(friend, "rockfruit_mine_answer")
            return true
        end
    end
    local pet = require("my_friend_pets").Parse(text)
    if pet ~= nil then return require("my_friend_pets").Request(friend, player, pet) end
    -- Parse names from the original case-preserving message, never from keywords.
    local rename = addressed_message:match("改名为%s*(.-)%s*$")
        or addressed_message:match("改名%s*(.-)%s*$")
    if rename == nil then
        local first, last = addressed_message:lower():find("rename to ", 1, true)
        if first == nil then first, last = addressed_message:lower():find("rename ", 1, true) end
        if first ~= nil then rename = addressed_message:sub(last + 1):match("^%s*(.-)%s*$") end
    end
    local affinity = friend.components.my_friend_affinity
    if rename ~= nil and affinity ~= nil then
        if rename:sub(1, 1) == ":" then rename = rename:sub(2)
        elseif rename:sub(1, #"：") == "：" then rename = rename:sub(#"：" + 1) end
        return M.Rename(friend, player, rename)
    end
    local id = FindCommand(friend, text)
    if friend:HasTag("playerghost") then
        local portal = Contains(text, "大门") or Contains(text, "绚丽之门")
            or Contains(text, "天体传送门") or Contains(text, "portal")
        if id == "revive" or portal then
            return require("my_friend_ghost_commands").Request(friend, player, portal)
        end
    end
    if id == "stop_ride" and (friend:HasTag("sitting_on_chair")
        or friend._my_friend_sitting ~= nil or friend._my_friend_seat_request ~= nil) then
        id = "stop_sit"
    end
    local special = SpecialCommands.Parse(friend, addressed_message, id ~= nil)
    if special ~= nil then
        if friend:HasTag("playerghost") or Policy.GetLeader(friend) ~= player then return false end
        M.Clear(friend)
        if special.special == "wendy_recall" then
            require("my_friend_abigail").Recall(friend, 480)
            Dialogue.Reply(friend, "special_recall")
        else
            friend._my_friend_command = {id = "special", special = special.special,
                recipe = special.recipe, target = special.target, spice = special.spice,
                food = special.food, player = player, started = GetTime(), deadline = GetTime() + 180}
            if special.special == "read" then
                require("my_friend_books").PrepareCommand(friend, friend._my_friend_command)
            elseif special.recipe == "bookstation" then
                require("my_friend_bookstation").PrepareCommand(friend._my_friend_command)
            end
            Dialogue.Reply(friend, special.special == "read" and "special_read_ok"
                or special.recipe == "bookstation" and "bookstation_prepare"
                or special.special == "spice" and "special_spice_ok" or "special_command_ok")
        end
        return true
    end
    if id == "ask_activity" then
        if friend:HasTag("playerghost") then return false end
        return Dialogue.AnswerActivity(friend)
    end
    if id == nil or affinity == nil then return false end
    if friend._my_friend_ghost_return_pending and id == "allow_pickup" then
        local return_player = friend._my_friend_ghost_return_player
        if return_player ~= player then return false end
        friend._my_friend_ghost_return_pending = nil
        friend._my_friend_ghost_return_player = nil
        affinity:RequestFollow(player)
        return true
    end
    -- A dead companion can still be ordered to follow its leader, but it must
    -- not enter any ordinary work, food, or inventory command while ghosted.
    if friend:HasTag("playerghost") and id ~= "follow" and id ~= "stop_follow" then
        return false
    end
    if id == "follow" then
        if not affinity:RequestFollow(player) then Reply(friend, "follow_unfamiliar") return false end
        if Policy.GetLeader(friend) == player then
            require("my_friend_ghost_commands").Cancel(friend)
            M.Clear(friend)
            Riding.AllowAutoRide(friend)
            friend._my_friend_greeting_pause_until = nil
            friend._my_friend_follow_requested_until = GetTime() + 30
            Reply(friend, "follow_ok")
        else Reply(friend, "follow_busy") end
        return true
    end
    if id == "ride" then
        if Policy.GetLeader(friend) ~= player then
            Reply(friend, "ride_not_following")
            return false
        end
        if not (friend.components.rider ~= nil and friend.components.rider:IsRiding())
            and Riding.GetBeefalo(friend) == nil then
            Reply(friend, "ride_unavailable")
            return false
        end
        if not Riding.RequestRide(friend, player) then
            Reply(friend, "ride_not_following")
            return false
        end
        M.Clear(friend)
        Reply(friend, "ride_ok")
        return true
    end
    if id == "stop_ride" then
        if Policy.GetLeader(friend) ~= player then return false end
        M.Clear(friend)
        Riding.StopRide(friend)
        Reply(friend, "ride_stop_ok")
        return true
    end
    if id == "allow_pickup" then return Home.GrantPickup(friend, player) end
    -- Sets how the next character change disposes of the companion's things.
    -- Gated by the same permission as the change itself, so a passer-by cannot
    -- arrange for the companion's gear to leave the world with it. Answered
    -- before the leader check below, because the free first change belongs to
    -- everyone standing nearby, not just the leader.
    if id == "farewell_gift" or id == "farewell_keep" then
        if not require("my_friend_farewell").CanRequest(friend, player) then
            Reply(friend, Policy.GetLeader(friend) ~= player
                and "switch_needs_follow" or "affinity_locked", "100")
            return false
        end
        friend._my_friend_farewell_gift = id == "farewell_gift" or nil
        Reply(friend, id == "farewell_gift" and "farewell_gift_ok"
            or "farewell_gift_cancel")
        return true
    end
    -- Waiting in place also works for a companion that already stopped
    -- following, as long as the player is standing next to it.
    if id == "hold_position" and Policy.GetLeader(friend) ~= player then
        if Policy.GetLeader(friend) ~= nil
            or friend:GetDistanceSqToInst(player) > 12^2 then return false end
        M.Clear(friend)
        Home.Set(friend, friend:GetPosition(), "hold")
        Reply(friend, "describe_hold")
        Dialogue.Say(friend, "hold_position", player)
        return true
    end
    if Policy.GetLeader(friend) ~= player then
        if id == "set_base" then Reply(friend, "base_needs_follow") end
        return false
    end
    if WORK[id] and not affinity:CanCommandWork(player) then
        Reply(friend, "affinity_work")
        return false
    end
    if (id == "backpack" or id == "backpack_drop") and not affinity:CanTakeItems(player) then
        Reply(friend, "affinity_items")
        return false
    end
    M.Clear(friend)
    if id == "stop_sit" then
        require("my_friend_sitting").StopSitting(friend)
        Reply(friend, "sit_stop_ok")
        return true
    end
    if id == "sit" then
        if not require("my_friend_sitting").Request(friend, player) then
            Reply(friend, "sit_unavailable")
            return false
        end
        if friend.components.rider ~= nil and friend.components.rider:IsRiding() then
            Riding.StopRide(friend)
        end
        Reply(friend, "describe_sit")
        return true
    end
    if id == "hold_position" then
        -- Stop following and live around this exact spot from now on.
        affinity:StopFollowing(player)
        Home.Set(friend, friend:GetPosition(), "hold")
        Reply(friend, "describe_hold")
        Dialogue.Say(friend, "hold_position", player)
        return true
    end
    if id == "set_base" then
        local origin = player:GetPosition()
        local anchor = Home.FindAnchor(friend, origin)
        Home.Set(friend, anchor ~= nil and anchor:GetPosition() or origin, "base")
        Reply(friend, "describe_base")
        Dialogue.Say(friend, "base_set", player)
        return true
    end
    if id == "stop_follow" then
        require("my_friend_ghost_commands").Cancel(friend)
        return affinity:StopFollowing(player)
    end
    if id == "stop_task" then
        friend._my_friend_command_drop = affinity:CanTakeItems(player) and true or nil
        return true
    end
    if id == "stop_fish" then
        friend._my_friend_follow_requested_until = GetTime() + 30
        Reply(friend, "follow_ok")
        return true
    end
    if id == "backpack" then
        local body = EquipSlots.GetBackpack(friend.components.inventory)
        local requested = Backpacks.Request(friend, body ~= nil and body:HasTag("backpack"))
        if not requested then Reply(friend, "no_backpack") end
        return requested
    end
    if id == "backpack_drop" then friend._my_friend_drop_backpack = true return true end
    friend._my_friend_command = {id = id, player = player, started = GetTime(),
        origin = player:GetPosition(),
        deadline = GetTime() + (id == "seeds" and 120 or (id == "tidy" or id == "chop"
            or id == "explore" or id == "fish") and math.huge
            or (id == "rockfruit" or id == "bullkelp" or id == "dry_meat") and 300
            or (id == "hoe" or id == "water" or id == "dig_grass"
                or id == "dig_sapling" or id == "dig_stump") and 600 or 180),
        charge_pending = WORK[id] == true}
    if id == "fish" then require("my_friend_fishing").Configure(friend) end
    Dialogue.Reply(friend, "describe_" .. id)
    return true
end

function M.Commit(friend, action)
    local command = M.Get(friend)
    if command == nil or action == nil then return action end
    if command.id == "chop" and not action._my_friend_chop_delivery then
        action._my_friend_command_origin = command.origin
    end
    local work = action.action
    if command.charge_pending and (work == ACTIONS.CHOP or work == ACTIONS.MINE
        or work == ACTIONS.PICK or work == ACTIONS.PICKUP or work == ACTIONS.HARVEST
        or work == ACTIONS.HAMMER or work == ACTIONS.DIG
        or command.id == "butterfly" and work == ACTIONS.ATTACK or work == ACTIONS.FISH
        or work == ACTIONS.TILL or work == ACTIONS.POUR_WATER_GROUNDTILE)
        and not action._my_friend_command_preparation then
        local affinity = friend.components.my_friend_affinity
        if not affinity:CanCommandWork(command.player) then M.Clear(friend) return end
        command.charge_pending = nil
        affinity:DoDelta(command.player, -.1, "work_command")
    end
    local previous = action.validfn
    action.validfn = function(act)
        return M.Get(friend) == command and (previous == nil or previous(act))
    end
    return action
end

return M
