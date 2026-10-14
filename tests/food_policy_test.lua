-- Run from the mod root: lua tests/food_policy_test.lua
package.path = "scripts/?.lua;" .. package.path
GetTime = function() return 10 end
TUNING = {TOTAL_DAY_TIME = 480}
local leader, manual, complete = nil, false, false
package.loaded.my_friend_policy = {GetLeader = function() return leader end}
package.loaded.my_friend_home = {NoConstruction = function() return manual end}
package.loaded.my_friend_base_ai = {IsComplete = function() return complete end}
package.loaded.my_friend_pets = {IsIngredient = function() return false end}
package.loaded.my_friend_food_storage = {IsReserved = function() return false end,
    ReferenceItems = function(inst) return inst.components.inventory:ReferenceAllItems() end}
local Recipes = {
    meatballs = {name = "meatballs", foodtype = "MEAT", hunger = 62.5, health = 3, sanity = 5,
        test = function(_, names) return (names.meat or 0) == 1 end, priority = 0},
    bonestew = {name = "bonestew", foodtype = "MEAT", hunger = 150, health = 12, sanity = 5,
        test = function(_, names) return (names.meat or 0) + (names.meat_cooked or 0) >= 3 end, priority = 0},
}
package.loaded.cooking = {ingredients = {meat = {tags = {meat = 1}}, meat_cooked = {tags = {meat = 1}},
    berries = {tags = {fruit = .5}}}, recipes = {cookpot = Recipes},
    IsCookingIngredient = function() return true end}
local Rules = require("my_friend_food_rules")
local Food = require("my_friend_food_ai")
local Planner = require("my_friend_recipe_planner")
local inst = {prefab = "wathgrithr", components = {}}
function inst:HasTag() return false end
inst.components.eater = {caneat = {"MEAT"}, preferseating = {"MEAT"},
    healthabsorption = 1, hungerabsorption = 1, sanityabsorption = 1,
    CanEat = function(_, item) return item.components.edible.foodtype == "MEAT" end,
    PrefersToEat = function() return true end, DoFoodEffects = function() return true end}
inst.components.health = {currenthealth = 150, maxhealth = 150}
inst.components.hunger = {current = 60, max = 150, GetPercent = function() return .4 end}
inst.components.sanity = {current = 100, max = 200}
local function item(name, freshness, foodtype, h, f, s)
    local value = {prefab = name, components = {inventoryitem = {GetGrandOwner = function() return inst end}}}
    function value:IsValid() return true end
    function value:HasTag() return false end
    function value:HasAnyTag() return false end
    value.components.perishable = {GetPercent = function() return freshness end}
    value.components.edible = {foodtype = foodtype or "MEAT", healthvalue = h or 0, sanityvalue = s or 0,
        GetHealth = function() return h or 0 end, GetHunger = function() return f or 25 end,
        GetSanity = function() return s or 0 end}
    return value
end
assert(Rules.CanCook(inst))
leader = {}; assert(not Rules.CanCook(inst)); leader = nil
manual = true; assert(not Rules.CanCook(inst)); manual = false
complete = true; assert(not Rules.CanCook(inst)); complete = false
for _, name in ipairs({"royal_jelly", "royaljelly", "mandrake", "tallbirdegg"}) do
    local food = item(name, 1, "MEAT", 40, 75, 50)
    assert(Food.Evaluate(inst, food) == nil and Food.CommandScore(inst, food) == nil, name)
end
assert(not Rules.CanUseIngredient(item("royal_jelly", .1)))
assert(not Rules.CanUseIngredient(item("mandrake", .1)))
assert(Rules.CanUseIngredient(item("tallbirdegg", 1)), "egg can be cooked but cannot be eaten raw")
assert(not Planner.Available(inst, item("meat_dried", .5)))
assert(Planner.Available(inst, item("meat_dried", .49)))
assert(Planner.Evaluate(inst, "cookpot", {"meat", "meat", "cookedmeat", "berries"}) == nil)
assert(Planner.Evaluate(inst, "cookpot", {"meat", "meat", "cookedmeat", "berries"}, 1) ~= nil)
assert(Planner.RecipeValue(inst, Recipes.meatballs) > Planner.RecipeValue(inst, Recipes.bonestew))
local jerky = item("meat_dried", 1, "MEAT", 20, 25, 15)
local stew = item("bonestew", 1, "MEAT", 12, 150, 5)
local vegetable = item("berries", 1, "VEGGIE", 0, 12.5, 0)
inst.components.inventory = {ReferenceAllItems = function() return {stew, vegetable, jerky} end}
assert(Food.FindBestFood(inst) == jerky, "Wigfrid should prefer jerky within her native meat diet")
assert(Food.Evaluate(inst, vegetable) == nil)
Food.Configure(inst)
assert(not inst.components.eater:CanEat(item("royal_jelly", 1)))
assert(not inst.components.eater:CanEat(item("mandrake", 1)))
assert(inst.components.eater:CanEat(jerky))
function inst:HasTag(tag) return tag == "my_friend" end
local calls = 0
local original = function() calls = calls + 1; return true end
leader = {}; assert(not Rules.CookAction({doer = inst}, original) and calls == 0); leader = nil
assert(Rules.CookAction({doer = inst}, original) and calls == 1)
local potitems = {item("meat", 1), item("meat", 1), item("cookedmeat", 1), item("berries", 1)}
local act = {doer = inst, target = {components = {stewer = {},
    container = {GetAllItems = function() return potitems end}}}}
assert(not Rules.CookAction(act, original))
potitems[1] = item("meat", .49); assert(Rules.CookAction(act, original))
potitems[1] = jerky; assert(not Rules.CookAction(act, original))
local player = {HasTag = function() return false end}
assert(Rules.CookAction({doer = player}, original), "ordinary players keep native cooking")
print("PASS: construction-only cooking, protected foods, raw eggs, freshness and Wigfrid food priorities")
