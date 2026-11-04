package.path = "./scripts/?.lua;../yuanma/scripts/?.lua;" .. package.path
local file = assert(io.open("tests/body_api_test.lua", "rb"))
local source = file:read("*a"):gsub("\r", ""); file:close()
local F = assert(loadstring(assert(source:match("^(.-)local passed = 0")) ..
    "\nreturn {setup=Setup,item=Item,entity=Entity,storage=Storage,perform=Perform,call=Call}"))()
local API = require("my_friend_body_api")
local O = API.Observation
local tech = require("my_friend_crafting_tech")
local function Setup()
    local inst, player, state = F.setup()
    AllRecipes = {cookpot={name="cookpot", product="cookpot", placer="cookpot_placer",
        level={}, ingredients={{type="rocks",amount=4}}, numtogive=1}}
    GetValidRecipe = function(name) return AllRecipes[name] end
    TheWorld.Map = {CanDeployRecipeAtPoint=function(_, point) return point.x > 0 end}
    tech.StationCanTeach = function(_, station) return station.prefab == "researchlab" end
    return inst, player, state
end
local function Drain(inst)
    for _=1,40 do if inst._my_friend_body.active == nil then return end; F.perform(inst) end
    error("plan did not finish")
end
local passed=0
local function Test(name, fn) fn();passed=passed+1;print("PASS "..name) end
Test("one recipe query combines inventory deficits, ground-first supplies, stations and distinct sites", function()
    local inst, p, s = Setup()
    for i=1,45 do
        F.item("unrelated",nil).x=1
        F.storage(F.entity("treasurechest",1),true)
    end
    F.item("rocks", inst, 1)
    local ground = F.item("rocks", nil, 2); ground.x=1.5
    local chest = F.entity("treasurechest", 2); F.storage(chest, true)
    local stored = F.item("rocks", chest, 10)
    local locked = F.entity("lockedchest", 1); F.storage(locked, true).restricted=true
    F.item("rocks", locked, 30)
    local station = F.entity("researchlab", 3); station.tags.structure=true
    station.components.prototyper = {CanUsePrototyper = function() return false end}
    local r=F.call(inst,p,"query_recipe",{query="cookpot",count=2})
    assert(r.status=="completed")
    local result=r.result
    assert(result.ingredients[1].required==8 and result.ingredients[1].missing==7)
    assert(#result.sources==2 and result.sources[1].count==2 and result.sources[1].source=="ground")
    assert(O.Resolve(s,result.sources[1].item)==ground and O.Resolve(s,result.sources[2].item)==stored)
    assert(result.sources[2].count==5 and result.unavailable.rocks==0 and #result.stations==1)
    assert(#result.placement.sites>1)
    for i,a in ipairs(result.placement.sites) do
        assert(a.position.x>0)
        for j,b in ipairs(result.placement.sites) do
            if i~=j then assert((a.position.x-b.position.x)^2+(a.position.z-b.position.z)^2>=3.2^2) end
        end
    end
end)
Test("placement sampling never suggests points outside the companion's action range",function()
    local inst,p,s=Setup()
    local result=F.call(inst,p,"query_sites",{recipe="cookpot",position={x=31,z=0},radius=16}).result
    assert(#result.sites>0)
    for _,site in ipairs(result.sites)do
        local pos=site.position
        assert(pos.x^2+pos.z^2<=32^2 and (pos.x-31)^2+pos.z^2<=16^2+.00001)
    end
end)
Test("fixed ring reports blocked positions without changing the planned circle", function()
    local inst, p = Setup()
    local result = F.call(inst, p, "query_sites", {recipe="cookpot", radius=6, layout={ring=6}}).result
    assert(#result.cells == 6 and #result.sites < 6 and result.partial)
    for index, cell in ipairs(result.cells) do
        assert(cell.index == index and math.abs(cell.position.x^2 + cell.position.z^2 - 36) < .00001)
        assert(cell.valid == (cell.position.x > 0))
    end
end)
Test("known base routes can span the map and finish only after arrival", function()
    local inst, p, state = Setup()
    inst._my_friend_base = {x = 400, z = 0}
    inst.components.locomotor = {ResetPath = function() end, Stop = function() end}
    local nav = require("my_friend_navigation")
    nav.CancelSteering, nav.ClearStuck = function() end, function() end
    nav.GetLongFollowPoint = function(actor, goal)
        assert(goal.x == 400)
        return Vector3(math.min(goal.x, actor.x + 20), 0, 0)
    end
    nav.GetSteeringPoint = function(_, point) return point end
    nav.Unstick = function() end
    nav.MoveToPoint = function(actor, point) actor.x = point.x end
    local r = F.call(inst, p, "move_to", {destination = "base"})
    assert(r.status == "accepted")
    API.GetAction(inst)
    assert(state.active ~= nil and inst.x == 20)
    Drain(inst)
    assert(state.jobs[r.action_id].result.position.x == 400 and state.active == nil)
end)
Test("building requires an explicit location and independent steps for multiple positions", function()
    local inst,p,s=Setup()
    assert(F.call(inst,p,"craft",{recipe="cookpot"}).reason=="placement_required")
    assert(F.call(inst,p,"craft",{recipe="cookpot",count=2,position={x=4,z=0}}).reason=="distinct_placement_steps_required")
    local item=F.item("rocks",nil,4)
    local builds=0
    ACTIONS.MY_FRIEND_BUILD.fn=function() builds=builds+1;return true end
    local r=F.call(inst,p,"execute_sequence",{steps={
        {id="take",skill="pickup",arguments={target=O.Handle(s,item),count=4}},
        {id="first",skill="craft",arguments={recipe="cookpot",position={x=4,z=0}}},
        {id="blocked",skill="craft",arguments={recipe="cookpot",position={x=-4,z=0}}}}})
    Drain(inst)
    local job=s.jobs[r.action_id]
    assert(job.reason=="placement_blocked" and job.result.completed==2 and job.result.failed_step=="blocked")
    assert(builds==1 and item.owner==inst and job.result.steps[3].result.materials_consumed==false)
    -- A new location completes the remainder without repeating the first building/pickup.
    r=F.call(inst,p,"craft",{recipe="cookpot",position={x=8,z=0}});Drain(inst)
    assert(s.jobs[r.action_id].status=="completed" and builds==2)
end)
Test("placement is revalidated after routing, before native material consumption", function()
    local inst,p,s=Setup()
    local r=F.call(inst,p,"craft",{recipe="cookpot",position={x=4,z=0}})
    local action=API.GetAction(inst)
    TheWorld.Map.CanDeployRecipeAtPoint=function() return false end
    assert(not action:IsValid());action:Fail()
    assert(s.jobs[r.action_id].reason=="placement_blocked")
end)
Test("carried deployables use native tile validation; unknown/foreign items and empty samples are explicit", function()
    local inst,p,s=Setup()
    local item=F.item("farm_plow_item",inst);item.tags.tile_deploy=true
    TheWorld.Map.GetTileCenterPoint=function(_,x,_,z) return math.floor(x/4)*4+2,0,math.floor(z/4)*4+2 end
    item.components.deployable={CanDeploy=function(_,point,_,deployer)
        assert(deployer==inst and point.x%4==2 and point.z%4==2);return point.x>3
    end}
    local r=F.call(inst,p,"query_batch",{queries={{skill="query_sites",arguments={item=O.Handle(s,item)}}}})
    assert(#r.result.results[1].result.sites>0)
    item.owner=p
    assert(F.call(inst,p,"query_sites",{item=O.Handle(s,item)}).reason=="item_not_deployable")
    TheWorld.Map.CanDeployRecipeAtPoint=function() return false end
    r=F.call(inst,p,"query_sites",{recipe="cookpot"})
    assert(#r.result.sites==0 and r.result.reason=="no_valid_site_in_sample" and r.result.checked<=64)
end)
Test("basic snapshot reports moisture, world time, ground items and boss identity", function()
    local inst,p,s=Setup()
    inst.components.moisture={GetMoisture=function() return 42 end}
    TheWorld.state={cycles=9,time=.25,phase="day",season="autumn",temperature=18}
    local ground=F.item("rocks",nil); F.item("rocks",p)
    local boss=F.entity("deerclops",3);boss.tags.epic=true
    boss.components.health={currenthealth=4000,IsDead=function() return false end};boss.components.locomotor={}
    O.RefreshEnvironment(inst,s)
    local snapshot=O.Snapshot(inst,s)
    assert(snapshot.moisture==42 and snapshot.world.day==10 and snapshot.world.time==.25)
    assert(#snapshot.environment.items==1 and O.Resolve(s,snapshot.environment.items[1].handle)==ground)
    assert(#snapshot.environment.bosses==1 and snapshot.environment.bosses[1].boss)
end)
Test("terrain and fixed layouts expose tile bounds and preserve row/column alignment", function()
    local inst,p,s=Setup()
    TILE_SCALE=4;WORLD_TILES={FARMING_SOIL=1};GetFarmTillSpacing=function()return 1 end
    TheWorld.Map.GetTileCenterPoint=function(_,x,_,z)return math.floor(x/4)*4+2,0,math.floor(z/4)*4+2 end
    TheWorld.Map.GetTileAtPoint=function()return 1 end
    TheWorld.Map.IsFarmableSoilAtPoint=function()return true end
    TheWorld.Map.CanTillSoilAtPoint=function()return true end
    local r=F.call(inst,p,"observe",{scope="terrain",radius=4})
    assert(r.status=="completed" and #r.result.tiles==9 and r.result.tiles[1].farming_soil)
    assert(r.result.tiles[1].bounds.max_x-r.result.tiles[1].bounds.min_x==4)
    local hoe=F.item("farm_hoe",inst);hoe.components.farmtiller={}
    ACTIONS.TILL={id="TILL",fn=function()return true end}
    hoe.CollectActions=function(_,mode,doer,point,actions)if mode=="POINT"then actions[#actions+1]=ACTIONS.TILL end end
    r=F.call(inst,p,"query_sites",{item=O.Handle(s,hoe),action="TILL",radius=4,layout={rows=3,columns=3,tile=true}})
    assert(r.status=="completed" and #r.result.cells==9 and #r.result.sites==9)
    assert(r.result.spacing==4/3 and r.result.minimum_spacing==1)
    assert(r.result.cells[1].row==1 and r.result.cells[1].column==1 and r.result.cells[9].row==3)
    r=F.call(inst,p,"query_sites",{item=O.Handle(s,hoe),action="TILL",radius=4,layout={rows=3,columns=3,spacing=.5}})
    assert(#r.result.sites==0 and #r.result.cells==9 and r.result.cells[1].reason=="spacing_below_native_minimum")
end)
Test("snapshot reports current base membership without claiming waiting circles or creating a base",function()
 local inst,p,state=Setup()
 local snapshot=O.Snapshot(inst,state)
 assert(snapshot.base.known==false and snapshot.base.at_base==nil and snapshot.home.known==false)
 assert(inst._my_friend_base==nil and inst._my_friend_home==nil)
 inst._my_friend_base={x=0,z=0,complete=true,phase="complete"}
 inst.x=33
 snapshot=O.Snapshot(inst,state)
 assert(snapshot.base.source=="automatic" and snapshot.base.radius==34 and snapshot.base.at_base)
 assert(snapshot.base.return_distance==12 and snapshot.base.distance==33)
 inst.x=35;assert(not O.Snapshot(inst,state).base.at_base)
 inst._my_friend_home={x=10,z=0,mode="base"}
 inst.x=42
 snapshot=O.Snapshot(inst,state)
 assert(snapshot.base.source=="manual" and snapshot.base.position.x==10 and snapshot.base.radius==32 and snapshot.base.at_base)
 inst.x=43;assert(not O.Snapshot(inst,state).base.at_base)
 for _,mode in ipairs({"hold","roam"})do
  inst._my_friend_home.mode=mode
  snapshot=O.Snapshot(inst,state)
  assert(not snapshot.base.known and snapshot.base.at_base==nil and snapshot.home.known and snapshot.home.mode==mode)
 end
 inst._my_friend_home=nil;inst._my_friend_base=nil
 assert(not O.Snapshot(inst,state).base.known)
end)
Test("nearby environment explicitly includes containers without reading their contents",function()
 local inst,p,state=Setup()
 local fridge=F.entity("icebox",3);F.storage(fridge,true);F.item("meat",fridge,3)
 O.RefreshEnvironment(inst,state)
 local snapshot=O.Snapshot(inst,state)
 assert(#snapshot.environment.containers==1 and snapshot.environment.containers[1].prefab=="icebox")
 assert(snapshot.environment.containers[1].contents==nil)
end)
Test("location reports current ground and topology islands without guessing from turf or cave names",function()
 local inst,p,state=Setup()
 local terrain=require("my_friend_body_terrain")
 WORLD_TILES={GRASS=1,MARSH=2,SAVANNA=3,DECIDUOUS=4,DESERT_DIRT=5}
 local tile=1
 TheWorld.Map.GetTileAtPoint=function()return tile end
 TheWorld.Map.GetNodeIdAtPoint=function()return 1 end
 TheWorld.topology={ids={"test"},nodes={{tags={"sandstorm"}}}}
 local original=ConvertTopologyIdToData
 local data={}
 ConvertTopologyIdToData=function()return data end
 for _,entry in ipairs({
  {{room_id="Marsh"},"marsh",2},{{room_id="BGSavanna"},"savanna",3},
  {{room_id="PigKingdom"},"pig_king_area",1},{{task_id="MoonIsland",room_id="MoonIsland_Forest"},"moon_island",1},
  {{layout_id="HermitcrabIsland"},"hermit_island",1},{{layout_id="MonkeyIsland"},"monkey_island",1},
  {{room_id="BeeClearing"},"bee_plains",1},{{room_id="LightningBluffOasis"},"oasis_desert",5}})do
  data,tile=entry[1],entry[3]
  local location=O.Snapshot(inst,state).location
  assert(location.known and location.region.id==entry[2] and location.region.source=="topology")
  assert(location.tile.id==tile and location.topology.tags[1]=="sandstorm")
 end
 data={room_id="MonkeyMeadow"};tile=1
 assert(terrain.Location(inst).region==nil)
 data={room_id="ModGrassRoom"};assert(terrain.Location(inst).region==nil)
 TheWorld.topology=nil
 local ground=terrain.Location(inst)
 assert(ground.tile.name=="GRASS" and ground.region==nil)
 TheWorld.Map=nil;assert(not terrain.Location(inst).known)
 ConvertTopologyIdToData=original
end)
print(passed.." planning tests passed")
