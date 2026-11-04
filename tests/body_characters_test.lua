-- Existing-role bridge with real API/role checks and real Wendy/Wormwood modules.
package.path = "./scripts/?.lua;../yuanma/scripts/?.lua;" .. package.path
local file = assert(io.open("tests/body_api_test.lua", "rb")); local source = file:read("*a"):gsub("\r", ""); file:close()
local fixture = assert(loadstring(assert(source:match("^(.-)local passed = 0")) ..
    "\nreturn {setup=Setup,entity=Entity,item=Item,perform=Perform,storage=Storage}"))()
local API = require("my_friend_body_api")
local commands = package.loaded.my_friend_commands
commands.Get = function(inst) return inst._my_friend_command end
package.loaded.my_friend_books = {PrepareCommand = function(_, command) command.prepared = true end, Close = function() end}
package.loaded.my_friend_bookstation = {PrepareCommand = function(command) command.prepared = true end}
package.loaded.my_friend_dialogue.Say = function() end
ACTIONS.READ = {id = "READ", fn = function() return true end}
ACTIONS.HEAL.fn = function(action)
    local target = action.target or action.doer
    target.components.health.currenthealth = target.components.health.currenthealth + action.invobject.components.healer.health
    return true
end
ACTIONS.MY_FRIEND_SPEAR_BUILD = {id = "MY_FRIEND_SPEAR_BUILD", fn = function() return true end}
local serial = 0
local function Setup(character)
    local inst, player, state = fixture.setup(); inst.prefab = character
    inst.components.health.GetPercent = function() return inst.components.health.currenthealth / 100 end
    inst.components.health.GetMaxWithPenalty = function() return 100 end
    return inst, player, state
end
local function Call(inst, player, args)
    serial = serial + 1
    return API.Call(inst, player, "role:" .. serial, "character_skill", args)
end
local function Factory(inst, command)
    assert(inst._my_friend_command == command)
    if command.waiting then return end
    local action = BufferedAction(inst, nil, command.special == "read" and ACTIONS.READ or ACTIONS.MY_FRIEND_BUILD)
    action.recipe = command.recipe
    action.validfn = function() return inst._my_friend_command == command end
    action:AddSuccessAction(function() commands.Clear(inst) end)
    return action
end
package.loaded.my_friend_special_actions = {GetAction = Factory}
local passed = 0
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
Test("catalogue covers only eight existing role scripts and distinguishes passive support", function()
    local inst, player = Setup("wendy")
    for _, character in ipairs({"wendy", "wanda", "wickerbottom", "wathgrithr", "warly", "wortox", "wormwood", "wx78"}) do
        inst.prefab = character
        local result = API.Call(inst, player, "caps:" .. character, "get_capabilities", {})
        assert(result.status == "completed" and #result.result.role.scripted_characters == 8)
        if character == "wx78" then assert(#result.result.role.actions == 0 and #result.result.role.automatic > 0) end
    end
    inst.prefab = "wilson"
    assert(Call(inst, player, {ability = "abigail_recall"}).reason == "unsupported_character_ability")
end)
Test("Wendy mode operations reuse the actual role script and preserve the native cooldown", function()
    local inst, player, state = Setup("wendy")
    local ghost = fixture.entity("abigail")
    function ghost:BecomeAggressive() self.is_defensive = false end
    function ghost:BecomeDefensive() self.is_defensive = true end
    inst.components.ghostlybond = {summoned = true, ghost = ghost}
    local job = Call(inst, player, {ability = "abigail_aggressive"}); API.GetAction(inst)
    assert(state.jobs[job.action_id].status == "completed" and ghost.is_defensive == false)
    assert(inst._my_friend_abigail_manual_until == GetTime() + 120)
    job = Call(inst, player, {ability = "abigail_defensive"}); API.GetAction(inst)
    assert(state.jobs[job.action_id].status == "completed" and ghost.is_defensive)
    local marker = {id = "existing-action", skill = "work", status = "running"}
    state.active, inst.busy = marker, true
    job = Call(inst, player, {ability = "abigail_aggressive"})
    assert(job.status == "completed" and state.active == marker and inst.busy)
    state.active, inst.busy = nil, false
end)
Test("existing Warly seasoning harvests closed ready stations without trying to reopen them", function()
    local inst, player = Setup("warly")
    local station = fixture.entity("portablespicer", 3)
    local container = {canbeopened = false, IsRestricted = function() return false end, IsOpenedByOthers = function() return false end,
        IsOpenedBy = function() return false end}
    station.components.container = container
    station.components.stewer = {IsCooking = function() return false end, IsDone = function() return true end}
    local f = assert(io.open("scripts/my_friend_special_actions.lua", "rb")); local source = f:read("*a"):gsub("\r", ""); f:close()
    local snippet = assert(source:match('(local function SpiceAction.-)\nlocal function DirectRoleRecipeAction'))
    local env = setmetatable({FindSpicer = function() return station end, Policy = require("my_friend_policy"),
        Inventory = {ContainerReach = function() return 2.4 end}}, {__index = _G})
    local chunk = assert(loadstring(snippet .. "\nreturn SpiceAction")); setfenv(chunk, env)
    local action = chunk()(inst, {})
    assert(action.action == ACTIONS.HARVEST and action.arrivedist == 2.4 and action:IsValid())
    container.readonlycontainer = true
    assert(not action:IsValid())
end)
Test("role build and bookshelf-aware read keep body ownership and finish from real action callbacks", function()
    local inst, player, state = Setup("wanda")
    local old_work = {id = "chop", player = player}; inst._my_friend_command = old_work
    assert(Call(inst, player, {ability = "build_special", recipe = "sisturn"}).reason == "unsupported_character_recipe")
    assert(inst._my_friend_command == old_work)
    local job = Call(inst, player, {ability = "build_special", recipe = "pocketwatch_heal"})
    assert(API.Score(inst, {}) > 0 and not API.AllowLocal(inst, "work", {}))
    fixture.perform(inst)
    assert(state.jobs[job.action_id].status == "completed" and state.jobs[job.action_id].result.actions.MY_FRIEND_BUILD == 1)
    assert(inst._my_friend_command == nil and inst._my_friend_body == state)
    inst.prefab = "wickerbottom"
    job = Call(inst, player, {ability = "read_book", recipe = "book_rain"})
    assert(state.active.command.prepared); fixture.perform(inst)
    assert(state.jobs[job.action_id].status == "completed" and state.jobs[job.action_id].result.actions.READ == 1)
    assert(Call(inst, player, {ability = "read_book", recipe = "made_up_book"}).reason == "unsupported_book")
end)
Test("no-effect native read does not claim success, waiting remains active and newer game commands survive cleanup", function()
    local inst, player, state = Setup("wickerbottom")
    package.loaded.my_friend_special_actions.GetAction = function(actor) commands.Clear(actor) end
    local job = Call(inst, player, {ability = "read_book"}); API.GetAction(inst)
    assert(state.jobs[job.action_id].status == "failed" and state.jobs[job.action_id].reason == "book_not_read")
    package.loaded.my_friend_special_actions.GetAction = Factory
    inst.prefab = "wanda"; job = Call(inst, player, {ability = "build_special", recipe = "pocketwatch_weapon"})
    state.active.command.waiting = true; assert(API.GetAction(inst) == nil and state.active ~= nil)
    local next_command = {id = "chop", player = player}
    inst._my_friend_command = next_command; API.ManualTakeover(inst)
    assert(inst._my_friend_command == next_command and state.jobs[job.action_id].status == "interrupted")
end)
Test("an intermediate material build cannot be reported as the requested role item", function()
    local inst, player, state = Setup("wanda")
    package.loaded.my_friend_special_actions.GetAction = function(actor, command)
        local action = Factory(actor, command); action.recipe = "rope"; return action
    end
    local job = Call(inst, player, {ability = "build_special", recipe = "pocketwatch_heal"})
    fixture.perform(inst)
    assert(state.jobs[job.action_id].status == "failed" and not state.jobs[job.action_id].result.built)
    package.loaded.my_friend_special_actions.GetAction = Factory
end)
Test("canceling a role task closes only its own opened station and never a newer command's station", function()
    for _, newer in ipairs({false, true}) do
        local inst, player, state = Setup("warly")
        local station = fixture.entity("portablespicer", 2); local container = fixture.storage(station, true)
        ACTIONS.MY_FRIEND_OPEN = {id = "MY_FRIEND_OPEN", fn = function() container:Open(inst); return true end}
        package.loaded.my_friend_special_actions.GetAction = function()
            return BufferedAction(inst, station, ACTIONS.MY_FRIEND_OPEN)
        end
        local job = Call(inst, player, {ability = "build_special", recipe = "portablespicer_item"})
        fixture.perform(inst); assert(container:IsOpenedBy(inst))
        if newer then inst._my_friend_command = {id = "chop", player = player} end
        API.ManualTakeover(inst)
        assert(state.jobs[job.action_id].status == "interrupted")
        assert(container:IsOpenedBy(inst) == newer)
    end
    package.loaded.my_friend_special_actions.GetAction = Factory
end)
Test("Wormwood uses existing carried-medicine scoring and does not heal through food", function()
    local inst, player, state = Setup("wormwood")
    local job = Call(inst, player, {ability = "heal_self"}); API.GetAction(inst)
    assert(state.jobs[job.action_id].result.already_healthy)
    inst.components.health.currenthealth = 50
    local medicine = fixture.item("healingsalve", inst); medicine.components.healer = {health = 20}
    job = Call(inst, player, {ability = "heal_self"}); fixture.perform(inst)
    assert(state.jobs[job.action_id].status == "completed" and state.jobs[job.action_id].result.actions.HEAL == 1)
    assert(inst.components.health.currenthealth > 50)
end)
print(passed .. " character script bridge tests passed")
