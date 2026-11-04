-- Model pickup delegates heavy lifting to the same controller as carry_statue.
local Carry = require("my_friend_command_carry")
local Slots = require("my_friend_equip_slots")
local Observation = require("my_friend_body_observation")
local M = {}
local function Current(inst, job)
    local parent=job
    while parent.parent~=nil do
        if parent.cancel_requested or parent.parent.child~=parent then return false end
        parent=parent.parent
    end
    return inst._my_friend_body~=nil and inst._my_friend_body.active==parent and not parent.cancel_requested
end
function M.Prepare(inst, state, job)
    local target=(Ents or {})[job.target]
    if target==nil or not target:IsValid() then return false,"item_lost" end
    local held=Slots.GetHeavy(inst.components.inventory)
    if held~=nil and held~=target then return false,"already_carrying_heavy" end
    if held~=target and not Carry.CanPickUp(inst,target) then return false,"heavy_pickup_unavailable" end
    if job.args.count~=nil and job.args.count~=1 then return false,"heavy_pickup_count_must_be_one" end
    local command={id="carry_statue",player=job.issuer or state.owner,body_target=target.GUID,
        origin=inst:GetPosition(),started=GetTime(),deadline=job.deadline or GetTime()+120,
        phase=held==target and "carrying" or nil}
    job.heavy_carry,job.command=true,command
    inst._my_friend_command=command
    job.cleanup=function()
        if inst._my_friend_command==command and not job.secured then
            require("my_friend_commands").Clear(inst,state)
        end
    end
    return true
end
function M.GetAction(inst, state, job)
    if not Current(inst,job) then return end
    local command=job.command
    if inst._my_friend_command~=command then
        require("my_friend_body_api").Finish(inst,job,"failed",nil,"carry_command_replaced");return
    end
    if Slots.GetHeavy(inst.components.inventory)==(Ents or {})[job.target] and command.phase=="carrying" then
        job.secured=true
        require("my_friend_body_api").Finish(inst,job,"completed",{count=1,requested=1,heavy=true,carrying=true,
            items={Observation.Describe(inst,state,(Ents or {})[job.target])}});return
    end
    local action=Carry.GetAction(inst,command)
    if action==nil then
        if command.phase=="carrying" and inst._my_friend_command==command
            and Slots.GetHeavy(inst.components.inventory)==(Ents or {})[job.target] then return M.GetAction(inst,state,job) end
        require("my_friend_body_api").Finish(inst,job,"failed",{carrying=Slots.GetHeavy(inst.components.inventory)~=nil},"heavy_pickup_failed");return
    end
    local valid=action.validfn
    action._my_friend_body_action,action._body_job=job.id,job
    action.validfn=function(act)return Current(inst,job) and (valid==nil or valid(act)) end
    action:AddSuccessAction(function()if Current(inst,job)then job.action=nil end end)
    action:AddFailAction(function()
        if Current(inst,job)then
            job.action=nil
            require("my_friend_body_api").Finish(inst,job,"failed",{carrying=Slots.GetHeavy(inst.components.inventory)~=nil},
                action._my_friend_path_failed and "unreachable" or "heavy_action_failed")
        end
    end)
    job.action=action
    return action
end
return M
