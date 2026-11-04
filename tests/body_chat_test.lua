-- Actual public chat routing, names, native speaker binding and authority checks.
package.path = "./scripts/?.lua;../yuanma/scripts/?.lua;" .. package.path
local function Read(path) local f=assert(io.open(path,"rb")); local s=f:read("*a"):gsub("\r",""); f:close(); return s end
local fixture=assert(loadstring(assert(Read("tests/body_api_test.lua"):match("^(.-)local passed = 0"))
    .. "\nreturn {setup=Setup,entity=Entity,call=Call,perform=Perform,advance=function(n)now=now+n end}"))()
package.loaded.my_friend_possess={GetCommandTarget=function()return nil end}
local API=require("my_friend_body_api")
local Chat=require("my_friend_chat")
local Commands=package.loaded.my_friend_commands
local original_calls=0
Commands.Dispatch=function()original_calls=original_calls+1; return true end
local function Setup()
    local inst,p,state=fixture.setup(); state.ready=true; original_calls=0
    ThePlayer=nil; TheNet=nil
    local other=fixture.entity("wickerbottom",100); other.userid="KU_other"; other.isplayer=true
    AllPlayers[#AllPlayers+1]=other
    return inst,p,state,other
end
local function LastInput(state)
    for n=#state.events,1,-1 do if state.events[n].kind=="player_input" then return state.events[n] end end
end
local function Bound(inst,transport,event,id,skill,args)
    return API.Call(inst,transport,id,skill,args or {},inst._my_friend_body.revision,"user",nil,event.turn_id)
end
local passed=0
local function Test(name,fn)fn(); passed=passed+1; print("PASS "..name)end
Test("connected public chat requires a known name and accepts any online player outside leader range",function()
    local inst,p,state,other=Setup()
    assert(not Chat.Dispatch(other,"你好啊","rpc") and #state.events==0 and original_calls==0)
    assert(Chat.Dispatch(other,"温蒂，你身上有什么？","rpc"))
    local event=assert(LastInput(state))
    assert(event.speaker.userid==other.userid and event.speaker.character.id=="wickerbottom" and not event.can_work)
    assert(state.owner==p and original_calls==0)
    assert(Bound(inst,p,event,"other-talk","say",{text="带着草。",speak=false}).status=="completed")
    assert(Bound(inst,p,event,"other-move","move_to",{position={x=2,z=0}}).reason=="leader_only_work")
    assert(Bound(inst,p,event,"other-cancel","cancel",{action_id="none"}).reason=="leader_only_work")
end)
Test("native and sender RPC copies forward only one model input; custom names also work",function()
    local inst,p,state=Setup(); inst._my_friend_custom_name="小温"
    assert(Chat.Dispatch(p,"小温，去捡东西","rpc"))
    assert(not Chat.Dispatch(p,"小温，去捡东西","native"))
    local inputs=0; for _,e in ipairs(state.events)do if e.kind=="player_input" then inputs=inputs+1 end end
    assert(inputs==1 and LastInput(state).can_work and original_calls==0)
end)
Test("listen host chat dispatches locally and still deduplicates the native copy", function()
    local inst, player, state = Setup()
    ThePlayer = player
    SendModRPCToServer = function() error("listen host sent an RPC to itself") end
    assert(Chat.Forward(player, "温蒂，你好", "input"))
    assert(not Chat.Dispatch(player, "温蒂，你好", "native"))
    local inputs = 0
    for _, event in ipairs(state.events) do
        if event.kind == "player_input" then inputs = inputs + 1 end
    end
    assert(inputs == 1 and LastInput(state).speaker.userid == player.userid and LastInput(state).speaker.same_shard == true)
    SendModRPCToServer = nil
end)
Test("disconnected and not-yet-ready transports retain exactly the original dispatch path",function()
    local inst,p,state=Setup(); state.ready=false
    assert(Chat.Dispatch(p,"旧指令","rpc") and original_calls==1)
    API.Close(inst,"done")
    assert(Chat.Dispatch(p,"原来的回答","rpc") and original_calls==2)
end)
Test("idle companion accepts another player's physical work and leader changes preserve transport",function()
    local inst,p,state,other=Setup()
    inst.components.follower.GetLeader=function()return nil end
    assert(Chat.Dispatch(other,"温蒂，跑到这里","rpc"))
    local event=LastInput(state); assert(event.can_work)
    local accepted=Bound(inst,p,event,"free-work","move_to",{position={x=3,z=0}})
    assert(accepted.status=="accepted" and state.active.issuer==other)
    inst.busy=true; inst.components.follower.GetLeader=function()return p end
    API.Tick(inst)
    assert(state.active.cancel_requested and API.Valid(inst)==state)
    inst.busy=false; API.Tick(inst)
    assert(state.jobs[accepted.action_id].status=="interrupted" and state.jobs[accepted.action_id].reason=="speaker_permission_changed")
    assert(API.Valid(inst)==state)
end)
Test("forged contexts and departed speakers cannot borrow the helper owner's authority",function()
    local inst,p,state,other=Setup()
    assert(API.Call(inst,p,"fake","say",{text="x"},0,"user",nil,"forged").reason=="invalid_input_context")
    assert(Chat.Dispatch(other,"温蒂，晚上好","rpc")); local event=LastInput(state)
    AllPlayers={p}
    assert(Bound(inst,p,event,"departed","say",{text="x"}).reason=="speaker_left")
end)
Test("world reason requests bind to the actual public speaker without granting companion work",function()
    local inst,p,state,other=Setup()
    TheNet={GetClientTableForUser=function(_,id)return {userid=id,admin=id==p.userid}end}
    assert(Chat.Dispatch(other,"温蒂，回档","rpc"));local event=LastInput(state)
    local review=Bound(inst,p,event,"request-rollback","rollback_game",{})
    assert(review.result.needs_reason and not review.result.requested)
    assert(require("my_friend_body_world").Status(other).pending_request.approval_id==review.result.approval_id)
    assert(require("my_friend_body_world").Status(p).pending_request==nil)
    assert(Bound(inst,p,event,"still-no-work","craft",{recipe="spear"}).reason=="leader_only_work")
end)
Test("speaker contexts are bounded and an idle transport connects without following or proximity",function()
    local inst,p,state,other=Setup()
    API.Close(inst,"setup"); inst.components.follower.GetLeader=function()return nil end; p.x=100
    state=assert(API.Open(inst,p)); state.ready=true
    for n=1,70 do fixture.advance(.6); assert(API.Input(inst,p,"wendy hi")) end
    local count=0; for _ in pairs(state.inputs)do count=count+1 end
    assert(count==64 and #state.input_order==64 and API.Valid(inst)==state)
end)
print(passed.." body chat tests passed")
