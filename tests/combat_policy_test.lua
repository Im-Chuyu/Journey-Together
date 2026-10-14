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
print("PASS: shadows and all tagged hounds engage, forced retreat skips them, and awake brightshade stays protected")
