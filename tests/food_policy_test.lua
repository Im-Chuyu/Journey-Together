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
inst.components.health = {currenthealth = 150, maxhealth = 150, IsDead = function() return false end}
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
leader = {}; assert(Rules.CanCook(inst)); leader = nil
manual = true; assert(Rules.CanCook(inst)); manual = false
complete = true; assert(Rules.CanCook(inst)); complete = false
for _, name in ipairs({"royal_jelly", "royaljelly", "mandrake", "tallbirdegg", "deerclops_eyeball", "minotaurhorn"}) do
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
local original_prefab = inst.prefab
for _, prefab in ipairs({"wilson", "wathgrithr", "wortox", "wanda", "wickerbottom"}) do
    inst.prefab = prefab
    for _, name in ipairs({"deerclops_eyeball", "minotaurhorn"}) do
        local drop = item(name, 1, "MEAT", 100, 150, 100)
        inst.components.inventory.ReferenceAllItems = function() return {drop} end
        inst._my_friend_food_supply_cache = nil
        assert(Food.IsForbiddenFood(name) and Food.IsForbiddenFood(drop))
        assert(not Food.IsUsableFood(inst, drop) and Food.FindBestFood(inst) == nil, prefab .. ": " .. name)
        assert(Food.GetFoodSupply(inst) == 0 and Food.GetEatAction(inst, drop) == nil)
        local health, hunger, sanity = inst.components.health.currenthealth,
            inst.components.hunger.current, inst.components.sanity.current
        inst.components.health.currenthealth, inst.components.hunger.current, inst.components.sanity.current = 1, 1, 1
        assert(Food.Evaluate(inst, drop) == nil and Food.CommandScore(inst, drop) == nil,
            "hunger, health and sanity emergencies must not consume boss drops")
        inst.components.health.currenthealth, inst.components.hunger.current, inst.components.sanity.current = health, hunger, sanity
        assert(inst.components.eater:CanEat(drop), "manual feeding still obeys the original diet")
        assert(Rules.CanUseIngredient(drop), "an autonomous eating restriction must not change ingredient rules")
    end
end
inst.prefab = original_prefab
inst.components.inventory.ReferenceAllItems = function() return {jerky} end
assert(Food.FindBestFood(inst) == jerky, "ordinary food remains available")
function inst:HasTag(tag) return tag == "my_friend" end
local calls = 0
local original = function() calls = calls + 1; return true end
leader = {}; assert(Rules.CookAction({doer = inst}, original) and calls == 1); leader = nil
assert(Rules.CookAction({doer = inst}, original) and calls == 2)
local potitems = {item("meat", 1), item("meat", 1), item("cookedmeat", 1), item("berries", 1)}
local act = {doer = inst, target = {components = {stewer = {},
    container = {GetAllItems = function() return potitems end}}}}
assert(not Rules.CookAction(act, original))
potitems[1] = item("meat", .49); assert(Rules.CookAction(act, original))
potitems[1] = jerky; assert(not Rules.CookAction(act, original))
local player = {HasTag = function() return false end}
assert(Rules.CookAction({doer = player}, original), "ordinary players keep native cooking")
local raw = item("meat", 1, "MEAT", 1, 25, -10)
raw.components.cookable = {product = "cookedmeat"}
inst.components.inventory.ReferenceAllItems = function() return {raw} end
inst.components.health.currenthealth, inst.components.sanity.current = 150, 200
inst.components.hunger.current = 60
assert(not Rules.NeedsRoasting(inst, raw) and Food.FindBestFood(inst) == raw,
    "a hungry healthy companion must eat raw meat despite its sanity cost")
inst.components.hunger.current = 0
assert(Food.FindBestFood(inst) == raw, "starvation must not reject food for its sanity cost")
inst.components.hunger.current, inst.components.health.currenthealth = 100, 50
local healing = item("healing_raw", 1, "MEAT", 30, 5, -10)
healing.components.cookable = {}
assert(Food.Evaluate(inst, healing) ~= nil, "healing food with sanity cost remains available")
local harmful = item("monstermeat", 1, "MEAT", -20, 18.75, -15)
harmful.components.cookable = {}
assert(Rules.NeedsRoasting(inst, harmful))
for _, freshness in ipairs({.5, .21, .2}) do
    local food = item("meat", freshness, "MEAT", 0, 25, -10)
    food.components.cookable = {}
    assert(not Rules.NeedsRoasting(inst, food), "only freshness strictly below 20% triggers roasting")
end
local red = item("meat", .199, "MEAT", 0, 25, -10)
red.components.cookable = {}
assert(Rules.NeedsRoasting(inst, red))
assert(not Rules.CookAction({doer = inst, invobject = raw}, original))
assert(Rules.CookAction({doer = inst, invobject = red}, original))
print("PASS: cooking across modes, health/red-freshness roasting, sanity-cost hunger/healing food, protected ingredients and role diets")
