-- World operations require a two-message reason review bound to the real caller.
-- Cave requests carry server-captured dialogue evidence; no administrator grants.
local json = require("json")
local M = {}
M.SKILLS = {save_game = true, rollback_game = true, pause_game = true, kick_player = true, ban_player = true}
local rpc, serial = nil, 0
local pending = {}
local function Now() return (GetStaticTime or GetTime)() end
local function Master() return TheWorld ~= nil and TheWorld.ismastershard == true end
local function UserID(value)
    return type(value) == "string" and #value > 0 and #value <= 128 and not value:find("[%z\1-\32]")
end
local function Client(userid)
    return TheNet ~= nil and TheNet.GetClientTableForUser ~= nil and TheNet:GetClientTableForUser(userid) or nil
end
function M.IsAdmin(player)
    if player == nil or not UserID(player.userid) then return false end
    local client = Client(player.userid)
    if client ~= nil then return client.admin == true end
    return player == ThePlayer and TheNet ~= nil and TheNet.GetIsServerAdmin ~= nil and TheNet:GetIsServerAdmin() == true
end
local function Dialogues()
    local world=TheWorld
    world._my_friend_world_dialogues=world._my_friend_world_dialogues or {by_user={},order={}}
    return world._my_friend_world_dialogues
end
function M.Status(player)
    local out={mode="reason_review",save=true,rollback=true,pause=true,kick=true,ban=true,players={}}
    local clients=TheNet~=nil and TheNet.GetClientTable~=nil and TheNet:GetClientTable() or AllPlayers or {}
    for _,entry in ipairs(clients or {}) do
        if UserID(entry.userid) and not (entry.HasTag~=nil and entry:HasTag("my_friend")) then
            out.players[#out.players+1]={userid=entry.userid,name=entry.name or entry.prefab}
        end
    end
    table.sort(out.players,function(a,b)return a.userid<b.userid end)
    local request=Dialogues().by_user[player.userid]
    if not Master() then request=(TheWorld._my_friend_world_review_view or {})[player.userid] end
    if request~=nil and not request.used and Now()<request.expires then
        out.pending_request={approval_id=request.id,skill=request.skill,count=request.count,paused=request.paused,userid=request.target,
            needs_reason=true}
    end
    return out
end
local function Send(name, shard, payload)
    rpc.SendModRPCToShard(rpc.GetShardModRPC("MyFriends", name), {tostring(shard)}, json.encode(payload))
end
local function Process(actor, skill, args, callback)
    local function Fail(reason)callback(false,nil,reason)end
    local context=actor.dialogue
    if type(context)~="table" or type(context.id)~="string" or #context.id>160
        or #context.id==0 or type(context.text)~="string" or #context.text==0 or #context.text>2048 then Fail("world_reason_dialogue_required");return end
    local keys={approval_id=true,reason=true,approved=true,assessment=true}
    if skill=="rollback_game"then keys.count=true elseif skill=="pause_game"then keys.paused=true
    elseif skill=="kick_player" or skill=="ban_player"then keys.userid=true end
    for key in pairs(args)do if not keys[key]then Fail("invalid_arguments");return end end
    local count=skill=="rollback_game" and (args.count or 1) or nil
    local paused
    if skill=="pause_game"then paused=args.paused;if paused==nil then paused=true end end
    if count~=nil and(type(count)~="number" or count<1 or count>2147483647 or count%1~=0)then Fail("invalid_arguments");return end
    if skill=="pause_game" and args.paused~=nil and type(args.paused)~="boolean"then Fail("invalid_arguments");return end
    local target=(skill=="kick_player" or skill=="ban_player") and args.userid or nil
    if (skill=="kick_player" or skill=="ban_player") and not UserID(target)then Fail("invalid_target");return end
    if target~=nil and Client(target)==nil then Fail("player_not_online");return end
    local dialogues=Dialogues()
    local request=dialogues.by_user[actor.userid]
    if args.approval_id==nil then
        serial=serial+1
        request={id=tostring(GetTime())..":review:"..serial,origin=context.id,skill=skill,count=count,paused=paused,
            target=target,expires=Now()+300}
        dialogues.by_user[actor.userid]=request
        dialogues.order[#dialogues.order+1]={userid=actor.userid,id=request.id}
        if #dialogues.order>64 then
            local old=table.remove(dialogues.order,1)
            if dialogues.by_user[old.userid] and dialogues.by_user[old.userid].id==old.id then dialogues.by_user[old.userid]=nil end
        end
        callback(true,{requested=false,needs_reason=true,approval_id=request.id,skill=skill,count=count,paused=paused,userid=target,
            question="请先询问玩家为什么需要这项操作，等待下一条回答，再判断理由是否合理；此时尚未执行。"})
        return
    end
    if request==nil or request.id~=args.approval_id or request.used or Now()>=request.expires then Fail("approval_expired");return end
    if request.skill~=skill or request.count~=count or request.paused~=paused or request.target~=target then Fail("approval_mismatch");return end
    if request.origin==context.id then Fail("reason_requires_next_player_message");return end
    if type(args.reason)~="string" or args.reason~=context.text or type(args.approved)~="boolean"
        or type(args.assessment)~="string" or #args.assessment==0 or #args.assessment>600 then Fail("reason_review_required");return end
    request.used=true
    if not args.approved then callback(true,{requested=false,rejected=true,assessment=args.assessment});return end
    local operation,result
    if skill=="save_game"then
        if type(c_save)~="function"then Fail("world_operation_unavailable");return end
        operation=function()c_save()end;result={requested=true,operation="save"}
    elseif skill=="rollback_game"then
        if type(c_rollback)~="function"then Fail("world_operation_unavailable");return end
        operation=function()c_rollback(count)end;result={requested=true,operation="rollback",count=count,reconnect_expected=true}
    elseif skill=="pause_game"then
        if TheNet==nil or TheNet.SetServerPaused==nil then Fail("world_operation_unavailable");return end
        operation=function()TheNet:SetServerPaused(paused)end;result={requested=true,operation="pause",paused=paused}
    elseif target~=nil then
        local fn=skill=="kick_player" and TheNet.Kick or TheNet.Ban
        if type(fn)~="function"then Fail("world_operation_unavailable");return end
        operation=function()if Client(target)~=nil then fn(TheNet,target)end end
        result={requested=true,operation=skill,userid=target}
    else Fail("invalid_request");return end
    local world=TheWorld
    world:DoStaticTaskInTime(1,function()if world==TheWorld and world:IsValid()then operation()end end)
    callback(true,result)
end
function M.Call(player, skill, args, callback, dialogue)
    if TheWorld == nil or not TheWorld.ismastersim or player == nil or not UserID(player.userid) or not M.SKILLS[skill] or not require("my_friend_policy").IsLocalPlayer(player) then
        callback(false, nil, "world_permission_denied"); return
    end
    local original_callback=callback
    local world=TheWorld
    callback=function(ok,result,reason)
        if TheWorld==world and world:IsValid() then
            world._my_friend_world_review_view=world._my_friend_world_review_view or {}
            if ok and result and result.needs_reason then
                world._my_friend_world_review_view[player.userid]={id=result.approval_id,skill=result.skill,count=result.count,
                    paused=result.paused,target=result.userid,expires=Now()+300}
                local order=world._my_friend_world_review_order or {}
                world._my_friend_world_review_order=order
                order[#order+1]={userid=player.userid,id=result.approval_id}
                if #order>64 then
                    local old=table.remove(order,1)
                    local entry=world._my_friend_world_review_view[old.userid]
                    if entry~=nil and entry.id==old.id then world._my_friend_world_review_view[old.userid]=nil end
                end
            elseif ok and result and (result.requested or result.rejected) or reason=="approval_expired" then
                world._my_friend_world_review_view[player.userid]=nil
            end
        end
        original_callback(ok,result,reason)
    end
    local actor = {userid = player.userid, dialogue=dialogue}
    if Master() then Process(actor, skill, args, callback); return end
    if rpc == nil or not Shard_IsWorldAvailable(SHARDID.MASTER) then callback(false, nil, "master_shard_unavailable"); return end
    serial = serial + 1
    local id = tostring(GetTime()) .. ":" .. serial
    local world = TheWorld
    if not world._my_friend_world_control_cleanup then
        world._my_friend_world_control_cleanup = true
        world:ListenForEvent("onremove", function()
            for key, record in pairs(pending) do
                if record.world == world then
                    pending[key] = nil; record.timeout:Cancel(); record.callback(false, nil, "world_removed")
                end
            end
        end)
    end
    local record = {callback = callback, world = world}
    pending[id] = record
    record.timeout = world:DoStaticTaskInTime(8, function()
        if pending[id] ~= record then return end
        pending[id] = nil; callback(false, nil, "master_shard_timeout")
    end)
    Send("BodyWorldRequest", SHARDID.MASTER, {id = id, actor = actor, skill = skill, args = args})
end
function M.Install(api)
    rpc = api.SendModRPCToShard ~= nil and api or nil
    if api.AddShardModRPCHandler == nil then return end
    api.AddShardModRPCHandler("MyFriends", "BodyWorldRequest", function(source, payload)
        if TheWorld == nil or not TheWorld.ismastersim or not Master() or type(payload) ~= "string" or #payload > 10000 then return end
        local ok, data = pcall(json.decode, payload)
        if not ok or type(data) ~= "table" or type(data.id) ~= "string" or #data.id > 128
            or type(data.actor) ~= "table" or not UserID(data.actor.userid)
            or not M.SKILLS[data.skill] or type(data.args) ~= "table" then return end
        local world = TheWorld
        local receipts = world._my_friend_world_control_receipts or {order = {}, results = {}}
        world._my_friend_world_control_receipts = receipts
        local key = tostring(source) .. ":" .. data.id
        if receipts.results[key] ~= nil then Send("BodyWorldReply", source, receipts.results[key]); return end
        Process(data.actor, data.skill, data.args, function(accepted, result, reason)
            local reply = {id = data.id, accepted = accepted, result = result, reason = reason}
            receipts.results[key], receipts.order[#receipts.order + 1] = reply, key
            if #receipts.order > 64 then receipts.results[table.remove(receipts.order, 1)] = nil end
            Send("BodyWorldReply", source, reply)
        end)
    end)
    api.AddShardModRPCHandler("MyFriends", "BodyWorldReply", function(source, payload)
        if tostring(source) ~= tostring(SHARDID.MASTER) or type(payload) ~= "string" or #payload > 10000 then return end
        local ok, data = pcall(json.decode, payload)
        local record = ok and type(data) == "table" and pending[data.id] or nil
        if record == nil then return end
        pending[data.id] = nil; record.timeout:Cancel()
        if record.world == TheWorld and record.world:IsValid() then record.callback(data.accepted == true, data.result, data.reason) end
    end)
end
return M
