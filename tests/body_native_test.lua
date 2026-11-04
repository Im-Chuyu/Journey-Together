-- Real API/native bridge/BufferedAction boundary; engine-only components are stubs.
package.path="./scripts/?.lua;../yuanma/scripts/?.lua;"..package.path
local f=assert(io.open("tests/body_api_test.lua","rb"));local source=f:read("*a"):gsub("\r","");f:close()
local F=assert(loadstring(assert(source:match("^(.-)local passed = 0"))..
    "\nreturn {setup=Setup,item=Item,entity=Entity,armor=Armor,storage=Storage,perform=Perform,call=Call,advance=function(n)now=now+n end}"))()
local API=require("my_friend_body_api")
local Native=require("my_friend_body_native")
local function Handle(s,e)return API.Observation.Handle(s,e)end
local function Action(name,fn)
    ACTIONS[name]={id=name,fn=fn or function()return true end};return ACTIONS[name]
end
local passed=0
local function Test(name,fn)fn();passed=passed+1;print("PASS "..name)end
Test("native GIVE fixes phonograph transfer instead of bypassing a trader into its inventory",function()
    local inst,p,s=F.setup();local record=F.item("record",inst);local gram=F.entity("phonograph",3)
    F.storage(gram);gram.components.trader={}
    local accepted=0;local give=Action("GIVE",function(a)accepted=accepted+1;a.invobject.owner=a.target;return true end)
    record.CollectActions=function(_,mode,doer,target,actions)if mode=="USEITEM" and target==gram then actions[#actions+1]=give end end
    local q=F.call(inst,p,"query_actions",{item=Handle(s,record),target=Handle(s,gram)})
    assert(q.result.actions[1].action=="GIVE")
    local job=F.call(inst,p,"transfer",{item=Handle(s,record),destination=Handle(s,gram)})
    F.perform(inst)
    assert(s.jobs[job.action_id].status=="completed" and accepted==1 and record.owner==gram)
end)
Test("inventory own-use and equipped-item right click query with scoped UI availability",function()
    local inst,p,s=F.setup();local item=F.item("handpan",inst);F.armor(item,"hands");item.equipped="hands"
    local use=Action("USEEQUIPPEDITEM")
    item.CollectActions=function(_,mode,doer,actions)
        if mode=="INVENTORY" and doer.components.inventory.isopen and doer.components.inventory.isvisible then actions[#actions+1]=use end
    end
    local q=F.call(inst,p,"query_actions",{item=Handle(s,item),mode="INVENTORY"})
    assert(q.result.actions[1].action==use.id and inst.components.inventory.isopen==nil and inst.components.inventory.isvisible==nil)
    local ok=pcall(Native.WithInventory,inst,function()error("collector failure")end)
    assert(not ok and inst.components.inventory.isopen==nil and inst.components.inventory.isvisible==nil)
end)
Test("entity spell and ground spell preserve native target, point and range handling",function()
    for _,mode in ipairs({"USEITEM","POINT"})do
        local inst,p,s=F.setup();local staff=F.item("telestaff",inst);local target=F.entity("pigman",8)
        local casts=0
        local cast=Action("CASTSPELL",function(a)
            casts=casts+1
            if mode=="POINT"then assert(a.point.x==9 and a.target==nil)else assert(a.target==target)end
            return true
        end)
        staff.CollectActions=function(_,m,doer,t,actions,right)if m==mode and right then actions[#actions+1]=cast end end
        local args={item=Handle(s,staff),mode=mode,action="CASTSPELL"}
        if mode=="POINT"then args.position={x=9,z=0}else args.target=Handle(s,target)end
        local accepted=F.call(inst,p,"perform_action",args)
        local action=assert(API.GetAction(inst));assert(action._my_friend_native_range and action.invobject==staff)
        F.perform(inst);assert(casts==1 and s.jobs[accepted.action_id].status=="completed")
    end
end)
Test("equipped-on-target requires actual hand equipment; losing a carried item invalidates execution",function()
    local inst,p,s=F.setup();local item=F.item("staff",inst);F.armor(item,"hands");local target=F.entity("pigman",2)
    local cast=Action("CASTSPELL");item.CollectActions=function(_,mode,doer,t,out)if mode=="EQUIPPED"then out[#out+1]=cast end end
    local args={item=Handle(s,item),target=Handle(s,target),mode="EQUIPPED",action="CASTSPELL"}
    assert(F.call(inst,p,"query_actions",args).result.requires_hand_equipment)
    assert(F.call(inst,p,"perform_action",args).reason=="native_action_unavailable")
    item.equipped="hands";local accepted=F.call(inst,p,"perform_action",args);local action=assert(API.GetAction(inst))
    item.owner=nil;assert(not action:IsValid());action:Fail()
    assert(s.jobs[accepted.action_id].status=="failed")
end)
Test("scene right clicks execute only currently advertised actions",function()
    local inst,p,s=F.setup();local target=F.entity("machine",2);local used=0;local toggle=Action("CUSTOM_TOGGLE",function()used=used+1;return true end)
    target.CollectActions=function(_,mode,doer,out,right)if mode=="SCENE" and right then out[#out+1]=toggle end end
    local args={target=Handle(s,target),action="CUSTOM_TOGGLE"}
    assert(F.call(inst,p,"query_actions",args).result.actions[1].mode=="SCENE")
    local accepted=F.call(inst,p,"interact",args);F.perform(inst)
    assert(s.jobs[accepted.action_id].status=="completed" and used==1)
    assert(F.call(inst,p,"perform_action",{target=Handle(s,target),mode="SCENE",action="NOT_REGISTERED"}).reason=="native_action_unavailable")
end)
Test("nonurgent remembered summer shade does not block work, genuine temperature danger still does",function()
    local inst,p,s=F.setup();inst.components.temperature={GetCurrent=function()return 65 end}
    local shade=true
    package.loaded.my_friend_survival_ai={NeedsTemperatureHelp=function()return true end,IsShadeComfortOnly=function()return shade end}
    API.Score(inst,{thermal=true,thermal_shade=true})
    assert(not API.Blocked(inst,s) and not API.Observation.Snapshot(inst,s).emergency)
    shade=false;API.Score(inst,{thermal=true,thermal_shade=false})
    assert(API.Blocked(inst,s) and API.Observation.Snapshot(inst,s).blockers[1]=="temperature")
end)
Test("one target HAMMER continues until destruction without intermediate terminal receipts",function()
    local inst,p,s=F.setup();local building=F.entity("wall",3);building.left=3
    building.components.workable={CanBeWorked=function()return building.left>0 end,GetWorkAction=function()return ACTIONS.HAMMER end}
    building.IsActionValid=function(_,kind,right)return kind==ACTIONS.HAMMER and right end
    ACTIONS.HAMMER.fn=function()building.left=building.left-1;if building.left==0 then building.valid=false end;return true end
    local hammer=F.item("hammer",inst);F.armor(hammer,"hands");hammer.tool_action=ACTIONS.HAMMER;hammer.equipped="hands"
    local nav=require("my_friend_navigation")
    local old_distance,old_base,old_visible=nav.ArrivalDistance,package.loaded.my_friend_base_ai,CanEntitySeeTarget
    nav.ArrivalDistance=function()return 2 end
    package.loaded.my_friend_base_ai={CanUseHandToolInCurrentLight=function()return true end}
    CanEntitySeeTarget=function()return true end
    local accepted=F.call(inst,p,"work",{target=Handle(s,building),action="HAMMER"})
    local repeat_work=require("my_friend_body_actions").RepeatWork
    local previous=F.perform(inst)
    local x=building.x
    building.x=x+5
    assert(repeat_work(inst,previous)==nil and s.active.action==nil)
    building.x=x
    s.active.cancel_requested=true
    assert(repeat_work(inst,previous)==nil and s.active.action==nil)
    s.active.cancel_requested=nil
    for _=2,3 do
        local next_swing=assert(repeat_work(inst,previous))
        assert(next_swing~=previous and next_swing._body_job==previous._body_job)
        assert(F.perform(inst)==next_swing and s.jobs[accepted.action_id].status~="completed")
        previous=next_swing
    end
    assert(repeat_work(inst,previous)==nil)
    nav.ArrivalDistance,package.loaded.my_friend_base_ai,CanEntitySeeTarget=old_distance,old_base,old_visible
    API.GetAction(inst);local job=s.jobs[accepted.action_id]
    assert(job.status=="completed" and job.result.work_units==3)
    local terminals=0;for _,e in ipairs(s.events)do if e.action_id==job.id and e.status=="completed"then terminals=terminals+1 end end
    assert(terminals==1)
end)
Test("assistant input omits a name while public input still requires it",function()
    local inst,p,s=F.setup();s.ready=true
    assert(not API.Input(inst,p,"你好",nil,true))
    assert(API.Input(inst,p,"你好","assistant-1",false))
end)
Test("native point effects return soil handles for immediate entity planting",function()
 local inst,p,s=F.setup();local hoe=F.item("hoe",inst);local seed=F.item("seeds",inst)
 local soil
 local till=Action("TILL",function() soil=F.entity("farm_soil",4);soil.tags.soil=true;return true end)
 local plant=Action("PLANTSOIL",function(a) assert(a.target==soil);soil.valid=false;return true end)
 hoe.CollectActions=function(_,mode,doer,point,actions)if mode=="POINT"then actions[#actions+1]=till end end
 seed.CollectActions=function(_,mode,doer,target,actions)if mode=="USEITEM" and target==soil then actions[#actions+1]=plant end end
 TheSim.FindEntities=function()return soil~=nil and soil.valid and {soil} or {} end
 local r=F.call(inst,p,"perform_action",{item=Handle(s,hoe),mode="POINT",position={x=4,z=0},action="TILL"})
 F.perform(inst)
 assert(s.jobs[r.action_id].result.entities[1].prefab=="farm_soil")
 local observed=F.call(inst,p,"query_batch",{queries={{skill="observe",arguments={scope="nearby",filter="farm_soil"}}}})
 assert(observed.result.results[1].result.entities[1].soil)
 local q=F.call(inst,p,"query_actions",{item=Handle(s,seed),position={x=4,z=0}})
 assert(q.result.target==Handle(s,soil) and q.result.actions[1].action=="PLANTSOIL")
 r=F.call(inst,p,"perform_action",{item=Handle(s,seed),mode="USEITEM",position={x=4,z=0},action="PLANTSOIL"})
 F.perform(inst);assert(s.jobs[r.action_id].status=="completed" and not soil.valid)
end)
Test("native effect scans surround execution and do not run when constructing the route",function()
 local inst,p,s=F.setup()
 local hoe=F.item("hoe",inst)
 local created,scans
 scans=0
 local till=Action("TILL",function() created=F.entity("farm_soil",4);return true end)
 hoe.CollectActions=function(_,mode,_,_,actions)if mode=="POINT"then actions[#actions+1]=till end end
 TheSim.FindEntities=function(_,_,_,_,radius)
  if radius==2 then scans=scans+1 end
  return created~=nil and {created} or {}
 end
 local old=BufferedAction
 BufferedAction=function(...)
  local action=old(...)
  function action:Do() return self.action.fn(self) end
  return action
 end
 local result=F.call(inst,p,"perform_action",{item=Handle(s,hoe),mode="POINT",position={x=4,z=0},action="TILL"})
 local action=assert(API.GetAction(inst))
 BufferedAction=old
 assert(scans==0 and action:Do() and scans==1)
 for _,fn in ipairs(action.successes)do fn()end
 assert(scans==2 and s.jobs[result.action_id].result.entities[1].prefab=="farm_soil")
end)
Test("heavy pickup uses the original carry controller for the exact selected object",function()
 local inst,p,s=F.setup()
 package.loaded.my_friend_riding.GetBeefalo=function()return nil end
 package.loaded.my_friend_navigation.IsBlocked=function()return false end
 local other=F.item("chesspiece_rook",nil);other.tags.heavy=true;F.armor(other,"body");other.x=1
 local target=F.item("chesspiece_bishop",nil);target.tags.heavy=true;F.armor(target,"body");target.x=5
 target.components.equippable.IsRestricted=function()return false end
 other.components.equippable.IsRestricted=function()return false end
 local original=ACTIONS.PICKUP.fn
 local equips=0
 ACTIONS.PICKUP.fn=function(a) a.target.owner=a.doer;a.target.equipped="body";return true end
 inst.components.inventory.Equip=function()equips=equips+1;return true end
 local r=F.call(inst,p,"pickup",{target=Handle(s,target)})
 F.perform(inst);API.GetAction(inst)
 local result=s.jobs[r.action_id]
 assert(result.status=="completed" and result.result.carrying and result.result.items[1].heavy)
 assert(target.owner==inst and other.owner==nil and equips==0)
 assert(inst._my_friend_command.id=="carry_statue" and inst._my_friend_command.phase=="carrying")
 local second=F.call(inst,p,"pickup",{target=Handle(s,other)})
 assert(second.reason=="already_carrying_heavy")
 assert(F.call(inst,p,"pickup_many",{targets={Handle(s,other)}}).reason=="heavy_requires_single_pickup")
 local transport=F.call(inst,p,"execute_sequence",{steps={
  {id="move",skill="move_to",arguments={position={x=9,z=0}}},
  {id="release",skill="drop",arguments={item=Handle(s,target),position={x=9,z=0}}}}})
 for _=1,8 do F.perform(inst)end
 assert(s.jobs[transport.action_id].status=="completed" and target.owner==nil and target.x==9)
 ACTIONS.PICKUP.fn=original
end)
Test("a sequence-owned carry command remains authorized while not following",function()
 local inst,p,state=F.setup();inst.components.follower.GetLeader=function()return nil end
 local file=assert(io.open("scripts/my_friend_commands.lua","rb"));local text=file:read("*a"):gsub("\r","");file:close()
 local body=assert(text:match("function M.Get%(friend%)(.-)\nend"))
 local get=assert(loadstring('local Policy={IsLocalPlayer=function(p)return p.isplayer end,GetLeader=function()return nil end};local SpecialCommands={IsPublic=function()return false end};local M={Clear=function(f)f._my_friend_command=nil end};return function(friend)'..body..' end'))()
 local command={id="carry_statue",player=p,deadline=GetTime()+120}
 inst._my_friend_command=command;state.active={child={command=command}}
 assert(get(inst)==command and inst._my_friend_command==command)
 state.active=nil;assert(get(inst)==nil)
end)
print(passed.." native body interface tests passed")
