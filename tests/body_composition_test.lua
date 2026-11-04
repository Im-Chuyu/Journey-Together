package.path="./scripts/?.lua;../yuanma/scripts/?.lua;"..package.path
local file=assert(io.open("tests/body_api_test.lua","rb"));local text=file:read("*a"):gsub("\r","");file:close()
local F=assert(loadstring(assert(text:match("^(.-)local passed = 0"))..
 "\nreturn {setup=Setup,item=Item,entity=Entity,storage=Storage,armor=Armor,perform=Perform,call=Call,advance=function(n)now=now+n end}"))()
local API=require("my_friend_body_api")
local function H(s,e)return API.Observation.Handle(s,e)end
local function Drain(inst,n)
 for _=1,n or 60 do if inst._my_friend_body.active==nil then return end;F.perform(inst)end
 assert(inst._my_friend_body.active==nil,"composition did not finish")
end
local function Terminals(s,id)local n=0;for _,e in ipairs(s.events)do if e.action_id==id and ({completed=true,failed=true,cancelled=true,interrupted=true})[e.status]then n=n+1 end end;return n end
local function ToolRecipe()
 local original=GetValidRecipe
 GetValidRecipe=function(name)return name=="shovel" and {name="shovel",numtogive=1} or original(name)end
 ACTIONS.MY_FRIEND_BUILD.fn=function(a)
  local tool=F.item(a.recipe,a.doer);F.armor(tool,"hands");tool.tool_action=ACTIONS.DIG;return true
 end
end
local passed=0
local function Test(name,fn)fn();passed=passed+1;print("PASS "..name)end
Test("inventory, ground and container queries return in one receipt without observe throttling",function()
 local inst,p,s=F.setup();local tool=F.item("shovel",nil);tool.x=2
 local box=F.entity("treasurechest",3);F.storage(box,true);F.item("twigs",box,5)
 local native_scan,scans=TheSim.FindEntities,0
 TheSim.FindEntities=function(...)scans=scans+1;return native_scan(...)end
 local r=F.call(inst,p,"query_batch",{queries={
  {id="carried",skill="observe",arguments={scope="inventory"}},
  {id="ground",skill="observe",arguments={scope="items",filter="shovel"}},
  {id="boxes",skill="observe",arguments={scope="containers",contents=true}}}})
 assert(r.status=="completed" and #r.result.results==3 and Terminals(s,r.action_id)==1)
 assert(#r.result.results[1].result.entities==0 and r.result.results[2].result.entities[1].prefab=="shovel")
 assert(r.result.results[3].result.entities[1].contents[1].prefab=="twigs")
 assert(scans==1)
end)
Test("craft, reference its product, equip, dig to completion and return run without intermediate completion",function()
 local inst,p,s=F.setup();ToolRecipe();local grass=F.entity("grass",8);grass.left=2
 grass.components.workable={CanBeWorked=function()return grass.left>0 end,GetWorkAction=function()return ACTIONS.DIG end}
 ACTIONS.DIG.fn=function()grass.left=grass.left-1;return true end
 local r=F.call(inst,p,"execute_sequence",{steps={
  {id="tool",skill="craft",arguments={recipe="shovel"}},
  {id="wear",skill="equip",arguments={item="$tool.items.1.handle"}},
  {id="dig",skill="work",arguments={target=H(s,grass),action="DIG"}},
  {id="back",skill="move_to",arguments={target=H(s,p),distance=2}}}})
 F.perform(inst);assert(s.active~=nil and Terminals(s,r.action_id)==0)
 Drain(inst)
 local job=s.jobs[r.action_id];assert(job.status=="completed" and job.result.completed==4 and grass.left==0 and inst.x==p.x)
 assert(job.result.steps[1].result.items[1].prefab=="shovel" and Terminals(s,r.action_id)==1)
end)
Test("first failed step stops the sequence, preserving the already picked quantity for single-step fallback",function()
 local inst,p,s=F.setup();local item=F.item("twigs",nil,5);local target=F.entity("grass",3)
 target.components.workable={CanBeWorked=function()return true end,GetWorkAction=function()return ACTIONS.DIG end}
 local r=F.call(inst,p,"execute_sequence",{steps={
  {id="take",skill="pickup",arguments={target=H(s,item),count=2}},
  {id="dig",skill="work",arguments={target=H(s,target),action="DIG"}},
  {id="drop",skill="drop",arguments={item="$take.items.1.handle"}}}})
 Drain(inst)
 local job=s.jobs[r.action_id]
 assert(job.status=="failed" and job.reason=="missing_tool" and job.result.completed==1 and job.result.failed_step=="dig")
 assert(#job.result.steps==2 and job.result.steps[1].result.count==2 and item.size==3 and Terminals(s,r.action_id)==1)
end)
Test("busy cancellation returns partial progress; world operations and recursive sequences cannot be nested",function()
 local inst,p,s=F.setup();local item=F.item("twigs",nil,5)
 local r=F.call(inst,p,"execute_sequence",{steps={{id="take",skill="pickup",arguments={target=H(s,item)}},{id="walk",skill="move_to",arguments={position={x=5,z=0}}}}})
 F.perform(inst);inst.busy=true;F.call(inst,p,"cancel",{action_id=r.action_id})
 assert(s.active~=nil);inst.busy=false;API.Tick(inst)
 local job=s.jobs[r.action_id];assert(job.status=="cancelled" and job.result.completed==1 and job.child==nil)
 for _,skill in ipairs({"rollback_game","execute_sequence","query_batch"})do
  assert(F.call(inst,p,"execute_sequence",{steps={{id="no",skill=skill,arguments={}}}}).reason=="unsupported_sequence_step")
 end
end)
Test("bulk pickup can be composed as one step and references never run code",function()
 local inst,p,s=F.setup();local a,b=F.item("livinglog",nil,2),F.item("livinglog",nil,3)
 local r=F.call(inst,p,"execute_sequence",{steps={{id="loot",skill="pickup_many",arguments={targets={H(s,a),H(s,b)}}}}})
 Drain(inst);assert(s.jobs[r.action_id].result.steps[1].result.count==5 and Terminals(s,r.action_id)==1)
 r=F.call(inst,p,"execute_sequence",{steps={{id="no",skill="drop",arguments={item="$missing.items.1.handle"}}}})
 Drain(inst);assert(s.jobs[r.action_id].reason=="unresolved_result_reference")
end)
Test("drop routes to an actual point before dropping the chosen count",function()
 local inst,p,s=F.setup();local item=F.item("rocks",inst,6)
 local r=F.call(inst,p,"drop",{item=H(s,item),count=2,position={x=8,z=0}})
 F.perform(inst);assert(inst.x==8 and item.owner==inst and item.size==6)
 F.perform(inst);local job=s.jobs[r.action_id]
 assert(job.status=="completed" and job.result.count==2 and job.result.position.x==8 and item.size==4)
end)
Test("read steps can resolve produced item handles inside a sequence",function()
 local inst,p,s=F.setup();local item=F.item("twigs",inst,3)
 local r=F.call(inst,p,"execute_sequence",{steps={
  {id="view",skill="observe",arguments={scope="inventory",filter="twigs"}},
  {id="drop",skill="drop",arguments={item="$view.entities.1.handle",count=1}}}})
 Drain(inst);assert(s.jobs[r.action_id].result.completed==2 and item.size==2)
 local invalid=F.call(inst,p,"query_batch",{queries={{skill="observe",arguments={scope="not_a_scope"}}}})
 assert(invalid.result.results[1].status=="failed")
end)
Test("bounded repetition binds each value and isolates local result references",function()
 local inst,p,s=F.setup();local item=F.item("twigs",inst,4)
 local r=F.call(inst,p,"execute_sequence",{steps={{id="put",for_each={{x=4,z=0},{x=8,z=0}},steps={
  {id="view",skill="observe",arguments={scope="inventory",filter="twigs"}},
  {id="drop",skill="drop",arguments={item="$view.entities.1.handle",count=1,position="$each"}}
 }}}})
 Drain(inst)
 local result=s.jobs[r.action_id]
 assert(result.status=="completed" and result.result.completed==4 and item.size==2 and inst.x==8)
 assert(result.result.steps[1].id=="put_1_view" and result.result.steps[3].id=="put_2_view")
 assert(result.result.steps[1].reason==nil and result.result.steps[3].reason==nil)
 local bad=F.call(inst,p,"execute_sequence",{steps={{id="bad",for_each={{}},steps={
  {id="go",skill="move_to",arguments={position="$each.missing"}}
 }}}})
 assert(bad.status=="failed" and bad.reason=="invalid_each_reference")
end)
Test("latest recipe receipt retains all ingredient rows rather than silently truncating deficits",function()
 local ingredients={}
 for n=1,30 do ingredients[n]={prefab="material_"..n,name=string.rep("x",60),required=n,missing=n}end
 local result=require("my_friend_body_composition").Result({records={{id="recipe",skill="query_recipe",status="completed",
  result={recipe="complex_recipe",ingredients=ingredients,sources={{item="e1",count=2}}}}},completed=1,total=1})
 assert(#result.steps[1].result.ingredients==30 and result.steps[1].result.ingredients[30].missing==30)
end)
Test("large container batches preserve a nearby fridge instead of halving the entity list",function()
 local inst,p,state=F.setup()
 for n=1,12 do
  local chest=F.entity("treasurechest",n);F.storage(chest,true)
  for k=1,10 do F.item("twigs",chest,k)end
 end
 local fridge=F.entity("icebox",13);F.storage(fridge,true);F.item("meat",fridge,2)
 local result=F.call(inst,p,"query_batch",{queries={
  {id="food",skill="observe",arguments={scope="containers",contents=true}},
  {id="items",skill="observe",arguments={scope="items"}},
  {id="plants",skill="observe",arguments={scope="nearby",filter="absent"}}}})
 local scan=result.result.results[1].result
 assert(scan~=nil and scan.truncated and #scan.entities==13 and scan.matched==13)
 local found=false
 for _,entry in ipairs(scan.entities)do
  if entry.prefab=="icebox"then found=true;assert(entry.handle and entry.position.x==13)end
  if entry.contents_limited then assert(entry.contents_next_offset==entry.contents_offset+#entry.contents)end
 end
 assert(found and scan.contents_limited and scan.next_offset==nil and not scan.entities_limited)
 local focused=F.call(inst,p,"query_batch",{queries={{skill="observe",arguments={scope="containers",filter="icebox",contents=true}}}})
 local details=focused.result.results[1].result
 assert(#details.entities==1 and details.entities[1].contents[1].prefab=="meat")
 assert(details.entities[1].contents[1].count==2)
end)
Test("scan pagination returns later containers and marks compacted pages explicitly",function()
 local inst,p,state=F.setup()
 for n=1,40 do local box=F.entity("treasurechest",n*.2);F.storage(box,true)end
 local fridge=F.entity("icebox",9);F.storage(fridge,true)
 local a=API.Observation.Scan(inst,state,{scope="containers"})
 assert(#a.entities==40 and a.matched==41 and a.next_offset==40 and a.entities_limited)
 local b=API.Observation.Scan(inst,state,{scope="containers",offset=a.next_offset})
 assert(#b.entities==1 and b.entities[1].prefab=="icebox" and not b.limited and b.next_offset==nil)
 local small=require("my_friend_body_composition").LimitResult(a,1000)
 assert(small and small.returned==#small.entities and small.next_offset==small.returned)
 local c=API.Observation.Scan(inst,state,{scope="containers",offset=small.next_offset})
 assert(#c.entities>0 and c.entities[1].handle~=small.entities[1].handle)
 local bad=F.call(inst,p,"query_batch",{queries={{skill="observe",arguments={offset=-1}}}})
 assert(bad.result.results[1].status=="failed")
end)
Test("a container moving into range without an event is visible on the next query",function()
 local inst,p,state=F.setup()
 local fridge=F.entity("icebox",24);F.storage(fridge,true)
 local args={scope="containers",filter="icebox"}
 assert(API.Observation.Scan(inst,state,args).matched==0)
 fridge.x=18
 local result=API.Observation.Scan(inst,state,args)
 assert(result.matched==1 and result.entities[1].position.x==18)
 fridge.x=24
 assert(API.Observation.Scan(inst,state,args).matched==0)
end)
Test("large container contents continue by exact handle and respect current permissions",function()
 local inst,p,state=F.setup()
 local box=F.entity("treasurechest",4);local storage=F.storage(box,true)
 local other=F.entity("treasurechest",3);F.storage(other,true)
 for n=1,25 do F.item("stack_"..n,box) end
 local handle=API.Observation.Handle(state,box)
 TheSim.FindEntities=function()error("known container must not rescan nearby entities")end
 local args={scope="containers",container=handle,contents=true}
 local first=F.call(inst,p,"observe",args).result.entities[1]
 assert(first.handle==handle and #first.contents==20 and first.contents_next_offset==20)
 args.contents_offset=first.contents_next_offset
 local query={queries={{skill="observe",arguments=args}}}
 local second=F.call(inst,p,"query_batch",query).result.results[1].result.entities[1]
 assert(second.handle==handle and second.contents_matched==25 and #second.contents==5)
 assert(second.contents[1].prefab=="stack_21" and second.contents_next_offset==nil)
 storage.restricted=true
 local locked=F.call(inst,p,"query_batch",query).result.results[1].result.entities[1]
 assert(not locked.accessible and locked.contents==nil)
 box.x=22
 local far=F.call(inst,p,"query_batch",query).result.results[1].result
 assert(far.matched==0 and #far.entities==0)
end)
Test("later pages in a large read batch do not invalidate the first visible handle",function()
 local inst,p,state=F.setup()
 local queries={}
 for group=1,6 do
  local filter="group_"..group.."_"
  for n=1,40 do F.item(filter..n,nil).x=2 end
  queries[group]={skill="observe",arguments={scope="items",filter=filter}}
 end
 local result=F.call(inst,p,"query_batch",{queries=queries}).result
 local first=result.results[1].result.entities[1]
 assert(state.handle_serial>=240 and API.Observation.Resolve(state,first.handle)~=nil)
end)
print(passed.." composition tests passed")
