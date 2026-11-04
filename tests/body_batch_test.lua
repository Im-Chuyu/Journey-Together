-- Real batch parent/child API and inventory actions; no model round trips between targets.
package.path = "./scripts/?.lua;../yuanma/scripts/?.lua;" .. package.path
local file = assert(io.open("tests/body_api_test.lua", "rb")); local source = file:read("*a"):gsub("\r", ""); file:close()
local prefix = assert(source:match("^(.-)local passed = 0"))
local f = assert(loadstring(prefix .. "\nreturn {setup=Setup,entity=Entity,item=Item,armor=Armor,perform=Perform,call=Call}"))()
local API = require("my_friend_body_api")
local function Scan(targets)
    local calls = 0
    TheSim.FindEntities = function() calls = calls + 1; return targets end
    return function() return calls end
end
local function Drain(inst, limit)
    for _ = 1, limit or 40 do if inst._my_friend_body.active == nil then return end; f.perform(inst) end
    assert(inst._my_friend_body.active == nil, "batch did not finish")
end
local function Terminals(state, id)
    local count = 0
    for _, e in ipairs(state.events) do
        if e.action_id == id and ({completed=true,failed=true,cancelled=true,interrupted=true})[e.status] then count = count + 1 end
    end
    return count
end
local passed = 0
local function Test(name, fn) fn(); passed=passed+1; print("PASS " .. name) end
Test("one pickup batch takes all stacks and sends one terminal receipt from one discovery", function()
    local inst,p,state = f.setup()
    local a,b,c,other = f.item("livinglog",nil,4),f.item("livinglog",nil,8),f.item("livinglog",nil),f.item("twigs",nil,3)
    b.x,c.x=3,5
    local scans=Scan({a,b,c,other})
    local accepted=f.call(inst,p,"pickup_many",{filter="livinglog",radius=12})
    f.perform(inst)
    assert(state.active ~= nil and Terminals(state,accepted.action_id)==0)
    Drain(inst)
    local job=state.jobs[accepted.action_id]
    assert(job.status=="completed" and job.result.count==13 and job.result.targets==3)
    assert(a.owner==inst and b.owner==inst and c.owner==inst and other.owner==nil)
    assert(scans()==1 and Terminals(state,accepted.action_id)==1)
end)
Test("normal pickup takes a whole stack by default and an explicit portion remains exact", function()
    local inst,p,state=f.setup(); local a=f.item("livinglog",nil,20)
    local first=f.call(inst,p,"pickup",{target=API.Observation.Handle(state,a)}); f.perform(inst)
    assert(state.jobs[first.action_id].result.count==20 and a.owner==inst)
    local b=f.item("rocks",nil,8)
    local second=f.call(inst,p,"pickup",{target=API.Observation.Handle(state,b),count=4}); f.perform(inst)
    assert(state.jobs[second.action_id].result.count==4 and b.size==4)
end)
Test("one PICK batch visits multiple ripe plants while skipping changed targets", function()
    local inst,p,state=f.setup(); local plants={}
    ACTIONS.PICK.fn=function(a) a.target.ripe=false; f.item("cutgrass",a.doer); return true end
    for n=1,4 do
        local plant=f.entity("grass",n*2); plant.ripe=true
        plant.components.pickable={CanBePicked=function() return plant.ripe end}
        -- Vanilla grass has BOTH pickable (PICK) and workable (DIG).
        plant.components.workable={CanBeWorked=function()return true end,GetWorkAction=function()return ACTIONS.DIG end}
        plants[n]=plant
    end
    local scans=Scan(plants)
    local accepted=f.call(inst,p,"work_many",{action="PICK",filter="grass"})
    plants[4].valid=false
    Drain(inst)
    local job=state.jobs[accepted.action_id]
    assert(job.status=="completed" and job.result.work_units==3 and job.result.targets==3 and job.result.skipped==1)
    assert(scans()==1 and Terminals(state,job.id)==1)
end)
Test("batch works each tree to completion using the actual tool, including CHOP-to-DIG transitions", function()
    local inst,p,state=f.setup(); local trees={}
    for n=1,2 do
        local tree=f.entity("evergreen",n*2); tree.left=3
        tree.components.workable={CanBeWorked=function()return true end,
            GetWorkAction=function()return tree.left>0 and ACTIONS.CHOP or ACTIONS.DIG end}
        trees[n]=tree
    end
    local axe=f.item("axe",inst); f.armor(axe,"hands"); axe.tool_action=ACTIONS.CHOP
    Scan(trees)
    local accepted=f.call(inst,p,"work_many",{action="CHOP",filter="evergreen"})
    Drain(inst)
    local result=state.jobs[accepted.action_id].result
    assert(result.work_units==6 and result.targets==2 and #result.failures==0)
end)
Test("inventory capacity stops a partially collected batch and retains actual quantity", function()
    local inst,p,state=f.setup(); local a,b=f.item("livinglog",nil,4),f.item("livinglog",nil,8); b.x=2
    inst.components.inventory.CanAcceptCount=function(_,_,n)return math.min(2,n)end
    Scan({a,b})
    local accepted=f.call(inst,p,"pickup_many",{filter="livinglog"}); Drain(inst)
    local job=state.jobs[accepted.action_id]
    assert(job.status=="failed" and job.reason=="inventory_full" and job.result.count==2 and job.result.partial)
    assert(a.size==2 and b.owner==nil and Terminals(state,job.id)==1)
end)
Test("manual cancellation waits for a busy boundary and preserves already collected quantity", function()
    local inst,p,state=f.setup(); local a,b=f.item("livinglog",nil,4),f.item("livinglog",nil,8); b.x=3
    Scan({a,b})
    local accepted=f.call(inst,p,"pickup_many",{}); f.perform(inst)
    inst.busy=true
    f.call(inst,p,"cancel",{action_id=accepted.action_id})
    assert(state.active ~= nil and a.owner==inst and b.owner==nil)
    inst.busy=false; API.Tick(inst)
    local job=state.jobs[accepted.action_id]
    assert(job.status=="cancelled" and job.result.count==4 and job.result.partial and job.queue==nil and job.child==nil)
end)
Test("explicit targets avoid scanning and missing tools fail once without claiming work", function()
    local inst,p,state=f.setup(); local rock=f.entity("rock1",2)
    rock.components.workable={CanBeWorked=function()return true end,GetWorkAction=function()return ACTIONS.MINE end}
    local scans=Scan({rock})
    local accepted=f.call(inst,p,"work_many",{action="MINE",targets={API.Observation.Handle(state,rock)}})
    Drain(inst)
    local job=state.jobs[accepted.action_id]
    assert(scans()==0 and job.status=="failed" and job.reason=="missing_tool" and job.result.work_units==0)
    assert(Terminals(state,job.id)==1)
end)
Test("batch discovery stays bounded and never expands to newly spawned items", function()
    local inst,p,state=f.setup(); local targets={}
    for n=1,105 do targets[n]=f.item("livinglog",nil) end
    local scans=Scan(targets)
    local accepted=f.call(inst,p,"pickup_many",{filter="livinglog"})
    local late=f.item("livinglog",nil); targets[#targets+1]=late
    Drain(inst,110)
    local job=state.jobs[accepted.action_id]
    assert(scans()==1 and job.result.targets==100 and job.result.limited and late.owner==nil)
end)
print(passed .. " body batch tests passed")
