-- Use the user's unpacked native OldAger, actual damage listener and retreat module.
package.path="./scripts/?.lua;../yuanma/scripts/?.lua;"..package.path
local function Read(path)local f=assert(io.open(path,"rb"));local s=f:read("*a"):gsub("\r","");f:close();return s end
local F=assert(loadstring(assert(Read("tests/body_api_test.lua"):match("^(.-)local passed = 0"))..
 "\nreturn {setup=Setup,advance=function(n)now=now+n end}"))()
require("class")
local OldAger=assert(loadfile("../yuanma/scripts/components/oldager.lua"))()
local Health=require("my_friend_health")
local AI=assert(loadfile("scripts/my_friend_behavior_ai.lua"))()
package.loaded.my_friend_behavior_ai=AI
local API=require("my_friend_body_api")
local listener_source=assert(Read("modmain.lua"):match('inst:ListenForEvent%("healthdelta", function%(_, data%)(.-)\n    end%)'))
local equipment_hits=0
package.loaded.my_friend_equipment={Hurt=function()equipment_hits=equipment_hits+1 end}
local listener=assert(loadstring("return function(inst) return function(_,data)"..listener_source.."\nend end"))()
local passed=0
local function Test(name,fn)fn();passed=passed+1;print("PASS "..name)end
Test("normal native aging never becomes a damaging ground area or equipment injury",function()
 local inst,p,state=F.setup();inst.prefab="wanda";equipment_hits=0
 TUNING=TUNING or {};TUNING.WANDA_MAX_YEARS_OLD=80
 inst.StartUpdatingComponent=function()end;inst.components.oldager=OldAger(inst)
 local hp=inst.components.health;hp.currenthealth=60
 hp.GetMaxWithPenalty=function()return 60 end
 hp.DoDelta=function(_,amount,overtime,cause)
  hp.currenthealth=hp.currenthealth+amount
  inst:PushEvent("healthdelta",{amount=amount,overtime=overtime,cause=cause})
 end
 inst:ListenForEvent("healthdelta",listener(inst))
 for n=1,3 do F.advance(40);inst.components.oldager:OnUpdate(40)end
 assert(hp.currenthealth==57 and equipment_hits==0)
 assert(inst._my_friend_hazard_position==nil and inst._my_friend_hurt_until==nil and inst._my_friend_hurt_evade_until==nil)
 local snapshot=API.Observation.Snapshot(inst,state)
 assert(snapshot.health_kind=="remaining_lifespan" and snapshot.age==23 and not snapshot.emergency)
 assert(not Health.IsAgeDisplayDelta({components={}}, {cause="oldager_component"}))
end)
Test("actual environmental damage still starts hazard retreat for Wanda",function()
 local inst,p,state=F.setup();inst.prefab="wanda";inst.components.oldager={};equipment_hits=0
 package.loaded.my_friend_container_ai={Cancel=function()end}
 listener(inst)(inst,{amount=-10,cause="sporecloud"})
 assert(equipment_hits==1 and inst._my_friend_hazard_position~=nil)
 assert(inst._my_friend_hurt_until>GetTime())
 assert(API.Blocked(inst,state))
end)
Test("renaming metadata does not replace the actual prefab or ordinary health semantics",function()
 local inst,p,state=F.setup();inst._my_friend_custom_name="妹妹"
 inst.GetDisplayName=function()return "妹妹"end
 local s=API.Observation.Snapshot(inst,state)
 assert(s.name=="妹妹" and s.custom_name=="妹妹" and s.renamed and s.character.id=="wendy" and s.health_kind=="health")
end)
print(passed.." age and naming tests passed")
