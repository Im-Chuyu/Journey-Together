local TechTree = require("techtree")

local M = {}

function M.CanBuild(inst, recipe)
    local builder = inst.components.builder
    return builder ~= nil and (builder:KnowsRecipe(recipe)
        or builder:CanLearn(recipe.name)
            and CanPrototypeRecipe(recipe.level, builder.accessible_tech_trees))
end

function M.StationCanTeach(inst, station, recipe)
    local builder = inst.components.builder
    local proto = station:IsValid() and station.components.prototyper or nil
    if builder == nil or not builder:CanLearn(recipe.name) or proto == nil
        or station:HasTag("burnt")
        or proto.restrictedtag ~= nil and not inst:HasTag(proto.restrictedtag) then return false end
    local trees = proto:GetTechTrees()
    -- Match Builder:EvaluateTechTrees, including Wickerbottom's science bonus.
    for _, tech in ipairs(TechTree.BONUS_TECH) do
        local key = string.lower(tech)
        trees[tech] = (trees[tech] or 0) + (builder[key .. "_bonus"] or 0)
            + (builder[key .. "_tempbonus"] or 0)
    end
    return CanPrototypeRecipe(recipe.level, trees)
end

function M.FindStation(inst, recipe, range)
    local x, y, z, radius = require("my_friend_policy").SearchOrigin(inst, range or 20)
    local best, distance
    for _, station in ipairs(TheSim:FindEntities(x, y, z, radius,
        {"prototyper"}, {"INLIMBO", "burnt"})) do
        -- CanUsePrototyper checks distance. Check it after walking to the
        -- station, not here while searching for one to approach.
        if M.StationCanTeach(inst, station, recipe)
            and station:GetCurrentPlatform() == inst:GetCurrentPlatform() then
            local d = inst:GetDistanceSqToInst(station)
            if best == nil or d < distance then best, distance = station, d end
        end
    end
    return best, distance
end

function M.Activate(inst, station, recipe)
    local builder = inst.components.builder
    if not M.StationCanTeach(inst, station, recipe)
        or not station.components.prototyper:CanUsePrototyper(inst) then return false end
    if builder:UsePrototyper(station, true) == false then return false end
    builder:EvaluateTechTrees()
    return M.CanBuild(inst, recipe)
end

function M.OnBuilt(inst, recipe)
    local builder = inst.components.builder
    local known = builder:KnowsRecipe(recipe)
    local known_permanent = builder:KnowsRecipe(recipe, true)
    local prototype_permanent = CanPrototypeRecipe(recipe.level, builder.accessible_tech_trees_no_temp)
    local learn = builder:CanLearn(recipe.name)
    -- Capture before the action: tech bonuses may change while crafting.
    return function()
        if not known_permanent and not prototype_permanent then builder:ConsumeTempTechBonuses() end
        if not known or not known_permanent and prototype_permanent and learn then
            builder:ActivateCurrentResearchMachine(recipe)
            builder:UnlockRecipe(recipe.name)
        elseif not recipe.nounlock then
            builder:AddRecipe(recipe.name)
        else
            builder:ActivateCurrentResearchMachine(recipe)
        end
    end
end

return M
