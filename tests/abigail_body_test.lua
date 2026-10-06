-- Run from the mod root: lua tests/abigail_body_test.lua
package.path = "scripts/?.lua;" .. package.path
GetTime = function() return 10 end
POSTACTIVATEHANDSHAKE = {READY = 1}
function deepcopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = deepcopy(v) end
    return copy
end
local Abigail = require("my_friend_abigail")

local function ghost(maxhealth, hp, inlimbo)
    local g = {inlimbo = inlimbo, is_defensive = true, components = {}}
    local health = {maxhealth = maxhealth, currenthealth = hp}
    function health:GetPercent() return self.currenthealth / self.maxhealth end
    function health:SetPercent(percent) self.currenthealth = self.maxhealth * percent end
    g.components.health = health
    function g:IsValid() return not self.removed end
    function g:IsInLimbo() return self.inlimbo end
    function g:Remove() self.removed = true end
    function g:BecomeAggressive() self.is_defensive = false end
    g.Transform = {SetPosition = function(_, x, y, z) g.position = {x, y, z} end}
    return g
end

local function owner(level, hp, inlimbo)
    local inst = {components = {}, callbacks = {}, _PostActivateHandshakeState_Server = 1}
    function inst:HasTag() return false end
    function inst:RemoveEventCallback(event, callback, source)
        if source == nil and self.callbacks[event] == callback then self.callbacks[event] = nil end
    end
    function inst:ListenForEvent(event, callback) self.callbacks[event] = callback end
    inst.Transform = {GetWorldPosition = function() return 50, 0, 60 end}
    inst._bondlevel = {set = function(_, value) inst.display_level = value end}
    local bond = {ghost = ghost(level * 200, hp, inlimbo), bondlevel = level,
        bondleveltimer = 125, notsummoned = inlimbo, summoned = not inlimbo}
    function bond:OnSave()
        return {bondlevel = self.bondlevel, elapsedtime = self.bondleveltimer,
            ghostinlimbo = self.notsummoned,
            ghost = {data = {health = {health = self.ghost.components.health.currenthealth}}}}
    end
    function bond:OnLoad(data)
        self.bondlevel, self.bondleveltimer = data.bondlevel, data.elapsedtime
        local saved = data.ghost.data.health
        -- Native loading applies health before linking the ghost to Wendy.
        local maximum = saved.maxhealth or 200
        self.ghost = ghost(maximum, math.min(saved.health, maximum), data.ghostinlimbo)
        local percent = self.ghost.components.health:GetPercent()
        self.ghost.components.health.maxhealth = data.bondlevel * 200
        self.ghost.components.health:SetPercent(percent)
        self.summoned, self.notsummoned = not data.ghostinlimbo, data.ghostinlimbo
        self.ghost._playerlink = inst
    end
    inst.components.ghostlybond = bond
    return inst, bond
end

local a, a_bond = owner(3, 487, false)
local b, b_bond = owner(2, 137, true)
a_bond.ghost.is_defensive = false
local a_saved, b_saved = Abigail.SaveBody(a), Abigail.SaveBody(b)
assert(a_saved.bond.ghost.data.health.maxhealth == 600)
assert(b_saved.bond.ghost.data.health.maxhealth == 400)
Abigail.RemoveSource(a)
Abigail.RemoveSource(b)
assert(a_bond.ghost == nil and b_bond.ghost == nil)
local a_new, a_new_bond = owner(1, 200, true)
local b_new, b_new_bond = owner(1, 200, true)
local default_a, default_b = a_new_bond.ghost, b_new_bond.ghost
local cancelled = false
a_new_bond.spawnghosttask = {Cancel = function() cancelled = true end}
Abigail.LoadBody(a_new, a_saved)
Abigail.LoadBody(b_new, b_saved)
assert(default_a.removed and default_b.removed and cancelled)
assert(a_new.display_level == 3 and b_new.display_level == 2)
assert(a_new_bond.bondleveltimer == 125 and b_new_bond.bondleveltimer == 125)
assert(math.abs(a_new_bond.ghost.components.health.currenthealth - 487) < .000001)
assert(math.abs(b_new_bond.ghost.components.health.currenthealth - 137) < .000001)
assert(a_new_bond.summoned and b_new_bond.notsummoned)
assert(a_new_bond.ghost.is_defensive == false)
assert(a_new_bond.ghost._playerlink == a_new and b_new_bond.ghost._playerlink == b_new)
assert(a_new_bond.ghost.position[1] == 50 and b_new_bond.ghost.position == nil)

local pending, pending_bond = owner(1, 200, true)
pending.userid, pending._PostActivateHandshakeState_Server = "owner", 0
Abigail.LoadBody(pending, a_saved)
assert(pending_bond.bondlevel == 1 and pending._my_friend_pending_abigail == a_saved)
assert(Abigail.SaveBody(pending).bond.bondlevel == 3)
pending._PostActivateHandshakeState_Server = 1
pending.callbacks.ms_skilltreeinitialized()
assert(pending.display_level == 3 and pending._my_friend_pending_abigail == nil)
assert(pending.callbacks.ms_skilltreeinitialized == nil)
assert(a_saved.bond.bondlevel == 3 and b_saved.bond.bondlevel == 2)
assert(Abigail.SaveBody({components = {}}) == nil)
print("PASS: independent Abigail levels, health, recall state and deferred player restoration")
