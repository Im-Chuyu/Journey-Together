-- Run from the mod root: lua tests/combat_dodge_integration_test.lua
package.path = "scripts/?.lua;" .. package.path
local now, scans, moves, attacks = 0, 0, 0, 0
GetTime = function() return now end
Vector3 = function(x, y, z) return {x = x, y = y, z = z} end
READY, RUNNING, SUCCESS, FAILED = 0, 1, 2, 3
BehaviourNode = {}
function BehaviourNode._ctor(self) self.status = READY end
function BehaviourNode:Sleep(period) self.nextupdatetime = GetTime() + period end
function BehaviourNode:Reset() self.status = READY end
function BehaviourNode:Stop() if self.OnStop ~= nil then self:OnStop() end end
Class = function(base, ctor)
    local class = {_ctor = ctor}
    class.__index = class
    return setmetatable(class, {__index = base, __call = function(_, ...)
        local self = setmetatable({}, class)
        ctor(self, ...)
        return self
    end})
end
EQUIPSLOTS = {HANDS = "hands"}
ACTIONS = {ATTACK = {}}
BufferedAction = function(inst, target, action) return {doer = inst, target = target, action = action} end
TUNING = {FRUITDRAGON = {HIT_RANGE = 3, ATTACK_RANGE = 2}, ALTERGUARDIAN_PHASE1_AOERANGE = 6,
    ALTERGUARDIAN_PROJECTILE_SPEED = 10}
TheSim = {FindEntities = function() scans = scans + 1; return {} end}
TheWorld = {Map = {}}
package.loaded.my_friend_navigation = {Caps = function() return {} end, IsStepClear = function() return true end}
package.loaded.my_friend_base_ai = {SetTask = function(inst, task) inst.task = task end}
package.loaded.my_friend_dialogue = {Say = function() end, OnDecision = function() end}
package.loaded.my_friend_wathgrithr = {GetCombatAction = function() end}
package.loaded.my_friend_progress = {Check = function() end}
local target
local function distance(a, b) return (a.pos.x - b.pos.x)^2 + (a.pos.z - b.pos.z)^2 end
package.loaded.my_friend_policy = {
    DistanceSq = distance, InRange = function() return true end,
    GetLeader = function() return nil end, IsBusy = function(inst) return inst.sg:HasStateTag("busy") end,
}
package.loaded.my_friend_behavior_ai = {
    ASSIST_RANGE = 20, THREAT_RANGE = 20,
    GetLeaderAttackCount = function() return 0 end,
    IsThreat = function(_, enemy) return enemy == target end,
    IsPriorityEngaged = function() return true end,
    FindThreat = function() return target end,
    CanContinueCombat = function() return true end,
    ShouldDodge = function() return false end,
    ObservePlayerAttack = function() end,
}
local function entity(prefab, x)
    local inst = {prefab = prefab, pos = Vector3(x, 0, 0), components = {}, tags = {}, anim = "idle", frame = 0}
    function inst:IsValid() return not self.removed end
    function inst:IsInLimbo() return false end
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:HasAnyTag() return false end
    function inst:GetPosition() return self.pos end
    function inst:GetCurrentPlatform() return nil end
    function inst:GetPhysicsRadius() return .5 end
    function inst:FacePoint() end
    function inst:GetBufferedAction() end
    function inst:ClearBufferedAction() end
    inst.Transform = {GetWorldPosition = function() return inst.pos.x, 0, inst.pos.z end}
    inst.AnimState = {GetCurrentAnimationFrame = function() return inst.frame end,
        IsCurrentAnimation = function(_, anim) return inst.anim == anim end}
    inst.sg = {currentstate = {name = "idle"},
        HasStateTag = function(_, tag) return inst.tags[tag] == true end,
        HasAnyStateTag = function(_, ...)
            for _, tag in ipairs({...}) do if inst.tags[tag] then return true end end
            return false
        end}
    inst.components.health = {IsDead = function() return false end}
    inst.components.combat = {GetAttackRange = function() return 3 end,
        SetTarget = function(self, enemy) self.target = enemy end,
        InCooldown = function() return false end, CalcAttackRangeSq = function() return 9 end}
    inst.components.locomotor = {GetRunSpeed = function() return 6 end, Stop = function() end,
        GoToPoint = function(self, point) moves = moves + 1; self.dest = point end,
        PushAction = function() attacks = attacks + 1 end, Clear = function() end}
    return inst
end
local inst = entity("wendy", 2.5)
local Combat = require("behaviours/my_friend_combat")
local node = Combat(inst)
for _, prefab in ipairs({"hound", "firehound", "icehound", "leif", "leif_sparse"}) do
    target = entity(prefab, 0)
    target.anim, target.frame = prefab:find("leif") and "atk" or "atk_pre", prefab:find("leif") and 14 or 5
    inst.tags.attack, inst.tags.abouttoattack = true, true
    local before = moves
    node:Visit()
    assert(moves == before, "preserve the companion's pending damage frame")
    inst.tags.abouttoattack = false
    node:Visit()
    assert(moves > before, prefab .. " must dodge after damage even while the attack recovery tag remains")
    node:OnStop()
end
-- Before the retreat deadline, hold off a new swing that would occupy it.
target = entity("leif", 0); target.anim, target.frame = "atk", 9
inst.tags.attack = false
local before = attacks
node:Visit()
assert(attacks == before and inst._my_friend_dodge.monitoring, "a new attack must not cover the next dodge window")
target.frame = 14
node:Visit()
local before_moves, before_scans = moves, scans
for frame = 1, 4 do now = frame / 30; node:Visit() end
assert(moves == before_moves, "unchanged dodge destinations must not restart native pathfinding each frame")
assert(scans == before_scans, "frame checks reuse local obstacles")
-- Once a native attack animation passes its damage window, return to attacking.
node:OnStop(); target = entity("hound", 0); target.anim, target.frame = "atk", 3
node:Visit()
assert(attacks == before + 1, "normal hounds must resume counterattacking after the hit window")
-- Exercise the actual utility scheduler, not just the dodge helper.
local Utility = require("behaviours/my_friend_utility")
local scores, snapshots, visits = 0, 0, 0
local leaf = BehaviourNode
local active_node = setmetatable({status = RUNNING, Visit = function(self)
    visits = visits + 1; self.status = RUNNING
end}, {__index = leaf})
local entry = {id = "combat", node = active_node, score = function() scores = scores + 1; return 125 end}
local context = {leader = nil}
local root = Utility(inst, {entry}, function() snapshots = snapshots + 1; return context end)
root.active, root.context, root.snapshot_at, root.combat_decision_at = entry, context, now + .6, now + .1
inst._my_friend_dodge = {monitoring = true}
local score_before = scores
root:Visit()
assert(root.nextupdatetime == now + 1 / 30, "observe the windup before a dodge row becomes active")
assert(scores == score_before and snapshots == 0 and visits == 1, "frame polling does not rerank survival/work or rescan the world")
now = now + .11; root:Visit()
assert(scores > score_before, "combat priorities are reconsidered at 100ms intervals")
-- Dropped equipment / new commands can bypass the fast lane immediately.
inst._my_friend_replan_requested = true
score_before = scores
root:Visit()
assert(scores > score_before and snapshots > 0 and not inst._my_friend_replan_requested)
-- The first tick of a priority switch must use the selected entry's ID.
local idle_node = setmetatable({status = RUNNING, Visit = function() end}, {__index = leaf})
local idle = {id = "idle", node = idle_node, passive = true, score = function() return 1 end}
local urgent = {id = "combat", node = active_node, score = function() return 125 end}
local switched = Utility(inst, {urgent, idle}, function() return context end)
switched.active, switched.context, switched.snapshot_at = idle, context, now + .6
inst._my_friend_dodge = {monitoring = true}
switched:Visit()
assert(switched.active == urgent and switched.nextupdatetime == now + 1 / 30,
    "first switched combat visit must not sleep for the ordinary 400ms period")
print("PASS: native ordinary-enemy windups, protected damage/recovery movement, bounded path/collision refresh and utility combat polling/preemption")
