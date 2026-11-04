-- Bounded read batches and sequential body jobs. No scripts or world operations.
local Observation=require("my_friend_body_observation")
local M={}
local READ={observe=true,query_recipe=true,query_sites=true,query_actions=true,get_capabilities=true}
local WRITE={move_to=true,pickup=true,drop=true,transfer=true,equip=true,unequip=true,craft=true,work=true,
    eat=true,cook=true,use_item=true,interact=true,harvest=true,perform_action=true,pickup_many=true,work_many=true,
    dismount=true,emote=true,revive=true}
local function API()return require("my_friend_body_api")end
local function Copy(value)
    if type(value)~="table"then return value end
    local out={};for k,v in pairs(value)do out[k]=Copy(v)end;return out
end
local function LimitScan(out,budget)
    local json=require("json")
    out.limited,out.truncated=true,true
    -- Preserve the identity/location of every visible container before spending
    -- the budget on its contents. Dropping the tail here hid nearby fridges.
    local fields={handle=true,prefab=true,name=true,position=true,kind=true,count=true,
        accessible=true,capacity=true,cooking=true,pickable=true,carried=true,equipped=true,slot=true,can_store=true,
        container=true,location=true,backpack=true,delivery=true,cooking_tags=true,durability=true,
        can_pick=true,pick_product=true,pick_count=true,work=true,prototyper=true,interactions=true,
        soil=true,plantable=true,deployable=true,terraformer=true,tendable=true,watersource=true,
        burning=true,burnable=true,building=true,boss=true,alive=true,health=true,ghost=true,
        platform=true,boat=true,shared_storage=true,reviver=true,
        contents=true,contents_limited=true,contents_matched=true,contents_offset=true,contents_next_offset=true,details_limited=true}
    for _,entity in ipairs(out.entities)do
        entity.details_limited=true
        for key in pairs(entity)do if not fields[key]then entity[key]=nil end end
        for _,item in ipairs(entity.contents or {})do
            item.details_limited=true
            for key in pairs(item)do if not fields[key] or key=="position"then item[key]=nil end end
        end
    end
    while #json.encode(out)>budget do
        local largest
        for _,entity in ipairs(out.entities)do
            if #(entity.contents or {})>0 and (largest==nil or #entity.contents>#largest.contents)then largest=entity end
        end
        if largest~=nil then
            table.remove(largest.contents)
            largest.contents_limited,out.contents_limited=true,true
            largest.contents_next_offset=(largest.contents_offset or 0)+#largest.contents
        elseif #out.entities>0 then
            table.remove(out.entities)
            if #out.entities==0 then return nil end
            out.returned=#out.entities
            out.next_offset=(out.offset or 0)+#out.entities
            out.entities_limited=true
        else return nil end
    end
    return out
end
local function Limit(value,budget)
    if value==nil then return end
    local out=Copy(value)
    local json=require("json")
    if out.entities~=nil and #json.encode(out)>budget then return LimitScan(out,budget)end
    while #json.encode(out)>budget do
        local longest
        local protected={ingredients=true,sources=true,character_costs=true,technology_costs=true,actions=true}
        local function Find(t)
            for key,v in pairs(t)do if type(v)=="table" and not protected[key] then
                if #v>0 and (longest==nil or #v>#longest)then longest=v end
                Find(v)
            end end
        end
        Find(out)
        if longest==nil then return nil end
        for n=#longest,math.floor(#longest/2)+1,-1 do longest[n]=nil end
        out.limited,out.truncated=true,true
    end
    return out
end
M.LimitResult=Limit
local function Array(value,max)
    if type(value)~="table" or #value<1 or #value>max then return false end
    for k in pairs(value)do if type(k)~="number" or k%1~=0 or k<1 or k>#value then return false end end
    return true
end
local function Read(inst,state,skill,args,nearby)
    if skill=="observe"then
        if not Observation.ValidScan(args) then return nil,"invalid_arguments" end
        return Observation.Scan(inst,state,args,nearby)
    elseif skill=="query_recipe"then return require("my_friend_body_recipes").Query(inst,state,args,nearby)
    elseif skill=="query_sites"then return require("my_friend_body_sites").Query(inst,state,args)
    elseif skill=="query_actions"then return require("my_friend_body_native").Query(inst,state,args)
    else return require("my_friend_body_recipes").Capabilities(inst)end
end
function M.Query(inst,state,args)
    if not Array(args.queries,8)then return nil,"invalid_queries"end
    local seen,out,cache,nearby={},{},{},{}
    for n,q in ipairs(args.queries)do
        if type(q)~="table" or not READ[q.skill] or type(q.arguments or {})~="table" then return nil,"invalid_query"end
        local id=q.id or tostring(n)
        if type(id)~="string" or #id>40 or seen[id]then return nil,"invalid_query_id"end
        seen[id]=true
    end
    for n,q in ipairs(args.queries)do
        -- Identical read requests reuse their result for this call only.
        local key=require("json").encode({skill=q.skill,args=q.arguments or {}})
        local record=cache[key]
        if record==nil then
            local ok,result,reason=pcall(Read,inst,state,q.skill,q.arguments or {},nearby)
            local limited=ok and Limit(result,math.floor(18000/#args.queries)) or nil
            record={status=ok and limited~=nil and "completed" or "failed",result=limited,
                reason=not ok and "query_failed" or result~=nil and limited==nil and "query_result_too_large" or reason}
            cache[key]=record
        end
        out[#out+1]={id=q.id or tostring(n),skill=q.skill,status=record.status,result=record.result,reason=record.reason}
    end
    return {results=out,queries=#out}
end
local function Dispose(job)
    if job.child~=nil then Dispose(job.child);job.child=nil end
    if job.cleanup~=nil then local fn=job.cleanup;job.cleanup=nil;fn()end
end
function M.Result(job)
    local steps={}
    local records=job.records or {}
    for n,record in ipairs(records)do
        local budget=n==#records and 8000 or math.max(180,math.floor(10000/math.max(1,#records-1)))
        local result=Limit(record.result,budget)
        local omitted=record.result~=nil and result==nil
        if omitted then
            result={details_omitted=true,recipe=record.result.recipe,count=record.result.count,
                operations=record.result.operations,produced=record.result.produced,partial=record.result.partial}
        end
        steps[#steps+1]={id=record.id,skill=record.skill,status=record.status,reason=record.reason,result=result,
            arguments=record.arguments~=nil and Limit(record.arguments,math.min(350,math.floor(4000/math.max(1,#records)))) or nil}
    end
    return {steps=steps,completed=job.completed or 0,total=job.steps~=nil and #job.steps or job.total,
        failed_step=job.failed_step,pending_step=job.child~=nil and job.steps[job.index].id or nil,
        in_progress=job.child~=nil and {skill=job.child.skill,progress=job.child.progress,stage=job.child.stage} or nil,
        partial=job.child~=nil or job.failed_step~=nil,
        failed_arguments=job.failed_step~=nil and records[#records]~=nil and records[#records].arguments or nil}
end
function M.Validate(args)
    if not Array(args.steps,64)then return false,"invalid_steps"end
    local expanded={}
    for _,step in ipairs(args.steps) do
        if type(step)~="table" then return false,"invalid_steps" end
        if step.for_each~=nil then
            if type(step.id)~="string" or not step.id:match("^[%w_]+$")
                or not Array(step.for_each,40) or not Array(step.steps,12) then return false,"invalid_repeat" end
            for n,value in ipairs(step.for_each) do
                local names={}
                for _,template in ipairs(step.steps) do
                    if type(template)~="table" or type(template.id)~="string" or template.for_each~=nil then return false,"invalid_repeat" end
                    names[template.id]=step.id.."_"..n.."_"..template.id
                end
                local bad_reference=false
                local function Bind(v)
                    if type(v)=="table" then local out={};for k,entry in pairs(v)do out[k]=Bind(entry)end;return out end
                    if type(v)~="string" then return v end
                    if v=="$each" then return Copy(value) end
                    if v:sub(1,6)=="$each." then
                        local current=value
                        for key in v:sub(7):gmatch("[^%.]+") do
                            if type(current)~="table" then bad_reference=true;return nil end
                            current=current[tonumber(key) or key]
                        end
                        if current==nil then bad_reference=true end
                        return Copy(current)
                    end
                    local id,path=v:match("^%$([%w_]+)(%..+)$")
                    return names[id]~=nil and "$"..names[id]..path or v
                end
                if bad_reference then return false,"invalid_each_reference" end
                for _,template in ipairs(step.steps) do
                    expanded[#expanded+1]={id=names[template.id],skill=template.skill,arguments=Bind(template.arguments or {})}
                    if bad_reference then return false,"invalid_each_reference" end
                    if #expanded>64 then return false,"too_many_expanded_steps" end
                end
            end
        else expanded[#expanded+1]=step end
        if #expanded>64 then return false,"too_many_expanded_steps" end
    end
    args.steps=expanded
    local seen={}
    for n,step in ipairs(args.steps)do
        if type(step)~="table" or not (WRITE[step.skill] or READ[step.skill]) or type(step.arguments or {})~="table" then return false,"unsupported_sequence_step"end
        local id=step.id or tostring(n)
        if type(id)~="string" or #id>40 or not id:match("^[%w_]+$") or seen[id]then return false,"invalid_step_id"end
        step.id=id;seen[id]=true
    end
    return true
end
function M.Prepare(inst,state,job)
    local ok,reason=M.Validate(job.args)
    if not ok then return false,reason end
    job.steps,job.records,job.by_id,job.index,job.completed,job.pins=job.args.steps,{},{},0,0,{}
    job.total=#job.steps
    local function Pin(value)
        if type(value)=="table"then for _,v in pairs(value)do Pin(v)end
        elseif type(value)=="string"then
            local e=Observation.Resolve(state,value)
            if e~=nil then job.pins[value]=e.GUID end
        end
    end
    Pin(job.steps)
    job.cleanup=function()
        if job.child~=nil then Dispose(job.child);job.child=nil end
        job.steps,job.by_id,job.pins=nil,nil,nil
    end
    return true
end
local function Resolve(job,value)
    if type(value)=="table"then
        local out={};for key,v in pairs(value)do local resolved,reason=Resolve(job,v);if reason then return nil,reason end;out[key]=resolved end
        return out
    end
    if type(value)~="string" or value:sub(1,1)~="$"then return value end
    local id,path=value:match("^%$([%w_]+)%.([%w_%.]+)$")
    if id==nil then return nil,"invalid_result_reference"end
    local record=job.by_id[id]
    if record==nil or record.status~="completed"then return nil,"unresolved_result_reference"end
    local current=record.result
    for key in path:gmatch("[^%.]+")do
        if type(current)~="table"then return nil,"unresolved_result_reference"end
        current=current[tonumber(key) or key]
    end
    if current==nil then return nil,"unresolved_result_reference"end
    return current
end
function M.FinishChild(inst,child,status,result,reason)
    local parent=child.parent
    local step=parent.steps[parent.index]
    parent.records[#parent.records+1]={id=step.id,skill=child.skill,status=status,result=result,reason=reason,arguments=Copy(child.args)}
    parent.by_id[step.id]=parent.records[#parent.records]
    local function Pin(value)
        if type(value)=="table"then for _,v in pairs(value)do Pin(v)end
        elseif type(value)=="string"then
            local e=Observation.Resolve(inst._my_friend_body,value)
            if e~=nil then parent.pins[value]=e.GUID end
        end
    end
    Pin(result)
    Dispose(child);parent.child=nil
    if status=="completed"then parent.completed=parent.completed+1
    else
        parent.failed_step=step.id
        API().Finish(inst,parent,status,M.Result(parent),reason)
    end
end
function M.GetAction(inst,state,job)
    if job.child~=nil then
        local child=job.child
        if child.skill=="pickup_many" or child.skill=="work_many"then return require("my_friend_body_batch").GetAction(inst,state,child)end
        return child.action or require("my_friend_body_actions").GetAction(inst,state,child)
    end
    job.index=job.index+1
    local step=job.steps[job.index]
    if step==nil then API().Finish(inst,job,"completed",M.Result(job));return end
    local args,reason=Resolve(job,step.arguments or {})
    job.stage="step:"..step.id
    if args==nil then
        job.child={id=job.id,parent=job,skill=step.skill,status="running"}
        M.FinishChild(inst,job.child,"failed",nil,reason);return
    end
    -- Pins were validated when accepting the sequence; refresh their leases,
    -- never resurrect a lost entity or a handle expired before acceptance.
    for handle,guid in pairs(job.pins)do
        local e=(Ents or {})[guid];local record=state.handles[handle]
        if e~=nil and e:IsValid() and record~=nil and record.guid==guid then record.expires=GetTime()+90 end
    end
    local child={id=job.id,request_id=job.request_id,parent=job,skill=step.skill,args=args,status="running",
        origin=inst:GetPosition(),deadline=job.deadline,issuer=job.issuer}
    job.child=child
    if READ[step.skill]then
        local ok,result,why=pcall(Read,inst,state,step.skill,args)
        M.FinishChild(inst,child,ok and result~=nil and "completed" or "failed",ok and result or nil,not ok and "query_failed" or why)
        if state.active==job then return M.GetAction(inst,state,job)end
        return
    end
    local ok,prepared,why=pcall(require("my_friend_body_actions").Prepare,inst,state,child)
    if not ok or not prepared then M.FinishChild(inst,child,"failed",nil,ok and why or "step_prepare_failed");return end
    if child.delegated~=nil then M.FinishChild(inst,child,"failed",nil,"requires_standalone_action");return end
    return M.GetAction(inst,state,job)
end
return M
