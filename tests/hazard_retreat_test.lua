-- Run from the mod root: lua tests/hazard_retreat_test.lua
package.path = "scripts/?.lua;" .. package.path
local now, scans, moves, attacks, clears = 0, 0, 0, 0, 0
GetTime = function() return now end
Vector3 = function(x, y, z) return {x = x, y = y, z = z} end
ACTIONS = {WALKTO = {}, ATTACK = {}}
READY, RUNNING, SUCCESS, FAILED = 0, 1, 2, 3
BehaviourNode = {}
function BehaviourNode._ctor(self) self.status = READY end
function BehaviourNode:Sleep(period) self.nextupdatetime = now + period end
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
BufferedAction = function(inst, target, action, _, point)
    local value = {doer = inst, target = target, action = action, pos = point}
    function value:AddSuccessAction(fn) self.success = fn end
    function value:AddFailAction(fn) self.failure = fn end
    function value:Fail() if self.failure ~= nil then self.failure() end end
    return value
end
local blocked
package.loaded.my_friend_navigation = {
    Caps = function() return {} end, IsNearHole = function() return false end,
    IsClear = function(_, point) return blocked == nil or not blocked(point) end,
}
for _, name in ipairs({"my_friend_food_ai", "my_friend_home", "my_friend_resource_reserves"}) do
    package.loaded[name] = {}
end
package.loaded.my_friend_container_ai = {Cancel = function() end}
package.loaded.my_friend_base_ai = {SetTask = function(inst, text) inst.task = text end}
package.loaded.my_friend_dialogue = {Say = function() end, OnDecision = function() end}
package.loaded.my_friend_progress = {Check = function() end}
package.loaded.my_friend_dodge = {Reset = function() end, GetDecision = function() return nil, false, true end}
package.loaded.my_friend_wathgrithr = {GetCombatAction = function() end}
local fire, heat
local Thermal = require("my_friend_survival_ai")
package.loaded.my_friend_survival_ai = {
    FindDamagingHeatSource = function(_, fire_only)
        scans = scans + 1
        return fire_only and fire or heat, fire ~= nil and 4 or nil
    end,
    GetFireDangerRadius = function(source) return source:IsValid() and source.burning and 4 or 0 end,
    FindDamagingTemperatureSource = Thermal.FindDamagingTemperatureSource,
    GetTemperatureDangerRadius = Thermal.GetTemperatureDangerRadius,
}
local overrides = {}
TheSim = {FindEntities = function(_, _, _, _, radius)
    assert(radius == Thermal.TEMPERATURE_SOURCE_RANGE, "only damage-triggered local temperature discovery is allowed")
    scans = scans + 1
    return overrides
end}
TheWorld = {state = {cycles = 1}, Map = {IsPassableAtPoint = function() return true end}}
AllPlayers = {}
local function entity(x, z)
    local inst = {pos = Vector3(x or 0, 0, z or 0), components = {}, tags = {my_friend = true}}
    function inst:IsValid() return not self.removed end
    function inst:IsInLimbo() return false end
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self.tags[tag] then return true end end
        return false
    end
    function inst:GetPosition() return Vector3(self.pos.x, 0, self.pos.z) end
    function inst:GetBufferedAction() return self.bufferedaction end
    function inst:ClearBufferedAction() clears = clears + 1; self.bufferedaction = nil end
    function inst:FacePoint() end
    inst.Transform = {GetWorldPosition = function() return inst.pos.x, 0, inst.pos.z end}
    inst.sg = {currentstate = {name = "idle"},
        HasStateTag = function(_, tag) return inst.tags[tag] == true end,
        HasAnyStateTag = function(_, ...) return inst:HasAnyTag(...) end}
    inst.components.health = {IsDead = function() return false end}
    inst.components.combat = {SetTarget = function(self, target) self.target = target end,
        CalcAttackRangeSq = function() return 9 end, InCooldown = function() return false end}
    inst.components.locomotor = {Stop = function() end, Clear = function() end,
        GoToPoint = function() moves = moves + 1 end,
        PushAction = function(_, action)
            inst.bufferedaction = action
            if action.action == ACTIONS.ATTACK then attacks = attacks + 1 else moves = moves + 1 end
            -- Native locomote leaves the interruptible attack without forcing idle.
            inst.tags.attack, inst.tags.abouttoattack = nil, nil
        end}
    return inst
end
local AI = require("my_friend_behavior_ai")
local enemy = entity(0, 0)
enemy.tags = {hound = true}
AI.FindThreat = function() return enemy end
AI.CanContinueCombat = function() return true end
AI.GetLeaderAttackCount = function() return 0 end
AI.IsPriorityEngaged = function() return true end

-- Native aura damage has a valid afflicter and uses combat:GetAttacked. Its
-- real radius wins over the generic six-unit fallback, even against priority foes.
local cloud = entity(0, 0)
cloud.components.aura = {active = true, radius = 9}
local inst = entity(1, 0)
AI.OnEnvironmentalDamage(inst, {amount = -5, cause = "mod_cloud", afflicter = cloud})
assert(AI.IsHazardRetreatActive(inst) and inst._my_friend_replan_requested)
local action = assert(AI.GetHurtRetreatAction(inst))
assert(action.pos.x == 10 and action._my_friend_fire_retreat)
inst.pos = Vector3(4, 0, 0); now = 1
AI.OnEnvironmentalDamage(inst, {amount = -5, cause = "mod_cloud", afflicter = cloud})
assert(inst._my_friend_hurt_source.x == 0 and inst._my_friend_hurt_destination == action.pos)
now = 4.2; AI.UpdateHazardRetreat(inst)
assert(inst._my_friend_hurt_until > now, "continuous exposure must outlive the ordinary hurt timer")
inst.pos = Vector3(10 - action.arrivedist, 0, 0); action.success()
assert(not AI.IsHazardRetreatActive(inst) and inst._my_friend_hurt_until == 0)
assert(AI.IsHazardousPath(inst, inst.pos, Vector3(-12, 0, 0)), "safe endpoints can still cross a cloud")
now = 30
assert(AI.IsHazardousPath(inst, inst.pos, cloud.pos), "a known active aura stays unsafe until disabled")
cloud.components.aura.active = false
assert(not AI.IsHazardousPath(inst, inst.pos, cloud.pos), "disabled sources release the area")
cloud.components.aura.active, cloud.components.aura.auraexcludetags = true, {"noauradamage"}
inst.pos = Vector3(1, 0, 0)
AI.OnEnvironmentalDamage(inst, {amount = -2, cause = "cloud", afflicter = cloud})
inst.tags.noauradamage = true
assert(not AI.IsHazardRetreatActive(inst), "newly equipped aura immunity must release remembered danger")
inst.tags.noauradamage = nil
AI.OnEnvironmentalDamage(inst, {amount = -2, cause = "cloud", afflicter = cloud})
cloud.removed = true
assert(not AI.IsHazardRetreatActive(inst), "removed sources must be released without a scan")
cloud.removed = nil

-- Generic terrain damage retains its original contact point, expires without
-- scanning, and never treats a failed/early WALKTO as reaching safety.
inst, now = entity(), 40
AI.OnEnvironmentalDamage(inst, {amount = -2, cause = "mod_terrain"})
action = assert(AI.GetHurtRetreatAction(inst))
inst.pos = Vector3(2, 0, 0); now = 41
AI.OnEnvironmentalDamage(inst, {amount = -2, cause = "mod_terrain"})
assert(inst._my_friend_hazard_position.x == 0 and inst._my_friend_hurt_source.x == 0)
action:Fail()
assert(inst._my_friend_hurt_until > now and inst._my_friend_hurt_evade_until > now)
local retry = assert(AI.GetHurtRetreatAction(inst))
assert(retry.pos ~= action.pos and math.abs(retry.pos.z) > .5, "path failure must choose another direction")
retry.success()
assert(inst._my_friend_hurt_until > now, "early arrival inside the area must keep retreating")
retry = assert(AI.GetHurtRetreatAction(inst))
local cached = retry.pos
blocked = function(point) return (point.x - cached.x)^2 + (point.z - cached.z)^2 < .01 end
retry = assert(AI.GetHurtRetreatAction(inst))
assert(retry.pos ~= cached, "an invalid cached destination must not be retried in every direction")
blocked = nil
inst.pos = retry.pos; retry.success()
AI.UpdateHazardRetreat(inst)
assert(inst._my_friend_hazard_position ~= nil, "leaving the area must preserve its short memory")
assert(AI.IsHazardousPath(inst, inst.pos, Vector3(0, 0, 0)))
now = 50
assert(not AI.IsHazardousPath(inst, inst.pos, Vector3(0, 0, 0)))

-- Creature hits, attached debuffs, item costs and global survival damage do
-- not become environmental areas; entity-backed ground effects still do.
for _, cause in ipairs({"hunger", "cold", "hot", "oldage", "sanity", "acidrain", "statue_attune"}) do
    inst = entity(); AI.OnEnvironmentalDamage(inst, {amount = -5, cause = cause})
    assert(not AI.IsHazardRetreatActive(inst), cause)
end
local item, debuff, beam = entity(), entity(), entity()
item.components.inventoryitem = {}
debuff.entity = {GetParent = function() return inst end}
beam.components.health = nil
for _, source in ipairs({enemy, item, debuff, inst}) do
    AI.OnEnvironmentalDamage(inst, {amount = -5, cause = "hit", afflicter = source})
    assert(not AI.IsHazardRetreatActive(inst), "normal attacks/costs must preserve existing combat policy")
end
AI.OnEnvironmentalDamage(inst, {amount = -5, cause = "beam", afflicter = beam})
assert(AI.IsHazardRetreatActive(inst), "environmental entities without health are not ordinary combatants")
inst = entity(); AI.OnEnvironmentalDamage(inst, {amount = 0, cause = "miasma"})
assert(not AI.IsHazardRetreatActive(inst), "no damage, no new hazard")

-- Fire discovery is event-triggered. Subsequent decisions only check the
-- remembered source and release it after extinguishing/removal.
fire = entity(); fire.burning = true
inst = entity(1, 0); AI.OnFireDamage(inst)
local before = scans
for tick = 1, 10 do now = now + .2; AI.UpdateFireRetreat(inst); AI.IsHazardRetreatActive(inst) end
assert(scans == before)
fire.burning = false
assert(not AI.IsHazardRetreatActive(inst) and inst._my_friend_fire_source == nil)
fire.burning, cloud.components.aura.active = true, true
inst = entity(1, 0); AI.OnFireDamage(inst)
AI.OnEnvironmentalDamage(inst, {amount = -2, cause = "cloud", afflicter = cloud})
action = assert(AI.GetHurtRetreatAction(inst))
inst._my_friend_replan_requested = nil
for tick = 1, 5 do
    now = now + .2; AI.UpdateFireRetreat(inst); AI.UpdateHazardRetreat(inst)
end
assert(inst._my_friend_hurt_destination == action.pos and not inst._my_friend_replan_requested,
    "overlapping fire and aura must not repeatedly cancel an escape that clears both")
before = scans
inst = entity(); inst.components.health.GetFireDamageScale = function() return 0 end
AI.OnFireDamage(inst); assert(scans == before, "fire immunity must prevent discovery and retreat")
heat = entity()
inst = entity(2, 0); AI.OnHeatDamage(inst)
assert(AI.IsHazardRetreatActive(inst), "local heat damage must bypass ordinary priority-enemy retreat rules")
action = assert(AI.GetHurtRetreatAction(inst))
assert(action.pos.x > inst.pos.x, "heat escape must head away from the source")
before = scans; AI.OnHeatDamage(inst)
assert(scans == before, "repeated heat events must share a throttled discovery")
heat, inst = nil, entity()
AI.OnHeatDamage(inst)
assert(not AI.IsHazardRetreatActive(inst), "ambient overheating remains a temperature-management problem")

local ward = entity(0, 0)
local enabled, value = true, -20
ward.prefab = "deerclopseyeball_sentryward"
ward.components.temperatureoverrider = {
    GetActiveRadius = function() return enabled and 35 or 0 end,
    GetTemperature = function() return value end,
}
overrides = {ward}
inst, now = entity(30, 0), 100
inst.components.temperature = {current = -1, overheattemp = 70}
AI.OnEnvironmentalDamage(inst, {amount = -1, cause = "cold"})
assert(AI.IsHazardRetreatActive(inst) and inst._my_friend_hazard_radius == 35,
    "sourceless cold damage must discover the actual active override, even beyond the old heat query range")
action = assert(AI.GetHurtRetreatAction(inst))
assert(action.pos.x == 36 and inst._my_friend_replan_requested)
before = scans
AI.OnEnvironmentalDamage(inst, {amount = -1, cause = "cold"})
assert(scans == before, "cold notifications must be throttled")
inst.pos = Vector3(36, 0, 0); action.success()
now = 130
assert(not AI.IsHazardRetreatActive(inst) and AI.IsHazardousPath(inst, inst.pos, ward.pos))
before = scans
for iteration = 1, 100 do AI.UpdateHazardRetreat(inst); AI.IsHazardRetreatActive(inst) end
assert(scans == before, "remembered temperature areas need no periodic discovery")
enabled = false
assert(not AI.IsHazardousPath(inst, inst.pos, ward.pos))
enabled, value = true, 20
inst.pos, now = Vector3(30, 0, 0), 140
AI.OnEnvironmentalDamage(inst, {amount = -1, cause = "cold"})
assert(not AI.IsHazardRetreatActive(inst), "a harmless temperature override must not become a cold hazard")
local shelter = entity(29, 0)
shelter.components.temperatureoverrider = {GetActiveRadius = function() return 5 end,
    GetTemperature = function() return 20 end}
value, overrides, now = -20, {ward, shelter}, 142
AI.OnEnvironmentalDamage(inst, {amount = -1, cause = "cold"})
assert(not AI.IsHazardRetreatActive(inst), "the closest override wins, just as in the native temperature system")
overrides, now = {ward}, 144
value = 100
AI.OnHeatDamage(inst)
assert(AI.IsHazardRetreatActive(inst) and inst._my_friend_hazard_radius == 35)
ward.removed = true
assert(not AI.IsHazardRetreatActive(inst))
overrides = {}

-- Exercise the actual combat node and utility selector with an active attack
-- and a still-valid cached combat snapshot. Contact must take over immediately.
local Combat = require("behaviours/my_friend_combat")
local Utility = require("behaviours/my_friend_utility")
for _, id in ipairs({"combat", "assist"}) do
    inst = entity(1, 0)
    local combat_node = Combat(inst)
    combat_node.target, combat_node.status = enemy, RUNNING
    inst.tags.attack, inst.tags.abouttoattack = true, true
    local old_attack = BufferedAction(inst, enemy, ACTIONS.ATTACK)
    inst.bufferedaction = old_attack
    local combat_entry = {id = id, node = combat_node, score = function(c) return c.hurt and 0 or 128 end}
    local retreat = setmetatable({}, {__index = BehaviourNode})
    function retreat:Visit()
        self.action = AI.GetHurtRetreatAction(inst)
        self.status = self.action ~= nil and RUNNING or FAILED
        if self.action ~= nil then inst.components.locomotor:PushAction(self.action, true) end
    end
    local hurt_entry = {id = "hurt", node = retreat, score = function(c) return c.hurt and 170 or 0 end}
    local context = {leader = nil, hurt = false}
    local root = Utility(inst, {hurt_entry, combat_entry}, function()
        AI.UpdateFireRetreat(inst); AI.UpdateHazardRetreat(inst)
        return {leader = nil, hurt = now < (inst._my_friend_hurt_until or 0)}
    end)
    root.active, root.context, root.snapshot_at, root.combat_decision_at = combat_entry, context, now + .6, now + .1
    AI.OnEnvironmentalDamage(inst, {amount = -2, cause = "miasma"})
    local before_moves, before_attacks = moves, attacks
    root:Visit()
    assert(root.active == hurt_entry and moves == before_moves + 1 and attacks == before_attacks, id)
    assert(inst.bufferedaction ~= old_attack and not inst.tags.attack, "native movement must replace the pending swing")
end

-- Pending urgent replans wait for genuine busy states, then leave immediately.
inst = entity(); inst.tags.busy, inst.sg.currentstate.name = true, "eat"
local meal = {action = {}}
inst.bufferedaction = meal
AI.OnEnvironmentalDamage(inst, {amount = -2, cause = "miasma"})
local root = Utility(inst, {}, function() error("busy states must not build a snapshot") end)
local before_clears = clears
root:Visit()
assert(inst.bufferedaction == meal and clears == before_clears and inst._my_friend_replan_requested)
assert(AI.GetHurtRetreatAction(inst) == nil)
inst.tags.busy, inst.sg.currentstate.name = nil, "idle"
assert(AI.GetHurtRetreatAction(inst) ~= nil)

-- Combat can hit an enemy from safety, but cannot chase across the remembered
-- area. Re-entry invalidates a queued attack and requests a fresh decision.
inst = entity(); AI.OnEnvironmentalDamage(inst, {amount = -2, cause = "miasma"})
inst.pos, enemy.pos = Vector3(7, 0, 0), Vector3(-7, 0, 0)
local combat_node = Combat(inst)
local before_moves, before_attacks = moves, attacks
combat_node:Visit()
assert(moves == before_moves and attacks == before_attacks)
enemy.pos = Vector3(8, 0, 0)
combat_node:Visit()
assert(attacks == before_attacks + 1, "safe combat can resume outside the area")
local queued = inst.bufferedaction
enemy.pos = Vector3(-7, 0, 0)
assert(not queued.validfn(), "a moving target must not turn an attack into a chase through the area")
enemy.pos = Vector3(8, 0, 0)
inst.pos = Vector3(5, 0, 0)
assert(not queued.validfn(), "queued attacks must revalidate environmental safety")
inst._my_friend_replan_requested = nil
combat_node:Visit()
assert(inst._my_friend_replan_requested and attacks == before_attacks + 1)
print("PASS: event-triggered area damage, aura radii, stable contact memory, retries, safe combat, immediate combat/assist preemption and busy protection")
