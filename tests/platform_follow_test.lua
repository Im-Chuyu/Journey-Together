-- Real navigation geometry and brain follow node. Locomotor requests and
-- native hop ownership are observed; actual hop physics still needs the game.
package.path = "scripts/?.lua;" .. package.path
local now, moves, resets, searches, guid = 0, 0, 0, 0, 0
GetTime = function() return now end
local vector = {}
vector.__index = vector
function vector:Get() return self.x, self.y, self.z end
function vector:LengthSq() return self.x^2 + self.y^2 + self.z^2 end
function vector.__sub(a, b) return Vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
Vector3 = function(x, y, z) return setmetatable({x = x, y = y, z = z}, vector) end
local function noop() end
local function entity(x, z)
    guid = guid + 1
    local inst = {GUID = guid, pos = Vector3(x or 0, 0, z or 0), tags = {}, components = {}}
    function inst:IsValid() return not self.removed end
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:GetPosition() return self.pos end
    function inst:GetCurrentPlatform() return self.platform end
    function inst:GetPhysicsRadius() return .5 end
    function inst:GetDistanceSqToPoint(p) return (self.pos - p):LengthSq() end
    function inst:ListenForEvent() error("follow must not track the leader's historical hops") end
    function inst:DoPeriodicTask() error("no new periodic scanning tasks") end
    inst.Transform = {GetWorldPosition = function() return inst.pos:Get() end}
    inst.entity = {
        WorldToLocalSpace = function(_, x1, y1, z1) return x1 - inst.pos.x, y1, z1 - inst.pos.z end,
        LocalToWorldSpace = function(_, x1, y1, z1) return x1 + inst.pos.x, y1, z1 + inst.pos.z end,
    }
    return inst
end
local inst, leader, boat = entity(-3), entity(-3), entity(0)
inst.components.follower = {GetLeader = function() return leader end}
inst.components.health = {IsDead = function() return false end}
inst.components.locomotor = {pathcaps = {},
    ResetPath = function() resets = resets + 1 end,
    Stop = function(self) self.dest = nil end,
    GoToPoint = function(self, point)
        moves = moves + 1; self.dest = point; self.was_ground_move = self.directdrive == true
    end}
inst.sg = {HasStateTag = function(_, tag) return inst.tags[tag] == true end,
    GoToState = function() error("no forced state changes") end}
TheSim = {FindEntities = function() searches = searches + 1; return {} end}
local ground = function(x) return x <= -3 or x >= 3 end
TheWorld = {Map = {
    IsPointNearHole = function() return false end,
    IsVisualGroundAtPoint = function(_, x, _, z) return ground(x, z) end,
    IsOceanTileAtPoint = function() return true end,
    IsPassableAtPoint = function() return true end,
}, Pathfinder = {IsClear = function() return false end, KillSearch = noop}}
local Navigation = require("my_friend_navigation")
local Platforms = require("my_friend_platforms")

-- Diagonally touching docks with native walkable overhang. Underlying ocean
-- flags and a conservative native path grid must not reject a usable seam.
inst.platform, inst.pos = nil, Vector3(-1, 0, -1)
ground = function(x, z)
    return x <= .15 and z <= .15 or x >= -.15 and z >= -.15
end
assert(Navigation.IsLand(Vector3(-.1, 0, .1)))
assert(Navigation.IsStepClear(inst, inst.pos, Vector3(1, 0, 1), {}, nil, true))
ground = function(x) return x <= -1 or x >= 1 end
assert(not Navigation.IsStepClear(inst, Vector3(-2, 0, 0), Vector3(2, 0, 0), {}, nil, true),
    "an actual open-water gap is still not walkable")
ground = function() return true end
TheWorld.Map.IsPointNearHole = function() return true end
assert(not Navigation.IsLand(inst.pos), "groundhole protection remains")
TheWorld.Map.IsPointNearHole = function() return false end

-- Register the real brain and execute its actual follow node after landing.
-- Unrelated task systems are stubs; platform/path reset and steering are real.
READY, RUNNING, SUCCESS, FAILED = 0, 1, 2, 3
BehaviourNode = {_ctor = noop, Sleep = noop}
Brain = {_ctor = function(self, value) self.inst = value end}
Class = function(base, ctor)
    local class = {_ctor = ctor}; class.__index = class
    return setmetatable(class, {__index = base, __call = function(_, ...)
        local result = setmetatable({}, class); ctor(result, ...); return result
    end})
end
local function node() return {} end
WhileNode, RunAway, StandStill = node, node, node
BT = function(_, root) return {root = root} end
for _, name in ipairs({"behaviours/doaction", "behaviours/runaway", "behaviours/standstill",
    "behaviours/my_friend_combat", "behaviours/my_friend_ghost_follow", "behaviours/my_friend_fishing",
    "my_friend_food_ai", "my_friend_light_ai", "my_friend_container_ai", "my_friend_survival_ai",
    "my_friend_base_ai", "my_friend_backpacks", "my_friend_revive_ai", "my_friend_ghost_commands",
    "my_friend_core_ai", "my_friend_cooking_ai", "my_friend_recipe_cooking", "my_friend_tidy",
    "my_friend_behavior_ai", "my_friend_commands", "my_friend_social_ai", "my_friend_emotes",
    "my_friend_sitting", "my_friend_beefalo", "my_friend_fishing", "my_friend_exploration",
    "my_friend_command_special_gather", "my_friend_farewell", "my_friend_wormhole", "my_friend_equipment",
    "my_friend_wanda", "my_friend_character_actions", "my_friend_wormwood", "my_friend_wortox",
    "my_friend_command_tower", "my_friend_rescue", "my_friend_butterfly", "my_friend_carry_backpack",
    "my_friend_fertilizer_search", "my_friend_books", "my_friend_feed_player", "my_friend_basic_equipment",
    "my_friend_pet_care"}) do
    package.loaded[name] = setmetatable({}, {__index = function() return noop end, __call = node})
end
package.loaded.my_friend_beefalo.Riding = {Behaviour = node}
package.loaded["behaviours/my_friend_route_action"] = node
package.loaded["behaviours/my_friend_utility"] = function(_, entries) return {entries = entries} end
local BrainClass = require("brains/my_friendbrain")
local brain = BrainClass(inst); brain:OnStart()
local follow
for _, entry in ipairs(brain.bt.root.entries) do if entry.id == "catch_up" then follow = entry.node end end
assert(follow ~= nil)
-- The companion is blocked on shore while the leader boards and disembarks.
-- Do not replay that obsolete trip once the obstruction has cleared.
inst.pos, leader.pos, leader.platform = Vector3(0, 0, 0), Vector3(8, 0, 0), boat
ground = function(x) return x <= 0 or x >= 12 end
local before = moves
local scans_before = searches
follow:Visit()
assert(moves == before + 1 and inst.components.locomotor.dest.x == 8
    and not inst.components.locomotor.was_ground_move and searches == scans_before,
    "shore-to-boat follow must let native locomotor approach the current leader")
leader.platform, leader.pos = nil, Vector3(12, 0, 0)
ground = function() return true end
follow:Visit()
assert(inst.components.locomotor.was_ground_move and inst.components.locomotor.dest.x == 12
    and not Platforms.NeedsCrossing(inst, leader),
    "after the leader leaves the boat, discard the old boarding destination and follow on land")

-- A complete fast boat trip while this node is preempted leaves no history
-- that can force the companion to board after the player has already left.
leader.platform = boat
leader.platform, leader.pos = nil, Vector3(16, 0, 0)
follow:Visit()
assert(inst.components.locomotor.was_ground_move and inst.components.locomotor.dest.x == 16)

-- Already aboard: pursue the leader's live position rather than a fixed old
-- disembark point. The native component chooses a currently reachable hop.
inst.platform, inst.pos, leader.pos = boat, Vector3(0, 0, 0), Vector3(9, 0, 0)
scans_before = searches
follow:Visit()
assert(not inst.components.locomotor.was_ground_move and inst.components.locomotor.dest.x == 9
    and searches == scans_before)
leader.pos = Vector3(20, 0, 0)
follow:Visit()
assert(inst.components.locomotor.dest.x == 20, "moving leaders replace old exit coordinates")

-- Different platforms must keep approaching even within the usual stop
-- radius, without changing ordinary following distance when on one boat.
leader.pos = Vector3(2, 0, 0)
follow:Visit()
assert(inst.components.locomotor.dest.x == 2 and follow.chasing)
leader.platform, leader.pos = boat, Vector3(4, 0, 0)
follow.chasing = false
before = moves
follow:Visit()
assert(moves == before and not follow.chasing, "same-boat following must not crowd the leader")

-- A stale non-nil destination retries, with no new observer or world scan.
leader.platform, leader.pos = nil, Vector3(9, 0, 0)
follow:Visit()
before, scans_before = moves, searches
for _ = 1, 14 do now = now + .1; follow:Visit() end
assert(moves == before, "do not submit another native path every follow tick")
now = 2
follow:Visit()
assert(moves == before + 1 and searches == scans_before)

-- Moving with the deck must not count as progress relative to the boat.
inst._my_friend_last_move = nil
Platforms.Run(inst, Vector3(9, 0, 0))
before = moves
boat.pos, inst.pos, now = Vector3(.5, 0, 0), Vector3(.5, 0, 0), now + 2
Platforms.Run(inst, Vector3(9, 0, 0))
assert(moves == before + 1, "boat motion must not hide a stuck companion")

-- Busy and pending native hops must complete before a follow/path reset.
inst.components.embarker = {HasDestination = function() return true end}
inst._my_friend_follow_route_reset = true
before = resets
follow:Visit()
assert(resets == before and inst._my_friend_follow_route_reset)
inst.components.embarker = nil

-- A changed leader platform invalidates a cached movement request even if
-- the leader's coordinates have not moved enough to trigger a refresh.
leader.platform = boat
follow:Visit()
leader.platform = nil
before = moves
follow:Visit()
assert(moves == before + 1, "platform changes supersede cached native destinations immediately")

-- Landing must still release old failed routes and resume normal following.
inst.platform = nil
inst.pos, leader.pos = Vector3(3, 0, 0), Vector3(15, 0, 0)
inst._my_friend_move_platform = boat
inst._my_friend_local_walk = {failed = true, goal = leader.pos, started = now}
inst._my_friend_land_route, inst._my_friend_long_follow = {}, {}
inst._my_friend_last_move = {point = Vector3(-3, 0, 0), run = true, untiltime = now + 100}
before = moves
follow:Visit()
assert(moves == before + 1 and inst.components.locomotor.dest.x == leader.pos.x
    and inst._my_friend_local_walk == nil and inst._my_friend_land_route == nil,
    "landing must clear failed boat/shore routes and resume ordinary pursuit")
inst._my_friend_local_walk = {failed = true, goal = leader.pos, started = now}
inst._my_friend_last_move = {point = leader.pos, run = true, untiltime = now + 100}
inst._my_friend_follow_route_reset = true
inst.tags.busy = true
before = moves
follow:Visit()
assert(moves == before and inst._my_friend_follow_route_reset,
    "a fresh follow request must wait for an active busy animation")
inst.tags.busy = nil
follow:Visit()
assert(moves == before + 1 and inst._my_friend_local_walk == nil
    and inst._my_friend_follow_route_reset == nil,
    "a follow request on the same shore must discard stale failed navigation")

-- Replacing a leader at the same coordinates must not inherit their native
-- movement cache, and losing the leader stops following altogether.
leader = entity(15)
before = moves
follow:Visit()
assert(moves == before + 1 and inst._my_friend_move_leader_guid == leader.GUID)
local current_leader = leader
leader = nil
follow:Visit()
assert(follow.status == FAILED and inst.components.locomotor.dest == nil)
leader = current_leader

-- The actual mounted follow method must also stop obsolete boarding and
-- honor native hop ownership after removing the old FollowCrossing API.
local Riding = require("my_friend_riding")
local mounted = Riding.Behaviour(inst)
inst.pos, leader.pos, leader.platform = Vector3(0, 0, 0), Vector3(8, 0, 0), boat
mounted:FollowMounted(leader)
assert(inst.components.locomotor.dest.x == 8 and not inst.components.locomotor.was_ground_move)
leader.platform, leader.pos = nil, Vector3(12, 0, 0)
scans_before = searches
mounted:FollowMounted(leader)
assert(inst.components.locomotor.dest.x == 12 and searches > scans_before,
    "mounted followers also discard old boarding targets and use land steering after the leader leaves")
inst._my_friend_follow_route_reset, inst.tags.busy = true, true
before = resets
mounted:FollowMounted(leader)
assert(resets == before and inst._my_friend_follow_route_reset)
inst.tags.busy = nil
inst.components.embarker = {HasDestination = function() return true end}
mounted:FollowMounted(leader)
assert(resets == before and inst._my_friend_follow_route_reset)
inst.components.embarker = nil
mounted:FollowMounted(leader)
assert(resets > before and inst._my_friend_follow_route_reset == nil)

-- Landing on a boat commits one four-unit deck move before live off-boat
-- following can take over. The point moves with the deck, not with the leader.
boat.components.walkableplatform = {platform_radius = 6}
boat.pos = Vector3(0, 0, 0)
inst.platform, inst.pos = nil, Vector3(-3, 0, 0)
leader.platform, leader.pos = boat, Vector3(9, 0, 0)
follow:Visit()
inst.platform = boat
follow:Visit()
assert(inst._my_friend_boarding_step ~= nil and inst.components.locomotor.dest.x == 1,
    "boarding must first move four units toward the captured leader direction")
leader.platform, leader.pos = nil, Vector3(20, 0, 0)
follow:Visit()
assert(inst.components.locomotor.dest.x == 1 and inst._my_friend_boarding_step ~= nil,
    "the leader's disembark must not overwrite the committed deck move")
boat.pos, inst.pos = Vector3(1, 0, 0), Vector3(-2, 0, 0)
now = now + .5
follow:Visit()
assert(inst.components.locomotor.dest.x == 2)
inst.pos = Vector3(2, 0, 0)
follow:Visit()
assert(inst._my_friend_boarding_step == nil and inst.components.locomotor.dest.x == 20,
    "normal disembark following resumes after the four-unit move completes")
follow:Visit()
assert(inst._my_friend_boarding_step == nil, "one landing must not restart the deck move")

-- Deck edges cap the one-off movement; timeout releases an obstructed move.
inst.platform = nil
follow:Visit()
inst.platform, inst.pos = boat, Vector3(5, 0, 0)
follow:Visit()
local deck_target = inst.components.locomotor.dest.x
assert(deck_target <= 6.25 and deck_target > 5, "the move must stay inside the deck safety margin")
before = resets
now = now + 2
follow:Visit()
assert(resets > before and inst._my_friend_boarding_step ~= nil,
    "a blocked deck move must retry its path before its total deadline")
now = now + 5
follow:Visit()
assert(inst._my_friend_boarding_step == nil, "a blocked deck move must have a bounded lifetime")
inst.platform = nil
follow:Visit()
boat.components.walkableplatform.platform_radius = 4
inst.platform, inst.pos = boat, Vector3(-2.5, 0, 0)
inst.tags.jumping = true
before = moves
follow:Visit()
assert(moves == before and inst._my_friend_boarding_step == nil, "native landing animation stays protected")
inst.tags.jumping = nil
follow:Visit()
assert(inst.components.locomotor.dest.x == 1.5,
    "landing just outside the extra safety margin must still allow four units inward")
assert(searches > 0, "geometry checks use the existing local obstacle query")
print("PASS: native current-leader boat following, no obsolete boarding, live exit targets, stall retry, dock geometry, landing recovery and follow reset")
