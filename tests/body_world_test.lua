-- World operations are stubbed: never save, roll back or moderate a live server.
package.path="./scripts/?.lua;../yuanma/scripts/?.lua;"..package.path
local function Read(path)local f=assert(io.open(path,"rb"));local s=f:read("*a"):gsub("\r","");f:close();return s end
local F=assert(loadstring(assert(Read("tests/body_api_test.lua"):match("^(.-)local passed = 0"))..
 "\nreturn {setup=Setup,entity=Entity,advance=function(n)now=now+n end}"))()
local API,World=require("my_friend_body_api"),require("my_friend_body_world")
local serial=0
local function Setup()
 local inst,p,s=F.setup();s.ready=true;ThePlayer=nil
 local clients,effects={[p.userid]={userid=p.userid,name="caller",admin=false}},{}
 TheNet={GetClientTableForUser=function(_,id)return clients[id]end,GetClientTable=function()local out={};for _,c in pairs(clients)do out[#out+1]=c end;return out end,
  Kick=function(_,id)effects[#effects+1]={"kick",id}end,Ban=function(_,id)effects[#effects+1]={"ban",id}end,
  SetServerPaused=function(_,paused)effects[#effects+1]={"pause",paused}end}
 c_save=function()effects[#effects+1]={"save"}end;c_rollback=function(n)effects[#effects+1]={"rollback",n}end
 return inst,p,s,clients,effects
end
local function Input(inst,p,text)
 F.advance(1);assert(API.Input(inst,p,text,nil,false));return inst._my_friend_body.input_order[#inst._my_friend_body.input_order]
end
local function Call(inst,p,turn,skill,args)
 serial=serial+1;return API.Call(inst,p,"review:"..serial,skill,args or {},nil,"user",nil,turn)
end
local function Followup(inst,p,request,text,skill,args,approved)
 local out={};for k,v in pairs(args or {})do out[k]=v end
 out.approval_id=request.result.approval_id;out.reason=text;out.approved=approved~=false;out.assessment="玩家解释清楚，模型已判断理由。"
 return Call(inst,p,Input(inst,p,text),skill,out),out
end
local passed=0
local function Test(name,fn)fn();passed=passed+1;print("PASS "..name)end
Test("even saves require a second real message; same-turn or fabricated reasons cannot execute",function()
 local inst,p,s,clients,effects=Setup();local turn=Input(inst,p,"保存游戏")
 local first=Call(inst,p,turn,"save_game",{})
 assert(first.result.needs_reason and not first.result.requested and #TheWorld.tasks==0)
 local fake={approval_id=first.result.approval_id,reason="保存游戏",approved=true,assessment="合理"}
 assert(Call(inst,p,turn,"save_game",fake).reason=="reason_requires_next_player_message")
 fake.reason="编造的理由";assert(Call(inst,p,Input(inst,p,"因为准备离开"),"save_game",fake).reason=="reason_review_required")
 local final=Followup(inst,p,first,"马上要离开，先保存进度","save_game")
 assert(final.result.requested and #effects==0)
 TheWorld.tasks[#TheWorld.tasks].fn();assert(#effects==1 and effects[1][1]=="save")
end)
Test("ordinary nonadmin can request rollback after model reason review, replay cannot repeat it",function()
 local inst,p,s,clients,effects=Setup()
 local first=Call(inst,p,Input(inst,p,"回档两次"),"rollback_game",{count=2})
 assert(first.result.needs_reason and World.Status(p).pending_request.count==2)
 local final,args=Followup(inst,p,first,"刚才服务器卡顿误操作烧掉基地，大家同意恢复","rollback_game",{count=2})
 assert(final.result.requested and not clients[p.userid].admin)
 local again=Call(inst,p,s.input_order[#s.input_order],"rollback_game",args)
 assert(again.reason=="approval_expired")
 TheWorld.tasks[#TheWorld.tasks].fn();assert(#effects==1 and effects[1][1]=="rollback" and effects[1][2]==2)
end)
Test("pause false remains false, rejected reasons do not schedule effects",function()
 local inst,p,s,clients,effects=Setup()
 local first=Call(inst,p,Input(inst,p,"恢复游戏"),"pause_game",{paused=false})
 local final=Followup(inst,p,first,"大家准备好了，继续游戏","pause_game",{paused=false})
 assert(final.result.paused==false);TheWorld.tasks[#TheWorld.tasks].fn();assert(effects[1][2]==false)
 first=Call(inst,p,Input(inst,p,"暂停"),"pause_game",{})
 final=Followup(inst,p,first,"只是想捣乱","pause_game",{},false)
 assert(final.result.rejected and not final.result.requested and #effects==1)
end)
Test("kick and ban use exact online userid and require their own reason conversation",function()
 for _,skill in ipairs({"kick_player","ban_player"})do
  local inst,p,s,clients,effects=Setup();clients.KU_target={userid="KU_target",name="target"}
  local first=Call(inst,p,Input(inst,p,"处理破坏基地的玩家"),skill,{userid="KU_target"})
  assert(first.result.needs_reason and #effects==0)
  local final=Followup(inst,p,first,"对方反复烧毁队友建筑，劝阻后仍继续破坏",skill,{userid="KU_target"})
  assert(final.result.requested);TheWorld.tasks[#TheWorld.tasks].fn()
  assert(#effects==1 and effects[1][1]==(skill=="kick_player" and "kick" or "ban") and effects[1][2]=="KU_target")
 end
end)
Test("expired, altered or another player's challenge cannot be used",function()
 local inst,p,s,clients,effects=Setup()
 local first=Call(inst,p,Input(inst,p,"回档两次"),"rollback_game",{count=2})
 assert(Followup(inst,p,first,"改成三次","rollback_game",{count=3}).reason=="approval_mismatch")
 F.advance(301);assert(Followup(inst,p,first,"需要恢复基地","rollback_game",{count=2}).reason=="approval_expired")
 assert(Call(inst,p,nil,"save_game",{}).reason=="world_reason_dialogue_required")
 assert(Call(inst,p,Input(inst,p,"授权"),"set_world_permission",{userid=p.userid,allowed=true}).reason=="invalid_request")
 assert(#effects==0)
end)
Test("paused simulation still accepts the next reason using the static clock",function()
 local inst,p,s,clients,effects=Setup();local static=1000;GetStaticTime=function()return static end
 local first=Call(inst,p,Input(inst,p,"恢复游戏"),"pause_game",{paused=false})
 static=1001
 local final=Followup(inst,p,first,"大家准备好了，可以继续","pause_game",{paused=false})
 assert(final.result.requested and final.result.paused==false)
 GetStaticTime=nil
end)
Test("old administrator grants are ignored and no grants or challenges enter world saves",function()
 local inst,p,s,clients,effects=Setup();TheWorld._my_friend_model_permissions={[p.userid]=true}
 local status=World.Status(p);assert(status.mode=="reason_review" and status.grant==nil and status.players[1].userid==p.userid)
 local mod=Read("modmain.lua");assert(not mod:find("data.my_friend_model_permissions =",1,true))
 assert(not mod:find("data.my_friend_world_dialogues",1,true))
end)
Test("cave reason review goes through the master and exposes the pending request back on the cave",function()
 local inst,p,s,clients,effects=Setup();local cave=TheWorld;cave.ismastershard=false
 local master=F.entity("master");master.ismastersim,master.ismastershard=true,true
 local handlers,packets={},{}
 SHARDID={MASTER="1"};Shard_IsWorldAvailable=function()return true end
 World.Install({AddShardModRPCHandler=function(_,name,fn)handlers[name]=fn end,GetShardModRPC=function(_,name)return name end,
  SendModRPCToShard=function(name,targets,payload)packets[#packets+1]={name=name,payload=payload}end})
 local first=Call(inst,p,Input(inst,p,"回档一次"),"rollback_game",{})
 local request=packets[#packets];assert(request.name=="BodyWorldRequest")
 TheWorld=master;handlers.BodyWorldRequest("2",request.payload);local reply=packets[#packets]
 TheWorld=cave;handlers.BodyWorldReply("1",reply.payload)
 local approval=World.Status(p).pending_request.approval_id;assert(approval and s.jobs[first.action_id].result.needs_reason)
 local second=Followup(inst,p,s.jobs[first.action_id],"保存后的误操作毁了基地，大家同意恢复","rollback_game",{})
 request=packets[#packets];TheWorld=master;handlers.BodyWorldRequest("2",request.payload);reply=packets[#packets]
 handlers.BodyWorldRequest("2",request.payload);assert(#master.tasks==1)
 master.tasks[1].fn();assert(#effects==1 and effects[1][1]=="rollback")
 TheWorld=cave;handlers.BodyWorldReply("1",reply.payload)
 assert(s.jobs[second.action_id].result.requested and World.Status(p).pending_request==nil)
end)
print(passed.." world reason-review tests passed")
