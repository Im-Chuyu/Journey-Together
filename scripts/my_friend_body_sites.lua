-- Explicit, bounded placement advice. Never reserves terrain or spawns items.
local Observation = require("my_friend_body_observation")
local M = {}
local function Finite(n) return type(n) == "number" and n == n and math.abs(n) < 1000000 end
function M.Valid(inst, recipe, point)
    return TheWorld.Map ~= nil and TheWorld.Map.CanDeployRecipeAtPoint ~= nil
        and TheWorld.Map:CanDeployRecipeAtPoint(point, recipe, 0, inst) == true
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
    local spacing = recipe ~= nil and (recipe.min_spacing or 3.2)
        or item.components.farmtiller ~= nil and GetFarmTillSpacing~=nil and GetFarmTillSpacing()
        or item.components.deployable ~= nil and item.components.deployable.DeploySpacingRadius~=nil and item.components.deployable:DeploySpacingRadius() or 1
    local layout=args.layout
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
        if item.components.deployable~=nil and args.action==nil then
            return item.components.deployable:CanDeploy(point,nil,inst)==true
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
    -- Prefer useful open space over the actor's feet. Keep a small, fixed budget.
    for ring = 1, 4 do
        for n = 0, 15 do
            local angle = n * math.pi / 8
            local point = Vector3(p.x + radius * ring / 4 * math.cos(angle), 0,
                p.z + radius * ring / 4 * math.sin(angle))
            if item ~= nil and item:HasTag("tile_deploy") and TheWorld.Map.GetTileCenterPoint ~= nil then
                local x, y, z = TheWorld.Map:GetTileCenterPoint(point:Get())
                if x ~= nil then point = Vector3(x, y, z) end
            end
            local key = tostring(point.x)..":"..tostring(point.z)
            if not seen[key] and (point.x-origin.x)^2+(point.z-origin.z)^2 <= 32^2
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
    return {sites=sites, checked=checked, radius=radius, observed_at=GetTime(),
        limited=true, minimum_spacing=spacing,reason=#sites==0 and "no_valid_site_in_sample" or nil,
        note="Native validity only; choose for player intent, access and surroundings. Rechecked at execution; not reserved or guaranteed reachable."}
end
return M
