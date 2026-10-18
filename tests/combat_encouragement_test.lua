-- Actual authenticated chat -> address/keyword parser -> dialogue -> speech.
package.path = "scripts/?.lua;" .. package.path
local now, tasks, spoken, follow_requests = 10, {}, {}, 0
GetTime = function() return now end
local friend, player, target
local function noop() end
package.loaded.my_friend_equip_slots = {}
package.loaded.my_friend_backpacks = {}
package.loaded.my_friend_policy = {
    IsLocalPlayer = function(p) return p == player end,
    GetLeader = function() return nil end,
}
package.loaded.my_friend_home = {IsAskPending = function() return false end}
package.loaded.my_friend_beefalo = {Riding = {}}
package.loaded.my_friend_special_commands = {Parse = noop}
package.loaded.my_friend_characters = {List = function() return {"wendy"} end}
package.loaded.my_friend_carry_backpack = {Answer = function() return false end}
package.loaded.my_friend_pets = {Parse = noop}
package.loaded.my_friend_possess = {GetCommandTarget = noop}
local Language = require("my_friend_strings")
local function entity(name)
    local inst = {name = name, components = {}, tags = {}}
    function inst:IsValid() return not self.removed end
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:GetDisplayName() return self.name end
    inst.components.health = {IsDead = function() return inst.dead == true end}
    function inst:DoTaskInTime(delay, fn)
        local task = {fn = fn, delay = delay}
        function task:Cancel() self.cancelled = true end
        tasks[#tasks + 1] = task
        return task
    end
    function inst:DoPeriodicTask() error("encouragement must not create periodic tasks") end
    return inst
end
local function pump()
    local pending = tasks; tasks = {}; now = now + .5
    for _, task in ipairs(pending) do if not task.cancelled then task.fn(friend) end end
end
for _, locale in ipairs({"zh", "zh_tw", "en", "ru"}) do
    now, tasks, spoken = now + 30, {}, {}
    Language.language = locale
    for _, module in ipairs({"my_friend_commands", "my_friend_dialogue", "my_friend_speech", "my_friend_chat"}) do
        package.loaded[module] = nil
    end
    STRINGS = {CHARACTER_TITLES = {}}
    friend, player, target = entity("Nova"), entity("Player"), entity("Hound")
    friend.prefab, friend.tags.my_friend, friend._my_friend_custom_name = "wendy", true, "Nova"
    player.userid = "KU_TEST"
    friend.components.combat = {target = target}
    friend.components.my_friend_affinity = {RequestFollow = function() follow_requests = follow_requests + 1; return true end}
    friend.components.talker = {IsTalking = function() return false end,
        Say = function(_, text, _, quiet) spoken[#spoken + 1] = {text = text, quiet = quiet} end}
    TheWorld = {ismastersim = true, _my_friend = friend}
    local Speech = require("my_friend_speech")
    Speech.BuildStrings()
    local Chat = require("my_friend_chat")
    local Commands = require("my_friend_commands")
    local source = require("my_friend_language").DialogueLines(locale)
    assert(#source.combat_encouragement_words >= 4 and Speech.CountFor(friend, "combat_encouraged") == 4)
    for _, line in ipairs(source.lines.combat_encouraged) do assert(type(line[1]) == "string" and line[1] ~= "") end
    local words = source.combat_encouragement_words
    local command = {id = "mine"}
    friend._my_friend_command = command
    friend._my_friend_decision = {task = "combat"}
    assert(not Chat.Dispatch(player, words[1], "rpc"), "a name is required")
    assert(not Chat.Dispatch(player, "Novalike " .. words[1], "rpc"), "respect name boundaries")
    assert(not Chat.Dispatch({}, "Nova " .. words[1], "rpc"), "reject unauthenticated senders")
    assert(Chat.Dispatch(player, "Nova " .. words[1], "rpc"), locale)
    assert(not Chat.Dispatch(player, "Nova " .. words[1], "native"), "native/RPC duplicate must not respond twice")
    assert(not Chat.Dispatch(player, "Nova " .. words[2], "rpc"), "queued replies suppress more encouragement")
    pump()
    assert(#spoken == 1 and spoken[1].quiet and spoken[1].text:find("Player", 1, true), "localized personal quiet response")
    assert(friend._my_friend_command == command and friend._my_friend_decision.task == "combat"
        and friend.components.combat.target == target, "speech must preserve commands and combat")
    assert(not Chat.Dispatch(player, "Nova " .. words[3], "rpc"), "six-second cooldown")
    now = now + 7
    friend.components.combat.target = nil
    assert(not Chat.Dispatch(player, "Nova " .. words[1], "rpc"), "idle companions must not react")
    friend.components.combat.target = target
    target.dead = true
    assert(not Chat.Dispatch(player, "Nova " .. words[1], "rpc"), "dead combat targets are not combat")
    target.dead, friend.tags.playerghost = false, true
    assert(not Chat.Dispatch(player, "Nova " .. words[1], "rpc"), "ghost companions cannot respond")
    friend.tags.playerghost = false
    assert(Chat.Dispatch(player, "Nova " .. words[1], "rpc")); pump()
    assert(#spoken == 2)
    now = now + 7
    local requests = follow_requests
    local follow_words
    for _, entry in ipairs(require("my_friend_language").CommandWords(locale)) do
        if entry.id == "follow" then follow_words = entry.keywords; break end
    end
    assert(Commands.Dispatch(friend, player, "Nova " .. follow_words[1] .. " " .. words[1]))
    assert(follow_requests == requests + 1 and #tasks == 0, "explicit commands take precedence")
end
print("PASS: combat-only named public encouragement in four languages, real speech queue, quiet animation safety, command precedence, cooldown, duplicate and player authentication guards")
