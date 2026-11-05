-- Discover vanilla/mod component actions, rather than guessing from prefab names.
local Observation = require("my_friend_body_observation")
local M = {}
local MODES = {INVENTORY=true, EQUIPPED=true, USEITEM=true, POINT=true, SCENE=true}
local CONTAINER_MOVES={STORE=true,TAKEITEM=true,HARVEST=true,COOK=true}
local DEDICATED={PICKUP="pickup",EAT="eat",DROP="drop",EQUIP="equip",UNEQUIP="unequip",BUILD="craft",ATTACK="engage",
    CHOP="work",MINE="work",DIG="work",HAMMER="work"}
local function Allowed(inst,c,action)
    if DEDICATED[action.id]~=nil then return false end
    if c.target ~= nil and c.target:HasTag("playerghost")
        and (action.id == "GIVETOPLAYER" or action.id == "GIVEALLTOPLAYER" or action.id == "GIVE" or action.id == "FEEDPLAYER") then
        return false
    end
    if CONTAINER_MOVES[action.id] and c.target ~= nil and c.target.components.container_proxy ~= nil then return false end
    return not (CONTAINER_MOVES[action.id] and c.target~=nil and c.target.components.container~=nil)
        or require("my_friend_inventory").CanWithdrawFrom(inst,c.target,c.target.components.stewer~=nil)
end
local NO_AUTO_EQUIP={COMBINESTACK=true,STORE=true,BUNDLESTORE=true,EQUIP=true,GIVETOPLAYER=true,GIVEALLTOPLAYER=true,
    GIVE=true,ADDFUEL=true,ADDWETFUEL=true,DEPLOY=true,DEPLOY_FLOATING=true,CONSTRUCT=true,ADDCOMPOSTABLE=true,
    EQUIPONBODY=true,DECORATESNOWMAN=true}
function M.EquipSlot(job,item)
    local equip=item~=nil and item.components.equippable or nil
    if equip==nil or job.native_mode=="INVENTORY" or NO_AUTO_EQUIP[job.native_action.id]
        or job.native_action.id=="TOSS" and item:HasTag("keep_equip_toss") then return end
    return equip.equipslot
end
function M.WithInventory(inst,fn,...)
    -- NPCs have no inventory window. Scope the native UI-only availability
    -- flags to this query/call, without opening widgets or altering ownership.
    local inv=inst.components.inventory
    local opened,visible=inv.isopen,inv.isvisible
    inv.isopen,inv.isvisible=true,true
    local ok,value,reason=pcall(fn,...)
    inv.isopen,inv.isvisible=opened,visible
    if not ok then error(value) end
    return value,reason
end
local function Owned(inst, item)
    return item ~= nil and item:IsValid() and item.components.inventoryitem ~= nil
        and not item.components.inventoryitem.islockedinslot and item.components.inventoryitem:GetGrandOwner() == inst
end
local function Position(p)
    return type(p)=="table" and type(p.x)=="number" and type(p.z)=="number" and p.x==p.x and p.z==p.z
        and math.abs(p.x)<1000000 and math.abs(p.z)<1000000
end
local function Context(inst, state, args)
    local item = args.item ~= nil and Observation.Resolve(state,args.item) or nil
    local target = args.target ~= nil and Observation.Resolve(state,args.target) or nil
    if args.item ~= nil and not Owned(inst,item) then return nil,"item_not_carried" end
    if args.target ~= nil and target == nil then return nil,"unknown_handle:target" end
    if args.mode ~= nil and not MODES[args.mode] then return nil,"invalid_action_mode" end
    if args.right ~= nil and type(args.right)~="boolean" then return nil,"invalid_click_button" end
    if args.mode=="SCENE" and item~=nil then return nil,"scene_action_has_no_item" end
    local point
    if args.position ~= nil then
        if not Position(args.position) then return nil,"invalid_position" end
        point=Vector3(args.position.x,0,args.position.z)
        if item ~= nil and item.components.deployable ~= nil and require("my_friend_body_sites").IsDeployAction(args.action) then
            point = require("my_friend_body_sites").Snap(item, point)
        end
        local p=inst:GetPosition()
        if (point.x-p.x)^2+(point.z-p.z)^2>64^2 then return nil,"position_out_of_range" end
    end
    if item~=nil and item.prefab=="yellowstaff" and point~=nil
        and not require("my_friend_survival_ai").IsFireClearPoint(inst,point) then return nil,"unsafe_fire_position" end
    if target == nil and point ~= nil and args.mode ~= "INVENTORY" then
        local best
        for _, entity in ipairs(TheSim:FindEntities(point.x,0,point.z,.6,nil,{"INLIMBO","FX","NOCLICK"})) do
            if entity ~= inst and (entity.components.inventoryitem == nil or entity.components.inventoryitem.owner == nil) then
                local p=entity:GetPosition()
                local d=(p.x-point.x)^2+(p.z-point.z)^2
                if best == nil or d<best or d==best and entity.GUID<target.GUID then target,best=entity,d end
            end
        end
    end
    return {item=item,target=target,point=point,right=args.right~=false}
end
local function Collect(inst,c,mode)
    local out, source = {}, mode=="SCENE" and c.target or c.item
    if source == nil or source.CollectActions == nil then return out end
    if mode=="EQUIPPED" and inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)~=c.item then return out end
    if mode=="INVENTORY" then M.WithInventory(inst,source.CollectActions,source,mode,inst,out,c.right)
    elseif mode=="SCENE" then
        source:CollectActions(mode,inst,out,c.right)
        local inherent=c.right and source.inherentscenealtaction or not c.right and source.inherentsceneaction or nil
        if source~=inst and inherent~=nil then out[#out+1]=inherent end
    elseif mode=="POINT" and c.point~=nil then source:CollectActions(mode,inst,c.point,out,c.right,c.target)
    elseif (mode=="USEITEM" or mode=="EQUIPPED") and c.target~=nil then source:CollectActions(mode,inst,c.target,out,c.right) end
    return out
end
function M.Wrap(inst,job,action)
    if action.Do==nil then return end
    local perform=action.Do
    action.Do=function(act,...)
        local ok,value,reason
        local target=job.native_hint_target~=nil and (Ents or {})[job.native_hint_target] or nil
        job.effect_point=job.point or target~=nil and target:IsValid() and target:GetPosition() or inst:GetPosition()
        job.effect_before={}
        for _,entity in ipairs(TheSim:FindEntities(job.effect_point.x,0,job.effect_point.z,2,nil,{"INLIMBO","FX"})) do
            job.effect_before[entity.GUID]=true
        end
        if job.native_mode=="INVENTORY" then ok,value,reason=pcall(M.WithInventory,inst,perform,act,...)
        else ok,value,reason=pcall(perform,act,...) end
        if not ok then job.operation_error="native_action_error"; act:Fail(); return false end
        return value,reason
    end
end
function M.Actions(inst,state,args)
    local c,reason=Context(inst,state,args)
    if c==nil then return nil,reason end
    local modes=args.mode~=nil and {args.mode} or c.item==nil and {"SCENE"}
        or c.point~=nil and (c.target~=nil and {"POINT","USEITEM","EQUIPPED"} or {"POINT"})
        or c.target~=nil and {"USEITEM","EQUIPPED"} or {"INVENTORY"}
    local actions={}
    for _,mode in ipairs(modes) do
        local ok,found=pcall(Collect,inst,c,mode)
        if not ok then return nil,"native_action_query_failed" end
        for _,action in ipairs(found) do
            if type(action)=="table" and type(action.id)=="string" and type(action.fn)=="function" and #actions<40 and Allowed(inst,c,action) then
                actions[#actions+1]={action=action,mode=mode}
            end
        end
    end
    return actions,nil,c
end
function M.Query(inst,state,args)
    local actions,reason,c=M.Actions(inst,state,args)
    if actions==nil then return nil,reason end
    local out={actions={},dedicated_interfaces=DEDICATED,right=c.right,requires_hand_equipment=args.mode=="EQUIPPED"
        and (c.item==nil or inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)~=c.item) or false}
    out.target=c.target~=nil and Observation.Handle(state,c.target) or nil
    out.position=c.point~=nil and {x=c.point.x,z=c.point.z} or nil
    out.item=c.item~=nil and Observation.Handle(state,c.item) or nil
    if c.target~=nil and c.target.components.container~=nil and c.item~=nil then
        out.acceptable_count=c.target.components.container:CanAcceptCount(c.item,math.min(40,Observation.Size(c.item)))
    end
    if c.target~=nil and c.target.isplayer and TheNet~=nil and TheNet.GetPVPEnabled~=nil then
        out.pvp_enabled=TheNet:GetPVPEnabled()
    end
    if #actions==0 then out.reason="no_native_action_for_current_context" end
    for _,entry in ipairs(actions) do
        out.actions[#out.actions+1]={action=entry.action.id,mode=entry.mode,
            instant=entry.action.instant==true, ranged=entry.action.distance ~= nil}
    end
    return out
end
function M.Prepare(inst,state,job)
    if type(job.args.action)~="string" then return false,"query_actions_first" end
    local actions,reason,c=M.Actions(inst,state,job.args)
    if actions==nil then return false,reason end
    local sites = require("my_friend_body_sites")
    local deployment = c.point ~= nil and c.item ~= nil and c.item.components.deployable ~= nil
        and (job.args.mode == nil or job.args.mode == "POINT") and sites.IsDeployAction(job.args.action)
    if deployment and not c.item.components.deployable:CanDeploy(c.point,nil,inst,0) then
        return false, "placement_blocked", sites.Details(inst,state,c.point,sites.Spacing(nil,c.item))
    end
    for _,entry in ipairs(actions) do
        if entry.action.id==job.args.action then
            job.native,job.native_mode,job.native_action=true,entry.mode,entry.action
            job.item=c.item~=nil and c.item.GUID or nil
            job.target=c.target~=nil and entry.mode~="POINT" and entry.mode~="INVENTORY" and c.target.GUID or nil
            job.native_hint_target=c.target~=nil and c.target.GUID or nil
            job.point,job.right=c.point,c.right
            job.native_deployment = deployment and entry.mode == "POINT"
            return true
        end
    end
    return false,"native_action_unavailable"
end
function M.Valid(inst,state,job)
    local item=job.item~=nil and (Ents or {})[job.item] or nil
    local target=job.native_hint_target~=nil and (Ents or {})[job.native_hint_target] or nil
    if job.item~=nil and not Owned(inst,item) or job.native_hint_target~=nil and (target==nil or not target:IsValid()) then return false end
    if job.native_deployment and (item.components.deployable == nil
        or not item.components.deployable:CanDeploy(job.point,nil,inst,0)) then
        job.operation_error = "placement_blocked"
        return false
    end
    if item~=nil and item.prefab=="yellowstaff" and job.point~=nil
        and not require("my_friend_survival_ai").IsFireClearPoint(inst,job.point) then return false end
    local ok,actions=pcall(Collect,inst,{item=item,target=target,point=job.point,right=job.right},job.native_mode)
    if not ok then return false end
    for _,action in ipairs(actions) do
        if action==job.native_action and Allowed(inst,{target=target},action) then return true end
    end
    return false
end
return M
