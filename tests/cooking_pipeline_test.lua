-- Real roasting selection, recipe planning, container access, ingredient
-- delivery, COOK guard and harvest; native action effects use small fixtures.
package.path = "scripts/?.lua;" .. package.path
local now, guid, leader = 10, 0, nil
GetTime = function() return now end
TUNING = {TOTAL_DAY_TIME = 480, PERISH_STALE = .2}
local function noop() end
Vector3 = function(x, y, z) return {x = x, y = y, z = z} end
ACTIONS = {}
for _, name in ipairs({"COOK", "EAT", "ADDFUEL", "HARVEST", "MY_FRIEND_OPEN", "MY_FRIEND_WITHDRAW",
    "MY_FRIEND_RECIPE_ADD", "PICKUP"}) do ACTIONS[name] = {id = name} end
BufferedAction = function(inst, target, kind, item)
    local act = {doer = inst, target = target, action = kind, invobject = item, success = {}, failure = {}}
    function act:AddSuccessAction(fn) self.success[#self.success + 1] = fn end
    function act:AddFailAction(fn) self.failure[#self.failure + 1] = fn end
    function act:Succeed() for _, fn in ipairs(self.success) do fn() end end
    return act
end
local function entity(prefab, x)
    guid = guid + 1
    local e = {GUID = guid, prefab = prefab, components = {}, tags = {}, x = x or 0, items = {}}
    function e:IsValid() return not self.removed end
    function e:HasTag(tag) return self.tags[tag] == true end
    function e:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    function e:GetCurrentPlatform() return nil end
    function e:GetPosition() return Vector3(self.x, 0, 0) end
    function e:GetPhysicsRadius() return .5 end
    function e:GetDistanceSqToInst(other) return (self.x - other.x)^2 end
    function e:GetDistanceSqToPoint(point) return (self.x - point.x)^2 end
    function e:PushEvent() end
    function e:DoTaskInTime() return {Cancel = noop} end
    e.Transform = {GetWorldPosition = function() return e.x, 0, 0 end}
    return e
end
package.loaded.my_friend_policy = {
    GetLeader = function() return leader end, InRange = function() return true end,
    IsBusy = function() return false end, IsFollowGatheringPaused = function() return false end,
    IsLeaderDead = function() return false end, GuardAction = function(_, act) return act end,
}
package.loaded.my_friend_pets = {IsIngredient = function() return false end}
package.loaded.my_friend_light_ai = {IsDark = function() return false end}
package.loaded.my_friend_survival_ai = {}
local manual, complete = false, false
package.loaded.my_friend_home = {NoConstruction = function() return manual end}
package.loaded.my_friend_base_ai = {IsComplete = function() return complete end}
local recipe = {name = "meatballs", foodtype = "MEAT", health = 3, hunger = 62.5,
    sanity = 5, cooktime = 1, test = function(_, names) return names.meat == 1 and names.berries == 3 end}
package.loaded.cooking = {ingredients = {meat = {tags = {meat = 1}}, berries = {tags = {fruit = .5}}},
    recipes = {cookpot = {meatballs = recipe}},
    GetRecipe = function(_, name) return name == "meatballs" and recipe or nil end,
    IsCookingIngredient = function(name) return name == "meat" or name == "berries" end}
local inst = entity("wilson")
inst.tags.my_friend = true
inst.sg = {HasStateTag = function() return false end}
inst.components.health = {currenthealth = 150, maxhealth = 150,
    IsDead = function() return false end, GetPercent = function() return 1 end}
inst.components.hunger = {current = 120, max = 150, GetPercent = function(self) return self.current / self.max end}
inst.components.sanity = {current = 200, max = 200}
inst.components.follower = {GetLeader = function() return leader end}
inst.components.eater = {caneat = {"MEAT", "VEGGIE"}, preferseating = {"MEAT", "VEGGIE"},
    healthabsorption = 1, hungerabsorption = 1, sanityabsorption = 1,
    CanEat = function() return true end, PrefersToEat = function() return true end,
    DoFoodEffects = function() return true end}
inst.components.inventory = {ReferenceAllItems = function() return inst.items end,
    FindItem = function(_, predicate) for _, item in ipairs(inst.items) do if predicate(item) then return item end end end,
    IsFull = function() return false end, CanAcceptCount = function(_, _, count) return count end}
local function remove(owner, item)
    for i, value in ipairs(owner.items) do if value == item then table.remove(owner.items, i) return end end
end
local function food(name, freshness, health, sanity)
    local item = entity(name)
    item.components.inventoryitem = {GetGrandOwner = function(self) return self.owner end,
        RemoveFromOwner = function(self)
            if self.owner ~= nil then remove(self.owner, item) end
            self.owner = nil
            return item
        end}
    item.components.edible = {foodtype = name == "berries" and "VEGGIE" or "MEAT",
        healthvalue = health or 0, sanityvalue = sanity or 0,
        GetHealth = function() return health or 0 end,
        GetHunger = function() return name == "berries" and 12.5 or 25 end,
        GetSanity = function() return sanity or 0 end}
    item.components.perishable = {GetPercent = function() return freshness end}
    return item
end
local function give(owner, item)
    owner.items[#owner.items + 1] = item
    item.components.inventoryitem.owner = owner
end
local function container(prefab, x)
    local e = entity(prefab, x)
    e.tags.chest = true
    e.components.container = {canbeopened = true, GetAllItems = function() return e.items end,
        IsRestricted = function(self) return self.restricted == true end,
        IsOpenedByOthers = function() return false end,
        IsOpenedBy = function(self, actor) return self.opened == actor end,
        CanOpen = function() return true end, CanTakeItemInSlot = function() return true end,
        GiveItem = function(_, item) give(e, item); return true end,
        Close = function(self) self.opened = nil end}
    return e
end
local entities = {}
TheSim = {FindEntities = function() return entities end}
local Rules = require("my_friend_food_rules")
local Roast = require("my_friend_cooking_ai")
local cooker = entity("firepit", 1)
cooker.components.cooker = {CanCook = function() return true end}
entities = {cooker}
for _, mode in ipairs({"construction", "follow", "manual", "complete"}) do
    leader = mode == "follow" and entity("wilson") or nil
    manual, complete = mode == "manual", mode == "complete"
    local raw = food("meat", 1, 1, -10)
    raw.components.cookable = {}
    inst.items = {}; give(inst, raw)
    assert(Roast.GetAction(inst) == nil, "sanity-only cost must not trigger roasting in " .. mode)
    local red = food("meat", .19, 0, -10)
    red.components.cookable = {}
    inst.items = {}; give(inst, red)
    local act = assert(Roast.GetAction(inst), "red food must roast in " .. mode)
    assert(act.action == ACTIONS.COOK and act.invobject == red and act:validfn())
    red.components.inventoryitem.islockedinslot = true
    assert(not act:validfn() and Roast.GetAction(inst) == nil, "locked food stays protected")
    local harmful = food("monstermeat", 1, -20, -15)
    harmful.components.cookable = {}
    inst.items = {}; give(inst, harmful)
    assert(Roast.GetAction(inst).invobject == harmful)
end

local Recipe = require("my_friend_recipe_cooking")
for _, mode in ipairs({"construction", "follow", "manual", "complete"}) do
    leader = mode == "follow" and entity("wilson") or nil
    manual, complete = mode == "manual", mode == "complete"
    inst.items = {}
    Recipe.Cancel(inst)
    inst._my_friend_food_supply_cache = nil
    local pot = container("cookpot", 1)
    local icebox, saltbox, chest = container("icebox", 2), container("saltbox", 2), container("treasurechest", 2)
    give(icebox, food("meat", .9, 1, -10))
    give(saltbox, food("berries", .9))
    give(chest, food("berries", .9)); give(chest, food("berries", .9))
    local cooking, done = false, false
    pot.components.stewer = {IsCooking = function() return cooking end,
        IsDone = function() return done end, CanCook = function() return #pot.items == 4 end}
    entities = {pot, icebox, saltbox, chest}
    local withdrawn, cooked, harvested = {}, false, false
    assert(Recipe.Score(inst) > 0, "recipe planning must be available in " .. mode)
    for _ = 1, 16 do
        local act, status = Recipe.GetAction(inst)
        assert(act ~= nil, "recipe pipeline unexpectedly stopped: " .. tostring(status))
        assert(act:validfn(), "queued recipe action must remain valid")
        if act.action == ACTIONS.MY_FRIEND_OPEN then
            act.target.components.container.opened = inst
        elseif act.action == ACTIONS.MY_FRIEND_WITHDRAW then
            withdrawn[act.target.prefab] = true
            local moved = act.invobject.components.inventoryitem:RemoveFromOwner(false)
            give(inst, moved)
        elseif act.action == ACTIONS.MY_FRIEND_RECIPE_ADD then
            assert(Recipe.AddIngredient(act), "native inventory interfaces must deliver one ingredient")
        elseif act.action == ACTIONS.COOK then
            assert(#pot.items == 4)
            assert(Rules.CookAction(act, function()
                pot.items = {}; cooking = true; pot.components.stewer.product = "meatballs"; return true
            end))
            cooked = true
        elseif act.action == ACTIONS.HARVEST then
            harvested = true
            local meal = food("meatballs", 1, 3, 5)
            meal.tags.preparedfood = true
            give(inst, meal)
            done = false
        else error("unexpected action " .. tostring(act.action.id)) end
        act:Succeed()
        now = now + .1
        if cooked and cooking then cooking, done = false, true end
        if harvested then break end
    end
    assert(cooked and harvested and withdrawn.icebox and withdrawn.saltbox and withdrawn.treasurechest,
        "all three pantry types must supply a completed meal in " .. mode)
    assert(pot._my_friend_recipe_job == nil and pot.components.container.opened == nil)
end
package.loaded.my_friend_container_ai = {GetCarriedFoodAction = noop}
local Food = require("my_friend_food_ai")
local raw = food("meat", 1, 1, -10)
raw.components.cookable = {}
inst.items = {}; give(inst, raw)
for _, hunger in ipairs({60, 0}) do
    inst.components.hunger.current = hunger
    local eat = assert(Food.GetEatAction(inst), "raw meat must generate a real eating action")
    assert(eat.action == ACTIONS.EAT and eat.invobject == raw and eat:validfn())
end

-- Restoring cooking must not bypass pantry permissions.
inst.components.hunger.current = 120
inst.items = {}
local blocked = container("icebox", 2)
give(blocked, food("meat", .9, 1, -10))
for _ = 1, 3 do give(blocked, food("berries", .9)) end
local pot = container("cookpot", 1)
pot.components.stewer = {IsCooking = function() return false end, IsDone = function() return false end}
entities = {pot, blocked}
blocked.components.container.readonlycontainer = true
Recipe.Cancel(inst)
assert(Recipe.Score(inst) == 0)
blocked.components.container.readonlycontainer, blocked.components.container.restricted = false, true
Recipe.Cancel(inst)
assert(Recipe.Score(inst) == 0)
print("PASS: real roasting filters and complete pantry -> pot -> cook -> harvest pipeline in follow/manual/complete/construction modes")
