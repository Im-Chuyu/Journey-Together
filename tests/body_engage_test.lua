-- Real body/action/combat nodes; stub only engine movement, SG and equipment scoring.
package.path = "./scripts/?.lua;../yuanma/scripts/?.lua;" .. package.path
local function Read(path) local f = assert(io.open(path, "rb")); local s = f:read("*a"):gsub("\r", ""); f:close(); return s end
local prefix = assert(Read("tests/body_api_test.lua"):match("^(.-)local passed = 0"))
local fixture = assert(loadstring(prefix .. "\nreturn {setup=Setup,entity=Entity,item=Item}"))()
local API, Policy = require("my_friend_body_api"), require("my_friend_policy")
require("class")
READY, RUNNING, SUCCESS, FAILED, FRAMES = "READY", "RUNNING", "SUCCESS", "FAILED", 1/30
BehaviourNode = Class(function(self, name) self.name, self.status = name, READY end)
function BehaviourNode:Sleep(delay) self.delay = delay end
function BehaviourNode:Stop() if self.OnStop then self:OnStop() end; self.status = READY end
package.loaded["behaviours/my_friend_route_action"] = function() error("engage must not become a move_to route") end
package.loaded.my_friend_base_ai = {SetTask = function(inst, text) inst._my_friend_current_task = text end}
package.loaded.my_friend_dodge = {GetDecision = function(inst) return nil, false, false, inst.hold_attack end, Reset = function() end}
package.loaded.my_friend_wathgrithr = {GetCombatAction = function() end}
package.loaded.my_friend_dialogue.Say = function() end
local AI = package.loaded.my_friend_behavior_ai
AI.THREAT_RANGE, AI.ASSIST_RANGE = 24, 32
AI.GetLeaderAttackCount, AI.IsThreat, AI.IsPriorityEngaged = function() return 0 end, function() return false end, function() return false end
AI.IsHazardRetreatActive = function(inst) return inst.hazard == true end
AI.IsHazardousPath = function(inst) return inst.unsafe == true end
AI.ShouldRetreatUnequipped, AI.ShouldDodge = function() return false end, function() return false end
AI.CanCounterAttack = function(inst) return inst.can_start ~= false end
AI.CanContinueCombat = function(inst) return inst.can_continue ~= false end
AI.FindThreat = function(inst) inst.scans = (inst.scans or 0) + 1; return inst.threat end
package.loaded.my_friend_combat_rules.CanAttack = function(_, inst) return not inst.forbidden end
local Combat = require("behaviours/my_friend_combat")
local Body = require("behaviours/my_friend_body")
ACTIONS.ATTACK = {id = "ATTACK"}
local serial = 0
local function Setup()
    local inst, player, state = fixture.setup()
    local target = fixture.entity("frog", 12)
    target.components.health = {currenthealth = 100, IsDead = function() return target.dead == true end}
    target.components.combat = {}
    inst.sg.HasAnyStateTag = function() return false end
    function inst:FacePoint() end
    function inst:GetBufferedAction() return self.buffered end
    function inst:ClearBufferedAction() self.buffered = nil end
    inst.components.health.GetPercent = function() return inst.hp or 1 end
    local motor = {points = {}, attacks = {}}
    function motor:Stop() self.stops = (self.stops or 0) + 1 end
    function motor:GoToPoint(point) self.points[#self.points + 1] = point end
    function motor:PushAction(action) self.attacks[#self.attacks + 1] = action; inst.buffered = action end
    inst.components.locomotor = motor
    inst.components.combat.CalcAttackRangeSq = function() return 4 end
    inst.components.combat.InCooldown = function() return false end
    return inst, player, state, target, motor, Body(inst)
end
local function Engage(inst, player, state, target)
    serial = serial + 1
    return API.Call(inst, player, "engage:" .. serial, "engage", {target = API.Observation.Handle(state, target)})
end
local passed = 0
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
Test("explicit neutral target is chased continuously at its live position and attacked without a move_to", function()
    local inst, player, state, target, motor, node = Setup()
    local result = Engage(inst, player, state, target); assert(result.status == "accepted")
    node:Visit(); assert(motor.points[1].x == 12 and inst.scans == nil)
    target.x, target.z = 19, 2
    node:Visit(); assert(motor.points[2].x == 19 and motor.points[2].z == 2 and #motor.attacks == 0)
    inst.x, inst.z = target.x - 1, target.z
    node:Visit(); assert(#motor.attacks == 1 and motor.attacks[1].target == target)
    assert(motor.attacks[1]:IsValid() and state.jobs[result.action_id].status == "running")
    target.dead = true; target:PushEvent("death")
    assert(state.jobs[result.action_id].status == "completed" and state.jobs[result.action_id].result.defeated)
    assert(inst.components.combat.target == nil)
end)
Test("default combat retains natural aggression gates and explicit combat never switches to unrelated enemies", function()
    local inst, player, state, target, motor, node = Setup()
    local automatic = Combat(inst); automatic:Visit()
    assert(automatic.status == FAILED and #motor.points == 0 and #motor.attacks == 0 and inst.scans == 1)
    local other = fixture.entity("spider", 2)
    inst.threat = other
    Engage(inst, player, state, target); node:Visit()
    assert(node.combat.target == target and inst.scans == 1 and motor.points[1].x == target.x)
end)
Test("native target refusal and target loss return promptly instead of running until timeout", function()
    local inst, player, state, target, motor, node = Setup()
    inst.components.combat.SetTarget = function(self) self.target = nil end
    local result = Engage(inst, player, state, target); node:Visit()
    assert(state.jobs[result.action_id].status == "failed" and state.jobs[result.action_id].reason == "target_not_attackable")
    assert(state.active == nil and #motor.attacks == 0)
    inst, player, state, target, motor, node = Setup()
    result = Engage(inst, player, state, target); target.components.health = nil; node:Visit()
    assert(state.jobs[result.action_id].reason == "target_lost")
end)
Test("danger, equipment withdrawal, range limits and manual cancellation still stop explicit attacks safely", function()
    local inst, player, state, target, motor, node = Setup()
    local result = Engage(inst, player, state, target)
    inst.hazard = true; node:Visit(); assert(#motor.points == 0 and #motor.attacks == 0)
    inst.hazard, inst.can_continue = false, false; node:Visit()
    assert(state.jobs[result.action_id].reason == "cannot_continue_combat")
    inst, player, state, target, motor, node = Setup()
    result = Engage(inst, player, state, target); target.x = 40; node:Visit()
    assert(state.jobs[result.action_id].status == "failed" and #motor.points == 0)
    inst, player, state, target, motor, node = Setup()
    target.x = 1; result = Engage(inst, player, state, target); node:Visit()
    local action = motor.attacks[1]
    inst.busy = true
    API.ManualTakeover(inst); node:Visit()
    assert(state.active ~= nil and state.jobs[result.action_id].status == "running")
    inst.busy = false; node:Visit()
    assert(state.jobs[result.action_id].status == "interrupted" and not action:IsValid())
    assert(inst.components.combat.target == nil and #motor.attacks == 1)
end)
Test("explicit start still needs a usable weapon, preserves health/rules, and does not pollute automatic eligibility cache", function()
    local inst, player, state, target = Setup()
    local hand = fixture.item("spear", inst); hand.equipped, hand.damage = "hands", 40
    hand.components.equippable = {equipslot = "hands"}
    local module = {ASSIST_RANGE = 32, IsTorchWeapon = function() return false end,
        FindBestCombatWeapon = function() return hand, hand.damage end,
        IsThreat = function() return false end, IsPriorityEngaged = function() return false end,
        GetLeaderAttackCount = function() return 0 end}
    local env = setmetatable({M = module, Policy = Policy, DistanceSq = Policy.DistanceSq,
        IsAlive = function(e) return e and e:IsValid() and e.components.health and not e.components.health:IsDead() end,
        EquipCombatDefense = function() end, IsActiveLight = function() return false end,
        WeaponDamage = function() return hand.damage end, IsWeaponBroken = function() return false end,
        GetArmorStats = function() return 0, 0, false end,
        require = function(name)
            if name == "my_friend_equipment" then return {FindDroppedCombatItem = function() end} end
            return require(name)
        end}, {__index = _G})
    local source = Read("scripts/my_friend_behavior_ai.lua")
    local methods = assert(source:match('(function M.CanCounterAttack.-)\nfunction M.ShouldDodgeWindow'))
    local chunk = assert(loadstring(methods)); setfenv(chunk, env); chunk()
    assert(not module.CanCounterAttack(inst, target) and module.CanCounterAttack(inst, target, true))
    assert(not module.CanContinueCombat(inst, target) and module.CanContinueCombat(inst, target, true))
    assert(not module.CanContinueCombat(inst, target))
    hand.damage = 20; assert(not module.CanCounterAttack(inst, target, true))
    hand.damage, inst.hp = 40, .1; assert(not module.CanCounterAttack(inst, target, true))
    inst.hp, inst.forbidden = 1, true; assert(not module.CanCounterAttack(inst, target, true))
end)
print(passed .. " engage behaviour tests passed")
