-- Run from the mod root: lua tests/dodge_test.lua
package.path = "scripts/?.lua;" .. package.path
local now, passable, scans, checks = 0, true, 0, 0
GetTime = function() return now end
Vector3 = function(x, y, z) return {x = x, y = y, z = z} end
TUNING = {FRUITDRAGON = {HIT_RANGE = 3, ATTACK_RANGE = 2}, ALTERGUARDIAN_PHASE1_AOERANGE = 6,
    ALTERGUARDIAN_PROJECTILE_SPEED = 10}
TheSim = {FindEntities = function() scans = scans + 1; return {} end}
package.loaded.my_friend_navigation = {Caps = function() return {} end,
    IsStepClear = function(_, _, _, _, obstacles)
        assert(obstacles ~= nil, "movement alternatives must reuse one obstacle query")
        checks = checks + 1
        return passable
    end}
local function entity(prefab, x)
    local e = {prefab = prefab, pos = {x = x, y = 0, z = 0}, components = {}, anim = "idle", frame = 0}
    function e:IsValid() return not self.removed end
    function e:GetPosition() return self.pos end
    function e:GetCurrentPlatform() return self.platform end
    function e:GetPhysicsRadius() return .5 end
    function e:HasTag() return false end
    e.AnimState = {GetCurrentAnimationFrame = function() return e.frame end,
        IsCurrentAnimation = function(_, anim) return e.anim == anim end,
        GetBuild = function() return "normal" end}
    e.components.health = {IsDead = function() return false end}
    e.components.combat = {GetAttackRange = function() return 2 end}
    return e
end
local inst, hound = entity("wendy", 1), entity("hound", 0)
inst.components.locomotor = {GetRunSpeed = function() return 6 end}
local Dodge = require("my_friend_dodge")
local Profiles = require("my_friend_dodge_profiles")
local library = Profiles.Create(inst)
local species, windows = 0, 0
for _, rows in pairs(library.targetanimtable) do
    species = species + 1
    for _, row in ipairs(rows) do if not row.noused then windows = windows + 1 end end
end
assert(species > 100 and windows > 150, "the companion dodge catalogue contains the supported attack windows")
hound.anim, hound.frame = "atk_pre", 16
local point, dodging, known = Dodge.GetDecision(inst, hound)
assert(dodging and known and point.x > inst.pos.x, "the attack window retreats away from the hound")
local before_scans = scans
for frame = 1, 6 do
    now = frame / 30
    assert(select(2, Dodge.GetDecision(inst, hound)))
end
assert(scans == before_scans, "30 Hz frame monitoring must not rescan collisions each frame")
now = .26; Dodge.GetDecision(inst, hound)
assert(scans == before_scans + 1, "the local collision cache expires after 250ms")
hound.anim, hound.frame = "atk", 3
local _, after, covered = Dodge.GetDecision(inst, hound)
assert(not after and covered, "the completed damage window permits counterattacking")
hound.anim = "new_mod_attack"
hound.sg = {HasAnyStateTag = function() return true end}
local _, unmatched, unmatched_known = Dodge.GetDecision(inst, hound)
assert(not unmatched and not unmatched_known, "unlisted attacks of known species retain the generic fallback")
hound.sg = nil
local giant = entity("deerclops", 0)
giant.anim, giant.frame = "atk", 14
local side, active = Dodge.GetDecision(inst, giant)
assert(active and math.abs(side.z) > .5, "Deerclops attacks use sideways avoidance")
passable = false
before_scans = scans
local before_checks = checks
local unsafe, still_dodging = Dodge.GetDecision(inst, giant)
assert(unsafe == nil and still_dodging, "blocked terrain never produces a movement destination")
assert(scans == before_scans and checks == before_checks + 5, "five blocked alternatives share the cached query")
passable = true
local custom = entity("unknown_mod_creature", 0)
local _, unknown_dodge, unknown_known = Dodge.GetDecision(inst, custom)
assert(not unknown_dodge and not unknown_known, "unknown enemies keep the generic dodge fallback")
-- A second NPC keeps its own position locks and frame state.
local other = entity("wathgrithr", -1)
other.components.locomotor = inst.components.locomotor
hound.anim, hound.frame = "atk_pre", 16
local other_point = Dodge.GetDecision(other, hound)
assert(other_point.x < other.pos.x and inst._my_friend_dodge ~= other._my_friend_dodge)
local boat = {}
inst.platform = boat
TheWorld = {Map = {GetPlatformAtPoint = function(_, x) return x <= 1.1 and boat or nil end}}
local offboat, avoiding = Dodge.GetDecision(inst, hound)
assert(offboat == nil or offboat.x <= 1.1, "boat dodges never step off the platform")
Dodge.Reset(inst)
assert(inst._my_friend_dodge.row == nil and inst._my_friend_dodge.target == nil)
assert(inst._my_friend_dodge.obstacles == nil, "stop clears collision/frame caches")
-- Native hounds have range 3; closer ordinary attackers must begin retreat
-- before their hit frame, not only in a final-frame artificial test.
inst.platform, inst.pos.x = nil, 2.5
for _, prefab in ipairs({"hound", "firehound", "icehound", "leif", "leif_sparse"}) do
    local enemy = entity(prefab, 0)
    enemy.components.combat.GetAttackRange = function() return 3 end
    enemy.anim = prefab:find("leif") and "atk" or "atk_pre"
    enemy.frame = prefab:find("leif") and 9 or 0
    local _, retreat, _, hold = Dodge.GetDecision(inst, enemy)
    assert(retreat or hold, prefab .. " must not queue a new attack before the retreat deadline")
    enemy.frame = prefab:find("leif") and 14 or 5
    assert(select(2, Dodge.GetDecision(inst, enemy)), prefab .. " must retreat before the native damage frame")
end
-- Dynamic boss callbacks (start, stop and distance) share their FX query too.
local boss = entity("alterguardian_phase2", 0)
boss.anim, boss.frame = "attk_chop", 0
before_scans = scans
for index = 1, 4 do Dodge.GetDecision(inst, boss) end
assert(scans == before_scans + 1, "multiple boss callbacks must share one cached local FX search")
print("PASS: bundled attack catalogue, frame windows, lateral dodges, terrain/boat safety, independent NPC state and unknown-enemy fallback")
