-- Run from the mod root: lua tests/combat_policy_test.lua
package.path = "scripts/?.lua;" .. package.path
local now = 10
GetTime = function() return now end
EQUIPSLOTS = {HANDS = "hands"}
ACTIONS = {ATTACK = {}}
package.loaded.my_friend_food_ai = {}
package.loaded.my_friend_navigation = {}
package.loaded.my_friend_home = {}
package.loaded.my_friend_resource_reserves = {}
local leader, friend
package.loaded.my_friend_policy = {
    GetLeader = function() return leader end,
    IsLocalPlayer = function(p) return p == leader and p ~= nil end,
    IsRoaming = function() return false end,
    InRange = function() return true end,
    DistanceSq = function() return 4 end,
}
local function entity(prefab, tags)
    local value = {prefab = prefab, components = {health = {IsDead = function() return false end,
        GetPercent = function() return .1 end}, combat = {}}, tags = tags or {}}
    function value:IsValid() return true end
    function value:HasTag(tag) return self.tags[tag] == true end
    function value:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    return value
end
friend, leader = entity("wendy", {my_friend = true}), entity("wilson", {player = true})
friend.components.inventory = {GetEquippedItem = function() return nil end,
    ReferenceAllItems = function() return {} end}
local AI = require("my_friend_behavior_ai")
local Rules = require("my_friend_combat_rules")
for _, target in ipairs({entity("terrorbeak", {shadowcreature = true}),
    entity("firehound", {hound = true}), entity("icehound", {hound = true})}) do
    target.components.combat.target = friend
    assert(AI.CanCounterAttack(friend, target), "priority foes bypass low-health attack veto")
    AI.StartHurtRetreat(friend, target)
    assert(friend._my_friend_hurt_until == nil, "priority foes must not trigger forced hurt retreat")
    target.components.combat.target = leader
    assert(AI.IsPriorityEngaged(friend, target), "assist against hounds/shadows already attacking the player")
    assert(AI.CanCounterAttack(friend, target), "assist without requiring the player's first hit")
end
local plant = entity("lunarthrall_plant")
plant.components.combat.target = friend
assert(not AI.CanCounterAttack(friend, plant))
plant.tired = true
friend.components.health.GetPercent = function() return 1 end
assert(AI.CanCounterAttack(friend, plant), "a tired brightshade body can be counterattacked")
plant.tired = nil
friend.components.combat.CanTarget = function() return true end
Rules.Configure(friend)
assert(not friend.components.combat:CanTarget(plant))
plant.tired = true; assert(friend.components.combat:CanTarget(plant))
local vine = entity("lunarthrall_plant_vine_end")
assert(friend.components.combat:CanTarget(vine), "vines remain attackable")
TheWorld = {state = {cycles = 498}}
assert(Rules.IsActiveDefenceWorld(), "displayed day 499 enables general active defence")
friend.components.health.GetPercent = function() return .1 end
local boss = entity("deerclops", {epic = true})
boss.components.combat.target = friend
assert(AI.CanCounterAttack(friend, boss), "early worlds fight any self-hostile creature despite low health")
AI.StartHurtRetreat(friend, boss)
assert(friend._my_friend_hurt_until == nil)
boss.components.combat.target = leader
assert(AI.IsPriorityEngaged(friend, boss) and AI.CanCounterAttack(friend, boss),
    "a hostile creature attacking a player requires no prior player hit")
boss.components.combat.target = nil
assert(not AI.IsPriorityEngaged(friend, boss), "neutral creatures are not attacked without provocation")
plant.tired, plant.components.combat.target = nil, friend
assert(not AI.CanCounterAttack(friend, plant), "early active defence preserves brightshade reflection safety")
TheWorld.state.cycles = 499
assert(not Rules.IsActiveDefenceWorld(), "displayed day 500 restores the existing creature rules")
boss.components.combat.target = friend
assert(not AI.CanCounterAttack(friend, boss), "ordinary creatures regain the old low-health restriction")

-- Combat candidates and escape targets share one scan but have independent
-- rankings. An assistance candidate must not hide a direct attacker.
local entities, scans = {}, 0
friend.Transform = {GetWorldPosition = function() return 0, 0, 0 end}
TheSim = {FindEntities = function() scans = scans + 1; return entities end}
local personal = entity("spider")
local player_enemy = entity("hound", {hound = true})
personal.components.combat.target = friend
player_enemy.components.combat.target = leader
player_enemy._my_friend_player_attacks = {[leader] = {count = 1, time = now}}
entities = {personal, player_enemy}
assert(AI.FindThreat(friend) == player_enemy, "existing assistance ranking stays intact")
assert(AI.FindEscapeThreat(friend) == personal, "escape uses the direct attacker independently")
assert(scans == 1, "combat and escape must reuse the same world scan")
personal.components.combat.target = leader
assert(AI.FindEscapeThreat(friend) == nil, "cached attacker changing aggro stops escape immediately")
player_enemy.components.combat.target = friend
assert(AI.FindEscapeThreat(friend) == player_enemy, "cached combat candidate can become a direct threat")
assert(scans == 1, "aggro revalidation must not add scans")
player_enemy.components.combat.target = leader
friend.components.combat.lastattacker = player_enemy
friend.components.combat.lastwasattackedtime = now
assert(AI.FindEscapeThreat(friend) == player_enemy, "recently hurting the companion remains a personal threat")
friend.components.combat.lastattacker = nil

-- Load the real brain registration and snapshot, replacing only unrelated
-- game systems. Verify actual escape scoring, continuation and RunAway's
-- getter, plus the cancellation paths for ongoing fishing/container work.
local function noop() end
READY, RUNNING, SUCCESS, FAILED = 0, 1, 2, 3
BehaviourNode = {_ctor = noop}
Brain = {_ctor = function(self, inst) self.inst = inst end}
Class = function(base, ctor)
    local class = {_ctor = ctor}
    class.__index = class
    return setmetatable(class, {__index = base, __call = function(_, ...)
        local self = setmetatable({}, class)
        ctor(self, ...)
        return self
    end})
end
local function node() return {} end
WhileNode = function(condition, name, child) return {condition = condition, child = child} end
RunAway = function(_, selector) return {selector = selector} end
StandStill = node
BT = function(_, root) return {root = root} end
for _, name in ipairs({
    "behaviours/doaction", "behaviours/runaway", "behaviours/standstill",
    "behaviours/my_friend_combat", "behaviours/my_friend_ghost_follow", "behaviours/my_friend_fishing",
    "my_friend_food_ai", "my_friend_light_ai", "my_friend_container_ai", "my_friend_survival_ai",
    "my_friend_base_ai", "my_friend_backpacks", "my_friend_revive_ai", "my_friend_ghost_commands",
    "my_friend_core_ai", "my_friend_cooking_ai", "my_friend_recipe_cooking", "my_friend_tidy",
    "my_friend_navigation", "my_friend_commands", "my_friend_social_ai", "my_friend_emotes",
    "my_friend_sitting", "my_friend_beefalo", "my_friend_fishing", "my_friend_exploration",
    "my_friend_command_special_gather", "my_friend_platforms", "my_friend_farewell", "my_friend_wormhole",
    "my_friend_equipment", "my_friend_wanda", "my_friend_character_actions", "my_friend_wormwood",
    "my_friend_wortox", "my_friend_command_tower", "my_friend_rescue", "my_friend_butterfly",
    "my_friend_carry_backpack", "my_friend_fertilizer_search", "my_friend_books", "my_friend_feed_player",
    "my_friend_basic_equipment", "my_friend_pet_care",
}) do
    package.loaded[name] = setmetatable({}, {__index = function() return noop end, __call = node})
end
package.loaded.my_friend_beefalo.Riding = {Behaviour = node}
package.loaded["behaviours/my_friend_route_action"] = node
package.loaded["behaviours/my_friend_utility"] = function(_, entries, snapshot)
    return {entries = entries, snapshot = snapshot}
end
local policy = package.loaded.my_friend_policy
policy.IsBusy, policy.IsRoaming, policy.UpdateVigil = noop, noop, noop
policy.IsLeaderDead, policy.UpdateFollowRequest = noop, noop
local fishing_cancels, container_cancels = 0, 0
local fishing = package.loaded.my_friend_fishing
fishing.IsWaiting = function() return true end
fishing.Cancel = function() fishing_cancels = fishing_cancels + 1 end
local container = package.loaded.my_friend_container_ai
container.IsOwnFoodContainer = function() return true end
container.Cancel = function() container_cancels = container_cancels + 1 end
package.loaded.my_friend_commands.Get = function(inst) return inst._my_friend_command end
friend.components.hunger = {GetPercent = function() return 1 end}
function friend.components.combat:SetTarget(target) self.target = target end
local BrainClass = require("brains/my_friendbrain")
local brain = BrainClass(friend)
brain:OnStart()
local root, entries = brain.bt.root, {}
for _, entry in ipairs(brain.bt.root.entries) do entries[entry.id] = entry end
local old_counter, should_fight, checked = AI.CanCounterAttack, false, 0
AI.CanCounterAttack = function(_, target)
    checked = checked + 1
    return should_fight and Rules.CanAttack(target)
end
local function snapshot(target, accepted)
    now = now + 1
    friend._my_friend_threat_scan = nil
    friend._my_friend_wait_until = now + 30
    friend._my_friend_command = {id = "fish"}
    local chest = entity("treasurechest")
    chest.components.container = {IsOpenedBy = function() return false end}
    friend._my_friend_container_target = chest
    entities, should_fight = {target}, accepted
    fishing_cancels, container_cancels, checked = 0, 0, 0
    local before_scans = scans
    local context = root.snapshot()
    assert(scans == before_scans + 1, "brain snapshot shares the combat/escape scan")
    return context
end
for _, cycles in ipairs({498, 499}) do
    TheWorld.state.cycles = cycles
    player_enemy._my_friend_player_attacks = nil
    player_enemy.components.combat.target = leader
    local context = snapshot(player_enemy, false)
    assert(checked > 0, "player-hostile enemies still pass through existing combat qualification")
    assert(not context.canfight and context.threat == nil and context.escape_threat == nil)
    assert(not friend._my_friend_under_threat, "declining assistance must not flag a personal threat")
    assert(entries.escape.score(context) == 0 and not entries.escape.node.condition())
    assert(entries.escape.node.child.selector.getfn(friend) == nil)
    assert(fishing_cancels == 0 and container_cancels == 0,
        "declining assistance preserves fishing and container work")
    assert(friend._my_friend_wait_until > now and context.wait_for_me,
        "declining assistance preserves the current wait")
    context = snapshot(player_enemy, true)
    assert(context.canfight and context.threat == player_enemy and entries.combat.score(context) > 0)
    assert(entries.escape.score(context) == 0, "accepted assistance does not grant escape eligibility")
    assert(fishing_cancels == 1 and container_cancels == 1, "accepted combat may interrupt ordinary work")

    personal.components.combat.target = friend
    context = snapshot(personal, false)
    assert(context.threat == personal and context.escape_threat == personal)
    assert(entries.escape.score(context) > 0 and entries.escape.node.condition())
    assert(entries.escape.node.child.selector.getfn(friend) == personal)
    assert(fishing_cancels == 1 and container_cancels == 1, "direct danger still interrupts work")
    context = snapshot(personal, true)
    assert(context.canfight and entries.combat.score(context) > entries.escape.score(context),
        "a personal attacker still triggers fighting when qualified")

    -- The awake Brightshade may target the player but cannot be attacked;
    -- that rejection must not turn into a request to flee or abandon work.
    plant.components.combat.target, plant.tired = leader, nil
    context = snapshot(plant, true)
    assert(context.threat == nil and entries.escape.score(context) == 0)
    assert(fishing_cancels == 0 and container_cancels == 0)

    -- Ordinary leader attack records also qualify as combat candidates,
    -- including after the early-world active-defence rule expires.
    local assisted = entity("deerclops")
    assisted.components.combat.target = leader
    assisted._my_friend_player_attacks = {[leader] = {count = 1, time = now}}
    context = snapshot(assisted, false)
    assert(checked > 0 and context.threat == nil and entries.escape.score(context) == 0)
    assert(fishing_cancels == 0 and container_cancels == 0)
end
AI.CanCounterAttack = old_counter
-- Use the actual brain snapshot and scoped scores: environment escape wins
-- over assistance, normal combat and healing, including early priority foes.
Vector3 = function(x, y, z) return {x = x, y = y, z = z} end
function friend:GetPosition() return Vector3(0, 0, 0) end
AI.OnEnvironmentalDamage(friend, {amount = -5, cause = "miasma"})
local hazard_context = root.snapshot()
assert(hazard_context.hazard_retreat and hazard_context.hurt and hazard_context.hurt_evade)
assert(entries.hurt.score(hazard_context) == 170 and entries.hurt_wait.score(hazard_context) == 169)
for _, id in ipairs({"combat", "assist", "escape", "light", "watch_heal"}) do
    assert(entries[id].score(hazard_context) == 0, "area damage must take priority over " .. id)
end
print("PASS: combat policies, shared threat scan, personal-only escape, cached aggro revalidation, and declined assistance preserving ongoing work/waiting")
