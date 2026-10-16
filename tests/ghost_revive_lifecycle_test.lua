package.path = "scripts/?.lua;" .. package.path
local now, guid, scans, pushes, brain_starts = 10, 0, 0, 0, 0
GetTime = function() return now end
TUNING = {TOTAL_DAY_TIME = 480, HAUNT_INSTANT_REZ = 99}
STRINGS = {CHARACTER_TITLES = {}}
EQUIPSLOTS = {HANDS = "hands", BODY = "body", HEAD = "head"}
ACTIONS = {HAUNT = {id = "HAUNT"}, WALKTO = {id = "WALKTO"}}
READY, RUNNING, SUCCESS, FAILED = 0, 1, 2, 3
local point_methods = {}
function point_methods:LengthSq() return self.x^2 + self.z^2 end
Vector3 = function(x, y, z)
    return setmetatable({x = x, y = y, z = z}, {__index = point_methods,
        __sub = function(first, second) return Vector3(first.x - second.x, 0, first.z - second.z) end})
end
Class = function(base, constructor)
    if constructor == nil then constructor, base = base, nil end
    local class = {_ctor = constructor}
    class.__index = class
    return setmetatable(class, {__index = base, __call = function(_, ...)
        local value = setmetatable({}, class)
        constructor(value, ...)
        return value
    end})
end
BehaviourNode = {}
function BehaviourNode._ctor(self) self.status = READY end
function BehaviourNode:Sleep(delay) self.nextupdatetime = now + delay end
function BehaviourNode:Reset() self.status = READY end
function BehaviourNode:Stop() if self.OnStop ~= nil then self:OnStop() end end
BufferedAction = function(inst, target, kind, item, point)
    local action = {doer = inst, target = target, action = kind, invobject = item,
        point = point, options = {}, success = {}, failure = {}}
    function action:AddSuccessAction(callback) self.success[#self.success + 1] = callback end
    function action:AddFailAction(callback) self.failure[#self.failure + 1] = callback end
    function action:GetActionPoint() return self.point end
    function action:IsValid() return self.validfn == nil or self.validfn(self) end
    function action:Fail() for _, callback in ipairs(self.failure) do callback() end; self.failure = {} end
    return action
end
local replies = {}
package.loaded.my_friend_dialogue = {Reply = function(_, key) replies[#replies + 1] = key end,
    Say = function() end, OnDecision = function() end, OnAction = function() end}
package.loaded.my_friend_backpacks = {FindOwned = function() end}
package.loaded.my_friend_recovery_safety = {IsSafe = function() return true end}
package.loaded.my_friend_home = {IsAskPending = function() return false end, Resume = function() end}
package.loaded.my_friend_beefalo = {Riding = {AllowAutoRide = function() end}}
package.loaded.my_friend_special_commands = {Parse = function() end}
package.loaded.my_friend_characters = {List = function() return {"wickerbottom"} end,
    IsCharacter = function(prefab) return prefab == "wickerbottom" end}
package.loaded.my_friend_carry_backpack = {Answer = function() return false end, Cancel = function() end}
package.loaded.my_friend_pets = {Parse = function() end}
package.loaded.my_friend_wathgrithr = {Answer = function() return false end}
package.loaded.my_friend_recipe_cooking = {Cancel = function() end}
package.loaded.my_friend_container_ai = {Cancel = function(inst) inst._my_friend_container_action = nil end}
package.loaded.my_friend_butterfly = {Cancel = function() end}
package.loaded.my_friend_base_ai = {SetTask = function() end}
package.loaded.my_friend_progress = {Check = function() end}
package.loaded.my_friend_behavior_ai = {ObservePlayerAttack = function() end}
package.loaded.my_friend_ghost_help = {Start = function() end, Stop = function() end}
local periodic_tasks = 0
local function entity(prefab, x)
    guid = guid + 1
    local value = {prefab = prefab, GUID = guid, pos = Vector3(x or 0, 0, 0),
        components = {}, events = {}, tags = {}, tasks = {}}
    function value:IsValid() return not self.removed end
    function value:HasTag(tag) return self.tags[tag] == true end
    function value:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    function value:IsInLimbo() return false end
    function value:GetPosition() return self.pos end
    function value:GetDisplayName() return "Grandma" end
    function value:GetDistanceSqToInst(other) return (self.pos - other.pos):LengthSq() end
    function value:ListenForEvent(event, callback)
        self.events[event] = self.events[event] or {}
        table.insert(self.events[event], callback)
    end
    function value:PushEvent(event, data)
        for _, callback in ipairs(self.events[event] or {}) do callback(self, data) end
    end
    function value:DoPeriodicTask() periodic_tasks = periodic_tasks + 1; return {Cancel = function() end} end
    function value:GetBufferedAction() return self.bufferedaction end
    function value:ClearBufferedAction()
        if self.bufferedaction ~= nil then self.bufferedaction:Fail(); self.bufferedaction = nil end
    end
    value.Transform = {GetWorldPosition = function() return value.pos.x, 0, value.pos.z end}
    value.components.health = {IsDead = function() return value.dead == true end}
    value.sg = {currentstate = {name = "idle"},
        HasStateTag = function(_, tag) return tag == "busy" and value.busy == true end,
        GoToState = function() error("lifecycle cleanup must preserve the native resurrection state") end}
    value.components.locomotor = {Clear = function() end, Stop = function() end,
        PushAction = function(_, action)
            assert(action:IsValid()); pushes = pushes + 1; value.bufferedaction = action
        end}
    return value
end
local player = entity("wanda", 0)
player.userid = "revival_owner"
AllPlayers = {player}
TheWorld = {ismastersim = true}
Ents = {}
local candidates = {}
TheSim = {FindEntities = function() scans = scans + 1; return candidates end}
local Policy = require("my_friend_policy")
local Commands = require("my_friend_commands")
local Ghost = require("my_friend_ghost_commands")
local Revive = require("my_friend_revive_ai")
local Utility = require("behaviours/my_friend_utility")
local Affinity = require("components/my_friend_affinity")
local inst = entity("wickerbottom")
inst.tags.my_friend = true
inst.isplayer = true
local leader = player
inst.components.follower = {GetLeader = function() return leader end,
    SetLeader = function(_, selected) leader = selected end}
inst.components.inventory = {ReferenceAllItems = function() return {} end,
    GetActiveItem = function() end, GetEquippedItem = function() end, DisableDropOnDeath = function() end}
inst.components.combat = {SetTarget = function() end}
inst.components.my_friend_affinity = Affinity(inst)
inst.components.my_friend_affinity.values[player.userid] = 50
inst.components.my_friend_affinity.requests = {player.userid}
local function leaf(getter)
    local node = setmetatable({status = READY, getactionfn = getter}, {__index = BehaviourNode})
    function node:Visit()
        self.action = self.getactionfn ~= nil and self.getactionfn(inst) or nil
        self.status = self.getactionfn == nil and RUNNING or self.action ~= nil and RUNNING or FAILED
        if self.action ~= nil then inst.components.locomotor:PushAction(self.action, true) end
    end
    return node
end
inst.brainfn = function()
    local entries = {
        {id = "revive", node = leaf(Ghost.GetAction), score = function(context)
            return context.ghost and math.max(150, Ghost.Score(inst)) or 0
        end},
        {id = "follow", node = leaf(), passive = true,
            score = function(context) return not context.ghost and context.leader ~= nil and 10 or 0 end},
        {id = "ghost_follow", node = leaf(), score = function(context)
            return context.ghost and context.leader ~= nil and 151 or 0
        end},
    }
    local brain = {stopped = false, wakes = 0, bt = {root = Utility(inst, entries, function()
        return {ghost = inst:HasTag("playerghost"), leader = Policy.GetLeader(inst)}
    end)}}
    function brain:ForceUpdate() self.wakes = self.wakes + 1 end
    function brain:_Stop_Internal()
        self.bt.root:OnStop()
        self.stopped = true
        inst._my_friend_storage_action = {cancelled_old_job = true}
    end
    return brain
end
function inst:SetBrain(constructor)
    if self.brain ~= nil then self.brain:_Stop_Internal() end
    self.brain = constructor()
    self.brain.stopped = self._brainstopped ~= nil
    brain_starts = brain_starts + 1
end
inst:SetBrain(inst.brainfn)
Revive.Configure(inst)
local before_tasks = periodic_tasks
local random = math.random
math.random = function() return 1 end
local amulet = entity("amulet", 4)
amulet.components.hauntable = {hauntvalue = TUNING.HAUNT_INSTANT_REZ}
amulet.components.inventoryitem = {IsHeld = function() return false end}
candidates = {amulet}
inst.tags.playerghost = true

local modfile = assert(io.open("modmain.lua", "r"))
local modsource = modfile:read("*a")
modfile:close()
local identity = assert(modsource:match("(local function IsActualCompanion%b()%s*.-\nend)"))
local management = assert(modsource:match("(local function CanManage%b()%s*.-\nend)"))
local wheelhandler = assert(modsource:match('(AddModRPCHandler%("MyFriends", "WheelCommand",.-\nend%))'))
local wheel_rpc
AddModRPCHandler = function(namespace, id, callback)
    assert(namespace == "MyFriends" and id == "WheelCommand")
    wheel_rpc = callback
end
local can_manage = assert(loadstring('local Characters = require("my_friend_characters")\nlocal Possess = {}\n'
    .. identity .. "\n" .. management .. "\n" .. wheelhandler .. "\nreturn CanManage"))()
for _, widget in ipairs({"widget", "image", "imagebutton", "text"}) do
    package.loaded["widgets/" .. widget] = {}
end
GetModRPC = function(namespace, id) assert(namespace == "MyFriends"); return id end
SendModRPCToServer = function(id, target, command)
    assert(id == "WheelCommand")
    wheel_rpc(player, target, command)
end
local Wheel = require("widgets/my_friend_command_wheel")
local wheel = setmetatable({commands = {"revive"}}, {__index = Wheel})
function wheel:HideWheel() self.closed, self.friend = true, nil end
assert(not can_manage(player, inst, true, true), "ordinary inventory management must still reject ghosts")
local outsider = entity("wilson")
wheel_rpc(outsider, inst, "revive")
wheel_rpc(player, inst, {})
assert(inst._my_friend_ghost_revive == nil, "RPC sender and command type checks remain in force")

for _, dispatch in ipairs({
    function()
        wheel.friend, wheel.closed = inst, false
        wheel:Choose(1)
        assert(wheel.closed, "the actual wheel button closes after sending its selected stable command ID")
        return inst._my_friend_ghost_revive ~= nil
    end,
    function() return Commands.Dispatch(inst, player, "奶奶，复活") end,
}) do
    local before = inst.brain.wakes
    assert(dispatch() and replies[#replies] == "ghost_revive_nearby")
    assert(inst.brain.wakes > before, "accepted wheel/chat requests must wake a hibernating brain")
    local before_pushes = pushes
    inst.brain.bt.root:Visit()
    assert(inst.brain.bt.root.active.id == "revive" and pushes == before_pushes + 1)
    assert(inst.bufferedaction.action == ACTIONS.HAUNT and inst.bufferedaction.target == amulet)
end

local old_brain, old_action = inst.brain, inst.bufferedaction
inst.busy = true
inst:PushEvent("ms_becameghost")
assert(old_brain.stopped and inst.brain ~= old_brain)
assert(inst._my_friend_storage_action == nil and inst._my_friend_ghost_revive ~= nil)
assert(old_action._my_friend_cancelled, "native stategraph replacement must retire the old queued action")
assert(leader == player, "becoming a ghost preserves the current follower relationship")

inst._my_friend_death_point = {x = 2, y = 0, z = 0}
inst._my_friend_backpack_action, inst._my_friend_container_action = true, true
inst._my_friend_navigation_action, inst._my_friend_route_planning = old_action, true
inst._my_friend_movement_owner = old_brain.bt.root
inst.tags.playerghost = nil
inst.sg.currentstate.name = "rewindtime_rebirth"
leader = nil
local before = brain_starts
inst:PushEvent("ms_respawnedfromghost")
assert(brain_starts == before + 1 and leader == player,
    "Wanda resurrection must rebuild companion decisions and restore an eligible prior follow request")
assert(inst._my_friend_backpack_action == nil and inst._my_friend_container_action == nil
    and inst._my_friend_storage_action == nil and inst._my_friend_navigation_action == nil)
assert(inst._my_friend_movement_owner == nil and inst._my_friend_route_planning == nil)
assert(inst._my_friend_ghost_revive.returning and inst._my_friend_recover_death_drops)
local root = inst.brain.bt.root
root:Visit()
assert(root.active == nil and inst.sg.currentstate.name == "rewindtime_rebirth",
    "native busy resurrection animation must finish before AI acts")
inst.busy, inst.sg.currentstate.name = false, "idle"
root:Visit()
assert(root.active.id == "follow", "revived Wickerbottom resumes following rather than a stale ghost/idle node")
assert(Commands.Dispatch(inst, player, "奶奶，跟随"))
root:Visit()
assert(root.active.id == "follow" and leader == player)

inst.components.my_friend_affinity.staying = true
inst.components.my_friend_affinity.requests = {}
leader = nil
inst:PushEvent("ms_respawnedfromghost")
assert(leader == nil, "revival must not override an explicit stay/stop-following command")
inst.components.my_friend_affinity.staying = false
inst.components.my_friend_affinity.requests = {player.userid}
leader, player.tags.playerghost = player, true
inst:PushEvent("ms_respawnedfromghost")
assert(leader == player, "keepdeadleader must survive the companion's own revival")
player.tags.playerghost = nil

before = brain_starts
inst._my_friend_possess_parked = true
inst:PushEvent("ms_respawnedfromghost")
assert(brain_starts == before, "a parked possession body must not acquire an active AI")
inst._my_friend_possess_parked = nil
assert(periodic_tasks == before_tasks, "lifecycle recovery must not add polling tasks")
math.random = random
print("PASS: actual wheel RPC/chat resurrection executes HAUNT, request wakeup, ghost/Wanda lifecycle reset, follow restoration, permissions, stay/dead-leader preservation and busy protection")
