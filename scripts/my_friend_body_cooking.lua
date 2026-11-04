-- Explicit four-slot recipes are checked against the live cooking rules, without RNG.
local M = {}
function M.Validate(inst, cooker, wanted, ingredients)
    if type(ingredients) ~= "table" or #ingredients ~= 4 then return false, "four_ingredients_required" end
    for key, prefab in pairs(ingredients) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 4
            or type(prefab) ~= "string" or #prefab > 80 then return false, "invalid_ingredients" end
    end
    local cooking, rules = require("cooking"), require("my_friend_food_rules")
    for _, prefab in ipairs(ingredients) do
        if not cooking.IsCookingIngredient(prefab) then return false, "not_cooking_ingredient:" .. prefab end
        if rules.IsProtected(prefab) then return false, "protected_ingredient:" .. prefab end
    end
    if not rules.AllowsMix(ingredients, 0) then return false, "fresh_big_meat_limit" end
    if require("my_friend_recipe_planner").EvaluateSpecific(inst, cooker, ingredients, wanted, 0) == nil then
        return false, "mix_does_not_guarantee_requested_recipe"
    end
    return true
end

function M.Pool(inst, containers, ground)
    local groups, pool, seen = {}, {}, {}
    local function Add(item)
        if seen[item] or not require("my_friend_recipe_planner").Available(inst,item,true)
            or not require("cooking").IsCookingIngredient(item.prefab) then return end
        seen[item] = true
        local group = groups[item.prefab]
        if group == nil then
            group = {prefab=item.prefab,count=0,sources={}}
            groups[item.prefab] = group; pool[#pool+1] = group
        end
        local count = require("my_friend_body_observation").Size(item)
        group.count = group.count + count
        group.sources[#group.sources+1] = {item=item,count=count}
    end
    for _,item in ipairs(require("my_friend_body_observation").Items(inst)) do Add(item) end
    for _,container in ipairs(containers or {}) do
        for _,item in ipairs(container.components.container:GetAllItems()) do Add(item) end
    end
    for _,item in ipairs(ground or {}) do Add(item) end
    return pool
end

function M.IsExplicitAction(action)
    local job = action._body_job
    if job == nil or job.skill ~= "cook" or not job.explicit_mix then return false end
    local state = require("my_friend_body_api").Valid(action.doer)
    local root = job
    while root.parent ~= nil do
        if root.cancel_requested or root.parent.child ~= root then return false end
        root = root.parent
    end
    return state ~= nil and state.active == root and not root.cancel_requested
        and action.target ~= nil and action.target._my_friend_body_cook == job.id
end
return M
