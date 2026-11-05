-- Implementations use vanilla BufferedActions and inventory/component interfaces.
local Observation = require("my_friend_body_observation")
local Inventory = require("my_friend_inventory")
local Storage = require("my_friend_body_storage")
local Policy = require("my_friend_policy")
local M = {}
local LEGACY_USES = {HEAL=true,SEW=true,REPAIR=true,ADDFUEL=true,FERTILIZE=true,READ=true,CAST_POCKETWATCH=true}
local function API() return require("my_friend_body_api") end
local function Owned(inst, item)
    local inv = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    return inv ~= nil and not inv.islockedinslot and inv:GetGrandOwner() == inst
end
local function Resolve(job, field)
    local entity = job[field] ~= nil and (Ents or {})[job[field]] or nil
    return entity ~= nil and entity:IsValid() and entity or nil
end
local function PotAvailable(inst, pot)
    local c = pot ~= nil and pot:IsValid() and pot.components.container or nil
    return c ~= nil and pot.components.stewer ~= nil and require("my_friend_cookpot").PREFABS[pot.prefab]
        and require("my_friend_cookpot").IsAllowed(inst, pot) and Inventory.CanWithdrawFrom(inst, pot, true)
        and inst:GetDistanceSqToInst(pot) <= 20^2 and inst:GetCurrentPlatform() == pot:GetCurrentPlatform()
        and not pot:HasAnyTag("INLIMBO", "burnt", "fire")
end
local function Finite(n) return type(n) == "number" and n == n and math.abs(n) < 1000000 end
local function Count(inst, prefab)
    local total = 0
    for _, item in ipairs(Observation.Items(inst)) do if item.prefab == prefab then total = total + Observation.Size(item) end end
    return total
end
local function Fail(inst, job, reason, details) API().Finish(inst, job, "failed", details or {progress = job.progress or 0, stage = job.stage}, reason) end
local function Done(inst, job, result) API().Finish(inst, job, "completed", result) end
local function ReleaseItem(inst, item)
    local equip = item.components.equippable
    -- Removed() reclaims a removed backpack before its recovery cooldown.
    -- A spare bag must not replace ownership of the bag still being worn.
    if equip ~= nil and (not item:HasTag("backpack") or inst._my_friend_owned_backpack == item) then
        require("my_friend_equipment").Removed(inst, equip.equipslot, item)
    end
    if item:HasTag("backpack") then
        local bags = require("my_friend_backpacks")
        bags.ClearOwned(item)
        if inst._my_friend_owned_backpack == item then inst._my_friend_owned_backpack = nil end
        if inst._my_friend_backpack_target == item then bags.CancelRecovery(inst) end
    end
end
local function ProductItems(inst, state, prefab)
    local out = {}
    for _, item in ipairs(Observation.Items(inst)) do
        if item.prefab == prefab and #out < 12 then out[#out + 1] = Observation.Describe(inst, state, item) end
    end
    return out
end
local function BeginWork(inst, job, target)
    -- The batch parent reports totals and never exposes individual drop lists.
    if job.work_before ~= nil or job.parent ~= nil and job.parent.skill == "work_many" then return end
    job.work_before,job.ground_before,job.work_point = {},{},target:GetPosition()
    if job.drop_prefab ~= nil then
        local function OnDrop(_, data)
            local action, loot = job.action, data ~= nil and data.loot or nil
            if action ~= nil and inst.bufferedaction == action and action.target == target
                and loot ~= nil and loot:IsValid() and loot.prefab == job.drop_prefab then
                job.drop_guid = loot.GUID
            end
        end
        inst:ListenForEvent("loot_prefab_spawned", OnDrop, target)
        job.cleanup = function() inst:RemoveEventCallback("loot_prefab_spawned", OnDrop, target) end
    end
    for _,item in ipairs(Observation.Items(inst)) do
        job.work_before[item.prefab]=(job.work_before[item.prefab] or 0)+Observation.Size(item)
    end
    local p=job.work_point
    for _,item in ipairs(TheSim:FindEntities(p.x,0,p.z,4,nil,{"INLIMBO","FX"})) do
        if item.components.inventoryitem~=nil and item.components.inventoryitem.owner==nil then
            job.ground_before[item.GUID]=Observation.Size(item)
        end
    end
end
local function WorkResult(inst,state,job,details)
    details.items,details.gained,details.ground_items={},{},{}
    if job.work_before==nil then return details end
    local counts={}
    for _,item in ipairs(Observation.Items(inst)) do counts[item.prefab]=(counts[item.prefab] or 0)+Observation.Size(item) end
    for prefab,count in pairs(counts) do
        local gained=count-(job.work_before[prefab] or 0)
        if gained>0 then
            details.gained[#details.gained+1]={prefab=prefab,count=gained}
            for _,entry in ipairs(ProductItems(inst,state,prefab)) do
                if #details.items<12 then details.items[#details.items+1]=entry else details.limited=true end
            end
        end
    end
    local p=job.work_point
    for _,item in ipairs(TheSim:FindEntities(p.x,0,p.z,4,nil,{"INLIMBO","FX"})) do
        if item.components.inventoryitem~=nil and item.components.inventoryitem.owner==nil
            and Observation.Size(item)>(job.ground_before[item.GUID] or 0) then
            if #details.ground_items<12 then details.ground_items[#details.ground_items+1]=Observation.Describe(inst,state,item)
            else details.limited=true end
        end
    end
    return details
end
local function FinishWork(inst, state, job, details)
    local result = WorkResult(inst, state, job, details)
    if job.drop_prefab ~= nil then
        local loot = job.drop_guid ~= nil and (Ents or {})[job.drop_guid] or nil
        local item = loot ~= nil and loot:IsValid() and loot.components.inventoryitem or nil
        if item == nil or item.owner ~= nil or loot:IsInLimbo() then
            result.expected_drop = job.drop_prefab
            Fail(inst, job, "expected_drop_missing", result)
            return
        end
        result.drop = Observation.Describe(inst, state, loot)
    end
    Done(inst, job, result)
end
local function Current(inst, job)
    local state = API().Valid(inst)
    local parent=job
    while parent.parent~=nil do
        if parent.cancel_requested or parent.parent.child~=parent then return false end
        parent=parent.parent
    end
    return state ~= nil and state.active == parent and not parent.cancel_requested
end
local function ValidItem(item)
    return item ~= nil and item:IsValid() and item.components.inventoryitem ~= nil
        and not item.components.inventoryitem.islockedinslot
end
local function Usable(item)
    return ValidItem(item) and (item.components.finiteuses == nil or item.components.finiteuses:GetPercent() > 0)
end
local function EquippedLocked(item)
    local e = item ~= nil and item.components.equippable or nil
    return e ~= nil and e:IsEquipped() and e:ShouldPreventUnequipping()
end
local function Riding(inst)
    return inst.components.rider ~= nil and inst.components.rider:IsRiding()
end
local function Source(job, item)
    local owner = item.components.inventoryitem.owner
    if job.container ~= nil then
        local opening = Resolve(job, "container")
        local _, master = Storage.Resolve(opening)
        if master == nil or master ~= owner then return nil, "item_moved" end
        return opening
    end
    if owner ~= nil and owner:HasTag("pocketdimension_container") then return nil, "storage_opening_required" end
    return owner
end
local function PlayerCanReceive(player)
    local inventory = player.components.inventory
    return inventory ~= nil and not player:HasTag("playerghost") and not player:HasTag("reviving")
        and (player.components.health == nil or not player.components.health:IsDead())
        and (inventory.IsOpenedBy == nil or inventory:IsOpenedBy(player))
end
local function ContainerIsOpen(inst, target, share_leader)
    local _, _, opening = Storage.Resolve(target)
    if opening == nil then return false end
    if opening:IsOpenedBy(inst) then return true end
    local leader = share_leader and Policy.GetLeader(inst) or nil
    return leader ~= nil and opening:IsOpenedBy(leader) or false
end
local function TrackContainer(inst, job, target)
    local _, _, opening = Storage.Resolve(target)
    local previous = job.cleanup
    -- Only attach this after deciding to open a new container ourselves.
    -- Finish/Dispose also run this for sequence children, cancellation and loss
    -- of the controller. Never close a leader's or pre-existing opener.
    job.cleanup = function()
        if previous ~= nil then previous() end
        local _, _, current = Storage.Resolve(target)
        if current == opening and current ~= nil and opening:IsOpenedBy(inst) then
            opening:Close(inst)
            if inst:IsValid() then inst:PushEvent("closecontainer", {container=target}) end
        end
    end
end
local function Make(inst, job, target, kind, item, point, success, validate)
    local action = BufferedAction(inst, target, kind, item, point)
    action._my_friend_body_action, action._body_job = job.id, job
    action.validfn = function()
        return Current(inst, job) and (target == nil or target:IsValid())
            and (item == nil or ValidItem(item) and (job.skill == "pickup" or Owned(inst, item)))
            and (validate == nil or validate())
    end
    action:AddSuccessAction(function()
        if not Current(inst, job) then return end
        job.action = nil
        if success ~= nil then success(action) end
    end)
    action:AddFailAction(function()
        if not Current(inst, job) then return end
        job.action = nil
        local details = {progress = job.progress or 0, stage = job.stage}
        if job.skill == "craft" and inst.components.builder.IsBuildBuffered ~= nil then
            details.prepared = inst.components.builder:IsBuildBuffered(job.recipe) == true
        end
        API().Finish(inst, job, action._my_friend_cancelled and "interrupted" or "failed",
            details, action._my_friend_path_failed and "unreachable"
            or action._my_friend_cancelled and "preempted" or job.operation_error or action.reason or "action_failed")
    end)
    job.action = action
    return require("my_friend_policy").GuardAction(inst, action)
end
local function WorkSwing(inst, state, job, target, kind, tool, validate)
    return Make(inst, job, target, kind, tool, nil, function()
        job.progress = job.progress + 1
        if job.progress >= job.count then FinishWork(inst, state, job, {work_units = job.progress}) end
    end, validate)
end

function M.RepeatWork(inst, previous)
    local job, target, kind, tool = previous._body_job, previous.target, previous.action, previous.invobject
    if job == nil or job.skill ~= "work" or job.action ~= nil or job.progress >= job.count
        or target == nil or not target:IsValid() or job.target ~= target.GUID or ACTIONS[job.verb] ~= kind
        or not Current(inst, job) then return end
    local api = API()
    local state = api.Valid(inst)
    local distance = require("my_friend_navigation").ArrivalDistance(inst, previous) + .1
    local function Ready()
        if GetTime() >= job.deadline or not api.Authorize(inst, job.issuer) or api.Blocked(inst, state, job)
            or not target:IsValid() or target:IsInLimbo() or inst:GetDistanceSqToInst(target) > distance^2
            or not Inventory.IsUsableTool(inst, tool, kind)
            or inst.components.inventory:GetEquippedItem(tool.components.equippable.equipslot) ~= tool
            or not require("my_friend_base_ai").CanUseHandToolInCurrentLight(inst) then return false end
        local workable = target.components.workable
        return workable ~= nil and workable:CanBeWorked() and workable:GetWorkAction() == kind
            and target:IsActionValid(kind, kind == ACTIONS.HAMMER or kind == ACTIONS.DIG)
            and CanEntitySeeTarget(inst, target)
    end
    if not Ready() then return end
    local action = WorkSwing(inst, state, job, target, kind, tool, Ready)
    require("my_friend_resource_safety").GuardAction(inst, action)
    if not action:IsValid() then job.action = nil; return end
    return action
end

function M.Prepare(inst, state, job)
    local a, skill = job.args, job.skill
    if not API().LeaderAllows(inst, job) then return false, "leader_dead" end
    if skill=="execute_sequence" then return require("my_friend_body_composition").Prepare(inst,state,job)end
    if skill == "pickup_many" or skill == "work_many" then return require("my_friend_body_batch").Prepare(inst, state, job) end
    if a.count ~= nil and (not Finite(a.count) or a.count % 1 ~= 0 or a.count < 1 or a.count > 40)
        or a.amount ~= nil and (not Finite(a.amount) or a.amount % 1 ~= 0 or a.amount < 1 or a.amount > 40) then return false, "invalid_count" end
    job.count, job.progress = a.count or a.amount or 1, 0
    for _, key in ipairs({"target", "item", "destination", "station", "player", "container"}) do
        if a[key] ~= nil and not (skill == "move_to" and key == "destination") then
            local entity = Observation.Resolve(state, a[key])
            if entity == nil then
                if not (skill == "revive" and key == "item") then return false, "unknown_handle:" .. key end
            else job[key] = entity.GUID end
        end
    end
    if skill == "interact" and not ({SITON=true,TURNON=true,TURNOFF=true,ACTIVATE=true})[a.action] then
        a.mode="SCENE"
        return require("my_friend_body_native").Prepare(inst,state,job)
    end
    if skill == "transfer" then
        local destination=Resolve(job,"destination")
        local item=Resolve(job,"item")
        if destination ~= nil and Policy.IsLocalPlayer(destination) and not PlayerCanReceive(destination) then
            return false, destination:HasTag("playerghost") and "recipient_ghost_use_revive" or "recipient_unavailable"
        end
        if item~=nil and item.components.inventoryitem~=nil and item.components.inventoryitem.cangoincontainer==false then
            return false,"item_cannot_be_stored_drop_near_recipient"
        end
        if destination~=nil and destination.components.trader~=nil and Storage.Resolve(destination)==nil
            and not require("my_friend_policy").IsLocalPlayer(destination) then
            a.target,a.action,a.mode=a.destination,"GIVE","USEITEM"
            return require("my_friend_body_native").Prepare(inst,state,job)
        end
    end
    if skill == "perform_action" or skill == "use_item" and a.action ~= nil and not LEGACY_USES[a.action] then
        local ok,reason,details=require("my_friend_body_native").Prepare(inst,state,job)
        if ok and a.action=="SITON" and job.native_mode=="SCENE" then
            job.native=nil;local original=job.skill;job.skill="interact"
            ok,reason=M.Prepare(inst,state,job);job.skill=original
        end
        return ok,reason,details
    end
    if skill == "character_skill" then return require("my_friend_body_characters").Prepare(inst, state, job)
    elseif skill == "dismount" then
        return true
    elseif skill == "emote" then
        if require("my_friend_emotes").BodyData(a.emote) == nil then return false, "unknown_emote" end
    elseif skill == "revive" then
        local target, item = Resolve(job, "target"), Resolve(job, "item")
        if not Policy.IsLocalPlayer(target) then return false, "invalid_revive_target" end
        if target:HasTag("playerghost") and not target:HasTag("reviving")
            and (not ValidItem(item) or not Owned(inst, item) or not item:HasTag("reviver")) then return false, "reviver_required" end
    elseif skill == "move_to" then
        if a.gait ~= nil and a.gait ~= "walk" and a.gait ~= "run" then return false, "invalid_gait" end
        if a.target ~= nil and a.position ~= nil then return false, "choose_one_destination" end
        local travel = require("my_friend_body_travel")
        if a.destination ~= nil then
            local ok, reason = travel.Prepare(inst, job)
            if not ok then return false, reason end
        elseif job.target == nil then
            local p = a.position
            if type(p) ~= "table" or not Finite(p.x) or not Finite(p.z) then return false, "invalid_position" end
            if not travel.SetPosition(job, Vector3(p.x, 0, p.z)) then return false, "invalid_terrain" end
        end
        if a.distance ~= nil and (not Finite(a.distance) or a.distance < .3 or a.distance > 12) then return false, "invalid_distance" end
        job.gait, job.distance = a.gait or "run", a.distance or (a.destination == "base" and 5 or job.target ~= nil and 3 or .5)
    elseif skill == "interact" then
        local target = Resolve(job, "target")
        local issuer = job.issuer or state.owner
        local seat_player = issuer._my_friend_remote_speaker and inst or issuer
        local allowed, reason = require("my_friend_body_interactions").Validate(inst, target, a.action, seat_player)
        if not allowed then return false, reason end
        job.verb = a.action
        if a.action == "SITON" then
            local sitting = require("my_friend_sitting")
            local request = sitting.RequestTarget(inst, seat_player, target, true, issuer)
            if request == nil then return false, "seat_unavailable" end
            job.delegated, job.seat_request = "sit", request
            job.cleanup = function()
                if not job.keep_seat and inst._my_friend_seat_request == request then sitting.StopSitting(inst) end
            end
        elseif ACTIONS[a.action] == nil then return false, "unsupported_interaction" end
    elseif skill == "harvest" then
        local target = Resolve(job, "target")
        if a.wait ~= nil and type(a.wait) ~= "boolean" then return false, "invalid_wait" end
        if target == nil or not PotAvailable(inst, target)
            or not (target.components.stewer:IsDone() or a.wait == true and target.components.stewer:IsCooking()) then
            return false, "product_not_ready"
        end
        if a.recipe ~= nil and a.recipe ~= target.components.stewer.product then return false, "unexpected_recipe" end
    elseif skill == "pickup" or skill == "engage" or skill == "work" then
        if job.target == nil then return false, "missing_target" end
        if skill=="pickup" and Resolve(job,"target"):HasTag("heavy") then
            return require("my_friend_body_carry").Prepare(inst,state,job)
        end
        if skill == "pickup" then
            local item = Resolve(job, "target")
            if not ValidItem(item) then return false, "invalid_item" end
            local source, reason = Source(job, item)
            if reason ~= nil then return false, reason end
            if a.count == nil and source == nil then job.count = Observation.Size(item) end
        end
        if skill == "engage" then
            local target = Resolve(job, "target")
            if target.components.health == nil or target.components.health:IsDead() or target.components.combat == nil
                or not require("my_friend_behavior_ai").CanCounterAttack(inst, target, true) then return false, "cannot_engage" end
            local fn = function() if Current(inst, job) then Done(inst, job, {target = a.target, defeated = true}) end end
            inst:ListenForEvent("death", fn, target)
            job.cleanup = function()
                inst:RemoveEventCallback("death", fn, target)
                if inst.components.combat ~= nil and inst.components.combat.target == target then inst.components.combat:SetTarget(nil) end
            end
        elseif skill == "work" then
            local item = Resolve(job,"target").components.inventoryitem
            if item ~= nil and item.owner ~= nil then return false,"work_requires_ground_target" end
            local allowed = {CHOP = true, MINE = true, DIG = true, HAMMER = true, PICK = true, HARVEST = true}
            if not allowed[a.action] or ACTIONS[a.action] == nil then return false, "unsupported_work" end
            job.verb = a.action
            if a.drop_prefab ~= nil then
                if type(a.drop_prefab) ~= "string" or #a.drop_prefab > 80 or not a.drop_prefab:match("^[%w_]+$") then
                    return false, "invalid_drop_prefab"
                end
                job.drop_prefab = a.drop_prefab
            end
            if a.amount == nil and a.action ~= "PICK" and a.action ~= "HARVEST" then
                job.until_finished,job.count=true,10000
            end
        end
    elseif skill == "craft" then
        if type(a.recipe) ~= "string" or #a.recipe > 80 or GetValidRecipe(a.recipe) == nil then return false, "unknown_recipe" end
        job.recipe = a.recipe
        local recipe = GetValidRecipe(a.recipe)
        job.craft_mode = a.mode or "auto"
        if job.craft_mode ~= "auto" and job.craft_mode ~= "prepare" and job.craft_mode ~= "place" then return false, "invalid_craft_mode" end
        if job.craft_mode ~= "auto" and (recipe.placer == nil or recipe.manufactured) then return false, "recipe_cannot_be_buffered" end
        if job.craft_mode == "prepare" and a.position ~= nil then return false, "prepare_has_no_placement" end
        if recipe.placer ~= nil and job.craft_mode ~= "prepare" and a.position == nil then return false, "placement_required" end
        if recipe.placer ~= nil and job.count > 1 then return false, "distinct_placement_steps_required" end
        if a.position ~= nil then
            if type(a.position) ~= "table" or not Finite(a.position.x) or not Finite(a.position.z)
                or (a.position.x - job.origin.x)^2 + (a.position.z - job.origin.z)^2 > 64^2 then return false, "invalid_position" end
            job.point = Vector3(a.position.x, 0, a.position.z)
        end
    elseif skill == "cook" then
        if a.wait~=nil and type(a.wait)~="boolean" then return false,"invalid_wait" end
        local station = Resolve(job, "station")
        local pot = require("my_friend_cookpot")
        if station == nil or not PotAvailable(inst, station) then return false, "station_unavailable" end
        local recipes = require("cooking").recipes[station.prefab]
        if type(a.recipe) ~= "string" or recipes == nil or recipes[a.recipe] == nil then return false, "unknown_recipe" end
        if a.ingredients ~= nil then
            local ok, reason = require("my_friend_body_cooking").Validate(inst,station.prefab,a.recipe,a.ingredients)
            if not ok then return false, reason end
            job.explicit_mix = true
        end
        if station._my_friend_recipe_job ~= nil or station._my_friend_body_cook ~= nil
            or station.components.stewer:IsCooking() or station.components.stewer:IsDone()
            or not station.components.container:IsEmpty() then return false, "station_busy" end
        job.recipe, job.stage, job.added = a.recipe, "planning", {}
        job.cleanup = function()
            if station:IsValid() and station._my_friend_body_cook == job.id then
                local c = station.components.container
                if c ~= nil and inst:IsValid() and not station.components.stewer:IsCooking() then
                    for guid in pairs(job.added) do
                        local item = (Ents or {})[guid]
                        if item ~= nil and item:IsValid() and item.components.inventoryitem.owner == station then
                            local moved = c:RemoveItem(item, true)
                            if moved ~= nil then moved.prevcontainer, moved.prevslot = nil, nil; Inventory.GiveCarried(inst, moved, inst:GetPosition()) end
                        end
                    end
                end
                if c ~= nil and c:IsOpenedBy(inst) then c:Close(inst); inst:PushEvent("closecontainer", {container = station}) end
                station._my_friend_body_cook = nil
            end
        end
    elseif skill == "unequip" then
        if type(a.slot) ~= "string" then return false, "empty_or_invalid_slot" end
        for _, slot in ipairs(require("my_friend_equip_slots").All()) do if tostring(slot) == a.slot then job.slot = slot; break end end
        local item = job.slot ~= nil and inst.components.inventory:GetEquippedItem(job.slot) or nil
        if item == nil then return false, "empty_or_invalid_slot" end
        job.item = item.GUID
    else
        local item = Resolve(job, "item")
        if not Owned(inst, item) or not ValidItem(item) then return false, "item_not_carried" end
        if (skill == "equip" or skill == "use_item") and not Usable(item) then return false, "item_exhausted" end
        if skill == "transfer" and job.destination == nil then return false, "missing_destination" end
        if skill == "equip" and item.components.equippable == nil then return false, "not_equippable" end
        if skill=="drop" and a.position~=nil then
            if type(a.position)~="table" or not Finite(a.position.x) or not Finite(a.position.z)
                or (a.position.x-job.origin.x)^2+(a.position.z-job.origin.z)^2>64^2 then return false,"invalid_position"end
            job.point=Vector3(a.position.x,0,a.position.z)
            if not require("my_friend_navigation").IsLand(job.point)then return false,"invalid_terrain"end
        end
        if skill == "eat" then
            local food = require("my_friend_food_ai")
            if food.IsForbiddenFood(item) or not inst.components.eater:CanEat(item)
                or not inst.components.eater:PrefersToEat(item) or not food.CanSafelyEat(inst, item) then return false, "cannot_eat" end
        end
        if skill == "use_item" then
            local components = item.components
            local actions = {HEAL = "healer", SEW = "sewing", REPAIR = "repairer", ADDFUEL = "fuel", FERTILIZE = "fertilizer", READ = "book", CAST_POCKETWATCH = "pocketwatch"}
            local selected = a.action
            if selected == nil then for _, name in ipairs({"HEAL", "SEW", "REPAIR", "ADDFUEL", "FERTILIZE", "READ"}) do
                if components[actions[name]] ~= nil then selected = name; break end
            end end
            if actions[selected] == nil or components[actions[selected]] == nil or ACTIONS[selected] == nil then return false, "unsupported_item_use" end
            if selected == "READ" and inst.components.reader == nil then return false, "character_cannot_read" end
            if selected == "CAST_POCKETWATCH" then
                if inst.prefab ~= "wanda" or not inst:HasTag("pocketwatchcaster") then return false, "character_cannot_cast" end
                if a.position ~= nil then
                    if type(a.position) ~= "table" or not Finite(a.position.x) or not Finite(a.position.z)
                        or (a.position.x - job.origin.x)^2 + (a.position.z - job.origin.z)^2 > 64^2 then return false, "invalid_position" end
                    job.point = Vector3(a.position.x, 0, a.position.z)
                end
                if not components.pocketwatch:CanCast(inst, Resolve(job, "target"), job.point) then return false, "watch_unavailable" end
            end
            job.verb = selected
        end
    end
    return true
end
function M.CombatTarget(inst, job)
    if not Current(inst, job) then return end
    local target = Resolve(job, "target")
    if target == nil or target.components.health == nil then Fail(inst, job, "target_lost"); return end
    if target.components.health:IsDead() then Done(inst, job, {target = job.args.target, defeated = true}); return end
    if target:IsInLimbo() or target.components.combat == nil
        or not require("my_friend_behavior_ai").CanContinueCombat(inst, target, true) then Fail(inst, job, "cannot_continue_combat"); return end
    return target
end
local function Transfer(inst, job, action)
    local skill = job.skill
    local item = skill == "pickup" and Resolve(job, "target") or Resolve(job, "item")
    if not ValidItem(item) or EquippedLocked(item) then return false end
    local source = item.components.inventoryitem.owner
    local opening = source
    if skill == "pickup" then
        local reason
        opening, reason = Source(job, item)
        if reason ~= nil or action.target ~= (opening or item) then
            job.operation_error = reason or "item_moved"; return false
        end
    end
    local n = math.min(job.count - (job.total_moved or 0), Observation.Size(item))
    if skill == "drop" then
        if not Owned(inst, item) then return false end
        local moved = n < Observation.Size(item) and item.components.stackable:Get(n)
            or item.components.inventoryitem:RemoveFromOwner(true)
        if moved == nil then return false end
        local dropped = inst.components.inventory:DropItem(moved, true, true, inst:GetPosition())
        if dropped ~= nil then ReleaseItem(inst, dropped) end
        job.moved = dropped ~= nil and n or 0
        job.moved_item = dropped ~= nil and dropped.GUID or nil
        return dropped ~= nil
    end
    local destination = skill == "pickup" and inst or Resolve(job, "destination")
    local target_container, target_owner = Storage.Resolve(destination)
    local c = destination ~= nil and (destination.components.inventory or target_container) or nil
    if c == nil then return false end
    if target_owner ~= nil and target_owner == source then job.operation_error = "item_already_in_destination"; return false end
    if skill == "pickup" then
        if source == inst or item.components.inventoryitem:GetGrandOwner() == inst then return false end
        if source ~= nil and not Storage.Accessible(inst, opening) then return false end
        if source == nil and (not item.components.inventoryitem.canbepickedup or item:IsInLimbo()) then return false end
    else
        if not Owned(inst,item) or destination==inst and source==inst then return false end
        if destination==inst and source~=nil and source.components.container~=nil
            and not Inventory.CanWithdrawFrom(inst,source) then return false end
        if target_container ~= nil and not Storage.Accessible(inst, destination) then return false end
        if destination ~= inst and destination.components.inventory ~= nil then
            if not Policy.IsLocalPlayer(destination) then return false end
            if not PlayerCanReceive(destination) then
                job.operation_error = destination:HasTag("playerghost") and "recipient_ghost_use_revive" or "recipient_unavailable"
                return false
            end
        end
    end
    local stack = item.components.stackable
    if source ~= nil and stack ~= nil and stack.originalmaxsize ~= nil then
        -- Removing the full slot from an infinite container can drop all
        -- excess natively. Withdraw at most one normal stack per operation.
        n = math.min(n, stack.originalmaxsize)
    end
    local backpack = skill == "pickup" and source == nil and item:HasTag("backpack")
    local acceptable = backpack and 1 or c:CanAcceptCount(item, n)
    local old_bag
    if backpack then
        local equip = item.components.equippable
        local slot = equip ~= nil and equip.equipslot or nil
        local worn = slot ~= nil and c:GetEquippedItem(slot) or nil
        if equip == nil or equip:IsRestricted(inst) or EquippedLocked(worn or item) then
            job.operation_error = "equipment_slot_locked"; return false
        end
        old_bag = worn ~= nil and worn:HasTag("backpack") and worn or nil
    end
    if skill == "pickup" and source == nil and acceptable <= 0 and item.components.equippable ~= nil then
        local equip = item.components.equippable
        if c:GetEquippedItem(equip.equipslot) == nil and not equip:IsRestricted(inst) then acceptable = 1 end
    end
    n = math.min(n, acceptable)
    -- Native non-stacking containers accept one entity per slot. Split before
    -- GiveItem instead of relying on its single-slot fallback for whole stacks.
    if target_container ~= nil and c.acceptsstacks == false then n=math.min(n,1) end
    if n <= 0 then job.operation_error = "inventory_full_or_equipment_slot_occupied"; return false end
    local container_target = skill == "pickup" and opening or skill == "transfer" and destination or nil
    if Storage.Resolve(container_target) ~= nil
        and not ContainerIsOpen(inst, container_target, true) then
        job.operation_error = "container_not_open"; return false
    end
    local before = skill == "pickup" and Count(inst, item.prefab) or nil
    local prefab = item.prefab
    if skill == "pickup" and source == nil then
        local moved = n < Observation.Size(item) and item.components.stackable:Get(n) or item
        if moved ~= item then moved.Transform:SetPosition(item.Transform:GetWorldPosition()) end
        local oldtarget = action.target; action.target = moved
        local previous = inst._my_friend_player_equipping
        inst._my_friend_player_equipping = true
        local called, ok, reason = pcall(ACTIONS.PICKUP.fn, action)
        if called and ok and backpack and Owned(inst, moved) then
            local slot = moved.components.equippable.equipslot
            if c:GetEquippedItem(slot) ~= moved then c:Equip(moved) end
            ok = c:GetEquippedItem(slot) == moved
            if ok then
                local backpacks = require("my_friend_backpacks")
                backpacks.MarkOwned(inst, moved)
                job.replaced_backpack = old_bag ~= nil and old_bag.GUID or nil
            end
        end
        inst._my_friend_player_equipping = previous
        action.target = oldtarget
        if (not called or not ok) and moved ~= item and moved:IsValid() and item:IsValid() then item.components.stackable:Put(moved) end
        job.moved = Count(inst, prefab) - before
        if moved:IsValid() and Owned(inst, moved) then job.moved = math.max(job.moved, Observation.Size(moved)) end
        if not called or not ok then job.operation_error = type(reason) == "string" and reason or "pickup_failed" end
        return called and ok and job.moved > 0
    end
    local source_container = source ~= nil and source.components.container or nil
    local source_slot = source_container ~= nil and source_container.GetItemSlot ~= nil and source_container:GetItemSlot(item) or nil
    local split = n < Observation.Size(item)
    local moved = split and stack:Get(n) or item.components.inventoryitem:RemoveFromOwner(true, true)
    if moved == nil then return false end
    if split and moved.components.inventoryitem.OnRemoved ~= nil then moved.components.inventoryitem:OnRemoved() end
    n = Observation.Size(moved)
    moved.prevcontainer, moved.prevslot = nil, nil
    local ignorefull = c.ignorefull
    if c ~= target_container then c.ignorefull = true end
    local ok = pcall(c.GiveItem, c, moved, nil, destination:GetPosition(), false)
    if c ~= target_container then c.ignorefull = ignorefull end
    local expected_owner = target_owner or destination
    local leftover = moved:IsValid() and moved.components.inventoryitem:GetGrandOwner() ~= expected_owner
        and moved.components.inventoryitem.owner ~= expected_owner and Observation.Size(moved) or 0
    if leftover > 0 then
        if source_container ~= nil and source:IsValid() then
            source_container:GiveItem(moved, source_slot, (opening or source):GetPosition(), false)
        else Inventory.GiveCarried(inst, moved, inst:GetPosition()) end
    end
    if not ok then job.operation_error = "item_transfer_failed" end
    job.moved, job.prefab = n - leftover, prefab
    if skill == "transfer" and job.moved > 0 and moved:IsValid() then ReleaseItem(inst, moved) end
    return job.moved > 0
end
local function CanReceiveProduct(inst, prefab)
    local inventory = inst.components.inventory
    if not inventory:IsFull() then return true end
    for _, item in ipairs(Observation.Items(inst)) do
        if item.prefab == prefab and inventory:CanAcceptCount(item, 1) > 0 then return true end
    end
    return false
end
-- Runs only from the custom vanilla BufferedAction after routing/SG validation.
function M.Operate(action)
    local inst, job = action.doer, action._body_job
    if job == nil or not Current(inst, job) then return false end
    if action._my_friend_surface_ready and not require("my_friend_body_travel").CanOperate(inst, action) then
        job.operation_error = "target_moved_out_of_reach"
        return false
    end
    if action.target ~= nil and inst:GetDistanceSqToInst(action.target) > ((action.arrivedist or 2.2) + .5)^2 then return false end
    local operation = action._body_operation
    if operation == "transfer" then return Transfer(inst, job, action)
    elseif operation == "prepare_build" then
        local builder = inst.components.builder
        local recipe = GetValidRecipe(job.recipe)
        if recipe == nil or recipe.placer == nil or recipe.manufactured then return false end
        if builder:IsBuildBuffered(job.recipe) then return true end
        if not require("my_friend_crafting_tech").CanBuild(inst, recipe) then
            job.operation_error = "missing_technology"; return false
        end
        if not builder:HasIngredients(recipe) then job.operation_error = "missing_materials"; return false end
        local native = require("my_friend_body_native")
        local ok = pcall(native.WithInventory, inst, builder.BufferBuild, builder, job.recipe)
        if not ok or not builder:IsBuildBuffered(job.recipe) then
            job.operation_error = "build_not_prepared"; return false
        end
        return true
    elseif operation == "revive" then
        local ghost, item = action.target, action.invobject
        if not require("my_friend_rescue").CanRevivePlayer(ghost) or not Owned(inst, item) or not item:HasTag("reviver") then
            job.operation_error = "ghost_not_ready"; return false
        end
        local give = ACTIONS.GIVETOPLAYER
        if give == nil then job.operation_error = "revive_unavailable"; return false end
        local ok, accepted, reason = pcall(give.fn, action)
        if not ok or not accepted then
            job.operation_error = ok and reason or "native_revive_failed"; return false
        end
        return true
    elseif operation == "equip" or operation == "unequip" then
        local item = action.invobject
        if not Owned(inst, item) or EquippedLocked(item) and operation == "unequip" then return false end
        local previous = inst._my_friend_player_equipping
        inst._my_friend_player_equipping = true
        local ok, result = pcall((operation == "equip" and ACTIONS.EQUIP or ACTIONS.UNEQUIP).fn, action)
        inst._my_friend_player_equipping = previous
        if ok and result and operation == "unequip" then ReleaseItem(inst, item) end
        return ok and result
    elseif operation == "harvest" then
        local target = action.target
        if not PotAvailable(inst, target) or not target.components.stewer:IsDone() then return false end
        local product = target.components.stewer.product
        local expected = job.recipe or job.args.recipe
        if expected ~= nil and product ~= expected then job.operation_error = "unexpected_recipe"; return false end
        if not CanReceiveProduct(inst, product) then job.operation_error = "inventory_full"; return false end
        local harvested = ACTIONS.HARVEST.fn(action)
        local reserved = target._my_friend_recipe_job
        if harvested and reserved ~= nil and reserved.owner == require("my_friend_cookpot").OwnerID(inst) then
            target._my_friend_recipe_job = nil
            if inst._my_friend_recipe_pot == target then inst._my_friend_recipe_pot = nil end
            inst._my_friend_recipe_cache, inst._my_friend_food_supply_cache = nil, nil
        end
        return harvested
    elseif operation == "open" then
        local target = action.target
        local _, _, c = Storage.Resolve(target)
        if not Storage.Accessible(inst, target) then job.operation_error="container_unavailable"; return false end
        local share_leader = job.skill == "pickup" or job.skill == "transfer"
        if ContainerIsOpen(inst, target, share_leader) then return true end
        if c.CanOpen ~= nil and not c:CanOpen() then job.operation_error="container_cannot_open"; return false end
        TrackContainer(inst, job, target)
        inst:PushEvent("opencontainer", {container=target})
        c:Open(inst)
        if not c:IsOpenedBy(inst) then job.operation_error="container_cannot_open"; return false end
        return true
    elseif operation == "cook_add" then
        local pot, item = action.target, action.invobject
        if pot._my_friend_body_cook ~= job.id or not Owned(inst, item)
            or not PotAvailable(inst, pot) or not pot.components.container:IsOpenedBy(inst)
            or pot.components.stewer:IsCooking() then return false end
        local moved = item.components.inventoryitem:RemoveFromOwner(false)
        if moved == nil then return false end
        moved.prevcontainer, moved.prevslot = nil, nil
        local guid = moved.GUID
        local accepted = pot.components.container:GiveItem(moved, nil, pot:GetPosition(), false)
        if accepted then job.added[guid] = true else if moved:IsValid() then Inventory.GiveCarried(inst, moved, inst:GetPosition()) end end
        return accepted == true
    end
    return false
end
local function Operate(inst, job, target, item, operation, success)
    local action = Make(inst, job, target, ACTIONS.MY_FRIEND_BODY, item, nil, success)
    action._body_operation = operation
    action.arrivedist = Storage.Resolve(target) ~= nil and Inventory.ContainerReach ~= nil
        and Inventory.ContainerReach(inst, target) or 2.2
    return action
end
local function Dismount(inst, job)
    if not Riding(inst) then return end
    if ACTIONS.DISMOUNT == nil then Fail(inst, job, "dismount_unavailable"); return end
    job.stage = "dismounting"
    return Make(inst, job, inst, ACTIONS.DISMOUNT)
end

local function Craft(inst, state, job)
    local recipe = GetValidRecipe(job.recipe)
    if recipe == nil then Fail(inst, job, "unknown_recipe"); return end
    local builder, tech = inst.components.builder, require("my_friend_crafting_tech")
    local buffered = recipe.placer ~= nil and builder.IsBuildBuffered ~= nil and builder:IsBuildBuffered(recipe.name)
    local can_buffer = recipe.placer ~= nil and not recipe.manufactured and builder.BufferBuild ~= nil
    local preparing = job.craft_mode == "prepare"
    if preparing and buffered then
        Done(inst, job, {recipe = job.recipe, prepared = true, already_prepared = true}); return
    end
    if job.craft_mode == "place" and not buffered then Fail(inst, job, "build_not_prepared"); return end
    if job.point ~= nil and recipe.placer ~= nil and not require("my_friend_body_sites").Valid(inst, recipe, job.point) then
        Fail(inst, job, "placement_blocked", {recipe = job.recipe, prepared = buffered == true,
            position = {x = job.point.x, z = job.point.z}, progress = job.progress, materials_consumed = false}); return
    end
    if not buffered then
        if not job.tech_checked and builder.EvaluateTechTrees ~= nil then builder:EvaluateTechTrees() end
        job.tech_checked = true
        local ready = tech.CanBuild(inst, recipe)
        if builder:HasIngredients(recipe) and (not ready or job.station ~= nil and not job.station_activated) then
            local station = Resolve(job, "station")
            if job.station == nil and tech.StationCanTeach ~= nil then
                for _, candidate in ipairs(Observation.Nearby(inst, 32)) do
                    if candidate:GetCurrentPlatform() == inst:GetCurrentPlatform() and tech.StationCanTeach(inst, candidate, recipe) then
                        station = candidate; break
                    end
                end
            end
            if station ~= nil and station:GetCurrentPlatform() == inst:GetCurrentPlatform()
                and tech.StationCanTeach(inst, station, recipe) then
                if tech.Activate(inst, station, recipe) then job.station_activated, ready = true, true
                else
                    job.stage = "approaching_technology"
                    local proto = station.components.prototyper
                    if proto:CanUsePrototyper(inst) then Fail(inst, job, "station_unavailable"); return end
                    local action = Make(inst, job, station, ACTIONS.WALKTO, nil, nil, function()
                        if tech.Activate(inst, station, recipe) then job.station_activated = true
                        else Fail(inst, job, "station_unavailable") end
                    end)
                    action.arrivedist = 1.5
                    return action
                end
            elseif job.station ~= nil then Fail(inst, job, "station_unavailable"); return end
        end
        if not ready or not builder:HasIngredients(recipe) then
            local details = require("my_friend_body_recipes").Craft(inst, recipe, job.count - job.progress)
            details.stage, details.completed_operations = "craft_blocked", job.progress
            Fail(inst, job, not details.materials_ready and "missing_materials"
                or not ready and "missing_technology" or "native_recipe_condition_unmet", details)
            return
        end
        if can_buffer then
            job.stage = "preparing_build"
            return Operate(inst, job, nil, nil, "prepare_build", function()
                if preparing then Done(inst, job, {recipe = job.recipe, prepared = true, operations = 1}) end
            end)
        elseif preparing then Fail(inst, job, "recipe_cannot_be_buffered"); return end
    end
    local built = not buffered and tech.OnBuilt(inst, recipe) or nil
    job.stage = buffered and "placing_build" or "crafting"
    local action = Make(inst, job, nil, ACTIONS.MY_FRIEND_BUILD or ACTIONS.BUILD, nil, job.point or inst:GetPosition(), function()
        if built ~= nil then built() end
        job.progress = job.progress + 1
        if job.progress < job.count then return end
        local product = recipe.product or job.recipe
        local result = {recipe = job.recipe, operations = job.progress, produced = job.progress * (recipe.numtogive or 1),
            items = ProductItems(inst, state, product)}
        if recipe.placer ~= nil then
            result.placed, result.position = true, {x = job.point.x, z = job.point.z}
            for _, entity in ipairs(TheSim:FindEntities(job.point.x, 0, job.point.z, .6, nil, {"INLIMBO", "FX"})) do
                if entity.prefab == product and entity:IsValid() then
                    result.entities = {Observation.Describe(inst, state, entity)}
                    break
                end
            end
        end
        Done(inst, job, result)
    end, function()
        if recipe.placer ~= nil and not require("my_friend_body_sites").Valid(inst, recipe, job.point) then
            job.operation_error = "placement_blocked"; return false
        end
        if buffered then return builder:IsBuildBuffered(recipe.name) end
        return tech.CanBuild(inst, recipe) and builder:HasIngredients(recipe)
    end)
    action.recipe = recipe.name
    return action
end
local function Cook(inst, state, job)
    local pot = Resolve(job, "station")
    if pot == nil or not PotAvailable(inst, pot) then Fail(inst, job, "station_unavailable"); return end
    local c, stew = pot.components.container, pot.components.stewer
    if job.stage == "planning" then
        local planner = require("my_friend_recipe_planner")
        local plan, pending
        if job.explicit_mix then
            local ok, reason = require("my_friend_body_cooking").Validate(inst,pot.prefab,job.recipe,job.args.ingredients)
            if not ok then Fail(inst,job,reason); return end
            plan = {prefabs=job.args.ingredients}
        else plan, pending = planner.Find(inst, pot.prefab, planner.Pool(inst), job.recipe) end
        if pending then return end
        if plan == nil then Fail(inst, job, "missing_ingredients"); return end
        job.prefabs, job.stage, pot._my_friend_body_cook = plan.prefabs, "filling", job.id
    end
    if pot._my_friend_body_cook ~= job.id then Fail(inst, job, "station_changed"); return end
    if stew:IsCooking() then job.stage = "cooking"; return end
    if stew:IsDone() then
        if not job.started or stew.product ~= job.recipe then Fail(inst, job, "unexpected_recipe"); return end
        if not CanReceiveProduct(inst, job.recipe) then Fail(inst, job, "inventory_full"); return end
        local before = Count(inst, job.recipe)
        return Operate(inst, job, pot, nil, "harvest", function()
            local received = Count(inst, job.recipe) - before
            if received < 1 then Fail(inst, job, "product_not_received") else Done(inst, job, {recipe = job.recipe, count = received,
                items = ProductItems(inst, state, job.recipe)}) end
        end)
    end
    if job.started then Fail(inst, job, "cooking_interrupted"); return end
    if not c:IsOpenedBy(inst) then return Operate(inst, job, pot, nil, "open") end
    local remaining, prefabs = {}, {}
    for _, name in ipairs(job.prefabs) do remaining[name] = (remaining[name] or 0) + 1 end
    for _, item in ipairs(c:GetAllItems()) do
        if (remaining[item.prefab] or 0) <= 0 then Fail(inst, job, "station_changed"); return end
        remaining[item.prefab] = remaining[item.prefab] - 1; prefabs[#prefabs + 1] = item.prefab
    end
    for _, name in ipairs(job.prefabs) do if remaining[name] > 0 then
        for _, item in ipairs(Observation.Items(inst)) do
            if item.prefab == name and require("my_friend_recipe_planner").Available(inst, item, job.explicit_mix) then
                return Operate(inst, job, pot, item, "cook_add")
            end
        end
        Fail(inst, job, "ingredients_changed"); return
    end end
    if require("my_friend_recipe_planner").EvaluateSpecific(inst, pot.prefab, prefabs, job.recipe,
        require("my_friend_food_rules").CountStaleMeat(c:GetAllItems())) == nil then Fail(inst, job, "recipe_changed"); return end
    return Make(inst, job, pot, ACTIONS.COOK, nil, nil, function()
        job.started,job.stage=true,"cooking"
        if job.args.wait == false then Done(inst,job,{recipe=job.recipe,station=job.args.station,
            started=true,ready=false,remaining=stew.GetTimeToCook~=nil and stew:GetTimeToCook() or nil}) end
    end)
end
function M.GetAction(inst, state, job)
    local skill, a = job.skill, job.args
    if job.heavy_carry then return require("my_friend_body_carry").GetAction(inst,state,job) end
    if job.delegated~=nil then return end
    if skill == "dismount" or skill == "revive" or skill == "pickup" or skill == "craft" or skill == "drop"
        or skill == "transfer" or skill == "equip" or skill == "unequip" then
        if Riding(inst) then return Dismount(inst, job) end
        if inst.sg ~= nil and inst.sg:HasStateTag("dismounting") then return end
        if skill == "dismount" then Done(inst, job, {riding = false}); return end
    end
    if skill == "emote" then
        local emotes = require("my_friend_emotes")
        local data = emotes.BodyData(a.emote)
        if not emotes.PlayBody(inst, data) then Fail(inst, job, "emote_unavailable"); return end
        Done(inst, job, {emote = a.emote, played = true}); return
    elseif skill == "revive" then
        local ghost, item = Resolve(job, "target"), Resolve(job, "item")
        if ghost == nil then Fail(inst, job, "target_lost"); return end
        if Policy.IsLocalPlayer(ghost) and (not ghost:HasTag("playerghost") or ghost:HasTag("reviving"))
            and (ghost.components.health == nil or not ghost.components.health:IsDead() or ghost:HasTag("reviving")) then
            Done(inst, job, {target = a.target, already_reviving_or_alive = true}); return
        end
        if not ValidItem(item) or not Owned(inst, item) then Fail(inst, job, "reviver_required"); return end
        if not require("my_friend_rescue").CanRevivePlayer(ghost) then
            if (ghost._my_friend_rescue_ready_after or 0) > GetTime() and job.wait_for_ghost == nil then
                job.wait_for_ghost = GetTime() + 5
            end
            if GetTime() < (job.wait_for_ghost or 0) then job.stage = "waiting_for_ghost"; return end
            Fail(inst, job, "ghost_not_ready"); return
        end
        return Operate(inst, job, ghost, item, "revive", function()
            Done(inst, job, {target = a.target, revive_started = true})
        end)
    end
    if job.native then
        local native=require("my_friend_body_native")
        if not native.Valid(inst,state,job) then Fail(inst,job,"native_action_unavailable"); return end
        local target,item=Resolve(job,"target"),Resolve(job,"item")
        local slot=native.EquipSlot(job,item)
        if slot~=nil and inst.components.inventory:GetEquippedItem(slot)~=item then
            return Operate(inst,job,nil,item,"equip")
        end
        local before=item~=nil and Count(inst,item.prefab) or 0
        local effect_point=job.point or target~=nil and target:GetPosition() or inst:GetPosition()
        local previous_entities={}
        local action=Make(inst,job,target,job.native_action,item,job.point,function()
            effect_point=job.effect_point or effect_point
            previous_entities=job.effect_before or previous_entities
            local created={}
            for _,entity in ipairs(TheSim:FindEntities(effect_point.x,0,effect_point.z,2,nil,{"INLIMBO","FX"})) do
                if not previous_entities[entity.GUID] and #created<12 then created[#created+1]=Observation.Describe(inst,state,entity) end
            end
            Done(inst,job,{action=job.native_action.id,mode=job.native_mode,executed=true,
                position={x=effect_point.x,z=effect_point.z},entities=created,
                target=target~=nil and target:IsValid() and Observation.Describe(inst,state,target) or nil,
                consumed=item~=nil and math.max(0,before-Count(inst,item.prefab)) or nil})
        end,function() return native.Valid(inst,state,job) end)
        action.rmb=job.right
        action._my_friend_native_range=true
        -- Real BufferedActions capture the baseline in Do, after routing.
        if action.Do==nil then
            for _,entity in ipairs(TheSim:FindEntities(effect_point.x,0,effect_point.z,2,nil,{"INLIMBO","FX"})) do
                previous_entities[entity.GUID]=true
            end
        end
        native.Wrap(inst,job,action)
        if job.native_mode=="POINT" and (job.native_action==ACTIONS.CASTSPELL or job.native_action==ACTIONS.CASTAOE
            or job.native_action==ACTIONS.BLINK or job.native_action==ACTIONS.THROW) then action._my_friend_cast_in_place=true end
        return action
    end
    if skill == "character_skill" then return require("my_friend_body_characters").GetAction(inst, job) end
    if skill == "interact" then
        if job.delegated ~= nil then return end
        local target = Resolve(job, "target")
        local allowed, reason = require("my_friend_body_interactions").Validate(inst, target, job.verb)
        if not allowed then Fail(inst, job, reason); return end
        if (job.verb == "TURNON" or job.verb == "TURNOFF")
            and target.components.machine:IsOn() == (job.verb == "TURNON") then
            Done(inst, job, {action = job.verb, target = a.target, already = true}); return
        end
        return Make(inst, job, target, ACTIONS[job.verb], nil, nil, function()
            Done(inst, job, {action = job.verb, target = a.target, executed = true})
        end, function() return require("my_friend_body_interactions").Validate(inst, target, job.verb) end)
    end
    if skill == "move_to" then
        local target = Resolve(job, "target")
        if job.target ~= nil and target == nil then Fail(inst, job, "target_lost"); return end
        local travel = require("my_friend_body_travel")
        local point = travel.Point(job, target)
        if point == nil then Fail(inst, job, "target_lost"); return end
        local surface, platform = require("my_friend_platforms").Surface(point, target)
        if job.point_platform ~= nil then surface, platform = "boat", job.point_platform end
        if travel.Needed(inst, job, surface, point) then
            if Riding(inst) and (inst:GetCurrentPlatform() ~= platform or surface == "water"
                or a.destination == "shore" and inst:GetCurrentPlatform() ~= nil) then return Dismount(inst, job) end
            if inst.sg ~= nil and inst.sg:HasStateTag("dismounting") then return end
            local result, reason = travel.Step(inst, state, job, target, point, surface, platform)
            if result ~= nil then Done(inst, job, result)
            elseif reason ~= nil then
                local current = inst:GetPosition()
                Fail(inst, job, reason, {stage = job.stage, position = {x = current.x, z = current.z},
                    target_surface = surface, distance = Observation.Distance(current, point)})
            end
            return
        end
        local action = Make(inst, job, target, ACTIONS.WALKTO, nil, target == nil and point or nil, function()
            local p = inst:GetPosition()
            Done(inst, job, {position = {x = p.x, z = p.z}, target = a.target, gait = job.gait,
                surface = "land", target_surface = surface, distance = Observation.Distance(p, point)})
        end)
        action.arrivedist = job.distance
        return action
    elseif skill == "engage" then return end
    if skill == "cook" then return Cook(inst, state, job) end
    if skill == "harvest" then
        local target = Resolve(job, "target")
        if target == nil or not PotAvailable(inst, target) then Fail(inst, job, "station_unavailable"); return end
        if a.recipe ~= nil and a.recipe ~= target.components.stewer.product then Fail(inst, job, "unexpected_recipe"); return end
        if not target.components.stewer:IsDone() then
            if a.wait == true and target.components.stewer:IsCooking() then job.stage = "cooking"; return end
            Fail(inst, job, "product_not_ready"); return
        end
        local product = target.components.stewer.product
        if not CanReceiveProduct(inst, product) then Fail(inst, job, "inventory_full"); return end
        local before = Count(inst, product)
        return Operate(inst, job, target, nil, "harvest", function()
            local count = Count(inst, product) - before
            if count < 1 then Fail(inst, job, "product_not_received")
            else Done(inst, job, {product = product, count = count, items = ProductItems(inst, state, product)}) end
        end)
    end
    if skill == "craft" then return Craft(inst, state, job) end
    if skill == "work" then
        local target, kind = Resolve(job, "target"), ACTIONS[job.verb]
        if target == nil then
            if job.progress > 0 then FinishWork(inst, state, job, {work_units = job.progress, target_removed = true})
            else Fail(inst, job, "target_lost") end
            return
        end
        BeginWork(inst,job,target)
        local c = target.components
        local tool
        if c.workable ~= nil and job.verb ~= "PICK" and job.verb ~= "HARVEST" then
            if not c.workable:CanBeWorked() then
                if job.progress > 0 then FinishWork(inst, state, job, {work_units = job.progress, finished = true})
                else Fail(inst, job, "target_not_workable") end
                return
            end
            if c.workable:GetWorkAction() ~= kind then
                if (job.parent ~= nil or job.until_finished) and job.progress > 0 then FinishWork(inst, state, job, {work_units = job.progress, finished = true})
                else Fail(inst, job, "wrong_work_action") end
                return
            end
            for _, item in ipairs(Observation.Items(inst)) do
                if Inventory.IsUsableTool(inst, item, kind) then tool = item; break end
            end
            if tool == nil then Fail(inst, job, "missing_tool"); return end
            local slot = tool.components.equippable.equipslot
            if inst.components.inventory:GetEquippedItem(slot) ~= tool then return Operate(inst, job, nil, tool, "equip") end
        elseif not (job.verb == "PICK" and c.pickable ~= nil or job.verb == "HARVEST"
            and (c.harvestable ~= nil or c.crop ~= nil or c.grower ~= nil or c.stewer ~= nil)) then
            Fail(inst, job, "not_workable"); return
        end
        return WorkSwing(inst, state, job, target, kind, tool)
    end
    local item = skill == "pickup" and Resolve(job, "target") or Resolve(job, "item")
    if not ValidItem(item) then Fail(inst, job, "item_lost"); return end
    if skill == "pickup" or skill == "drop" or skill == "transfer" then
        if skill=="drop" and job.point~=nil then
            local p=inst:GetPosition()
            if (p.x-job.point.x)^2+(p.z-job.point.z)^2>.5^2 then
                local action=Make(inst,job,nil,ACTIONS.WALKTO,nil,job.point)
                action.arrivedist=.5
                return action
            end
        end
        local source
        if skill == "pickup" then
            local reason
            source, reason = Source(job, item)
            if reason ~= nil then Fail(inst, job, reason); return end
        end
        local target = skill == "pickup" and (source or item) or skill == "transfer" and Resolve(job, "destination") or nil
        if skill == "pickup" and source ~= nil and Storage.Resolve(source) == nil then Fail(inst, job, "item_owned"); return end
        if skill == "transfer" and target == nil then Fail(inst, job, "target_lost"); return end
        if skill ~= "pickup" and not Owned(inst, item) then Fail(inst, job, "item_not_carried"); return end
        if Storage.Resolve(target) ~= nil then
            if not Storage.Accessible(inst, target) then Fail(inst, job, "container_unavailable"); return end
            if not ContainerIsOpen(inst, target, true) then
                job.stage = "opening_container"
                return Operate(inst, job, target, nil, "open")
            end
        end
        job.stage = "transferring"
        return Operate(inst, job, target, item, "transfer", function()
            job.total_moved=(job.total_moved or 0)+(job.moved or 0)
            job.progress=job.total_moved
            local destination=skill=="transfer" and Resolve(job,"destination") or nil
            local container = Storage.Resolve(destination)
            local stack = item:IsValid() and item.components.stackable or nil
            if job.total_moved < job.count and ValidItem(item) then
                if skill == "pickup" and source ~= nil and stack ~= nil and stack.originalmaxsize ~= nil
                    and inst.components.inventory:CanAcceptCount(item, 1) > 0 then return end
                if container ~= nil and container.acceptsstacks == false and Owned(inst, item)
                    and container:CanAcceptCount(item, 1) > 0 then return end
            end
            local old = job.replaced_backpack ~= nil and (Ents or {})[job.replaced_backpack] or nil
            Done(inst, job, {prefab = job.prefab or item.prefab, count = job.total_moved, requested = job.count,
                partial=job.total_moved<job.count,remaining=math.max(0,job.count-job.total_moved),
                items=skill=="pickup" and ProductItems(inst,state,job.prefab or item.prefab) or nil,
                replaced_backpack=old~=nil and old:IsValid() and Observation.Describe(inst,state,old) or nil,
                item_state=skill=="drop" and job.moved_item~=nil and Observation.Describe(inst,state,(Ents or {})[job.moved_item]) or nil,
                position=skill=="drop" and {x=inst:GetPosition().x,z=inst:GetPosition().z} or nil})
        end)
    elseif skill == "equip" or skill == "unequip" then
        if not Owned(inst, item) then Fail(inst, job, "item_not_carried"); return end
        if skill == "equip" and inst.components.inventory:GetEquippedItem(item.components.equippable.equipslot) == item then
            Done(inst, job, {slot = tostring(item.components.equippable.equipslot), already_equipped = true,
                item_state=Observation.Describe(inst,state,item)}); return
        end
        return Operate(inst, job, nil, item, skill, function()
            Done(inst, job, {slot = tostring(job.slot or item.components.equippable.equipslot), item = Observation.Handle(state,item),
                item_state=Observation.Describe(inst,state,item)})
        end)
    elseif skill == "eat" then
        if not Owned(inst, item) or not require("my_friend_food_ai").CanSafelyEat(inst, item) then Fail(inst, job, "cannot_eat"); return end
        local before = {inst.components.health.currenthealth, inst.components.hunger.current, inst.components.sanity.current}
        return Make(inst, job, nil, ACTIONS.EAT, item, nil, function()
            Done(inst, job, {health_delta = inst.components.health.currenthealth - before[1],
                hunger_delta = inst.components.hunger.current - before[2], sanity_delta = inst.components.sanity.current - before[3]})
        end, function()
            local food = require("my_friend_food_ai")
            return Owned(inst, item) and not food.IsForbiddenFood(item) and inst.components.eater:CanEat(item)
                and inst.components.eater:PrefersToEat(item) and food.CanSafelyEat(inst, item)
        end)
    elseif skill == "use_item" then
        local target = Resolve(job, "target") or (job.verb ~= "READ" and job.verb ~= "CAST_POCKETWATCH" and inst or nil)
        local action = Make(inst, job, target, ACTIONS[job.verb], item, job.point, function() Done(inst, job, {action = job.verb, executed = true}) end,
            function() return job.verb ~= "CAST_POCKETWATCH" or inst.prefab == "wanda" and inst:HasTag("pocketwatchcaster")
                and item.components.pocketwatch:CanCast(inst, target, job.point) end)
        if job.verb == "CAST_POCKETWATCH" and job.point ~= nil and target == nil then
            action._my_friend_cast_in_place, action.arrivedist = true, 96
        end
        return action
    end
end
return M
