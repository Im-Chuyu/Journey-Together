-- Bridge only the mod's existing role scripts; no parallel character AI.
local M = {}
local PROFILES = {
    wendy = {actions = {"abigail_aggressive", "abigail_defensive", "abigail_recall", "build_special"}, automatic = {"abigail_summoning", "abigail_combat_mode"}},
    wanda = {actions = {"build_special"}, automatic = {"watch_healing", "watch_refuelling", "dreadstone_equipment"}},
    wickerbottom = {actions = {"read_book", "build_special"}, automatic = {"bookshelf_memory", "last_copy_storage"}},
    wathgrithr = {actions = {"lightning_spear"}, automatic = {"combat_lunge", "spear_cycle"}},
    warly = {actions = {"build_special", "spice_food"}, automatic = {}},
    wortox = {actions = {"make_heart", "squeeze_heart"}, automatic = {"soul_balance", "nearby_player_healing", "soul_collection"}},
    wormwood = {actions = {"heal_self"}, automatic = {"carried_medicine_healing"}},
    wx78 = {actions = {}, automatic = {"circuit_and_charge_save_restore"}},
}
local function Has(list, value) for _, v in ipairs(list) do if v == value then return true end end; return false end
local function HasHeart(inst)
    for _, item in ipairs(require("my_friend_body_observation").Items(inst)) do
        if item:IsValid() and item.prefab == "wortox_reviver" then return true end
    end
    return false
end
function M.IsControl(ability)
    return ability == "abigail_aggressive" or ability == "abigail_defensive" or ability == "abigail_recall"
end
function M.Control(inst, ability)
    if inst.prefab ~= "wendy" or not M.IsControl(ability) then return false end
    if ability == "abigail_recall" then return require("my_friend_abigail").Recall(inst, 480) end
    return require("my_friend_wendy").Request(inst, ability == "abigail_aggressive")
end
function M.BuildAllowed(inst, recipe)
    return Has(require("my_friend_special_commands").ModelRecipes(inst.prefab), recipe)
end
function M.Catalogue(inst)
    local profile = PROFILES[inst.prefab]
    local scripts = {}; for name in pairs(PROFILES) do scripts[#scripts + 1] = name end; table.sort(scripts)
    local actions = {}; for _, action in ipairs(profile ~= nil and profile.actions or {}) do actions[#actions + 1] = action end
    if HasHeart(inst) and not Has(actions, "squeeze_heart") then actions[#actions + 1] = "squeeze_heart" end
    local recipes, names = require("my_friend_special_commands").ModelRecipes(inst.prefab), {}
    for _, recipe in ipairs(recipes) do
        local label = STRINGS ~= nil and STRINGS.NAMES ~= nil and STRINGS.NAMES[string.upper(recipe)] or nil
        names[recipe] = type(label) == "string" and label or recipe
    end
    return {scripted_characters = scripts, actions = actions,
        automatic = profile ~= nil and profile.automatic or {}, recipes = recipes, recipe_names = names,
        books = inst.prefab == "wickerbottom" and require("my_friend_special_commands").ModelBooks() or nil,
        costs = inst.prefab == "wortox" and {make_heart = {wortox_soul = require("my_friend_wortox").HEART_SOUL_COST}} or nil}
end
local function API() return require("my_friend_body_api") end
local function Current(inst, job)
    local state = API().Valid(inst)
    return state ~= nil and state.active == job and not job.cancel_requested and inst.prefab == job.character
end
local function Finish(inst, job, success, reason)
    local result = {ability = job.ability, character = job.character, actions = job.effects or {},
        recipe = job.command ~= nil and job.command.recipe or nil, failed_action = job.failed_action,
        product = job.product, built = job.final_built, deployed = job.final_deployed}
    if job.command ~= nil and job.command.special == "lightning_spear" then
        result.built, result.charged = job.command.spear_built == true, (job.effects or {}).MY_FRIEND_SPEAR_CHARGE ~= nil
    end
    API().Finish(inst, job, success and "completed" or "failed", result, not success and (reason or "character_ability_unavailable") or nil)
end
function M.Validate(inst, state, args)
    local profile = PROFILES[inst.prefab]
    if type(args.ability) ~= "string" or not (profile ~= nil and Has(profile.actions, args.ability)
        or args.ability == "squeeze_heart" and HasHeart(inst)) then return false, "unsupported_character_ability" end
    local kind = args.ability
    if kind == "build_special" and not M.BuildAllowed(inst, args.recipe) then return false, "unsupported_character_recipe" end
    if kind == "read_book" and args.recipe ~= nil and not Has(require("my_friend_special_commands").ModelBooks(), args.recipe) then return false, "unsupported_book" end
    if kind == "spice_food" then
        local observation = require("my_friend_body_observation")
        local food, spice = observation.Resolve(state, args.food), observation.Resolve(state, args.spice)
        if food == nil or spice == nil or food.components.inventoryitem == nil or spice.components.inventoryitem == nil
            or food.components.inventoryitem:GetGrandOwner() ~= inst or spice.components.inventoryitem:GetGrandOwner() ~= inst
            or not food:HasTag("preparedfood") or food:HasTag("spicedfood")
            or not Has(require("my_friend_special_commands").ModelSpices(), spice.prefab) then return false, "spice_ingredients_unavailable" end
        return true, nil, food.prefab, spice.prefab
    end
    return true
end
function M.Prepare(inst, state, job)
    local args = job.args
    local allowed, reason, food, spice = M.Validate(inst, state, args)
    if not allowed then return false, reason end
    job.character, job.ability, job.effects = inst.prefab, args.ability, {}
    job.stage, job.food, job.spice = "character_skill", food, spice
    local kind = args.ability
    if kind == "build_special" or kind == "read_book" or kind == "spice_food" or kind == "lightning_spear"
        or kind == "make_heart" or kind == "squeeze_heart" then
        local command = {id = (kind == "make_heart" or kind == "squeeze_heart") and kind or "special",
            special = kind == "build_special" and "build" or kind == "read_book" and "read"
                or kind == "spice_food" and "spice" or kind == "lightning_spear" and "lightning_spear" or nil,
            recipe = kind == "lightning_spear" and "spear_wathgrithr_lightning" or args.recipe,
            target = kind == "read_book" and args.recipe or nil, food = job.food, spice = job.spice,
            player = job.issuer or state.owner, started = GetTime(), deadline = GetTime() + 300}
        job.command, inst._my_friend_command = command, command
        job.cleanup = function()
            local owned = inst._my_friend_command == command
            if owned or inst._my_friend_command == nil then
                for station in pairs(job.opened or {}) do
                    local c = station:IsValid() and station.components.container or nil
                    if c ~= nil and c:IsOpenedBy(inst) then c:Close(inst); inst:PushEvent("closecontainer", {container = station}) end
                end
            end
            if owned then require("my_friend_commands").Clear(inst, state) end
            job.command, job.opened = nil, nil
        end
        local ok = pcall(function()
            if kind == "read_book" then
                require("my_friend_books").PrepareCommand(inst, command)
            elseif command.recipe == "bookstation" or command.recipe == "sisturn" then
                require("my_friend_bookstation").PrepareCommand(command)
                job.recipe, job.point = command.recipe, command.build_point
            end
        end)
        if not ok then job.cleanup(); job.cleanup = nil; return false, "character_setup_failed" end
    end
    return true
end
local function TerminalEffect(job)
    local effects, kind = job.effects, job.ability
    if kind == "read_book" then return (effects.READ or 0) > 0 end
    if kind == "make_heart" then return (effects.MY_FRIEND_MAKE_HEART or 0) > 0 end
    if kind == "squeeze_heart" then return (effects.CASTSPELL or 0) > 0 end
    if kind == "spice_food" then return (effects.HARVEST or 0) > 0 and job.product == job.food .. "_" .. job.spice end
    if kind == "lightning_spear" then return job.command.spear_built or (effects.MY_FRIEND_SPEAR_CHARGE or 0) > 0 end
    return job.final_built == true or job.final_deployed == true
end
function M.GetAction(inst, job)
    if not Current(inst, job) then return end
    local kind = job.ability
    if M.IsControl(kind) then
        local ok = M.Control(inst, kind)
        Finish(inst, job, ok == true); return
    end
    local action
    if kind == "heal_self" then
        local wormwood = require("my_friend_wormwood")
        if not wormwood.NeedsHeal(inst) then
            local health = inst.components.health
            if health.canheal == false then Finish(inst, job, false, "character_healing_unavailable"); return end
            API().Finish(inst, job, "completed", {no_action_needed = true,
                already_healthy = health.currenthealth >= health:GetMaxWithPenalty()}); return
        end
        if GetTime() < (inst._my_friend_wormwood_heal_after or 0) then job.stage = "waiting_healing_cooldown"; return end
        action = wormwood.GetHealAction(inst)
    elseif inst._my_friend_command ~= job.command then
        Finish(inst, job, TerminalEffect(job), kind == "read_book" and "book_not_read" or "character_command_stopped"); return
    elseif kind == "make_heart" then action = require("my_friend_wortox").GetMakeHeartCommandAction(inst)
    elseif kind == "squeeze_heart" then action = require("my_friend_character_actions").GetSqueezeAction(inst)
    else action = require("my_friend_special_actions").GetAction(inst, job.command) end
    if action == nil then
        if job.command ~= nil and job.command.waiting and inst._my_friend_command == job.command then job.stage = "waiting_character_action"; return end
        Finish(inst, job, job.command ~= nil and not job.command.reported and TerminalEffect(job),
            kind == "read_book" and "book_not_read"
            or job.command ~= nil and (job.command.failure_reason or job.command.failure_reply) or nil); return
    end
    local previous = action.validfn
    job.stage = action.action.id
    local final_build = job.command ~= nil and (action.action == ACTIONS.BUILD or action.action == ACTIONS.MY_FRIEND_BUILD)
        and action.recipe == job.command.recipe
    local final_deploy = job.command ~= nil and action.action == ACTIONS.DEPLOY
        and action.invobject ~= nil and action.invobject.prefab == job.command.recipe
    local product = kind == "spice_food" and action.action == ACTIONS.HARVEST and action.target ~= nil
        and action.target.components.stewer ~= nil and action.target.components.stewer.product or nil
    action._my_friend_body_action, action._body_job = job.id, job
    action.validfn = function(act)
        if not Current(inst, job) then return false end
        if previous == nil or previous(act) then return true end
        job.operation_error = job.command ~= nil and job.command.failure_reason or nil
        if job.operation_error ~= nil then act.reason = job.operation_error end
        return false
    end
    action:AddSuccessAction(function()
        if not Current(inst, job) then return end
        job.action = nil
        local id = action.action.id
        if action.action == ACTIONS.MY_FRIEND_OPEN and action.target ~= nil and action.target.components.container ~= nil then
            job.opened = job.opened or {}; job.opened[action.target] = true
        end
        job.effects[id] = (job.effects[id] or 0) + 1
        if final_build then job.final_built = true end
        if final_deploy then job.final_deployed = true end
        if product ~= nil then job.product = product end
        if kind == "heal_self" then Finish(inst, job, true)
        elseif inst._my_friend_command ~= job.command then Finish(inst, job, TerminalEffect(job)) end
    end)
    action:AddFailAction(function()
        if not Current(inst, job) then return end
        job.action = nil
        if kind == "lightning_spear" and job.command.spear_phase == "charge" and inst._my_friend_command == job.command then return end
        job.failed_action = action.action.id
        Finish(inst, job, false, action._my_friend_path_failed and "unreachable"
            or action._my_friend_cancelled and "preempted" or job.operation_error or action.reason
            or job.command ~= nil and job.command.failure_reply or "character_action_failed")
    end)
    job.action = action
    return action
end
return M
