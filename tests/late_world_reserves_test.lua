-- Run from the mod root: lua tests/late_world_reserves_test.lua
package.path = "scripts/?.lua;" .. package.path
GetTime = function() return 10 end
TheWorld = {state = {cycles = 149}}
ACTIONS = {PICKUP = {}, PICK = {}, HARVEST = {}}
package.loaded.my_friend_food_ai = {NeedsFoodSupply = function() return false end, IsUsableFood = function() return false end}
package.loaded.my_friend_home = {AllowsTarget = function() return true end}
package.loaded.my_friend_navigation = {IsBlocked = function() return false end}
package.loaded.my_friend_resource_safety = {IsBlocked = function() return false end}
package.loaded.my_friend_policy = {
    IsBusy = function() return false end, GetLeader = function() return nil end,
    IsBaseCacheItem = function() return false end, InRange = function() return true end,
    SearchOrigin = function() return 0, 0, 0, 12 end,
    DistanceSq = function(_, item) return item.x^2 end,
}
BufferedAction = function(inst, target, action)
    local a = {doer = inst, target = target, action = action}
    function a:AddSuccessAction() end
    function a:AddFailAction() end
    return a
end
local counts = {cutgrass = 10, twigs = 10}
local inst = {components = {inventory = {
    Has = function(_, prefab) return (counts[prefab] or 0) > 0, counts[prefab] or 0 end,
    CanAcceptCount = function() return 40 end,
}, health = {IsDead = function() return false end}, hunger = {GetPercent = function() return 1 end}, eater = {}}}
function inst:IsValid() return true end
function inst:HasTag() return false end
inst.Transform = {GetWorldPosition = function() return 0, 0, 0 end}
local function item(prefab, x)
    local e = {prefab = prefab, x = x, components = {inventoryitem = {canbepickedup = true}}}
    function e:IsValid() return true end
    function e:IsInLimbo() return false end
    function e:HasTag() return false end
    function e:HasAnyTag() return false end
    function e:GetPosition() return {x = x, y = 0, z = 0} end
    e.Transform = {GetWorldPosition = function() return x, 0, 0 end}
    return e
end
local grass, twigs, rocks, gold = item("cutgrass", 1), item("twigs", 2), item("rocks", 3), item("goldnugget", 4)
TheSim = {FindEntities = function(_, _, _, _, _, must)
    return must ~= nil and must[1] == "_combat" and {} or {rocks, gold, twigs, grass}
end}
local Reserves = require("my_friend_resource_reserves")
local AI = require("my_friend_behavior_ai")
assert(not Reserves.IsLateWorld(), "displayed day 150 keeps the original behavior")
assert(Reserves.FollowingKeep().rocks == 10)
assert(AI.GetFoodOrResourceAction(inst) ~= nil)
TheWorld.state.cycles = 150
assert(Reserves.IsLateWorld(), "displayed day 151 enters the late-world branch")
local keep = Reserves.FollowingKeep()
assert(keep.cutgrass == 10 and keep.twigs == 10 and keep.rocks == nil and keep.goldnugget == nil and keep.log == nil)
assert(AI.GetFoodOrResourceAction(inst) == nil, "normal opportunity gathering stops filling material reserves")
assert(AI.GetResourceAction(inst) == nil and AI.GetLateMinimumAction(inst) == nil)
counts.cutgrass = 9
assert(AI.GetLateMinimumAction(inst).target == grass)
assert(not inst._my_friend_resource_needs.rocks and not inst._my_friend_resource_needs.goldnugget)
counts.cutgrass, counts.twigs = 10, 9
assert(AI.GetLateMinimumAction(inst).target == twigs)
inst._my_friend_command = {id = "mine"}
assert(AI.GetLateMinimumAction(inst) == nil, "the low-priority branch yields to explicit work commands")
assert(Reserves.LATE_MINIMUM_SCORE < 40, "minimum supplies rank below normal opportunities and work")
print("PASS: day 150/151 boundary, no late material stockpiling, low-priority 10 grass/10 twig minimum and command yielding")
