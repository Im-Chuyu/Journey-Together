package.path = "scripts/?.lua;" .. package.path
local now, guid, scans, moves, attacks, wakes = 10, 0, 0, 0, 0, 0
GetTime = function() return now end
Vector3 = function(x, y, z) return {x = x, y = y, z = z} end
EQUIPSLOTS = {HANDS = "hands", HEAD = "head", BODY = "body"}
ACTIONS = {ATTACK = {id = "ATTACK"}, WALKTO = {id = "WALKTO"}}
STRINGS = {CHARACTER_TITLES = {}}
TUNING = {TOTAL_DAY_TIME = 480}
READY, RUNNING, SUCCESS, FAILED = 0, 1, 2, 3
BehaviourNode = {}
function BehaviourNode._ctor(self) self.status = READY end
function BehaviourNode:Sleep(delay) self.nextupdatetime = now + delay end
function BehaviourNode:Reset() self.status = READY end
function BehaviourNode:Step() end
function BehaviourNode:Stop() if self.OnStop ~= nil then self:OnStop() end end
Brain = {_ctor = function(self, inst) self.inst = inst end}
Class = function(base, constructor)
    local class = {_ctor = constructor}
    class.__index = class
    return setmetatable(class, {__index = base, __call = function(_, ...)
        local value = setmetatable({}, class)
        constructor(value, ...)
        return value
    end})
end
local function empty_node()
    return setmetatable({status = READY, Visit = function(self) self.status = FAILED end}, {__index = BehaviourNode})
end
StandStill, RunAway = empty_node, empty_node
WhileNode = function(condition, _, child)
    local node = empty_node()
    node.children = {child}
    function node:Visit()
        if condition() then child:Visit(); self.status = child.status else self.status = FAILED end
    end
    function node:OnStop() child:Stop(); child:Reset() end
    return node
end
BT = function(_, root) return {root = root} end
local function noop() end
local function zero() return 0 end
local function stub()
    return setmetatable({}, {__index = function(_, key)
        if key:find("Score$") or key == "Priority" then return zero end
        return noop
    end, __call = empty_node})
end
for _, name in ipairs({"behaviours/doaction", "behaviours/runaway", "behaviours/standstill",
    "behaviours/my_friend_ghost_follow", "behaviours/my_friend_fishing",
    "my_friend_food_ai", "my_friend_light_ai", "my_friend_container_ai", "my_friend_survival_ai",
    "my_friend_base_ai", "my_friend_backpacks", "my_friend_revive_ai", "my_friend_ghost_commands",
    "my_friend_core_ai", "my_friend_cooking_ai", "my_friend_recipe_cooking", "my_friend_tidy",
    "my_friend_social_ai", "my_friend_emotes", "my_friend_sitting", "my_friend_fishing",
    "my_friend_exploration", "my_friend_command_special_gather", "my_friend_platforms",
    "my_friend_farewell", "my_friend_wormhole", "my_friend_equipment", "my_friend_wanda",
    "my_friend_character_actions", "my_friend_wormwood", "my_friend_wortox", "my_friend_command_tower",
    "my_friend_rescue", "my_friend_butterfly", "my_friend_carry_backpack", "my_friend_fertilizer_search",
    "my_friend_books", "my_friend_feed_player", "my_friend_basic_equipment", "my_friend_pet_care",
    "my_friend_resource_reserves", "my_friend_dodge", "my_friend_progress"}) do
    package.loaded[name] = stub()
end
package.loaded.my_friend_dialogue = {Reply = noop, Say = noop, OnDecision = noop, OnAction = noop}
package.loaded.my_friend_home = {IsAskPending = function() return false end, Resume = noop}
package.loaded.my_friend_special_commands = {Parse = noop, IsPublic = function() return false end}
package.loaded.my_friend_pets = {Parse = noop}
package.loaded.my_friend_characters = {List = function() return {"wendy"} end}
package.loaded.my_friend_wathgrithr = {Answer = function() return false end, GetCombatAction = noop}
package.loaded.my_friend_beefalo = {Score = zero, GetAction = noop,
    Riding = {Behaviour = empty_node, Score = zero, AllowAutoRide = noop}}
package.loaded.my_friend_navigation = {CancelSteering = noop, ClearStuck = noop,
    GetLongFollowPoint = function(_, point) return point end,
    GetSteeringPoint = function(_, point) return point end, Unstick = noop,
    MoveToPoint = function(inst, point) inst.components.locomotor:GoToPoint(point) end}
package.loaded.my_friend_base_ai.SetTask = function(inst, task) inst.task = task end
package.loaded.my_friend_dodge.GetDecision = function() return nil, false, true end
package.loaded["behaviours/my_friend_route_action"] = function(inst, getter)
    local node = empty_node()
    node.getactionfn = getter
    function node:Visit()
        self.action = self.getactionfn(inst)
        self.status = self.action ~= nil and RUNNING or FAILED
    end
    return node
end
BufferedAction = function(inst, target, kind)
    local action = {doer = inst, target = target, action = kind, options = {}}
    function action:AddSuccessAction() end
    function action:AddFailAction() end
    function action:Fail() self.failed = true end
    function action:IsValid() return self.validfn == nil or self.validfn(self) end
    return action
end
local function entity(prefab, x, tags)
    guid = guid + 1
    local value = {prefab = prefab, GUID = guid, components = {}, pos = Vector3(x or 0, 0, 0), tags = tags or {}}
    function value:IsValid() return not self.removed end
    function value:IsInLimbo() return false end
    function value:HasTag(tag) return self.tags[tag] == true end
    function value:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    function value:GetPosition() return self.pos end
    function value:GetCurrentPlatform() return nil end
    function value:GetPhysicsRadius() return .5 end
    function value:GetDisplayName() return "Wendy" end
    function value:GetDistanceSqToInst(other) return (self.pos.x - other.pos.x)^2 end
    function value:GetBufferedAction() return self.bufferedaction end
    function value:ClearBufferedAction()
        if self.bufferedaction ~= nil then self.bufferedaction:Fail() end
        self.bufferedaction = nil
    end
    function value:FacePoint() end
    function value:DoPeriodicTask() error("follow disengagement must not add periodic tasks") end
    value.Transform = {GetWorldPosition = function() return value.pos.x, 0, value.pos.z end}
    value.sg = {currentstate = {name = "idle"},
        HasStateTag = function(_, tag) return value.tags[tag] == true end,
        HasAnyStateTag = function(_, ...) return value:HasAnyTag(...) end,
        GoToState = function() error("follow orders must use native movement rather than force state transitions") end}
    value.components.health = {IsDead = function() return false end, GetPercent = function() return value.health or 1 end}
    value.components.combat = {inst = value, CanTarget = function() return true end,
        SetTarget = function(self, target) if target == nil or self:CanTarget(target) then self.target = target end end,
        CalcAttackRangeSq = function() return 9 end, InCooldown = function() return false end}
    return value
end
local inst = entity("wendy", 0, {my_friend = true})
local player = entity("wilson", 20, {player = true})
player.userid = "follow_owner"
local leader, accepted = player, true
inst.components.follower = {GetLeader = function() return leader end}
inst.components.my_friend_affinity = {RequestFollow = function(_, sender)
    if not accepted then return false end
    leader = sender
    return true
end}
local hand
inst.components.inventory = {GetEquippedItem = function() return hand end, ReferenceAllItems = function() return {} end}
inst.components.hunger = {GetPercent = function() return 1 end}
inst.components.locomotor = {Clear = function(self) self.bufferedaction = nil end, Stop = noop,
    GoToPoint = function(self, point)
        moves = moves + 1; self.dest = point
        inst.tags.attack, inst.tags.abouttoattack = nil, nil
    end,
    PushAction = function(_, action) attacks = attacks + 1; inst.bufferedaction = action end}
local enemy = entity("hound", 2, {hound = true})
enemy.components.combat.target = inst
local entities = {enemy}
AllPlayers = {player}
TheWorld = {ismastersim = true, state = {cycles = 10}, Map = {CanCastAtPoint = function() return true end}}
TheSim = {FindEntities = function() scans = scans + 1; return entities end}
local Policy = require("my_friend_policy")
local Rules = require("my_friend_combat_rules")
local AI = require("my_friend_behavior_ai")
local Commands = require("my_friend_commands")
Rules.Configure(inst)
local BrainClass = require("brains/my_friendbrain")
local brain = BrainClass(inst)
brain:OnStart()
local root = brain.bt.root
inst.brain = {bt = brain.bt, ForceUpdate = function() wakes = wakes + 1 end}
local random = math.random
math.random = function() return 1 end
root:Visit()
assert(root.active.id == "combat" and attacks == 1, "the fixture must start in actual self-defence combat")
local original_attack = inst.bufferedaction
player.pos.x = 32
assert(AI.CanContinueCombat(inst, enemy) and original_attack:validfn(), "the exact 32-unit boundary remains allowed")
player.pos.x = 32.01
inst._my_friend_hurt_until, inst._my_friend_hurt_evade_until = now + 3, now + 3.5
assert(not AI.CanContinueCombat(inst, enemy) and not original_attack:validfn(),
    "priority self-defence and cached attacks must stop immediately beyond 32 units")
local prior_moves = moves
now = now + .7
root:Visit()
assert(root.active.id == "catch_up" and moves > prior_moves and inst.components.combat.target == nil)
assert(inst._my_friend_hurt_until == nil and inst._my_friend_hurt_evade_until == nil,
    "an old ordinary hit retreat must not hold the companion outside the follow combat range")
assert(AI.FindThreat(inst) == nil and AI.FindEscapeThreat(inst) == nil,
    "the distant leader must cause ordinary catching up rather than continued fighting or escape")
inst._my_friend_command = {id = "explore", player = player, deadline = now + 30}
assert(not Rules.IsBeyondFollowCombatRange(inst), "explicit roaming keeps its existing independent combat rules")
inst._my_friend_command = nil
player.pos.x, now = 20, now + .7
root:Visit()
assert(root.active.id == "combat")
local queued = inst.bufferedaction
assert(queued:validfn() and AI.CanContinueCombat(inst, enemy))
inst.tags.attack, inst.tags.abouttoattack = true, true
local before_moves, before_attacks, before_scans = moves, attacks, scans
local requested_at = now
assert(Commands.Dispatch(inst, player, "温蒂，跟随"))
assert(wakes > 0 and scans == before_scans, "accepting follow must wake the AI without a new world scan")
assert(queued.failed and not queued:validfn() and inst.components.combat.target == nil)
assert(not Rules.CanAttack(enemy, inst) and not inst.components.combat:CanTarget(enemy))
root:Visit()
assert(root.active.id == "catch_up" and moves > before_moves and attacks == before_attacks)
assert(inst.components.locomotor.dest.x == player.pos.x and not inst.tags.attack)
assert(AI.IsThreat(inst, enemy), "a temporary ceasefire must not erase actual hostility for safety checks")
assert(AI.FindThreat(inst) == nil and AI.FindEscapeThreat(inst) == nil)
player.bufferedaction = {action = ACTIONS.ATTACK, target = enemy}
inst._my_friend_assist_candidate, inst._my_friend_assist_until = enemy, now + 16
assert(AI.FindAssistTarget(inst) == nil and not AI.IsPriorityEngaged(inst, enemy))
assert(not AI.CanCounterAttack(inst, enemy) and not AI.CanContinueCombat(inst, enemy),
    "priority enemies and cached combat decisions cannot bypass the five-second pause")
AI.StartHurtRetreat(inst, enemy)
assert(inst._my_friend_hurt_until == nil)

local stranger = entity("spider", 3)
stranger.components.combat.target = inst
assert(Rules.CanAttack(stranger, inst) and AI.CanCounterAttack(inst, stranger),
    "the pause is specific to the disengaged target, not immunity to every new threat")
local Wigfrid = assert(loadfile("scripts/my_friend_wathgrithr.lua"))()
hand = entity("spear_wathgrithr_lightning_charged")
hand.components.aoespell = {CastSpell = function() error("a paused target must not be hit by a lunge") end}
hand.components.aoeweapon_lunge = {}
hand.components.rechargeable = {IsCharged = function() return true end}
inst.prefab = "wathgrithr"
assert(not Wigfrid.CanLunge(inst, enemy, hand))
assert(not Wigfrid.PerformLunge({doer = inst, target = enemy, invobject = hand}))
now = requested_at + 4.999
assert(not Rules.CanAttack(enemy, inst))
now = requested_at + 5
assert(Rules.CanAttack(enemy, inst) and Wigfrid.CanLunge(inst, enemy, hand))
inst.prefab, hand, player.bufferedaction = "wendy", nil, nil
assert(AI.FindThreat(inst) == enemy and AI.CanCounterAttack(inst, enemy))
root:Visit()
assert(root.active.id == "combat" and attacks > before_attacks,
    "at five seconds, existing hostility and normal combat rules resume")

now = 20
assert(Commands.DispatchWheel(inst, player, "follow"))
assert(Rules.IsFollowTargetPaused(inst, enemy))
now = 22
assert(Commands.DispatchWheel(inst, player, "follow"))
assert(inst._my_friend_follow_combat_pause.until_time == 27)
now = 26.999
assert(not Rules.CanAttack(enemy, inst), "repeated follow orders must retain and refresh the old target pause")
enemy.components.combat.target = nil
now = 27
assert(AI.FindThreat(inst) == nil, "a creature that lost aggro is not forcibly re-engaged after the pause")

inst.components.combat.target = enemy
enemy.components.combat.target = inst
inst.tags.busy, inst.sg.currentstate.name = true, "eat"
local meal = {action = {}, Fail = function() error("a follow order must not cancel a busy meal") end}
inst.bufferedaction = meal
before_moves = moves
assert(Commands.DispatchWheel(inst, player, "follow"))
root:Visit()
assert(inst.bufferedaction == meal and moves == before_moves and inst.sg.currentstate.name == "eat")
inst.tags.busy, inst.sg.currentstate.name, inst.bufferedaction = nil, "idle", nil
root:Visit()
assert(root.active.id == "catch_up" and moves > before_moves)

local pause = inst._my_friend_follow_combat_pause
accepted = false
assert(not Commands.DispatchWheel(inst, player, "follow"))
assert(inst._my_friend_follow_combat_pause == pause, "a rejected follow order must not change combat state")
accepted = true
inst.components.combat.target = enemy
inst._my_friend_hurt_attacker, inst._my_friend_hurt_fire_distance = enemy, 7
inst._my_friend_hurt_until, inst._my_friend_hurt_evade_until = now + 3, now + 3.5
assert(Commands.DispatchWheel(inst, player, "follow"))
assert(inst._my_friend_hurt_until == now + 3 and inst._my_friend_hurt_fire_distance == 7,
    "follow disengagement must preserve environmental escape")
leader = nil
assert(not Rules.IsFollowTargetPaused(inst, enemy) and inst._my_friend_follow_combat_pause == nil)
leader, now, inst.health, TheWorld.state.cycles = player, 40, .1, 499
inst._my_friend_hurt_until, inst._my_friend_hurt_evade_until, inst._my_friend_hurt_fire_distance = nil, nil, nil
inst.components.combat.target = stranger
assert(Commands.DispatchWheel(inst, player, "follow"))
now = 45
assert(Rules.CanAttack(stranger, inst) and not AI.CanCounterAttack(inst, stranger),
    "after the pause, late-world low-health rules may still decline combat")
player.pos.x = 33
AI.StartHurtRetreat(inst, stranger)
assert(inst._my_friend_hurt_until == nil, "new ordinary hits must not restart a distant hit-retreat loop")
math.random = random
print("PASS: 32-unit automatic combat leash, chat/wheel follow interruption, five-second target pause, queued attack/lunge guards, normal-rule resumption and busy/environmental protection")
