-- Explicit local terrain query; no background scans or saved entity references.
local M = {}
local REGIONS={PigKingdom="pig_king_area",BeeClearing="bee_plains",BeeQueenBee="bee_queen_area",
    BGMarsh="marsh",Marsh="marsh",SpiderMarsh="marsh",ChessMarsh="marsh",BGSavanna="savanna",
    BGDeciduous="deciduous_forest",DeepDeciduous="deciduous_forest",MagicalDeciduous="deciduous_forest",
    DeciduousMole="deciduous_forest",MolesvilleDeciduous="deciduous_forest",DeciduousClearing="deciduous_forest",
    BGBadlands="desert",Badlands="desert",HoundyBadlands="desert",BuzzardyBadlands="desert",DragonflyArena="dragonfly_desert",
    BGLightningBluff="oasis_desert",LightningBluffAntlion="oasis_desert",LightningBluffOasis="oasis_desert",
    LightningBluffLightning="oasis_desert"}
local function Short(value)
    return type(value)=="string" and value:sub(1,160) or nil
end
-- Only the current tile and current topology node. Never enumerate the map or
-- infer an island from planted turf, a nearby NPC, or a similarly named room.
function M.Location(inst)
    local world=TheWorld
    local map=world~=nil and world.Map or nil
    local out={known=false,on_platform=inst:GetCurrentPlatform()~=nil,world=world~=nil and world.prefab or nil}
    if map==nil then return out end
    local p=inst:GetPosition()
    if map.GetTileAtPoint~=nil then
        local id=map:GetTileAtPoint(p.x,0,p.z)
        out.tile={id=id}
        for name,value in pairs(WORLD_TILES or {})do if id==value then out.tile.name=name;break end end
        out.known=id~=nil
    end
    local index=map.GetNodeIdAtPoint~=nil and map:GetNodeIdAtPoint(p.x,0,p.z) or nil
    local topology=world.topology
    local node=index~=nil and topology~=nil and topology.nodes~=nil and topology.nodes[index] or nil
    local id=index~=nil and topology~=nil and topology.ids~=nil and topology.ids[index] or nil
    if node~=nil or id~=nil then
        local record={index=index,id=Short(id),tags={}}
        local data=ConvertTopologyIdToData~=nil and ConvertTopologyIdToData(id) or {}
        record.task,record.room,record.layout=Short(data.task_id),Short(data.room_id),Short(data.layout_id)
        for _,tag in ipairs(node~=nil and node.tags or {})do
            if type(tag)=="string" and #record.tags<12 then record.tags[#record.tags+1]=Short(tag) end
        end
        local layout,task,room=record.layout or "",record.task or "",record.room or ""
        local region=layout=="HermitcrabIsland" and "hermit_island"
            or (layout=="MonkeyIsland" or layout=="MonkeyIslandSmall") and "monkey_island"
            or (task:find("MoonIsland",1,true) or room:find("^MoonIsland_")) and "moon_island" or REGIONS[room]
        out.topology,out.known=record,true
        if region~=nil then out.region={id=region,source="topology"} end
    end
    return out
end
function M.At(x, z)
    local map = TheWorld.Map
    local cx, _, cz = map:GetTileCenterPoint(x, 0, z)
    local id = map:GetTileAtPoint(x, 0, z)
    local name
    for key, value in pairs(WORLD_TILES or {}) do if value == id then name=key;break end end
    local scale = TILE_SCALE or 4
    local out = {id=id, name=name, center={x=cx,z=cz}, size=scale,
        bounds={min_x=cx-scale/2,max_x=cx+scale/2,min_z=cz-scale/2,max_z=cz+scale/2},
        farming_soil=map.IsFarmableSoilAtPoint ~= nil and map:IsFarmableSoilAtPoint(x,0,z) or false,
        tillable=map.CanTillSoilAtPoint ~= nil and map:CanTillSoilAtPoint(x,0,z) or false}
    local manager = TheWorld.components ~= nil and TheWorld.components.farming_manager or nil
    if out.farming_soil and manager ~= nil then out.moist=manager:IsSoilMoistAtPoint(x,0,z) end
    return out
end
function M.Scan(inst, state, args)
    local p, radius = inst:GetPosition(), math.min(16,args.radius or 8)
    local scale, tiles, seen = TILE_SCALE or 4, {}, {}
    for dx=-radius,radius,scale do
        for dz=-radius,radius,scale do
            local tile=M.At(p.x+dx,p.z+dz)
            local key=tostring(tile.center.x)..":"..tostring(tile.center.z)
            if not seen[key] then
                seen[key]=true
                local match=(args.filter or ""):lower()
                if match=="" or (tile.name or tostring(tile.id)):lower():find(match,1,true) then
                    tiles[#tiles+1]=tile
                end
            end
            if #tiles>=49 then break end
        end
        if #tiles>=49 then break end
    end
    return {tiles=tiles,location=M.Location(inst),radius=radius,observed_at=GetTime(),limited=#tiles>=49,
        till_spacing=GetFarmTillSpacing ~= nil and GetFarmTillSpacing() or nil}
end
return M
