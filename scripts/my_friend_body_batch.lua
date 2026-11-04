-- One bounded discovery, then sequential vanilla actions; only the parent publishes receipts.
local Observation = require("my_friend_body_observation")
local M = {}
local VERBS = {CHOP = true, MINE = true, DIG = true, HAMMER = true, PICK = true, HARVEST = true}
local function API() return require("my_friend_body_api") end
local function Eligible(inst, job, target)
    if target == nil or not target:IsValid() or target == inst or target:HasAnyTag("INLIMBO", "FX", "burnt", "fire")
        or (target:GetPosition().x - job.origin.x)^2 + (target:GetPosition().z - job.origin.z)^2 > job.radius^2
        or target:GetCurrentPlatform() ~= inst:GetCurrentPlatform() then return false end
    local c = target.components
    if job.skill == "pickup_many" then
        return not target:HasTag("heavy") and c.inventoryitem ~= nil and c.inventoryitem.owner == nil and c.inventoryitem.canbepickedup == true
            and not c.inventoryitem.islockedinslot
    end
    if job.args.action == "PICK" then return c.pickable ~= nil and c.pickable:CanBePicked() end
    if c.workable ~= nil then return c.workable:CanBeWorked() and c.workable:GetWorkAction() == ACTIONS[job.args.action] end
    return job.args.action == "HARVEST" and (c.harvestable ~= nil or c.crop ~= nil or c.grower ~= nil)
end
function M.Prepare(inst, state, job)
    local a = job.args
    if a.radius ~= nil and (type(a.radius) ~= "number" or a.radius ~= a.radius or a.radius < 1 or a.radius > 32)
        or a.filter ~= nil and (type(a.filter) ~= "string" or #a.filter > 120)
        or a.targets ~= nil and (type(a.targets) ~= "table" or #a.targets > 100)
        or job.skill == "work_many" and (not VERBS[a.action] or ACTIONS[a.action] == nil) then return false, "invalid_batch_arguments" end
    job.radius, job.queue, job.index, job.progress, job.completed_targets, job.skipped, job.failures = a.radius or 20, {}, 0, 0, 0, 0, {}
    local candidates, seen = {}, {}
    if a.targets ~= nil then
        for _, handle in ipairs(a.targets) do
            local target = Observation.Resolve(state, handle)
            if target == nil then return false, "unknown_handle:targets" end
            if job.skill=="pickup_many" and target:HasTag("heavy") then return false,"heavy_requires_single_pickup" end
            candidates[#candidates + 1] = target
        end
    else
        local p = job.origin
        candidates = TheSim:FindEntities(p.x, 0, p.z, job.radius, nil, {"INLIMBO", "FX", "burnt", "fire"})
    end
    table.sort(candidates, function(x, y) return inst:GetDistanceSqToInst(x) < inst:GetDistanceSqToInst(y) end)
    local filter = (a.filter or ""):lower()
    for _, target in ipairs(candidates) do
        local name = tostring(target.GetDisplayName ~= nil and target:GetDisplayName() or ""):lower()
        if not seen[target.GUID] and Eligible(inst, job, target)
            and ((target.prefab or ""):lower():find(filter, 1, true) or name:find(filter, 1, true)) then
            seen[target.GUID] = true
            if #job.queue == 100 then job.limited = true; break end
            job.queue[#job.queue + 1] = target.GUID
        end
    end
    job.cleanup = function()
        local child = job.child
        if child ~= nil and child.cleanup ~= nil then local fn = child.cleanup; child.cleanup = nil; fn() end
        job.child, job.queue = nil, nil
    end
    return true
end
local function Result(job)
    return {count = job.skill == "pickup_many" and job.progress or nil,
        work_units = job.skill == "work_many" and job.progress or nil, targets = job.completed_targets,
        skipped = job.skipped, failures = job.failures, limited = job.limited or false,
        partial = job.skipped > 0 or #job.failures > 0 or job.limited or false}
end
function M.PartialResult(job)
    local result = Result(job)
    result.partial = true
    if job.child ~= nil and job.skill == "work_many" then result.work_units = result.work_units + (job.child.progress or 0) end
    return result
end
function M.FinishChild(inst, child, status, result, reason)
    local parent = child.parent
    if child.cleanup ~= nil then local fn = child.cleanup; child.cleanup = nil; fn() end
    child.status, child.action = status, nil
    parent.child = nil
    parent.progress = parent.progress + (result ~= nil and (result.count or result.work_units or result.progress) or child.progress or 0)
    if status == "completed" and child.skill == "pickup" and result ~= nil and result.count < child.count then
        status, reason = "failed", "inventory_full"
    end
    if status == "completed" then parent.completed_targets = parent.completed_targets + 1
    else
        if #parent.failures < 12 then parent.failures[#parent.failures + 1] = {target = child.args.target, reason = reason} end
        if reason == "inventory_full" or reason == "inventory_full_or_equipment_slot_occupied" or reason == "missing_tool" or status == "interrupted" then
            API().Finish(inst, parent, status, Result(parent), reason)
        end
    end
end
function M.GetAction(inst, state, job)
    for _ = 1, 101 do
        if job.child ~= nil then
            local child = job.child
            return child.action or require("my_friend_body_actions").GetAction(inst, state, child)
        end
        job.index = job.index + 1
        local guid = job.queue[job.index]
        if guid == nil then
            local failed = job.progress == 0 and #job.failures > 0
            API().Finish(inst, job, failed and "failed" or "completed", Result(job), failed and job.failures[1].reason or nil)
            return
        end
        local target = (Ents or {})[guid]
        if Eligible(inst, job, target) then
            local child = {id = job.id, skill = job.skill == "pickup_many" and "pickup" or "work",
                args = {target = Observation.Handle(state, target), action = job.args.action}, parent = job,
                origin = job.origin, deadline = job.deadline, status = "running", issuer = job.issuer}
            -- Work an entire resource before advancing; PICK/HARVEST are one operation.
            local repeated = child.skill == "work" and target.components.workable ~= nil
                and job.args.action ~= "PICK" and job.args.action ~= "HARVEST"
            if repeated then child.args.amount = 40 end
            local ok, reason = require("my_friend_body_actions").Prepare(inst, state, child)
            if ok and repeated then child.count = 10000 end
            job.child = child
            if ok then return require("my_friend_body_actions").GetAction(inst, state, child) end
            M.FinishChild(inst, child, "failed", nil, reason)
        else job.skipped = job.skipped + 1 end
        if state.active ~= job then return end
    end
end
return M
