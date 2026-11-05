-- Explicit, bounded placement advice. Never reserves terrain or spawns items.
local Observation = require("my_friend_body_observation")
local M = {}
local function Finite(n) return type(n) == "number" and n == n and math.abs(n) < 1000000 end
function M.IsDeployAction(action)
    return action == "DEPLOY" or action == "DEPLOY_TILEARRIVE" or action == "DEPLOY_FLOATING"
end
function M.Valid(inst, recipe, point)
    return TheWorld.Map ~= nil and TheWorld.Map.CanDeployRecipeAtPoint ~= nil
        and TheWorld.Map:CanDeployRecipeAtPoint(point, recipe, 0, inst) == true
end

function M.Snap(item, point)
    local map = TheWorld.Map
    if item ~= nil and item:HasTag("tile_deploy") and map.GetTileCenterPoint ~= nil then
        local x, y, z = map:GetTileCenterPoint(point:Get())
        if x ~= nil then return Vector3(x, y, z) end
    end
    return point
end

function M.Spacing(recipe, item)
    return recipe ~= nil and (recipe.min_spacing or 3.2)
        or item ~= nil and item.components.farmtiller ~= nil and GetFarmTillSpacing ~= nil and GetFarmTillSpacing()
        or item ~= nil and item.components.deployable ~= nil and item.components.deployable.DeploySpacingRadius ~= nil
            and item.components.deployable:DeploySpacingRadius() or 1
end

function M.Details(inst, state, point, spacing)
    local map = TheWorld.Map
    local surface = require("my_friend_platforms").Surface(point)
    local radius = math.min(12, math.max(4, spacing + 2, DEPLOY_EXTRA_SPACING or 0))
    local result = {position = {x=point.x,z=point.z}, surface=surface, minimum_spacing=spacing,
        nearby_obstacles={}, obstacles_radius=radius, obstacles_matched=0, obstacles_limited=false}
    if map.GetTileAtPoint ~= nil then
        local id = map:GetTileAtPoint(point.x,0,point.z)
        result.tile = {id=id}
        for name, value in pairs(WORLD_TILES or {}) do if id == value then result.tile.name=name;break end end
    end
    if map.IsPassableAtPoint ~= nil then result.passable = map:IsPassableAtPoint(point.x,0,point.z) == true end
    if map.CanPlantAtPoint ~= nil then result.plantable = map:CanPlantAtPoint(point.x,0,point.z) == true end
    if map.IsGroundTargetBlocked ~= nil then result.ground_target_blocked = map:IsGroundTargetBlocked(point) == true end
    local entities = TheSim:FindEntities(point.x, 0, point.z, radius, nil,
        {"NOBLOCK", "player", "FX", "INLIMBO", "DECOR", "walkableplatform", "walkableperipheral", "isdead"})
    local distances = {}
    for _, entity in ipairs(entities) do distances[entity] = Observation.Distance(point, entity:GetPosition()) end
    table.sort(entities, function(a, b)
        return distances[a] == distances[b] and a.GUID < b.GUID or distances[a] < distances[b]
    end)
    for _, entity in ipairs(entities) do
        if entity ~= inst and entity.components.placer == nil
            and (entity.entity == nil or entity.entity:IsVisible()
                and (entity.entity:GetParent() == nil or entity:HasTag("childdeployblocker"))) then
            result.obstacles_matched = result.obstacles_matched + 1
            if #result.nearby_obstacles < 4 then
                result.nearby_obstacles[#result.nearby_obstacles+1] = {handle=Observation.Handle(state,entity),
                    prefab=entity.prefab, name=entity:GetDisplayName(), distance=distances[entity],
                    position={x=entity:GetPosition().x,z=entity:GetPosition().z},
                    deploy_radius=entity.deploy_smart_radius or entity.deploy_extra_spacing,
                    physics_radius=entity.GetPhysicsRadius ~= nil and entity:GetPhysicsRadius(0) or nil}
            end
        end
    end
    result.obstacles_limited = result.obstacles_matched > #result.nearby_obstacles
    return result
end

function M.Query(inst, state, args)
    local origin = inst:GetPosition()
    local p, radius = args.position or {x = origin.x, z = origin.z}, args.radius or 12
    if type(p) ~= "table" or not Finite(p.x) or not Finite(p.z)
        or (p.x-origin.x)^2+(p.z-origin.z)^2 > 32^2
        or not Finite(radius) or radius < 1 or radius > 16 then return nil, "invalid_position" end
    local recipe, item
    if args.recipe ~= nil then
        if type(args.recipe) ~= "string" then return nil, "unknown_recipe" end
        recipe = GetValidRecipe(args.recipe)
        if recipe == nil or recipe.placer == nil then return nil, "recipe_has_no_placement" end
    elseif args.item ~= nil then
        item = Observation.Resolve(state, args.item)
        if item == nil or item.components.inventoryitem == nil
            or item.components.inventoryitem:GetGrandOwner() ~= inst then return nil, "item_not_deployable" end
    else return nil, "recipe_or_item_required" end
    local sites, checked, seen = {}, 0, {}
    local spacing = M.Spacing(recipe, item)
    local layout=args.layout
    if args.exact ~= nil and type(args.exact) ~= "boolean" or args.exact == true and (args.position == nil or layout ~= nil) then
        return nil, "invalid_exact_site"
    end
    if layout ~= nil and type(layout) ~= "table" then return nil, "invalid_layout" end
    local ring = layout ~= nil and layout.ring or nil
    if layout ~= nil then
        if layout.rotation ~= nil and not Finite(layout.rotation) then return nil, "invalid_layout" end
        if ring ~= nil then
            if not Finite(ring) or ring < 3 or ring > 40 or ring % 1 ~= 0 or layout.tile == true
                or layout.rows ~= nil or layout.columns ~= nil or layout.spacing ~= nil then return nil, "invalid_layout" end
        elseif not Finite(layout.rows) or not Finite(layout.columns) or layout.rows < 1 or layout.columns < 1
            or layout.rows % 1 ~= 0 or layout.columns % 1 ~= 0 or layout.rows * layout.columns > 40
            or layout.spacing ~= nil and (not Finite(layout.spacing) or layout.spacing <= 0) then return nil, "invalid_layout" end
    end
    if layout~=nil and layout.tile==true then
        local x,_,z=TheWorld.Map:GetTileCenterPoint(p.x,0,p.z);p={x=x,z=z}
    end
    local function Valid(point)
        if recipe~=nil then return M.Valid(inst,recipe,point) end
        if item.components.deployable~=nil and (args.action==nil or M.IsDeployAction(args.action)) then
            if not item.components.deployable:CanDeploy(point,nil,inst,0) then return false end
            if args.action==nil then return true end
        end
        local result=require("my_friend_body_native").Query(inst,state,{item=args.item,position={x=point.x,z=point.z}})
        for _,action in ipairs(result~=nil and result.actions or {}) do
            if args.action==nil or action.action==args.action then return true end
        end
        return false
    end
    if layout~=nil then
        local gap=ring ~= nil and 2 * radius * math.sin(math.pi / ring)
            or layout.spacing or (layout.tile==true and (TILE_SCALE or 4)/math.max(layout.rows,layout.columns) or spacing)
        local angle=(layout.rotation or 0)*math.pi/180
        local cells={}
        local function AddCell(x, z, cell)
            if (x-origin.x)^2+(z-origin.z)^2>32^2 or (x-p.x)^2+(z-p.z)^2>radius^2+.00001 then
                return false
            end
            local valid=gap>=spacing and Valid(Vector3(x,0,z))
            cell.position, cell.valid = {x=x,z=z}, valid
            if not valid then cell.reason = gap<spacing and "spacing_below_native_minimum" or "native_position_blocked" end
            cells[#cells+1]=cell
            if valid then sites[#sites+1]=cell end
            return true
        end
        if ring ~= nil then
            for index = 1, ring do
                local a = angle + (index - 1) * 2 * math.pi / ring
                if not AddCell(p.x + radius * math.cos(a), p.z + radius * math.sin(a), {index=index}) then
                    return nil,"layout_out_of_range"
                end
            end
        else
            for row=1,layout.rows do for column=1,layout.columns do
                local dx,dz=(column-(layout.columns+1)/2)*gap,(row-(layout.rows+1)/2)*gap
                if not AddCell(p.x+dx*math.cos(angle)-dz*math.sin(angle), p.z+dx*math.sin(angle)+dz*math.cos(angle),
                    {row=row,column=column}) then return nil,"layout_out_of_range" end
            end end
        end
        return {sites=sites,cells=cells,spacing=gap,minimum_spacing=spacing,layout=layout,
            center=p,checked=#cells,limited=false,observed_at=GetTime(),
            partial=#sites<#cells,note="Blocked positions are retained. Recheck during execution."}
    end
    local requested
    if args.position ~= nil then
        local point = M.Snap(item, Vector3(p.x,0,p.z))
        local in_range = (point.x-origin.x)^2+(point.z-origin.z)^2 <= 32^2
        local valid = in_range and Valid(point)
        requested = M.Details(inst,state,point,spacing)
        requested.valid = valid
        if not valid then requested.reason = in_range and "placement_blocked" or "position_out_of_range" end
        if valid then sites[1] = {position=requested.position} end
        checked, seen[tostring(point.x)..":"..tostring(point.z)] = 1, true
        if args.exact then
            return {sites=sites, requested_site=requested, checked=checked, minimum_spacing=spacing,
                observed_at=GetTime(), limited=false, reason=requested.reason}
        end
    end
    -- Without an explicit point prefer space around the companion's feet.
    for ring = 1, 4 do
        for n = 0, 15 do
            local angle = n * math.pi / 8
            local point = Vector3(p.x + radius * ring / 4 * math.cos(angle), 0,
                p.z + radius * ring / 4 * math.sin(angle))
            point = M.Snap(item, point)
            local key = tostring(point.x)..":"..tostring(point.z)
            if checked < 64 and not seen[key] and (point.x-origin.x)^2+(point.z-origin.z)^2 <= 32^2
                and (point.x-p.x)^2+(point.z-p.z)^2 <= radius^2 + .00001 then
                seen[key], checked = true, checked + 1
                local valid = Valid(point)
                if valid then
                    for _, site in ipairs(sites) do
                        if (site.position.x-point.x)^2+(site.position.z-point.z)^2 < spacing^2 then valid=false;break end
                    end
                end
                if valid then
                    local nearby = {}
                    for _, e in ipairs(TheSim:FindEntities(point.x, 0, point.z, 6, {"structure"}, {"INLIMBO", "FX"})) do
                        if #nearby < 4 then nearby[#nearby+1] = Observation.Describe(inst, state, e) end
                    end
                    sites[#sites+1] = {position={x=point.x,z=point.z}, nearby=nearby}
                    if #sites >= 8 then break end
                end
            end
        end
        if #sites >= 8 then break end
    end
    return {sites=sites, requested_site=requested, checked=checked, radius=radius, observed_at=GetTime(),
        limited=true, minimum_spacing=spacing,reason=#sites==0 and "no_valid_site_in_sample" or nil,
        note="Native validity only; choose for player intent, access and surroundings. Rechecked at execution; not reserved or guaranteed reachable."}
end
return M
