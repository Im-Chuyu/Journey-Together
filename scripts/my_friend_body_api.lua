-- Public body interface. Only JSON-safe snapshots/results leave the server.
local Policy = require("my_friend_policy")
local Observation = require("my_friend_body_observation")
local M = {}
M.NAMES = {"observe", "move_to", "pickup", "drop", "transfer", "equip", "unequip", "craft",
    "work", "eat", "cook", "use_item", "interact", "engage", "disengage", "follow", "say", "cancel", "get_action_status",
    "save_game", "rollback_game", "pause_game", "kick_player", "ban_player", "query_recipe", "query_sites", "get_capabilities", "harvest", "character_skill", "pickup_many", "work_many", "query_actions", "perform_action", "query_batch", "execute_sequence",
    "dismount", "emote", "revive"}
local KNOWN = {}; for _, name in ipairs(M.NAMES) do KNOWN[name] = true end
local TERMINAL = {completed = true, failed = true, cancelled = true, interrupted = true}
local session_serial = 0
local PHYSICAL = {move_to = true, pickup = true, drop = true, transfer = true, equip = true, unequip = true,
    craft = true, work = true, eat = true, cook = true, use_item = true, interact = true, engage = true, harvest = true, character_skill = true,
    pickup_many = true, work_many = true, perform_action = true, execute_sequence=true,
    dismount = true, emote = true, revive = true}
function M.PlanActive(inst)
    local state = inst._my_friend_body
    local plan = state ~= nil and state.plan or nil
    if plan ~= nil and (plan.revision ~= state.revision or GetTime() >= plan.until_time) then state.plan = nil; plan = nil end
    return plan ~= nil
end
function M.UpdatePlan(inst, data)
    local state = M.Valid(inst)
    local plan = state ~= nil and state.plan or nil
    if plan == nil or type(data) ~= "table" or data.id ~= plan.id or data.revision ~= state.revision then return end
    if data.active == true then plan.until_time = GetTime() + 30
    elseif data.active == false then
        state.plan = nil
        if state.active == nil then inst._my_friend_replan_requested = true end
    end
end
local REFLEXES = {body = true, revive = true, revive_return = true, ghost = true, ghost_follow = true,
    farewell = true, hurt = true, hurt_wait = true, combat = true, recover_combat_item = true, escape = true,
    light = true, seek_light = true, emergency_light_supply = true, emergency_fire = true, eat = true,
    watch_heal = true, wanda_dreadstone = true, wormwood_heal = true, wanda_refuel = true,
    temperature = true, repair = true, thermal_wait = true, base_fire = true, light_wait = true,
    rescue = true, food_return = true, dark_standby = true, backpack_recovery = true, vigil = true}
function M.AllowLocal(inst, id, context)
    local state = inst._my_friend_body
    local planning = state ~= nil and M.PlanActive(inst)
    if state == nil or state.active == nil and not planning then return true end
    if state.active ~= nil and state.active.delegated == "sit" and id == "sit" then return true end
    if planning and (id == "backpack_recovery" or id == "eat" and not context.emergency_food and (context.hunger or 1) >= .4) then return false end
    if REFLEXES[id] then return true end
    return (id == "food" or id == "container_food" or id == "food_route" or id == "cook")
        and (context.emergency_food or (context.hunger or 1) < .4) or false
end
local function Wake(inst)
    inst._my_friend_replan_requested = true
    if inst.brain ~= nil and inst.brain.ForceUpdate ~= nil then inst.brain:ForceUpdate() end
end
function M.CanConnect(inst, player)
    local active = inst ~= nil and player ~= nil and TheWorld ~= nil and TheWorld.ismastersim and TheWorld._my_friend == inst
        and inst._my_friend_model_enabled == true and inst:IsValid() and inst:HasTag("my_friend") and not inst._my_friend_possess_parked
        and not inst:HasTag("playerghost")
    if not active then return false end
    if player._my_friend_remote_speaker == true then return require("my_friend_body_chat").Available(inst, player) end
    return Policy.IsLocalPlayer(player)
end
function M.Authorize(inst, player)
    local leader = inst ~= nil and Policy.GetLeader(inst) or nil
    return M.CanConnect(inst, player) and (leader == nil or leader == player)
end
local PUBLIC = {observe = true, say = true, query_recipe = true, query_sites = true, query_actions = true, query_batch=true, get_capabilities = true, get_action_status = true,
    save_game = true, rollback_game = true, pause_game = true, kick_player = true, ban_player = true}
function M.Input(inst, player, text, request_id, require_name)
    local state = M.Valid(inst)
    if state == nil or not state.ready or not M.CanConnect(inst, player) then return false, "disconnected" end
    if type(text) ~= "string" or #text == 0 or #text > 2048 then return false, "invalid_text" end
    if require_name ~= false and require("my_friend_commands").AddressedMessage(inst, text) == nil then return false, "companion_name_required" end
    local input_time=(GetStaticTime or GetTime)()
    if input_time < (state.input_after[player.userid or player.GUID] or 0) then return false, "rate_limited" end
    state.input_after[player.userid or player.GUID] = input_time + .5
    state.input_serial = state.input_serial + 1
    local id = state.session .. ":input:" .. state.input_serial
    state.inputs[id] = {player = player, expires = GetTime() + 900, text=text}
    state.input_order[#state.input_order + 1] = id
    while #state.input_order > 64 do state.inputs[table.remove(state.input_order, 1)] = nil end
    local speaker = player._my_friend_remote_speaker and player.speaker or Observation.Describe(inst, state, player)
    if not player._my_friend_remote_speaker then speaker.same_shard = true end
    M.Emit(inst, {kind = "player_input", text = text, input_id = request_id, turn_id = id,
        speaker = speaker, can_work = M.Authorize(inst, player),
        world_control = player._my_friend_remote_speaker and player.world_control or require("my_friend_body_world").Status(player)})
    return true
end
function M.Emit(inst, record)
    local state = inst ~= nil and inst._my_friend_body or nil
    if state == nil then return end
    state.event_serial = state.event_serial + 1
    record.event_id = state.session .. ":" .. state.event_serial
    record.revision = state.revision
    state.events[#state.events + 1] = record
    if #state.events > 64 then table.remove(state.events, 1) end
    if state.on_emit ~= nil then state.on_emit() end
end
function M.Result(job)
    return {action_id = job.id, request_id = job.request_id, skill = job.skill,
        status = job.status, result = job.result, reason = job.reason}
end
function M.Finish(inst, job, status, result, reason)
    local state = inst._my_friend_body
    if state == nil or TERMINAL[job.status] then return end
    if status == "failed" and reason == "placement_blocked" and job.point ~= nil
        and (result == nil or result.nearby_obstacles == nil) then
        local sites = require("my_friend_body_sites")
        local recipe = job.recipe ~= nil and GetValidRecipe(job.recipe) or nil
        local item = job.item ~= nil and (Ents or {})[job.item] or nil
        result = result or {}
        result.placement = sites.Details(inst, state, job.point, sites.Spacing(recipe, item))
    end
    if job.parent ~= nil then
        if job.parent.skill=="execute_sequence"then return require("my_friend_body_composition").FinishChild(inst,job,status,result,reason)end
        return require("my_friend_body_batch").FinishChild(inst, job, status, result, reason)
    end
    if result==nil and job.skill=="execute_sequence" and job.steps~=nil then result=require("my_friend_body_composition").Result(job)end
    if result == nil and (job.skill == "pickup_many" or job.skill == "work_many") and job.queue ~= nil then
        result = require("my_friend_body_batch").PartialResult(job)
    end
    local cleanup = job.cleanup; job.cleanup = nil
    if cleanup ~= nil then cleanup() end
    job.status, job.result, job.reason = status, result, reason
    job.finished = GetTime()
    local owned_body = state.active == job
    if owned_body then state.active = nil end
    if job.delegated == "sit" and status == "completed" then state.plan = nil end
    if state.pending == job then state.pending = nil end
    job.args, job.action = nil, nil
    M.Emit(inst, M.Result(job))
    -- Delegated seating is already owned by the normal Sit node. Forcing a
    -- selector restart here would immediately eject it from the chair.
    if owned_body and job.delegated == nil then Wake(inst) end
end
function M.Open(inst, player)
    if not M.CanConnect(inst, player) then return nil, "permission_denied" end
    if inst._my_friend_body ~= nil then return nil, "already_connected" end
    session_serial = session_serial + 1
    local state = {owner = player, session = tostring(inst.GUID) .. ":" .. tostring(GetTime()) .. ":" .. session_serial,
        jobs = {}, requests = {}, order = {}, serial = 0, event_serial = 0, events = {},
        handles = {}, by_guid = {}, handle_order = {}, handle_serial = 0, speech_pending = {}, revision = 0,
        next_context = GetTime() + math.random(60, 120),
        inputs = {}, input_order = {}, input_serial = 0, input_after = {}, input_requests = {}}
    inst._my_friend_body = state
    return state
end
function M.ManualTakeover(inst)
    local state = inst._my_friend_body
    if state == nil then return end
    state.revision = state.revision + 1
    state.plan = nil
    state.speech_pending, inst._my_friend_body_speaking = {}, nil
    if state.pending ~= nil then M.Finish(inst, state.pending, "cancelled", nil, "manual_command") end
    if state.active ~= nil then
        state.active.cancel_requested, state.active.cancel_reason = true, "manual_command"
        if not Policy.IsBusy(inst) then M.Finish(inst, state.active, "interrupted", nil, "manual_command") end
    end
    M.Emit(inst, {kind = "control_changed", reason = "manual_command"})
end
function M.Close(inst, reason)
    local state = inst ~= nil and inst._my_friend_body or nil
    if state == nil then return end
    if state.pending ~= nil then M.Finish(inst, state.pending, "interrupted", nil, reason or "disconnected") end
    if state.active ~= nil then M.Finish(inst, state.active, "interrupted", nil, reason or "disconnected") end
    if state.cleanup ~= nil then state.cleanup(reason or "disconnected") end
    inst._my_friend_body, inst._my_friend_body_speaking = nil, nil
    Wake(inst)
end
function M.Valid(inst)
    local state = inst ~= nil and inst._my_friend_body or nil
    return state ~= nil and M.CanConnect(inst, state.owner) and state or nil
end
function M.LeaderAllows(inst, job)
    if not Policy.IsLeaderDead(inst) then return true end
    if job == nil or job.issuer ~= Policy.GetLeader(inst) or not job.issuer:HasTag("playerghost") then return false end
    return job.skill == "execute_sequence" or job.skill == "revive" or job.skill == "pickup"
        or job.skill == "dismount" or job.skill == "move_to"
        or job.skill == "craft" and job.args.recipe == "reviver"
end
function M.Blocked(inst, state, job)
    local c = inst.components
    return inst:HasTag("playerghost") or state.blocked == true or not M.LeaderAllows(inst, job)
        or c.health ~= nil and c.health:IsDead()
        or c.hunger ~= nil and c.hunger.GetPercent ~= nil and c.hunger:GetPercent() < .4
        or inst.LightWatcher ~= nil and require("my_friend_light_ai").IsDark(inst)
        or c.temperature ~= nil and require("my_friend_survival_ai").NeedsTemperatureHelp(inst)
            and not require("my_friend_survival_ai").IsShadeComfortOnly(inst)
        or GetTime() < (inst._my_friend_hurt_evade_until or 0)
        or GetTime() < (inst._my_friend_hurt_until or 0)
        or (state.threat or inst._my_friend_under_threat) and (job == nil or job.skill ~= "engage") or false
end
function M.Blockers(inst,state,job)
    local out,c={},inst.components
    local function Add(test,id) if test then out[#out+1]=id end end
    Add(inst:HasTag("playerghost"),"ghost")
    Add(not M.LeaderAllows(inst,job),"leader_dead")
    Add(c.health~=nil and c.health:IsDead(),"dead")
    Add(c.hunger~=nil and c.hunger.GetPercent~=nil and c.hunger:GetPercent()<.4,"low_hunger")
    Add(inst.LightWatcher~=nil and require("my_friend_light_ai").IsDark(inst),"darkness")
    Add(c.temperature~=nil and require("my_friend_survival_ai").NeedsTemperatureHelp(inst)
        and not require("my_friend_survival_ai").IsShadeComfortOnly(inst),"temperature")
    Add(GetTime()<(inst._my_friend_hurt_evade_until or 0),"hurt_evade")
    Add(GetTime()<(inst._my_friend_hurt_until or 0),"recent_hurt")
    Add((state.threat or inst._my_friend_under_threat) and (job==nil or job.skill~="engage"),"threat")
    if #out==0 and state.blocked then out[1]="survival_recheck" end
    return out
end
local function Duration(skill)
    if skill == "execute_sequence" or skill == "move_to" then return 600 end
    if skill == "cook" or skill == "harvest" or skill == "character_skill" or skill == "pickup_many" or skill == "work_many" then return 300 end
    return 120
end
local function StartPending(inst, state)
    local job = state.pending
    if job == nil or state.active ~= nil or Policy.IsBusy(inst) or M.Blocked(inst, state, job) then return end
    state.pending = nil
    job.deadline = GetTime() + Duration(job.skill)
    require("my_friend_commands").Clear(inst, state)
    if job.skill == "follow" then
        local target = job.args.player ~= nil and Observation.Resolve(state, job.args.player) or job.issuer
        if target ~= job.issuer then M.Finish(inst, job, "failed", nil, "follow_current_speaker_only"); return end
        local accepted, reason = require("my_friend_follow_request").Apply(inst, target, nil, true)
        M.Finish(inst, job, accepted and reason == "follow_ok" and "completed" or "failed",
            {following = reason == "follow_ok", player = Observation.Handle(state, target), mode = "legacy", distance = Policy.FOLLOW_RANGE},
            reason ~= "follow_ok" and reason or nil)
        Wake(inst)
        return
    end
    local ok, reason, details = require("my_friend_body_actions").Prepare(inst, state, job)
    if not ok then M.Finish(inst, job, "failed", details, reason)
    else state.active = job; job.stage = job.stage or "ready"; M.Emit(inst, M.Result(job)); Wake(inst) end
end
function M.Tick(inst)
    local state = M.Valid(inst)
    if state == nil then if inst ~= nil and inst._my_friend_body ~= nil then M.Close(inst, "owner_or_body_changed") end; return end
    for _, job in ipairs({state.pending or false, state.active or false}) do
        if job and not M.Authorize(inst, job.issuer) then
            job.cancel_requested, job.cancel_reason = true, "speaker_permission_changed"
            state.plan = nil
            if job == state.pending or not Policy.IsBusy(inst) then M.Finish(inst, job, "interrupted", nil, "speaker_permission_changed") end
        end
    end
    if state.pending ~= nil and GetTime() >= state.pending.deadline then
        M.Finish(inst, state.pending, "failed", {blockers=M.Blockers(inst,state,state.pending),busy=Policy.IsBusy(inst)}, "unsafe_or_busy_timeout")
    end
    local job = state.active
    if job ~= nil and job.delegated == "sit" then
        local chair = (Ents or {})[job.target]
        local sg = inst.sg
        if not job.cancel_requested and chair ~= nil and chair:IsValid() and sg ~= nil
            and sg.currentstate.name == "sitting" and sg.statemem ~= nil and sg.statemem.chair == chair then
            job.keep_seat = true
            M.Finish(inst, job, "completed", {action = "SITON", target = job.args.target, seated = true})
            return
        elseif chair == nil or not chair:IsValid() or inst._my_friend_seat_request ~= job.seat_request then
            M.Finish(inst, job, "failed", nil, "seat_unavailable"); return
        end
        if job.status == "accepted" and inst._my_friend_sitting ~= nil then
            job.status, job.stage = "running", "walking_to_seat"; M.Emit(inst, M.Result(job))
        end
    end
    if job ~= nil and not Policy.IsBusy(inst) then
        if job.cancel_requested then M.Finish(inst, job, job.cancel_reason == "manual_command" and "interrupted" or "cancelled", nil, job.cancel_reason or "cancelled_by_user")
        elseif GetTime() >= job.deadline then M.Finish(inst, job, "failed", nil, "timeout") end
    end
    StartPending(inst, state)
end
local function Finite(n) return type(n) == "number" and n == n and math.abs(n) < 1000000 end
function M.InTravelRange(inst, action, point)
    local state = M.Valid(inst)
    local job = state ~= nil and state.active or nil
    local operation = action ~= nil and action._body_job or job
    local origin = operation ~= nil and operation.origin or nil
    return job ~= nil and action ~= nil and action._my_friend_body_action == job.id
        and GetTime() < job.deadline and point ~= nil and Finite(point.x) and Finite(point.z)
        and origin ~= nil and (point.x - origin.x)^2 + (point.z - origin.z)^2 <= 96^2
end
function M.Score(inst, context)
    local raw = inst._my_friend_body
    local awaiting = raw ~= nil and raw.pending or nil
    local replan_before = inst._my_friend_replan_requested
    if raw ~= nil then
        raw.blocked = context.ghost or context.hurt or context.hurt_evade
            or context.dark or context.thermal and not context.thermal_shade or context.hunger ~= nil and context.hunger < .4 or false
        raw.threat = context.threat ~= nil
    end
    M.Tick(inst)
    -- Starting a deferred job while this selector is already ranking must
    -- not leave a new forced-replan flag that kills that same job next tick.
    if awaiting ~= nil and raw.active == awaiting and not replan_before then
        inst._my_friend_replan_requested = nil
    end
    local state = M.Valid(inst)
    if state == nil then return 0 end
    local job = state.active
    if inst._my_friend_command ~= nil and (job == nil or inst._my_friend_command ~= job.command) then return 0 end
    if job == nil then return 0 end
    if job.delegated ~= nil then return 0 end
    if context.ghost or context.leaderdead and not M.LeaderAllows(inst, job) or context.hurt or context.hurt_evade or context.dark or context.thermal and not context.thermal_shade
        or context.hunger ~= nil and context.hunger < .4
        or context.threat ~= nil and (job == nil or job.skill ~= "engage") then return 0 end
    local step = job.child or job
    if step.skill == "revive" then return 145 end
    return (job.skill == "engage" or job.skill == "character_skill" and job.ability == "heal_self") and 132 or 112
end
function M.Call(inst, player, request_id, skill, args, revision, source, plan_id, turn_id)
    local state = M.Valid(inst)
    if state == nil or not M.CanConnect(inst, player) then return {status = "failed", reason = "permission_denied"} end
    local dialogue
    if turn_id ~= nil then
        local input = type(turn_id) == "string" and state.inputs[turn_id] or nil
        if player ~= state.owner or input == nil or GetTime() > input.expires then return {status = "failed", reason = "invalid_input_context"} end
        dialogue={id=turn_id,text=input.text}
        player = input.player
        if not M.CanConnect(inst, player) then return {status = "failed", reason = "speaker_left"} end
    end
    if not PUBLIC[skill] and not M.Authorize(inst, player) then return {status = "failed", reason = "leader_only_work"} end
    if revision ~= nil and revision ~= state.revision then return {status = "failed", reason = "superseded"} end
    if source == "ambient" and skill ~= "say" then return {status = "failed", reason = "ambient_chat_only"} end
    if source == "ambient" and M.Blocked(inst, state, nil) then return {status = "failed", reason = "unsafe_for_idle_chat"} end
    if type(request_id) ~= "string" or #request_id < 1 or #request_id > 80
        or type(skill) ~= "string" or not KNOWN[skill] or type(args) ~= "table"
        or plan_id ~= nil and (type(plan_id) ~= "string" or #plan_id < 1 or #plan_id > 80) then
        return {status = "failed", reason = "invalid_request"}
    end
    if player._my_friend_remote_speaker and (skill == "follow" or skill == "character_skill"
        and not require("my_friend_body_characters").IsControl(args.ability) and args.ability ~= "heal_self") then
        return {status = "failed", reason = "speaker_in_other_shard"}
    end
    local old = state.requests[request_id]
    if old ~= nil then return M.Result(old) end
    if skill == "transfer" then
        local recipient = Observation.Resolve(state, args.destination)
        if recipient ~= nil and recipient:HasTag("playerghost") then return {status = "failed", reason = "recipient_ghost_use_revive"} end
    end
    if PHYSICAL[skill] and not M.LeaderAllows(inst, {skill = skill, args = args, issuer = player}) then
        return {status = "failed", reason = "leader_dead"}
    end
    if skill=="execute_sequence"then
        local ok,reason=require("my_friend_body_composition").Validate(args)
        if not ok then return {status="failed",reason=reason}end
    end
    if skill == "character_skill" then
        local allowed, reason = require("my_friend_body_characters").Validate(inst, state, args)
        if not allowed then return {status = "failed", reason = reason} end
    end
    if skill == "get_action_status" then
        local job = state.jobs[args.action_id]
        return job ~= nil and M.Result(job) or {status = "failed", reason = "unknown_action"}
    end
    if skill == "cancel" then
        local job = state.jobs[args.action_id]
        if job == nil then return {status = "failed", reason = "unknown_action"} end
        if job == state.pending then M.Finish(inst, job, "cancelled", nil, "cancelled_by_user")
        elseif not TERMINAL[job.status] then job.cancel_requested = true; M.Tick(inst); Wake(inst) end
        return M.Result(job)
    end
    if skill == "observe" then
        if GetTime() < (state.observe_after or 0) then return {status = "failed", reason = "rate_limited"} end
        if not Observation.ValidScan(args) then
            return {status = "failed", reason = "invalid_arguments"}
        end
        state.observe_after = GetTime() + .3
    end
    state.serial = state.serial + 1
    local job = {id = state.session .. ":a" .. state.serial, request_id = request_id, skill = skill,
        args = args, issuer = player, status = "accepted", origin = inst:GetPosition(),
        deadline = GetTime() + Duration(skill)}
    state.jobs[job.id], state.requests[request_id] = job, job
    state.order[#state.order + 1] = job.id
    while #state.order > 40 do
        local oldest = 1
        while oldest <= #state.order and (state.jobs[state.order[oldest]] == state.active
            and state.active ~= nil or state.jobs[state.order[oldest]] == state.pending and state.pending ~= nil) do oldest = oldest + 1 end
        local id = table.remove(state.order, oldest)
        local previous = state.jobs[id]
        if previous ~= nil and previous ~= state.active then state.requests[previous.request_id], state.jobs[id] = nil, nil end
    end
    if skill == "observe" then
        local scan, reason = Observation.Scan(inst,state,args)
        local result=require("my_friend_body_composition").LimitResult(scan,18000)
        M.Finish(inst,job,result~=nil and "completed" or "failed",result,result==nil and (reason or "query_result_too_large") or nil)
    elseif skill == "query_sites" then
        local result, reason = require("my_friend_body_sites").Query(inst, state, args)
        M.Finish(inst, job, result ~= nil and "completed" or "failed", result, reason)
    elseif skill == "query_recipe" then
        local result, reason = require("my_friend_body_recipes").Query(inst, state, args)
        M.Finish(inst, job, result ~= nil and "completed" or "failed", result, reason)
    elseif skill == "query_actions" then
        local result, reason = require("my_friend_body_native").Query(inst,state,args)
        M.Finish(inst,job,result ~= nil and "completed" or "failed",result,reason)
    elseif skill=="query_batch"then
        local result,reason=require("my_friend_body_composition").Query(inst,state,args)
        M.Finish(inst,job,result~=nil and "completed" or "failed",result,reason)
    elseif skill == "get_capabilities" then
        M.Finish(inst, job, "completed", require("my_friend_body_recipes").Capabilities(inst))
    elseif skill == "character_skill" and require("my_friend_body_characters").IsControl(args.ability) then
        local ok = require("my_friend_body_characters").Control(inst, args.ability)
        M.Finish(inst, job, ok and "completed" or "failed", {ability = args.ability, character = inst.prefab},
            not ok and (inst.prefab ~= "wendy" and "unsupported_character_ability" or "character_ability_unavailable") or nil)
    elseif require("my_friend_body_world").SKILLS[skill] then
        local called_revision = state.revision
        local invoke = player._my_friend_remote_speaker and require("my_friend_body_chat").WorldCall or require("my_friend_body_world").Call
        invoke(player, skill, args, function(ok, result, reason)
            if not inst:IsValid() or M.Valid(inst) ~= state then return end
            if state.revision ~= called_revision then M.Finish(inst, job, "interrupted", nil, "superseded"); return end
            M.Finish(inst, job, ok and "completed" or "failed", result, reason)
        end,dialogue)
    elseif skill == "say" then
        if type(args.text) ~= "string" or #args.text == 0 or #args.text > 600 or args.text:find("[%z\1-\8\11\12\14-\31]") then
            M.Finish(inst, job, "failed", nil, "invalid_text")
        else
            if args.speak ~= false then
                state.speech_pending[job.id] = true
                inst._my_friend_body_speaking = GetTime() + 15
                require("my_friend_voice").StopCustom(inst)
            end
            local spoken = require("my_friend_dialogue").Reply(inst, "ai_dynamic", args.text)
            if spoken and player._my_friend_remote_speaker then require("my_friend_body_chat").Reply(inst, player, job.id, args.text) end
            M.Finish(inst, job, spoken and "completed" or "failed",
                {text = args.text, speech = args.speak == false and "disabled" or "external_pending"}, not spoken and "talker_unavailable" or nil)
        end
    elseif skill == "disengage" then
        state.plan = nil
        if state.active ~= nil then state.active.cancel_requested = true; M.Tick(inst) end
        require("my_friend_combat_rules").DisengageForFollow(inst, player)
        M.Finish(inst, job, "completed", {combat = "disengaged"})
    else
        if PHYSICAL[skill] and plan_id ~= nil then state.plan = {id = plan_id, revision = state.revision, until_time = GetTime() + 30}
        elseif skill == "follow" or PHYSICAL[skill] then state.plan = nil end
        if state.pending ~= nil then M.Finish(inst, state.pending, "cancelled", nil, "superseded") end
        if state.active ~= nil then state.active.cancel_requested, state.active.cancel_reason = true, "superseded" end
        job.stage, state.pending = "waiting_for_safe_boundary", job
        M.Emit(inst, M.Result(job))
        M.Tick(inst)
        if state.pending == job and not M.Blocked(inst, state, job) then Wake(inst) end
    end
    return M.Result(job)
end
function M.Playback(inst, action_id, status)
    local state = inst._my_friend_body
    local job = state ~= nil and state.jobs[action_id] or nil
    if job == nil or job.skill ~= "say" or job.result == nil
        or not ({queued = true, playing = true, completed = true, failed = true, disabled = true})[status] then return end
    if job.result.speech == status then return end
    job.result.speech = status
    if status == "playing" then inst._my_friend_body_speaking = GetTime() + 90
    elseif status == "completed" or status == "failed" or status == "disabled" then state.speech_pending[action_id] = nil end
    if next(state.speech_pending) == nil then inst._my_friend_body_speaking = nil end
    M.Emit(inst, {request_id = job.request_id, action_id = action_id, skill = "say", status = "speech", result = job.result})
end
function M.GetAction(inst)
    M.Tick(inst)
    local state = M.Valid(inst)
    local job = state ~= nil and state.active or nil
    if job == nil or Policy.IsBusy(inst) then return end
    if job.status == "accepted" then job.status = "running"; M.Emit(inst, M.Result(job)) end
    local action = job.action
    if action == nil then
        if job.skill == "execute_sequence" then
            action = require("my_friend_body_composition").GetAction(inst, state, job)
        elseif job.skill == "pickup_many" or job.skill == "work_many" then
            action = require("my_friend_body_batch").GetAction(inst, state, job)
        else
            action = require("my_friend_body_actions").GetAction(inst, state, job)
        end
    end
    if action == nil or action._body_job == nil or action._body_job.heavy_carry then return action end
    local ready, reason, surface, point = require("my_friend_body_travel").ApproachAction(inst, action)
    if reason ~= nil then
        local step, current = action._body_job, inst:GetPosition()
        M.Finish(inst, step, "failed", {progress = step.progress or 0, stage = step.stage,
            target_surface = surface, distance = Observation.Distance(current, point),
            position = {x = current.x, z = current.z}}, reason)
    end
    return ready
end
function M.Configure(inst)
    if inst._my_friend_body_configured then return end
    inst._my_friend_body_configured = true
    for _, event in ipairs({"onremove", "death", "ms_becameghost"}) do
        local reason = event
        inst:ListenForEvent(event, function() M.Close(inst, reason) end)
    end
end
M.Observation = Observation
return M
