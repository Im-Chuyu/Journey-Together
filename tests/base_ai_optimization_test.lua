-- Regression for base-mode cleanup, unchanged resource saves, and cached ground discovery.
-- Run from the mod root: lua tests/base_ai_optimization_test.lua
package.path = "./scripts/?.lua;" .. package.path
local now, serial, queries = 100, 0, {}
function GetTime() return now end
function Vector3(x,y,z) return {x=x,y=y,z=z} end
local function Noop() end
local function Stub(name, value) package.loaded[name]=value or {} end
local function Read(path) local f=assert(io.open(path,"rb")); local s=f:read("*a"); f:close(); return (s:gsub("\r\n", "\n")) end
local function Upvalue(fn,name)
    for i=1,100 do local key,value=debug.getupvalue(fn,i); if key==nil then break end; if key==name then return value end end
    error("missing upvalue "..name)
end
local function Entity(prefab,x)
    serial=serial+1
    local e={GUID=serial,prefab=prefab or "wendy",components={},x=x or 0,z=0,tags={}}
    function e:IsValid() return true end
    function e:HasTag(t) return self.tags[t]==true end
    function e:AddTag(t) self.tags[t]=true end
    function e:PushEvent() end
    function e:GetPosition() return Vector3(self.x,0,self.z) end
    function e:GetDistanceSqToInst(other) return (self.x-other.x)^2+(self.z-other.z)^2 end
    function e:GetDistanceSqToPoint(p) return (self.x-p.x)^2+(self.z-p.z)^2 end
    function e:IsInLimbo() return self.tags.INLIMBO==true end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,
        SetPosition=function(_,x,y,z) e.x,e.z=x,z end}
    return e
end
ACTIONS={}
for _,name in ipairs({"WALKTO","BUILD","MY_FRIEND_BUILD","PICKUP","CHOP","MINE","DIG","HAMMER","PICK"}) do ACTIONS[name]={id=name} end
function BufferedAction(doer,target,action,item,point,recipe)
    local a={doer=doer,target=target,action=action,invobject=item,pos=point,recipe=recipe,success={},fail={}}
    function a:AddSuccessAction(fn) self.success[#self.success+1]=fn end
    function a:AddFailAction(fn) self.fail[#self.fail+1]=fn end
    function a:Fail() for _,fn in ipairs(self.fail) do fn() end end
    function a:GetActionPoint() return self.pos end
    return a
end
TUNING={TOTAL_DAY_TIME=480,SPEAR_DAMAGE=34}
TheWorld={state={iswinter=true,issummer=false,cycles=10},ismastersim=true}
Ents={}
TheSim={FindEntities=function(_,x,y,z,r,must,cant,oneof)
    queries[#queries+1]={radius=r,must=must,oneof=oneof}; return {}
end}
local recipes={backpack={name="backpack",ingredients={{type="cutgrass",amount=4},{type="twigs",amount=4}}},
    umbrella={name="umbrella",ingredients={{type="twigs",amount=6},{type="pigskin",amount=1},{type="silk",amount=2}}}}
function GetValidRecipe(name) return recipes[name] end
Stub("my_friend_backpacks",{NeedsCraftedBackpack=function() return false end})
Stub("my_friend_equip_slots",{All=function() return {"head","body","hands"} end})
Stub("my_friend_light_ai",{IsExternallyLit=function() return true end,IsEnvironmentDark=function() return false end,
    IsDark=function() return false end})
Stub("my_friend_behavior_ai")
Stub("my_friend_food_ai")
Stub("my_friend_world_resources")
Stub("my_friend_forestry",{TREE_LIMIT=20,OnSave=function() return {} end,OnLoad=Noop})
Stub("my_friend_navigation",{IsBlocked=function() return false end})
Stub("my_friend_inventory",{IsUsableTool=function() return false end})
Stub("my_friend_resource_safety",{IsBlocked=function() return false end})
Stub("my_friend_garden")
Stub("my_friend_storage")
Stub("my_friend_equipment_reserves")
local station=Entity("researchlab",10)
local Tech={CanBuild=function() return false end,FindStation=function() return station,100 end,
    Activate=function() return false end,OnBuilt=function() return Noop end}
Stub("my_friend_crafting_tech",Tech)
local Policy={GetLeader=function(i) return i.leader end,IsBusy=function() return false end,
    IsFollowGatheringPaused=function() return false end,IsLeaderDead=function() return false end,
    SearchOrigin=function(_,r) return 0,0,0,r end,InRange=function() return true end,
    GuardAction=function(_,a) return a end,DistanceSq=function(a,b) return a:GetDistanceSqToInst(b) end}
Stub("my_friend_policy",Policy)
Stub("my_friend_exploration",{Save=Noop,Load=Noop})
Stub("my_friend_carry_backpack",{Cancel=Noop})
Stub("cooking")
Stub("my_friend_recipe_planner")
Stub("my_friend_food_storage")
Stub("my_friend_cookpot",{Close=Noop})
Stub("my_friend_cookpot_cleanup")
local Memory=require("my_friend_resource_memory")
local Home=require("my_friend_home")
local Discovery=require("my_friend_discovery")
local Base=require("my_friend_base_ai")
local Recipe=require("my_friend_recipe_cooking")
local Basic=require("my_friend_basic_equipment")
local CanPlan=Upvalue(Recipe.Score,"CanPlan")
local function Actor()
    local i=Entity("wendy"); i.tags.my_friend=true
    i._my_friend_base={x=0,z=0,site_version=2,complete=true}
    i.components.health={IsDead=function() return false end,GetPercent=function() return .8 end}
    i.components.hunger={GetPercent=function() return .8 end}
    i.components.follower={GetLeader=function() return i.leader end}
    i.components.inventory={inst=i,opencontainers={},ReferenceAllItems=function() return {} end,GetActiveItem=function() end,
        CanAcceptCount=function() return 1 end,
        Has=function() return false,0 end,FindItem=function() end,NumItems=function() return 0 end,GetNumSlots=function() return 15 end,
        GetOverflowContainer=function() end}
    i.components.builder={HasIngredients=function() return true end,EvaluateTechTrees=Noop}
    i.sg={HasStateTag=function() return false end}
    return i
end
local passed,failed=0,0
local function Test(name,fn)
    local ok,message=pcall(fn)
    if ok then passed=passed+1; print("PASS "..name) else failed=failed+1; print("FAIL "..name..": "..tostring(message)) end
end
local commandSource=Read("scripts/my_friend_commands.lua")
local a=assert(commandSource:find("function M.Clear(friend)",1,true))
local b=assert(commandSource:find("function M.Register(",a,true))
local commandEnv=setmetatable({M={}},{__index=_G})
local clearChunk=assert(loadstring(commandSource:sub(a,b-1).."\nreturn M.Clear")); setfenv(clearChunk,commandEnv)
local Clear=clearChunk()
Test("manual base change retires an old prototype trip without blocking cooking",function()
    local i=Actor(); assert(CanPlan(i))
    local action=assert(Base.GetRecipeAction(i,"backpack")); assert(i._my_friend_pending_recipe=="backpack")
    action._my_friend_cancelled=true; action:Fail()
    i.leader=Entity("wilson")
    Clear(i); Home.Set(i,Vector3(0,0,0),"base")
    for n=1,10 do Base.GetAction(i) end
    i.leader=nil; Clear(i)
    for n=1,10 do Base.GetAction(i) end
    assert(i._my_friend_pending_recipe==nil)
    assert(CanPlan(i) and Basic.Score(i,{})==73)
    assert(CanPlan(i) and Basic.Score(i,{})==73)
    print("  pending marker after cancel/home switch: nil; cooking allowed: true")
end)
Test("cancellation preserves resumption while ordinary recipe failure clears pending state",function()
    local i=Actor(); local action=assert(Base.GetRecipeAction(i,"backpack"))
    action:Fail(); assert(i._my_friend_pending_recipe==nil and CanPlan(i))
end)
local modmain=Read("modmain.lua")
local start=assert(modmain:find("    if inst._my_friend_save_hooks_added ~= true then",1,true))
local finish=assert(modmain:find("    PushPanelData(inst)\n    FriendReplication.Configure(inst)",start,true))
local env=setmetatable({_G=_G,BaseAI=Base,ResourceMemory=Memory,ReviveAI={OnSave=Noop,OnLoad=Noop},
    CookingAI={OnSave=Noop,OnLoad=Noop},FriendReplication={RestoreSkin=Noop},
    RemovePlayerIdentity=Noop,PushPanelData=Noop},{__index=_G})
for _,name in ipairs({"my_friend_farewell","my_friend_equipment","my_friend_wathgrithr","my_friend_wickerbottom"}) do
    Stub(name,{Save=Noop,Load=Noop})
end
Stub("my_friend_feed_player",{OnSave=Noop,OnLoad=Noop})
Stub("my_friend_social_ai",{SaveCare=Noop,LoadCare=Noop})
Stub("my_friend_migration",{SaveWorldMemory=Noop,SelectWorldMemory=Noop})
local hookChunk=assert(loadstring("return function(inst)\n"..modmain:sub(start,finish-1).."\nend"))
setfenv(hookChunk,env); local Install=hookChunk(); env.ConfigureFriend=Install
local loadStart=assert(modmain:find("    local oldload = inst.OnLoad\n    inst.OnLoad = function(self, data, ents)",1,true))
local loadEnd=assert(modmain:find("    if not _G.TheWorld.ismastersim then\n        inst._my_friend_identity_task",loadStart,true))
local initialChunk=assert(loadstring("return function(inst)\n"..modmain:sub(loadStart,loadEnd-1).."\nend"))
setfenv(initialChunk,env); local InstallInitial=initialChunk()
local originalSave,originalLoad=Memory.Save,Memory.Load
local saves,loads=0,0
Memory.Save=function(...) saves=saves+1; return originalSave(...) end
Memory.Load=function(...) loads=loads+1; return originalLoad(...) end
Test("actual companion save hook serializes resource memory once",function()
    local i=Actor(); Install(i); saves=0
    i._my_friend_resource_memory={one={x=32,z=0,seen=90,counts={rocks=5}}}
    local data={}; i:OnSave(data)
    assert(saves==1 and #data.my_friend_resource_memory==1 and data.my_friend_resource_memory[1].counts.rocks==5)
    print("  ResourceMemory.Save calls for one companion save: "..saves)
end)
Test("actual initial saved-prefab load rebuilds resource memory once with equivalent data",function()
    local i=Actor(); InstallInitial(i); loads=0
    i:OnLoad({my_friend_companion=true,my_friend_resource_memory={{x=32,z=0,age=10,counts={rocks=5}}}})
    assert(loads==1 and i._my_friend_resource_memory["2:0"].counts.rocks==5)
    assert(i._my_friend_resource_memory["2:0"].seen==90)
    print("  ResourceMemory.Load calls for one initial saved-prefab load: "..loads)
end)
Test("single serialization still preserves all 64 resource-memory cells",function()
    local i=Actor(); Install(i); i._my_friend_resource_memory={}
    for n=0,63 do i._my_friend_resource_memory[tostring(n)..":0"]={x=n*16,z=0,seen=90,counts={rocks=n+1}} end
    local data={}; saves=0; i:OnSave(data)
    assert(saves==1 and #data.my_friend_resource_memory==64)
    local j=Actor(); InstallInitial(j); loads=0; j:OnLoad(data)
    local n=0
    for _,cell in pairs(j._my_friend_resource_memory) do n=n+1; assert(cell.counts.rocks==cell.x/16+1 and cell.seen==90) end
    assert(loads==1 and n==64)
end)
local InternalGoal=Upvalue(Base.GetRemainsAction,"GetRecipeGoalAction")
local function GroundQueries()
    local n=0; for _,q in ipairs(queries) do if q.must~=nil and q.must[1]=="_inventoryitem" and q.radius==36 then n=n+1 end end
    return n
end
Test("actual empty-material recipe chain shares identical ground discovery in a missing-material recipe chain",function()
    local i=Actor(); i.components.builder.HasIngredients=function() return false end
    queries={}; assert(InternalGoal(i,"umbrella")==nil)
    assert(GroundQueries()==1,"ground query count="..GroundQueries())
    print("  same-location ground-material queries for one missing recipe evaluation: "..GroundQueries())
    queries={}; i._my_friend_discoveries=nil; for n=1,10 do InternalGoal(i,"umbrella") end
    assert(GroundQueries()==1)
    print("  unchanged conditions, ten evaluations: "..GroundQueries().." ground-material queries")
end)
Test("existing Discovery supports sharing empty results under unchanged conditions",function()
    local i=Actor(); queries={}
    for n=1,10 do Discovery.Query(i,"audit_empty_materials","resources",0,0,0,36,{"_inventoryitem"},{"INLIMBO"}) end
    assert(#queries==1)
    print("  same empty-result query through existing Discovery, ten evaluations: "..#queries)
end)
Test("newly dropped materials invalidate an empty cache through native drop events",function()
    local native=arg[1] or "../yuanma/scripts"
    local function Method(path,first,last,tableName,methodName)
        local s=Read(native.."/"..path)
        local a=assert(s:find(first,1,true)); local b=assert(s:find(last,a+#first,true))
        return assert(loadstring("local "..tableName.."={}\n"..s:sub(a,b-1).."\nreturn "..tableName.."."..methodName))()
    end
    local Drop=Method("components/inventory.lua","function Inventory:DropItem(","function Inventory:ForceNoInsulated(","Inventory","DropItem")
    local Dropped=Method("components/inventoryitem.lua","function InventoryItem:OnDropped(","function InventoryItem:DoDropPhysics(","InventoryItem","OnDropped")
    local shared={PushEvent_Internal=function() end}
    Discovery.Install(shared,{pickable={},crop={},dryer={}})
    local results={}
    local original=TheSim.FindEntities
    TheSim.FindEntities=function(self,x,y,z,r,must,cant,oneof)
        original(self,x,y,z,r,must,cant,oneof)
        local list={}
        if must~=nil and must[1]=="_inventoryitem" then
            for _,e in ipairs(results) do
                local excluded=false
                for _,tag in ipairs(cant or {}) do if e:HasTag(tag) then excluded=true end end
                if e:IsValid() and not excluded and (e.x-x)^2+(e.z-z)^2<=r*r then list[#list+1]=e end
            end
        end
        return list
    end
    local Ground=Upvalue(InternalGoal,"GetNeededGroundAction")
    local i=Actor(); queries={}
    assert(Ground(i,{silk=1})==nil and GroundQueries()==1)
    local player=Actor(); local material=Entity("silk"); material.tags._inventoryitem=true
    material.components.inventoryitem={inst=material,owner=player,canbepickedup=true,OnDropped=Dropped,
        RemoveFromOwner=function(self) self.owner=nil; return self.inst end,
        OnRemoved=function(self) self.owner=nil end,
        DoDropPhysics=function(self,x,y,z) self.inst.Transform:SetPosition(x,y,z) end}
    function material:PushEvent(event) shared.PushEvent_Internal(self,event) end
    Ents[material.GUID]=material; results[1]=material
    local point=Vector3(6,0,0); point.Get=function(p) return p.x,p.y,p.z end
    assert(Drop(player.components.inventory,material,true,false,point)==material)
    local action=assert(Ground(i,{silk=1})); assert(action.target==material and GroundQueries()==2)
    action=assert(Ground(i,{silk=1})); assert(action.target==material and GroundQueries()==2)
    material.components.inventoryitem.owner=player
    assert(Ground(i,{silk=1})==nil,"cached target bypassed current item ownership")
    material.components.inventoryitem.owner=nil; material.tags.INLIMBO=true
    assert(Ground(i,{silk=1})==nil,"cached target bypassed current limbo state")
    material.tags.INLIMBO=nil
    assert(Ground(i,{silk=1},4)==nil,"search radius was expanded by the cache")
    assert(Ground(i,{silk=1})~=nil)
    material.x=40
    assert(Ground(i,{silk=1})==nil,"cached item that moved outside the radius was still selected")
    TheSim.FindEntities=original
end)
print(string.format("RESULT: %d passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end
