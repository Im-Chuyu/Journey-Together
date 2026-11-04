-- Two authoritative shard contexts; native save/rollback are stubs, never a real world.
package.path="./scripts/?.lua;../yuanma/scripts/?.lua;"..package.path
local function Read(path)local f=assert(io.open(path,"rb"));local s=f:read("*a"):gsub("\r","");f:close();return s end
local f=assert(loadstring(assert(Read("tests/body_api_test.lua"):match("^(.-)local passed = 0"))
    .."\nreturn {setup=Setup,entity=Entity,perform=Perform,advance=function(n)now=now+n end}"))()
local API=require("my_friend_body_api")
local Relay=require("my_friend_body_chat")
local json=require("json")
local handlers,packets={},{}
local function Network(world,players,admin)
    return {world=world,players=players,net={GetClientTableForUser=function(_,id)return {admin=admin and id==players[1].userid or false}end}}
end
local function Switch(env)TheWorld,AllPlayers,TheNet=env.world,env.players,env.net end
local function Setup(admin)
    local inst,p,state=f.setup();state.ready=true;ThePlayer=nil;packets={}
    TheWorld.ismastershard=false;TheWorld.shard="2"
    local dest=Network(TheWorld,AllPlayers,true)
    local world=f.entity("surface");world.ismastersim,world.ismastershard,world.shard=true,true,"1"
    local guest=f.entity("wickerbottom",100);guest.userid="KU_SURFACE";guest.isplayer=true
    local origin=Network(world,{guest},admin)
    Shard_IsWorldAvailable=function(id)return id=="1" or id=="2"end
    Shard_GetConnectedShards=function()return {[TheWorld.shard=="1" and "2" or "1"]={}}end
    Relay.Install({AddShardModRPCHandler=function(_,name,fn)handlers[name]=fn end,
        GetShardModRPC=function(_,name)return name end,
        SendModRPCToShard=function(name,shards,payload)packets[#packets+1]={name=name,shards=shards,payload=payload,source=TheWorld.shard}end})
    Switch(dest)
    return inst,p,state,guest,origin,dest
end
local function Receive(packet,env)Switch(env);handlers[packet.name](packet.source,packet.payload)end
local function Forward(guest,origin,dest,text)
    Switch(origin);assert(Relay.Forward(guest,text or "温蒂，你好","rpc"));local packet=packets[#packets]
    Receive(packet,dest);return packet
end
local function Input(state)for n=#state.events,1,-1 do if state.events[n].kind=="player_input"then return state.events[n]end end end
local function Call(inst,p,event,id,skill,args)return API.Call(inst,p,id,skill,args or {},0,"user",nil,event.turn_id)end
local passed=0
local function Test(name,fn)fn();passed=passed+1;print("PASS "..name)end
Test("surface public speech reaches a cave companion once with actual remote identity and stats",function()
    local inst,p,state,guest,origin,dest=Setup(false)
    guest.components.health={currenthealth=31,maxhealth=150}
    local packet=Forward(guest,origin,dest)
    local event=assert(Input(state))
    assert(event.speaker.userid==guest.userid and event.speaker.health==31 and event.speaker.same_shard==false)
    assert(event.speaker.handle==nil and event.speaker.position==nil and not event.can_work)
    local count=#state.events;Receive(packet,dest);assert(#state.events==count)
    assert(Call(inst,p,event,"remote-say","say",{text="你好。",speak=false}).status=="completed")
    assert(Call(inst,p,event,"remote-work","move_to",{position={x=2,z=0}}).reason=="leader_only_work")
end)
Test("independent companion can perform physical work requested on another shard",function()
    local inst,p,state,guest,origin,dest=Setup(false)
    inst.components.follower.GetLeader=function()return nil end
    Forward(guest,origin,dest,"温蒂，向前走两步")
    local event=assert(Input(state));assert(event.can_work)
    local accepted=Call(inst,p,event,"remote-move","move_to",{position={x=2,z=0}})
    assert(accepted.status=="accepted" and state.active.issuer._my_friend_remote_speaker)
    f.perform(inst);assert(state.jobs[accepted.action_id].status=="completed" and inst.x==2)
    assert(Call(inst,p,event,"remote-follow","follow",{}).reason=="speaker_in_other_shard")
end)
Test("speaker departure interrupts their work without closing the room assistant",function()
    local inst,p,state,guest,origin,dest=Setup(false)
    inst.components.follower.GetLeader=function()return nil end
    Forward(guest,origin,dest);local event=Input(state)
    local accepted=Call(inst,p,event,"departing-work","move_to",{position={x=2,z=0}})
    Switch(origin);guest:PushEvent("onremove");Receive(packets[#packets],dest)
    API.Tick(inst)
    assert(state.jobs[accepted.action_id].status=="interrupted" and API.Valid(inst)==state)
    assert(Call(inst,p,event,"departed-speech","say",{text="x"}).reason=="speaker_left")
end)
Test("remote world request asks the actual speaker why instead of borrowing helper authority",function()
    local inst,p,state,guest,origin,dest=Setup(false)
    Forward(guest,origin,dest);local event=Input(state)
    local accepted=Call(inst,p,event,"remote-review-rollback","rollback_game",{})
    Receive(packets[#packets],origin);Receive(packets[#packets],dest)
    assert(state.jobs[accepted.action_id].result.needs_reason)
    Switch(origin);assert(require("my_friend_body_world").Status(guest).pending_request~=nil);Switch(dest)
end)
Test("cross-shard reason reply permits one save and server RPC replay cannot duplicate it",function()
    local inst,p,state,guest,origin,dest=Setup(false)
    Forward(guest,origin,dest);local event=Input(state);local effects=0;c_save=function()effects=effects+1 end
    local accepted=Call(inst,p,event,"remote-save","save_game",{})
    Receive(packets[#packets],origin);Receive(packets[#packets],dest)
    assert(#origin.world.tasks==0 and effects==0)
    local approval=state.jobs[accepted.action_id].result.approval_id
    f.advance(1);local reason="温蒂，大家要下线了，保存一下进度"
    Forward(guest,origin,dest,reason);event=Input(state)
    accepted=Call(inst,p,event,"reviewed-remote-save","save_game",{approval_id=approval,reason=reason,approved=true,assessment="准备下线，保存进度合理"})
    local request=packets[#packets];Receive(request,origin);local reply=packets[#packets];Receive(request,origin)
    assert(#origin.world.tasks==1 and effects==0)
    origin.world.tasks[1].fn();assert(effects==1)
    Receive(reply,dest);assert(state.jobs[accepted.action_id].result.requested)
end)
Test("unaddressed and invalid shard messages never enter the model event queue",function()
    local inst,p,state,guest,origin,dest=Setup(false)
    local packet=Forward(guest,origin,dest,"只是房间里的普通聊天")
    assert(Input(state)==nil)
    local data=json.decode(packet.payload);data.text="温蒂，你好"
    handlers.BodyChat("not-connected",json.encode(data));assert(Input(state)==nil)
    handlers.BodyChat("1",string.rep("x",16001));assert(Input(state)==nil)
end)
Test("cross-shard game chat uses one native identity and deduplicates sender RPC/native echo",function()
    local inst,p,state,guest,origin,dest=Setup(false)
    package.loaded.my_friend_possess={GetCommandTarget=function()return nil end}
    local Chat=require("my_friend_chat")
    Switch(origin)
    assert(not Chat.Dispatch(guest,"温蒂，你好","rpc"))
    assert(not Chat.Dispatch(guest,"温蒂，你好","native"))
    assert(#packets==1)
    Receive(packets[1],dest);assert(Input(state).speaker.userid==guest.userid)
end)
Test("a cross-shard reply is delivered to its real speaker's chat notification once",function()
    local inst,p,state,guest,origin,dest=Setup(false)
    Forward(guest,origin,dest);local event=Input(state)
    assert(Call(inst,p,event,"reply-other-shard","say",{text="晚上好。",speak=false}).status=="completed")
    local reply=packets[#packets];assert(reply.name=="BodyChatSpeech" and reply.shards[1]=="1")
    local visible={};Networking_Announcement=function(text)visible[#visible+1]=text end;ThePlayer=guest
    Receive(reply,origin);Receive(reply,origin)
    assert(#visible==1 and visible[1]:find("晚上好。",1,true))
    Networking_Announcement=nil;ThePlayer=nil
end)
print(passed.." body shard chat tests passed")
