-- On-demand game-authoritative knowledge; no recipe tables or scans per frame.
local Observation = require("my_friend_body_observation")
local Storage = require("my_friend_body_storage")
local M = {}
local function Name(prefab)
    local name = STRINGS ~= nil and STRINGS.NAMES ~= nil and STRINGS.NAMES[string.upper(prefab)] or nil
    return type(name) == "string" and name or prefab
end
local function Carried(inst, prefab)
    local total = 0
    for _, item in ipairs(Observation.Items(inst)) do
        if item.prefab == prefab then total = total + Observation.Size(item) end
    end
    return total
end
local function Find(recipes, query)
    if recipes[query] ~= nil then return query end
    local found = {}
    for key, recipe in pairs(recipes) do
        local product = recipe.product or key
        if key:lower():find(query:lower(), 1, true) or Name(product):lower():find(query:lower(), 1, true) then
            found[#found + 1] = {recipe = key, product = product, name = Name(product)}
        end
    end
    table.sort(found, function(a, b) return a.recipe < b.recipe end)
    if #found == 1 then return found[1].recipe end
    while #found > 12 do table.remove(found) end
    return nil, found
end
local function Costs(inst, recipe, count)
    local out, builder = {}, inst.components.builder
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        local raw = ingredient.amount or 0
        local amount = math.max(1, RoundBiasedUp ~= nil and RoundBiasedUp(raw * (builder.ingredientmod or 1))
            or math.floor(raw * (builder.ingredientmod or 1) + .5))
        local own = Carried(inst, ingredient.type)
        local available = own
        if inst.components.inventory.Has ~= nil then
            local _, found = inst.components.inventory:Has(ingredient.type,amount*count,true)
            if type(found)=="number" then available=found end
        end
        out[#out + 1] = {prefab = ingredient.type, name = Name(ingredient.type), per_operation = amount,
            required = amount * count, carried = own, available_for_crafting=available, missing = builder.freebuildmode and 0 or math.max(0, amount * count - available)}
    end
    return out
end
function M.Craft(inst, recipe, count)
    local builder = inst.components.builder
    local buffered = recipe.placer ~= nil and builder.IsBuildBuffered ~= nil and builder:IsBuildBuffered(recipe.name)
    local needed = buffered and math.max(0, count - 1) or count
    local costs = {}
    for _, ingredient in ipairs(recipe.character_ingredients or {}) do
        local allowed, available = builder:HasCharacterIngredient(ingredient)
        costs[#costs + 1] = {type = ingredient.type, amount = ingredient.amount, available = available, allowed = allowed == true}
    end
    local tech_costs = {}
    for _, ingredient in ipairs(recipe.tech_ingredients or {}) do
        local allowed, available = builder:HasTechIngredient(ingredient)
        tech_costs[#tech_costs + 1] = {type = ingredient.type, amount = ingredient.amount, available = available, allowed = allowed == true}
    end
    local tech = {}
    for key, level in pairs(recipe.level or {}) do if type(level) == "number" and level>0 then tech[key] = level end end
    local ingredients=Costs(inst,recipe,needed)
    local materials_ready=true
    for _,ingredient in ipairs(ingredients)do if ingredient.missing>0 then materials_ready=false end end
    local buffered = recipe.placer ~= nil and builder.IsBuildBuffered ~= nil and builder:IsBuildBuffered(recipe.name)
    local out={kind = "craft", recipe = recipe.name, product = recipe.product or recipe.name, name = Name(recipe.product or recipe.name),
        operations = count, new_operations = needed, produced = count * (recipe.numtogive or 1), ingredients = ingredients, materials_ready=materials_ready,
        character_costs = costs, technology_costs = tech_costs, technology = tech, builder_tag = recipe.builder_tag,
        can_build_technology = require("my_friend_crafting_tech").CanBuild(inst, recipe),
        special_build = require("my_friend_body_characters").BuildAllowed(inst, recipe.name),
        special_build_ability = require("my_friend_body_characters").BuildAllowed(inst, recipe.name)
            and (inst.prefab == "wathgrithr" and "lightning_spear" or "build_special") or nil,
        has_ingredients = builder:HasIngredients(recipe), requires_placement = recipe.placer ~= nil,
        can_prepare = recipe.placer ~= nil and not recipe.manufactured and builder.BufferBuild ~= nil,
        prepared = buffered == true,
        can_learn = builder.CanLearn ~= nil and builder:CanLearn(recipe.name) == true, freebuild = builder.freebuildmode == true}
    out.expected_output=out.produced
    out.technology_status={required=tech,available={},known=builder.KnowsRecipe~=nil and builder:KnowsRecipe(recipe) or false,
        can_learn=out.can_learn,satisfied=out.can_build_technology,station_tag=recipe.station_tag}
    for key in pairs(tech)do out.technology_status.available[key]=(builder.accessible_tech_trees or {})[key] or 0 end
    out.builder_tag_met=recipe.builder_tag==nil or inst:HasTag(recipe.builder_tag)
    out.character_resources_ready=true
    for _,entries in ipairs({costs,tech_costs})do for _,cost in ipairs(entries)do
        cost.per_operation=cost.amount
        cost.required=(cost.amount or 0)*needed
        if type(cost.available)=="number" then cost.missing=math.max(0,cost.required-cost.available) end
        if not out.freebuild and (not cost.allowed or cost.missing~=nil and cost.missing>0)then out.character_resources_ready=false end
    end end
    out.blockers={}
    if not materials_ready then out.blockers[#out.blockers+1]="missing_materials" end
    if not out.can_build_technology then out.blockers[#out.blockers+1]="missing_technology" end
    if not out.has_ingredients and materials_ready then out.blockers[#out.blockers+1]="native_recipe_condition_unmet" end
    if not out.character_resources_ready then out.blockers[#out.blockers+1]="missing_character_resources" end
    if not out.builder_tag_met then out.blockers[#out.blockers+1]="wrong_character" end
    out.can_craft_now=materials_ready and out.can_build_technology and out.has_ingredients and out.character_resources_ready and out.builder_tag_met
    out.stage="recipe_query"
    return out
end
local function Cook(inst, state, recipe, cooker, count, wanted, mix, nearby)
    local planner = require("my_friend_recipe_planner")
    local containers, ground, stations, stations_limited = {}, {}, {}, false
    local openings = {}
    local platform = inst:GetCurrentPlatform()
    for _, entity in ipairs(Observation.Nearby(inst, 20, nearby)) do
        if entity:GetCurrentPlatform() == platform then
            local c = entity.components
            if Storage.Accessible(inst, entity) then
                local _, owner = Storage.Resolve(entity)
                if openings[owner] == nil then containers[#containers+1], openings[owner] = owner, entity end
            end
            if c.inventoryitem ~= nil and c.inventoryitem.owner == nil and c.inventoryitem.canbepickedup == true then
                ground[#ground+1] = entity
            end
            if c.stewer ~= nil and require("my_friend_cookpot").PREFABS[entity.prefab] then
                if #stations < 12 then stations[#stations+1] = Observation.Describe(inst,state,entity)
                else stations_limited = true end
            end
        end
    end
    local explicit = mix ~= nil
    local out = {kind="cook",recipe=wanted,product=wanted,name=Name(wanted),cooker=cooker,pots=count,
        health=recipe.health,hunger=recipe.hunger,sanity=recipe.sanity,ingredients={},sources={},
        stations=stations,stations_limited=stations_limited,radius=20,supplies_limited=false,stage="recipe_query",expected_output=count}
    local plan, pending
    if explicit then
        local ok,reason = require("my_friend_body_cooking").Validate(inst,cooker,wanted,mix)
        if not ok then out.valid_mix=false;out.reason=reason;return out end
        plan = {prefabs=mix}
    end
    local pool = explicit and require("my_friend_body_cooking").Pool(inst,containers,ground)
        or planner.Pool(inst,containers,ground)
    if not explicit then plan,pending = planner.Find(inst,cooker,pool,wanted) end
    out.pending,out.valid_mix = pending == true,plan ~= nil
    if plan == nil then
        out.reason=pending and "recipe_search_pending" or "no_valid_mix_in_observed_supplies"
        out.next_step="observe_resources_or_validate_proposed_four_ingredients"
        return out
    end
    out.mix,out.materials_ready,out.unavailable = plan.prefabs,true,{}
    local needed,groups,order = {},{},{}
    for _,prefab in ipairs(plan.prefabs) do needed[prefab]=(needed[prefab] or 0)+count end
    for _,group in ipairs(pool) do
        groups[group.prefab]=group
        if needed[group.prefab] ~= nil then order[#order+1]=group.prefab end
    end
    for _,prefab in ipairs(plan.prefabs) do
        if groups[prefab] == nil then
            groups[prefab]={count=0,sources={}};order[#order+1]=prefab
        end
    end
    for _,prefab in ipairs(order) do
        local group,amount = groups[prefab],needed[prefab]
        local carried = 0
        for _,source in ipairs(group.sources or {}) do
            if source.item.components.inventoryitem:GetGrandOwner() == inst then carried=carried+source.count end
        end
        local missing=math.max(0,amount-carried)
        out.ingredients[#out.ingredients+1]={prefab=prefab,name=Name(prefab),per_pot=amount/count,
            required=amount,carried=carried,available=group.count,missing=missing}
        if missing>0 then out.materials_ready=false end
        local remaining=missing
        for _,source in ipairs(group.sources or {}) do
            if remaining<=0 then break end
            local item=source.item
            if item.components.inventoryitem:GetGrandOwner()~=inst then
                local take=math.min(source.count,remaining)
                local owner=item.components.inventoryitem.owner
                local opening = owner ~= nil and (openings[owner] or owner) or nil
                out.sources[#out.sources+1]={item=Observation.Handle(state,item),prefab=prefab,count=take,
                    carried=false,skill="pickup",source=owner~=nil and "container" or "ground",
                    container=Observation.Handle(state,opening)}
                remaining=remaining-take
            end
        end
        out.unavailable[prefab]=remaining
    end
    out.next_step=out.materials_ready and "cook_one_pot_per_call_using_mix"
        or #out.sources>0 and "collect_sources_then_resolve_unavailable" or "gather_or_process_missing_ingredients"
    return out
end

function M.Query(inst, state, args, nearby)
    local kind, count = args.kind or "craft", args.count or 1
    if type(args.query) ~= "string" or #args.query < 1 or #args.query > 120
        or type(count) ~= "number" or count < 1 or count > 40 or count % 1 ~= 0
        or not (kind == "craft" or kind == "cook") then return nil, "invalid_arguments" end
    local cooker = "cookpot"
    if kind == "cook" and args.station ~= nil then
        local station = Observation.Resolve(state, args.station)
        if station == nil or not require("my_friend_cookpot").PREFABS[station.prefab] then return nil, "station_unavailable" end
        if not require("my_friend_cookpot").IsAllowed(inst, station) then return nil, "character_cannot_cook" end
        cooker = station.prefab
    end
    local recipes = kind == "craft" and (AllRecipes or {}) or require("cooking").recipes[cooker] or {}
    local name, matches = Find(recipes, args.query)
    if name == nil then return {matches = matches, reason = #matches > 0 and "ambiguous_recipe" or "unknown_recipe"} end
    local recipe
    if kind == "craft" then recipe = GetValidRecipe(name) else recipe = recipes[name] end
    if recipe == nil then return nil, "unknown_recipe" end
    if kind == "cook" then return Cook(inst, state, recipe, cooker, count, name, args.ingredients, nearby) end
    local out = M.Craft(inst, recipe, count)
    -- Match actual deficits before publishing any handles or applying an
    -- observation page limit. Unrelated boxes and loot cannot hide supplies.
    out.sources, out.stations = {}, {}
    out.technology_status.active_station = Observation.Handle(state, inst.components.builder.current_prototyper)
    out.supplies_limited, out.stations_limited = false, false
    local needed = {}
    for _, ingredient in ipairs(out.ingredients) do needed[ingredient.prefab] = ingredient.missing end
    -- Owned nested storage may be visible to the companion but excluded by the
    -- native builder. Return an explicit transfer into normal inventory.
    local eligible={}
    if inst.components.inventory.GetCraftingIngredient~=nil then
        for _,ingredient in ipairs(out.ingredients)do
            for item in pairs(inst.components.inventory:GetCraftingIngredient(ingredient.prefab,ingredient.required) or {})do eligible[item]=true end
        end
    end
    for _,item in ipairs(Observation.Items(inst))do
        local remaining=needed[item.prefab] or 0
        local owner=item.components.inventoryitem~=nil and item.components.inventoryitem.owner or nil
        if remaining>0 and owner~=nil and owner~=inst and not eligible[item] and owner.components.container~=nil
            and not item:HasTag("nocrafting") and not item.components.inventoryitem.islockedinslot then
            if require("my_friend_inventory").CanWithdrawFrom(inst,owner) then
                local take=math.min(remaining,Observation.Size(item))
                out.sources[#out.sources+1]={item=Observation.Handle(state,item),prefab=item.prefab,count=take,
                    source="carried_container",skill="transfer",destination=Observation.Handle(state,inst)}
                needed[item.prefab]=remaining-take
            end
        end
    end
    local tech = require("my_friend_crafting_tech")
    local platform = inst:GetCurrentPlatform()
    local function AddSource(item, container, owner)
        local remaining, inv = needed[item.prefab] or 0, item.components.inventoryitem
        if remaining <= 0 or inv == nil or inv.owner ~= owner or inv.islockedinslot or item:HasTag("nocrafting")
            or container == nil and inv.canbepickedup ~= true then return end
        local take = math.min(remaining, Observation.Size(item))
        if take <= 0 then return end
        if #out.sources >= 64 then out.supplies_limited = true; return end
        out.sources[#out.sources+1] = {item=Observation.Handle(state,item), prefab=item.prefab, count=take,
            source=container==nil and "ground" or "container", skill="pickup",
            container=container~=nil and Observation.Handle(state,container) or nil}
        needed[item.prefab] = remaining-take
    end
    local candidates = Observation.Nearby(inst, 32, nearby)
    local seen_storage = {}
    for _, entity in ipairs(candidates) do
        if entity:GetCurrentPlatform() == platform then AddSource(entity) end
    end
    for _, entity in ipairs(candidates) do
        if entity:GetCurrentPlatform() == platform then
            local c = entity.components
            if Storage.Accessible(inst, entity) then
                local container, owner = Storage.Resolve(entity)
                if not seen_storage[owner] then
                    seen_storage[owner] = true
                    for _, item in ipairs(container:GetAllItems()) do AddSource(item, entity, owner) end
                end
            end
            if c.prototyper ~= nil and tech.StationCanTeach ~= nil and tech.StationCanTeach(inst, entity, recipe) then
                if #out.stations < 12 then
                    local station = Observation.Describe(inst,state,entity)
                    station.usable_here = c.prototyper:CanUsePrototyper(inst)
                    station.distance = math.sqrt(inst:GetDistanceSqToInst(entity))
                    out.stations[#out.stations+1] = station
                else out.stations_limited = true end
            end
        end
    end
    out.unavailable = needed
    out.radius, out.observed_at = 32, GetTime()
    if recipe.placer ~= nil then
        out.placement = require("my_friend_body_sites").Query(inst, state, {recipe=name})
    end
    out.next_step=out.prepared and count == 1 and "place_prepared_build"
        or not out.builder_tag_met and "character_not_allowed" or not out.character_resources_ready and "resolve_character_resources"
        or not out.has_ingredients and out.materials_ready and "resolve_native_recipe_conditions" or not out.materials_ready and (#out.sources>0 and "collect_sources" or "resolve_missing_conditions")
        or not out.can_build_technology and "approach_station"
        or out.can_prepare and "prepare_or_place_at_chosen_site" or out.requires_placement and "choose_site_then_craft" or "craft"
    return out
end
function M.Capabilities(inst)
    local reader = inst.components.reader ~= nil
    local watch = inst.prefab == "wanda" and inst:HasTag("pocketwatchcaster")
    local uses = {"HEAL", "SEW", "REPAIR", "ADDFUEL", "FERTILIZE"}
    if reader then uses[#uses + 1] = "READ" end
    if watch then uses[#uses + 1] = "CAST_POCKETWATCH" end
    local slots = {}
    for _, slot in ipairs(require("my_friend_equip_slots").All()) do slots[#slots + 1] = tostring(slot) end
    return {character = inst.prefab, item_actions = uses, native_actions = "query_actions", native_execution = "perform_action", reader = reader, pocketwatchcaster = watch,
        recipes = "query_recipe", equipment_slots = slots, role = require("my_friend_body_characters").Catalogue(inst),
        native_commands = require("my_friend_body_command_catalog").Get(inst),
        notes = "role.actions are callable using character_skill; role.automatic lists existing autonomous/passive support, not forced commands. Other characters use only their advertised native item actions and recipes."}
end
return M
