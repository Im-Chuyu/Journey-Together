-- Actual body API/recipes/inventory permission code, with engine boundaries stubbed.
package.path = "./scripts/?.lua;../yuanma/scripts/?.lua;" .. package.path
local f = assert(io.open("tests/body_api_test.lua", "rb")); local source = f:read("*a"):gsub("\r", ""); f:close()
local prefix = assert(source:match("^(.-)local passed = 0"))
local fixture = assert(loadstring(prefix .. "\nreturn {setup=Setup,entity=Entity,item=Item,storage=Storage,armor=Armor,perform=Perform,advance=function(n)now=now+n end}"))()
local makeitem, armor = fixture.item, fixture.armor
fixture.item = function(...)
    local item = makeitem(...)
    function item:AddTag(tag) self.tags[tag] = true end
    function item:RemoveTag(tag) self.tags[tag] = nil end
    return item
end
fixture.armor = function(item, slot)
    armor(item, slot); item.components.equippable.IsRestricted = function() return false end
end
local API, Observation = require("my_friend_body_api"), require("my_friend_body_observation")
local RealInventory = assert(loadfile("scripts/my_friend_inventory.lua"))()
package.loaded.my_friend_inventory.CanWithdrawFrom = RealInventory.CanWithdrawFrom
package.loaded.my_friend_inventory.ContainerReach = function() return 2.6 end
local base_recipe, base_cook = GetValidRecipe, ACTIONS.COOK.fn
local sequence = 0
local function Call(inst, p, skill, args, plan)
    sequence = sequence + 1
    return API.Call(inst, p, "resources:" .. sequence, skill, args or {}, nil, "user", plan)
end
local function Setup()
    local inst, p, state = fixture.setup()
    STRINGS = {NAMES = {RESEARCHLAB = "科学机器", GOLDNUGGET = "金块", LOG = "木头", ROCKS = "石头"}}
    AllRecipes = {researchlab = {name = "researchlab", product = "researchlab", numtogive = 1, level = {SCIENCE = 0},
        ingredients = {{type = "goldnugget", amount = 1}, {type = "log", amount = 4}, {type = "rocks", amount = 4}}}}
    GetValidRecipe = function(name) return AllRecipes[name] or base_recipe(name) end
    ACTIONS.COOK.fn = base_cook
    return inst, p, state
end
local function Handle(state, item) return Observation.Handle(state, item) end
local passed = 0
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
Test("container pickup and deposit open before moving items and close on completion", function()
    for _, prefab in ipairs({"treasurechest", "icebox", "saltbox"}) do
        local inst, p, state = Setup()
        local box = fixture.entity(prefab, 3); local c = fixture.storage(box, true)
        local item = fixture.item("rocks", box, 5)
        local opened, closed = 0, 0
        inst:ListenForEvent("opencontainer", function() opened=opened+1 end)
        inst:ListenForEvent("closecontainer", function() closed=closed+1 end)
        local r = Call(inst,p,"pickup",{target=Handle(state,item),count=2})
        fixture.perform(inst)
        assert(c:IsOpenedBy(inst) and opened==1 and item.size==5 and state.jobs[r.action_id].status=="running")
        fixture.perform(inst)
        local final=state.jobs[r.action_id]
        assert(final.status=="completed" and final.result.count==2 and item.size==3)
        assert(not c:IsOpenedBy(inst) and closed==1)
        local carried=Observation.Resolve(state,final.result.items[1].handle)
        r=Call(inst,p,"transfer",{item=Handle(state,carried),destination=Handle(state,box),count=1})
        fixture.perform(inst); assert(c:IsOpenedBy(inst) and carried.size==2)
        fixture.perform(inst)
        assert(state.jobs[r.action_id].result.count==1 and carried.size==1 and not c:IsOpenedBy(inst))
        assert(opened==2 and closed==2)
    end
end)
Test("cancellation and failed transfer release only the container opened by this job", function()
    local inst,p,state=Setup(); local box=fixture.entity("icebox",3); local c=fixture.storage(box,true)
    local item=fixture.item("rocks",box,5)
    local r=Call(inst,p,"pickup",{target=Handle(state,item),count=2});fixture.perform(inst)
    assert(c:IsOpenedBy(inst))
    Call(inst,p,"cancel",{action_id=r.action_id});API.Tick(inst)
    assert(not c:IsOpenedBy(inst) and item.size==5)
    r=Call(inst,p,"pickup",{target=Handle(state,item),count=2});fixture.perform(inst)
    inst.components.inventory.full=true;fixture.perform(inst)
    assert(state.jobs[r.action_id].status=="failed" and not c:IsOpenedBy(inst) and item.size==5)
    inst.components.inventory.full=false
    c:Open(p)
    r=Call(inst,p,"pickup",{target=Handle(state,item),count=1});fixture.perform(inst)
    assert(state.jobs[r.action_id].status=="completed" and c:IsOpenedBy(p) and not c:IsOpenedBy(inst))
    c:Open(inst)
    r=Call(inst,p,"pickup",{target=Handle(state,item),count=1});fixture.perform(inst)
    assert(state.jobs[r.action_id].status=="completed" and c:IsOpenedBy(inst))
    c:Close(inst)
    r=Call(inst,p,"pickup",{target=Handle(state,item),count=1});fixture.perform(inst)
    API.Close(inst,"disconnected")
    assert(not c:IsOpenedBy(inst) and item.size==3)
end)
Test("shared storage withdraws an exact portion from an overstacked slot", function()
    local inst, p, state = Setup()
    local master = fixture.entity("shadow_container", 400)
    master.tags.pocketdimension_container = true
    local c = fixture.storage(master, true)
    local chest = fixture.entity("magician_chest", 3)
    chest.components.container_proxy = {
        GetMaster = function() return master end,
        CanBeOpened = function() return true end,
        IsOpenedBy = function(_, who) return c:IsOpenedBy(who) end,
        Open = function(_, who) c:Open(who) end,
        Close = function(_, who) c:Close(who) end,
    }
    local item = fixture.item("spidergland", master, 999)
    item.components.stackable.originalmaxsize = 40
    item.components.inventoryitem.RemoveFromOwner = function() error("must not remove an overstacked slot") end
    local q = Call(inst, p, "observe", {scope = "containers", filter = "magician_chest", contents = true})
    local observed = q.result.entities[1].contents[1]
    assert(observed.container == Handle(state, chest))
    assert(Call(inst, p, "pickup", {target = observed.handle}).reason == "storage_opening_required")
    local r = Call(inst, p, "pickup", {target = observed.handle, container = observed.container})
    fixture.perform(inst); fixture.perform(inst)
    assert(state.jobs[r.action_id].result.count == 1 and item.size == 998 and item.owner == master)
    assert(not c:IsOpenedBy(inst))
end)
Test("localized recipe lookup and failed craft return current native counts, modifiers and deficits", function()
    local inst, p, state = Setup(); fixture.item("rocks", inst, 1)
    local result = Call(inst, p, "query_recipe", {query = "科学机器"})
    assert(result.status == "completed" and result.result.recipe == "researchlab")
    local ingredients = {}; for _, entry in ipairs(result.result.ingredients) do ingredients[entry.prefab] = entry end
    assert(ingredients.rocks.required == 4 and ingredients.rocks.missing == 3)
    assert(ingredients.log.required == 4 and ingredients.goldnugget.required == 1)
    AllRecipes.researchlab.ingredients[3].amount = 7
    inst.materials = false
    result = Call(inst, p, "craft", {recipe = "researchlab"}); API.GetAction(inst)
    local final = state.jobs[result.action_id]
    assert(final.reason == "missing_materials" and final.result.ingredients[3].required == 7 and final.result.ingredients[3].missing == 6)
    inst.components.builder.ingredientmod = .5
    assert(Call(inst, p, "query_recipe", {query = "researchlab"}).result.ingredients[3].required == 4)
end)
Test("recipe technology distinguishes current access, saved unlocks and station manufacturing", function()
    local inst, p = Setup()
    local builder = inst.components.builder
    local recipe = AllRecipes.researchlab
    builder.KnowsRecipe = function() return true end
    builder.recipes = {}
    local function Status()
        return Call(inst, p, "query_recipe", {query = recipe.name}).result.technology_status
    end
    local technology = Status()
    assert(technology.known and technology.satisfied and technology.permanently_unlocked == false)
    assert(technology.allows_permanent_unlock and technology.manufactured == false)
    builder.recipes[1] = recipe.name
    assert(Status().permanently_unlocked == true)
    builder.recipes = {}
    recipe.nounlock = true
    technology = Status()
    assert(technology.allows_permanent_unlock == false and technology.permanently_unlocked == false)
    recipe.manufactured = true
    assert(Status().manufactured == true)
end)
Test("closed cooking and ready pots stay usable, preserve permissions and return product handles", function()
    local inst, p, state = Setup(); local pot = fixture.entity("cookpot", 3); local c = fixture.storage(pot, true)
    pot.components.stewer = {IsCooking = function() return pot.cooking end, IsDone = function() return pot.done end}
    fixture.item("froglegs", inst); fixture.item("carrot", inst); fixture.item("ice", inst, 2)
    ACTIONS.COOK.fn = function(a) local ok = base_cook(a); c.canbeopened = false; return ok end
    local job = Call(inst, p, "cook", {recipe = "frogglebunwich", station = Handle(state, pot)})
    for i = 1, 6 do fixture.perform(inst) end
    assert(pot.cooking and not c.canbeopened and API.GetAction(inst) == nil and state.active ~= nil)
    assert(not RealInventory.CanWithdrawFrom(inst, pot) and RealInventory.CanWithdrawFrom(inst, pot, true))
    pot.cooking, pot.done, pot.product = false, true, "frogglebunwich"; pot.components.stewer.product = pot.product
    local action = API.GetAction(inst)
    assert(action.action == ACTIONS.MY_FRIEND_BODY and action.arrivedist == 2.6 and action._body_operation == "harvest")
    fixture.perform(inst)
    local final = state.jobs[job.action_id]
    assert(final.status == "completed" and final.result.count == 1 and final.result.items[1].handle)
    local food = Observation.Resolve(state, final.result.items[1].handle)
    fixture.storage(p):Open(p)
    local transfer = Call(inst, p, "transfer", {item = Handle(state, food), destination = Handle(state, p), count = 1})
    fixture.perform(inst); assert(state.jobs[transfer.action_id].status == "completed" and food.owner == p)
    pot.done = true; c.restricted = true
    assert(Call(inst, p, "harvest", {target = Handle(state, pot)}).reason == "product_not_ready")
end)
Test("standalone harvest recovers finished pots independently of the old cooking job", function()
    local inst, p, state = Setup(); local pot = fixture.entity("cookpot", 2); local c = fixture.storage(pot, true)
    c.canbeopened, pot.done, pot.product = false, true, "meatballs"
    package.loaded.my_friend_cookpot.OwnerID = function(entity) return tostring(entity.GUID) end
    pot._my_friend_recipe_job = {owner = tostring(inst.GUID)}
    pot.components.stewer = {product = "meatballs", IsDone = function() return pot.done end, IsCooking = function() return false end}
    local job = Call(inst, p, "harvest", {target = Handle(state, pot)})
    fixture.perform(inst)
    assert(state.jobs[job.action_id].result.product == "meatballs" and state.jobs[job.action_id].result.items[1].prefab == "meatballs")
    assert(pot._my_friend_recipe_job == nil)
end)
Test("cooking knowledge returns the existing planner's validated mix and real container item handles", function()
    local inst, p, state = Setup(); local fridge = fixture.entity("icebox", 4); fixture.storage(fridge, true)
    for i=1,41 do fixture.storage(fixture.entity("treasurechest",2),true) end
    local meat, veg = fixture.item("monstermeat", fridge), fixture.item("carrot", fridge, 3)
    package.loaded.cooking.recipes.cookpot.meatballs = {hunger = 62.5}
    local planner = package.loaded.my_friend_recipe_planner
    local oldpool, oldfind = planner.Pool, planner.Find
    planner.Pool = function(_, containers)
        assert(#containers==42 and containers[42] == fridge)
        return {{prefab = "monstermeat", count = 1, sources = {{item = meat, count = 1}}},
            {prefab = "carrot", count = 3, sources = {{item = veg, count = 3}}}}
    end
    planner.Find = function(_, cooker, _, wanted)
        assert(cooker == "cookpot" and wanted == "meatballs")
        return {prefabs = {"monstermeat", "carrot", "carrot", "carrot"}}
    end
    local result = Call(inst, p, "query_recipe", {kind = "cook", query = "meatballs"})
    assert(result.result.valid_mix and result.result.ingredients[2].required == 3 and #result.result.sources == 2)
    assert(Observation.Resolve(state, result.result.sources[1].item) == meat and not result.result.sources[1].carried)
    planner.Find = function() return nil, true end
    assert(Call(inst, p, "query_recipe", {kind = "cook", query = "meatballs"}).result.pending)
    planner.Pool, planner.Find = oldpool, oldfind
end)
Test("backpacks with zero inventory capacity use native auto-equip and manual drops release recovery ownership", function()
    local inst, p, state = Setup(); local bag = fixture.item("backpack", nil); bag.tags.backpack = true
    fixture.armor(bag, "body"); bag.components.equippable.IsRestricted = function() return false end
    bag._my_friend_owned_backpack = true; inst._my_friend_owned_backpack = bag
    inst.components.inventory.full = true
    local pickup = ACTIONS.PICKUP.fn
    ACTIONS.PICKUP.fn = function(a)
        if a.target == bag then bag.owner, bag.equipped = inst, "body"; return true end
        return pickup(a)
    end
    local result = Call(inst, p, "pickup", {target = Handle(state, bag)})
    fixture.perform(inst); assert(state.jobs[result.action_id].status == "completed" and bag.equipped == "body")
    assert(Observation.Describe(inst, state, bag).equipped)
    local result = Call(inst, p, "drop", {item = Handle(state, bag)})
    fixture.perform(inst); assert(state.jobs[result.action_id].status == "completed" and bag.owner == nil)
    assert(not bag._my_friend_owned_backpack and inst._my_friend_owned_backpack == nil)
    ACTIONS.PICKUP.fn = pickup
end)
Test("dropping a spare backpack does not clear ownership of the backpack still worn", function()
    local inst, p, state = Setup()
    local worn, spare = fixture.item("backpack", inst), fixture.item("piggyback", inst)
    for _, bag in ipairs({worn, spare}) do bag.tags.backpack = true; fixture.armor(bag, "body") end
    worn.equipped, worn._my_friend_owned_backpack, inst._my_friend_owned_backpack = "body", true, worn
    local job = Call(inst, p, "drop", {item = Handle(state, spare)}); fixture.perform(inst)
    assert(state.jobs[job.action_id].status == "completed" and spare.owner == nil)
    assert(inst._my_friend_owned_backpack == worn and worn._my_friend_owned_backpack)
end)
Test("extra equipment slots and character use capabilities reflect actual components", function()
    local inst, p, state = Setup(); EQUIPSLOTS.PACK = "pack"
    local bag = fixture.item("backpack", inst); fixture.armor(bag, "pack"); bag.equipped = "pack"
    local result = Call(inst, p, "unequip", {slot = "pack"}); fixture.perform(inst)
    assert(state.jobs[result.action_id].status == "completed" and bag.equipped == nil)
    inst.components.reader = {}
    assert(Call(inst, p, "get_capabilities").result.reader)
    inst.prefab, inst.tags.pocketwatchcaster = "wanda", true
    local watch = fixture.item("pocketwatch_heal", inst)
    watch.components.pocketwatch = {inactive = true, CanCast = function(self) return self.inactive end}
    ACTIONS.CAST_POCKETWATCH = {id = "CAST_POCKETWATCH", fn = function(a) a.invobject.components.pocketwatch.inactive = false; return true end}
    result = Call(inst, p, "use_item", {item = Handle(state, watch), action = "CAST_POCKETWATCH"}); fixture.perform(inst)
    assert(state.jobs[result.action_id].status == "completed" and not watch.components.pocketwatch.inactive)
    assert(Call(inst, p, "use_item", {item = Handle(state, watch), action = "CAST_POCKETWATCH"}).reason == "watch_unavailable")
    watch.components.pocketwatch.inactive = true
    result = Call(inst, p, "use_item", {item = Handle(state, watch), action = "CAST_POCKETWATCH", position = {x = 12, z = 0}})
    local action = API.GetAction(inst)
    assert(action._my_friend_cast_in_place and action.arrivedist == 96 and action:GetActionPoint().x == 12)
    fixture.perform(inst); assert(state.jobs[result.action_id].status == "completed")
    inst.prefab = "wendy"
    assert(Call(inst, p, "use_item", {item = Handle(state, watch), action = "CAST_POCKETWATCH"}).reason == "character_cannot_cast")
    EQUIPSLOTS.PACK = nil
end)
Test("a multi-step plan holds inventory autonomy but yields to emergencies, newer commands, follow and expiry", function()
    local inst, p, state = Setup(); local item = fixture.item("twigs", nil)
    local job = Call(inst, p, "pickup", {target = Handle(state, item)}, "plan-1"); fixture.perform(inst)
    assert(state.active == nil and API.PlanActive(inst))
    assert(not API.AllowLocal(inst, "backpack_recovery", {hunger = 1}) and not API.AllowLocal(inst, "recipe_cooking", {hunger = 1}))
    assert(not API.AllowLocal(inst, "eat", {hunger = 1}) and API.AllowLocal(inst, "eat", {hunger = .1}))
    assert(API.AllowLocal(inst, "rescue", {hunger = 1}) and API.AllowLocal(inst, "hurt", {hunger = 1}))
    API.UpdatePlan(inst, {id = "wrong", revision = 0, active = false}); assert(API.PlanActive(inst))
    API.UpdatePlan(inst, {id = "plan-1", revision = 0, active = false}); assert(not API.PlanActive(inst))
    job = Call(inst, p, "move_to", {position = {x = 5, z = 0}}, "plan-2")
    API.ManualTakeover(inst); assert(not API.PlanActive(inst) and state.jobs[job.action_id].reason == "manual_command")
    API.UpdatePlan(inst, {id = "plan-2", revision = 0, active = true}); assert(not API.PlanActive(inst))
    Call(inst, p, "move_to", {position = {x = 5, z = 0}}, "plan-3"); fixture.perform(inst)
    Call(inst, p, "follow"); assert(not API.PlanActive(inst) and API.AllowLocal(inst, "sit", {}))
    Call(inst, p, "move_to", {position = {x = 6, z = 0}}, "plan-4"); fixture.perform(inst)
    fixture.advance(31); assert(not API.PlanActive(inst))
end)
Test("multi-slot non-stacking containers fill requested quantities and report remaining capacity",function()
 local inst,p,state=Setup();local rack=fixture.entity("meatrack",2);local c=fixture.storage(rack,true)
 c.acceptsstacks=false;c.slots={}
 function c:GetNumSlots() return 3 end
 function c:CanAcceptCount(_,n)local used=0;for _ in pairs(c.slots)do used=used+1 end;return math.min(n,3-used) end
 function c:GiveItem(item)
  assert(item.size==1,"native GiveItem must receive one entity for a non-stacking slot")
  for n=1,3 do if not c.slots[n]then c.slots[n]=item;item.owner=rack;return true end end
  return false
 end
 local meat=fixture.item("meat",inst,5)
 local r=Call(inst,p,"transfer",{item=Handle(state,meat),destination=Handle(state,rack),count=5})
 for _=1,8 do fixture.perform(inst) end
 local result=state.jobs[r.action_id]
 assert(result.status=="completed" and result.result.count==3 and result.result.partial and result.result.remaining==2)
 assert(meat.size==2 and not c:IsOpenedBy(inst))
end)
Test("nonwaiting cooking releases its job after start without harvesting or returning spent ingredients",function()
 local inst,p,state=Setup();local pot=fixture.entity("cookpot",3);fixture.storage(pot,true)
 pot.components.stewer={IsCooking=function()return pot.cooking end,IsDone=function()return pot.done end}
 fixture.item("froglegs",inst);fixture.item("carrot",inst);fixture.item("ice",inst,2)
 local r=Call(inst,p,"cook",{recipe="frogglebunwich",station=Handle(state,pot),wait=false})
 for _=1,8 do fixture.perform(inst)end
 local job=state.jobs[r.action_id]
 assert(job.status=="completed" and job.result.started and job.result.ready==false)
 assert(pot.cooking and pot._my_friend_body_cook==nil and state.active==nil)
 pot.components.stewer.product = "frogglebunwich"
 r=Call(inst,p,"harvest",{target=Handle(state,pot),recipe="frogglebunwich",wait=true})
 assert(API.GetAction(inst)==nil and state.active.stage=="cooking")
 pot.cooking,pot.done,pot.product=false,true,"frogglebunwich"
 fixture.perform(inst)
 assert(state.jobs[r.action_id].result.count==1)
end)
Test("recipe deficits follow native crafting inventory instead of counting every owned bag item",function()
 local inst,p,state=Setup()
 local own=fixture.item("rocks",inst,3);fixture.item("log",inst,4);fixture.item("goldnugget",inst,1)
 local sack=fixture.item("beargerfur_sack",inst);fixture.storage(sack,true)
 local nested=fixture.item("rocks",sack,4)
 function inst.components.inventory:Has(prefab,amount,crafting)
  assert(crafting==true)
  local n=0;for _,item in ipairs(self:ReferenceAllItems())do if item.owner==inst and item.prefab==prefab then n=n+item.size end end
  return n>=amount,n
 end
 function inst.components.inventory:GetCraftingIngredient(prefab)
  local out={};for _,item in ipairs(self:ReferenceAllItems())do if item.owner==inst and item.prefab==prefab then out[item]=item.size end end;return out
 end
 inst.components.builder.HasIngredients=function()return inst.components.inventory:Has("rocks",4,true)end
 inst.components.builder.CanLearn=function()return true end
 inst.components.builder.KnowsRecipe=function()return false end
 inst.components.builder.accessible_tech_trees={SCIENCE=0}
 AllRecipes.researchlab.level={SCIENCE=1};inst.technology=false
 local result=Call(inst,p,"query_recipe",{query="researchlab"}).result
 local rocks=result.ingredients[3]
 assert(rocks.carried==7 and rocks.available_for_crafting==3 and rocks.missing==1)
 assert(not result.materials_ready and not result.can_craft_now)
 assert(result.technology_status.required.SCIENCE==1 and result.technology_status.available.SCIENCE==0)
 assert(not result.technology_status.satisfied and result.sources[1].source=="carried_container")
 local r=Call(inst,p,"transfer",{item=Handle(state,nested),destination=Handle(state,inst),count=1})
 fixture.perform(inst)
 assert(state.jobs[r.action_id].status=="completed")
 result=Call(inst,p,"query_recipe",{query="researchlab"}).result
 assert(result.ingredients[3].missing==0 and result.materials_ready and not result.can_build_technology)
end)

Test("explicit cooking checks hypothetical supplies, preserves fresh jerky and native recipe competition",function()
    local inst,p,state=Setup()
    local saved={}
    for _,name in ipairs({"my_friend_food_rules","my_friend_recipe_planner","cooking"}) do saved[name]=package.loaded[name] end
    local food=package.loaded.my_friend_food_ai
    local oldheal=food.CanHealWithFood;food.CanHealWithFood=function()return true end
    local storage=package.loaded.my_friend_food_storage
    local oldreserved=storage.IsReserved;storage.IsReserved=function()return false end
    local rules=assert(loadfile("scripts/my_friend_food_rules.lua"))()
    package.loaded.my_friend_food_rules=rules
    local ingredients={meat_dried={tags={meat=1}},rock_avocado_fruit_ripe={tags={veggie=1}}}
    local recipe={name="meatballs",foodtype="MEAT",hunger=62.5,priority=0,
        test=function(_,names,tags)return (tags.meat or 0)>0 and (tags.veggie or 0)==3 end}
    package.loaded.cooking={ingredients=ingredients,recipes={cookpot={meatballs=recipe}},
        IsCookingIngredient=function(name)return ingredients[name]~=nil end}
    local planner=assert(loadfile("scripts/my_friend_recipe_planner.lua"))()
    package.loaded.my_friend_recipe_planner=planner
    local mix={"meat_dried","rock_avocado_fruit_ripe","rock_avocado_fruit_ripe","rock_avocado_fruit_ripe"}
    local fridge=fixture.entity("icebox",3);fixture.storage(fridge,true)
    local meat=fixture.item("meat_dried",fridge,2)
    assert(not rules.CanUseIngredient(meat) and rules.CanUseIngredient(meat,true))
    local unrelated={doer=inst,target=fridge,_body_job={id="fake",skill="cook",explicit_mix=true}}
    fridge.components.stewer={};fridge._my_friend_body_cook="fake"
    assert(not require("my_friend_body_cooking").IsExplicitAction(unrelated))
    assert(not rules.CookAction(unrelated,function()error("must not bypass the ordinary fresh jerky guard")end))
    fridge.components.stewer=nil;fridge._my_friend_body_cook=nil
    assert(not planner.Available(inst,meat) and planner.Available(inst,meat,true))
    local q=Call(inst,p,"query_recipe",{kind="cook",query="meatballs",count=2,ingredients=mix}).result
    assert(q.valid_mix and not q.materials_ready and q.unavailable.rock_avocado_fruit_ripe==6)
    assert(q.sources[1].count==2 and q.sources[1].skill=="pickup" and q.mix[1]=="meat_dried")
    package.loaded.cooking.recipes.cookpot.competitor={priority=1,test=function()return true end}
    assert(not require("my_friend_body_cooking").Validate(inst,"cookpot","meatballs",mix))
    package.loaded.cooking.recipes.cookpot.competitor=nil
    meat.owner=inst;fixture.item("rock_avocado_fruit_ripe",inst,6)
    q=Call(inst,p,"query_recipe",{kind="cook",query="meatballs",count=2,ingredients=mix}).result
    assert(q.materials_ready and #q.sources==0)
    local pot=fixture.entity("cookpot",2);fixture.storage(pot,true)
    pot.components.stewer={IsCooking=function()return pot.cooking end,IsDone=function()return pot.done end}
    local nativecook=ACTIONS.COOK.fn
    ACTIONS.COOK.fn=function(action)return rules.CookAction(action,nativecook)end
    local job=Call(inst,p,"cook",{recipe="meatballs",station=Handle(state,pot),ingredients=mix})
    for i=1,6 do fixture.perform(inst) end
    assert(pot.cooking and state.jobs[job.action_id].explicit_mix)
    pot.cooking,pot.done,pot.product=false,true,"meatballs";pot.components.stewer.product="meatballs"
    fixture.perform(inst)
    assert(state.jobs[job.action_id].status=="completed" and state.jobs[job.action_id].result.count==1)
    assert(meat.size==1 and not rules.CanUseIngredient(meat))
    fixture.storage(p):Open(p)
    local meal=state.jobs[job.action_id].result.items[1]
    local delivered=Call(inst,p,"transfer",{item=meal.handle,destination=Handle(state,p),count=1})
    fixture.perform(inst);assert(state.jobs[delivered.action_id].result.count==1)
    job=Call(inst,p,"cook",{recipe="meatballs",station=Handle(state,pot),ingredients=mix})
    for i=1,6 do fixture.perform(inst) end
    assert(pot.cooking)
    pot.cooking,pot.done=false,true;fixture.perform(inst)
    meal=state.jobs[job.action_id].result.items[1]
    delivered=Call(inst,p,"transfer",{item=meal.handle,destination=Handle(state,p),count=1})
    fixture.perform(inst);assert(state.jobs[delivered.action_id].result.count==1)
    local total=0;for _,item in ipairs(p.components.inventory:ReferenceAllItems())do
        if item.prefab=="meatballs"then total=total+item.size end
    end
    assert(total==2)
    ACTIONS.COOK.fn=nativecook;food.CanHealWithFood=oldheal;storage.IsReserved=oldreserved
    for name,module in pairs(saved)do package.loaded[name]=module end
end)
Test("backpack handover describes the old dropped bag and refuses inventory delivery before checking space",function()
    local inst,p,state=Setup();fixture.storage(p):Open(p)
    local old=fixture.item("backpack",inst);old.tags.backpack=true;fixture.armor(old,"body");old.equipped="body"
    old.components.inventoryitem.cangoincontainer=false
    local new=fixture.item("piggyback",nil);new.tags.backpack=true;fixture.armor(new,"body")
    new.components.inventoryitem.cangoincontainer=false
    local before=Observation.Describe(inst,state,old)
    assert(before.backpack and not before.can_store and before.delivery=="drop_near_recipient")
    local rejected=Call(inst,p,"transfer",{item=Handle(state,old),destination=Handle(state,p)})
    assert(rejected.reason=="item_cannot_be_stored_drop_near_recipient" and old.owner==inst)
    local drop=Call(inst,p,"drop",{item=Handle(state,old)})
    fixture.perform(inst)
    local result=state.jobs[drop.action_id].result
    assert(result.item_state.handle==Handle(state,old) and result.item_state.prefab=="backpack" and old.owner==nil)
    assert(new.owner==nil)
end)
Test("work receipts return gathered products for composition and carried work targets are rejected",function()
    local inst,p,state=Setup();local bush=fixture.entity("rock_avocado_bush",2)
    bush.components.pickable={product="rock_avocado_fruit",numtoharvest=3,CanBePicked=function()return true end}
    local previous=ACTIONS.PICK.fn
    ACTIONS.PICK.fn=function()fixture.item("rock_avocado_fruit",inst,3);return true end
    local desc=Observation.Describe(inst,state,bush)
    assert(desc.pick_product=="rock_avocado_fruit" and desc.pick_count==3)
    local job=Call(inst,p,"work",{target=Handle(state,bush),action="PICK"});fixture.perform(inst)
    local result=state.jobs[job.action_id].result
    assert(result.gained[1].count==3 and result.items[1].prefab=="rock_avocado_fruit")
    local failed=Call(inst,p,"work",{target=result.items[1].handle,action="MINE"})
    assert(failed.reason=="work_requires_ground_target")
    ACTIONS.PICK.fn=previous
end)

print(passed .. " resource workflow tests passed")
