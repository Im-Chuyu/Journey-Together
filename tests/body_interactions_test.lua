-- Real body API/scene validators and sitting request/score functions;
-- native animation completion is an explicit fixture boundary.
package.path = "./scripts/?.lua;../yuanma/scripts/?.lua;" .. package.path
local function Read(path)
    local file = assert(io.open(path, "rb")); local source = file:read("*a"):gsub("\r\n", "\n"); file:close(); return source
end
local fixture = assert(loadstring(assert(Read("tests/body_api_test.lua"):match("^(.-)local passed = 0"))
    .. "\nreturn {setup=Setup,entity=Entity}"))()
package.loaded["behaviours/my_friend_route_action"] = function() end
package.loaded.my_friend_navigation.IsBlocked = function() return false end
package.loaded.my_friend_behavior_ai.IsTargetUnsafe = function() return false end
package.loaded.my_friend_light_ai = {IsDark = function() return false end}
package.loaded.my_friend_survival_ai = {NeedsTemperatureHelp = function() return false end}
local Sitting = assert(loadstring(assert(Read("scripts/my_friend_sitting.lua"):match("^(.-)local Sit = Class")) .. "\nreturn M"))()
package.loaded.my_friend_sitting = Sitting
local API = require("my_friend_body_api")
local interactions = require("my_friend_body_interactions")
local serial, passed = 0, 0
local function Call(inst, p, skill, args) serial = serial + 1; return API.Call(inst, p, "interaction:" .. serial, skill, args or {}) end
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
local function Setup()
    local inst, p, state = fixture.setup()
    inst.components.inventory.IsHeavyLifting = function() return false end
    inst.components.hunger.GetPercent = function() return 1 end
    inst.sg.HasAnyStateTag = function() return false end
    inst.sg.statemem = {}
    return inst, p, state
end
local function Chair(state)
    local chair = fixture.entity("wood_chair", 3); chair.tags.cansit = true
    chair.components.sittable = {IsOccupied = function() return chair.occupied == true end}
    return chair, API.Observation.Handle(state, chair)
end
Test("observations advertise real scene components and preserve false state", function()
    local inst, p, state = Setup(); local chair = Chair(state)
    local record = API.Observation.Describe(inst, state, chair)
    assert(record.interactions[1] == "SITON" and record.occupied == false)
    assert(API.Observation.Describe(inst, state, p).interactions == nil)
    local machine = fixture.entity("machine"); machine.components.machine = {IsOn = function() return false end}
    assert(API.Observation.Describe(inst, state, machine).switched_on == false)
    TheSim.FindEntities = function() return {chair, machine} end
    local result = Call(inst, p, "observe", {scope = "interactions"})
    assert(result.status == "completed" and #result.result.entities == 2)
end)
Test("specified chair uses original sitting eligibility and reports only actual seating", function()
    local inst, p, state = Setup(); local chair, handle = Chair(state)
    local result = Call(inst, p, "interact", {target = handle, action = "SITON"})
    assert(result.status == "accepted" and state.active.delegated == "sit")
    assert(inst._my_friend_seat_request.strict and inst._my_friend_seat_request.chair == chair)
    assert(API.Score(inst, {}) == 0 and API.AllowLocal(inst, "sit", {}))
    assert(Sitting.Score(inst, {}) == 104)
    API.Tick(inst); assert(state.jobs[result.action_id].status == "accepted")
    inst.sg.currentstate.name, inst.sg.statemem.chair, inst.busy = "sitting", chair, true
    inst._my_friend_replan_requested = nil
    API.Tick(inst)
    assert(state.jobs[result.action_id].status == "completed" and state.jobs[result.action_id].result.seated)
    assert(state.active == nil and inst._my_friend_seat_request ~= nil and API.AllowLocal(inst, "follow", {}))
    assert(inst._my_friend_replan_requested == nil)
    assert(inst.components.follower:GetLeader() == p)
end)
Test("occupied, distant, unsupported chairs fail without choosing another seat", function()
    local inst, p, state = Setup(); local chair, handle = Chair(state)
    chair.occupied = true
    assert(Call(inst, p, "interact", {target = handle, action = "SITON"}).reason == "seat_unavailable")
    chair.occupied, chair.x = false, 30
    assert(Call(inst, p, "interact", {target = handle, action = "SITON"}).status == "failed")
    assert(Call(inst, p, "interact", {target = handle, action = "MOUNT"}).reason == "native_action_unavailable")
    chair.x = 3
    local result = Call(inst, p, "interact", {target = handle, action = "SITON"})
    inst._my_friend_seat_request = nil; API.Tick(inst)
    assert(state.jobs[result.action_id].status == "failed")
end)
Test("cancel/close cleans only the model's pending seat request", function()
    local inst, p, state = Setup(); local chair, handle = Chair(state)
    local result = Call(inst, p, "interact", {target = handle, action = "SITON"})
    assert(Call(inst, p, "cancel", {action_id = result.action_id}).status == "cancelled")
    assert(inst._my_friend_seat_request == nil)
    result = Call(inst, p, "interact", {target = handle, action = "SITON"})
    API.Close(inst, "manual_command")
    assert(inst._my_friend_seat_request == nil and state.jobs[result.action_id].status == "interrupted")
end)
Test("native switch/activation rechecks availability and does not toggle twice", function()
    local inst, p, state = Setup(); local target = fixture.entity("machine", 2)
    target.components.machine = {IsOn = function() return target.on == true end}
    target.components.activatable = {CanActivate = function() return target.blocked ~= true end}
    ACTIONS.TURNON = {id = "TURNON"}; ACTIONS.ACTIVATE = {id = "ACTIVATE"}
    local handle = API.Observation.Handle(state, target)
    local result = Call(inst, p, "interact", {target = handle, action = "TURNON"})
    local action = assert(API.GetAction(inst)); assert(action:IsValid() and action.action == ACTIONS.TURNON)
    target.on = true; for _, fn in ipairs(action.successes) do fn() end
    assert(state.jobs[result.action_id].result.executed)
    result = Call(inst, p, "interact", {target = handle, action = "TURNON"})
    assert(API.GetAction(inst) == nil and state.jobs[result.action_id].result.already)
    Call(inst, p, "interact", {target = handle, action = "ACTIVATE"})
    action = assert(API.GetAction(inst)); target.blocked = true; assert(not action:IsValid())
    assert(not interactions.Supports(target, "CUSTOM_MOD_ACTION"))
end)
Test("explicit model seating also works while independent and disappears when transport ends", function()
    local inst,p,state=Setup(); local chair,handle=Chair(state)
    inst.components.follower.GetLeader=function()return nil end
    assert(Sitting.Score(inst,{})==0)
    local accepted=Call(inst,p,"interact",{target=handle,action="SITON"})
    assert(accepted.status=="accepted" and Sitting.Score(inst,{})==104)
    inst.sg.currentstate.name,inst.sg.statemem.chair="sitting",chair
    API.Tick(inst)
    assert(state.jobs[accepted.action_id].status=="completed" and Sitting.Score(inst,{})==104)
    API.Close(inst,"done"); assert(Sitting.Score(inst,{})==0)
end)
Test("remote independent seating keeps the real issuer and uses the companion for physical distance",function()
    local inst,p,state=Setup();local chair,handle=Chair(state)
    inst.components.follower.GetLeader=function()return nil end
    local actor={_my_friend_remote_speaker=true,key="remote",shard="1",userid="KU_remote",expires=GetTime()+100}
    state.remote_speakers={[actor.key]=actor};Shard_IsWorldAvailable=function(id)return id=="1"end
    local accepted=Call(inst,actor,"interact",{target=handle,action="SITON"})
    assert(accepted.status=="accepted" and state.active.issuer==actor and inst._my_friend_seat_request.leader==inst)
    assert(Sitting.Score(inst,{})==104)
    actor.left=true;API.Tick(inst)
    assert(state.jobs[accepted.action_id].status=="interrupted" and Sitting.Score(inst,{})==0)
end)
print(passed .. " body interaction tests passed")
