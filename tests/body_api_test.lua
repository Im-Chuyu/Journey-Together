-- Real body API/actions/observations with engine inventory/action boundaries.
-- lua tests/body_api_test.lua [native scripts path]
package.path = "./scripts/?.lua;" .. (arg[1] or "../yuanma/scripts") .. "/?.lua;" .. package.path
local json = require("json")
local now, serial, objects, spoken, equip_calls, builds = 0, 0, {}, {}, 0, 0
function GetTime() return now end
function Vector3(x, y, z) return {x = x, y = y, z = z, Get = function(p) return p.x, p.y, p.z end} end
EQUIPSLOTS = {HANDS = "hands", HEAD = "head", BODY = "body"}
ACTIONS = {}
for _, name in ipairs({"WALKTO", "PICKUP", "EQUIP", "UNEQUIP", "DROP", "EAT", "BUILD", "MY_FRIEND_BUILD",
    "MY_FRIEND_BODY", "CHOP", "MINE", "DIG", "HAMMER", "PICK", "HARVEST", "COOK", "HEAL", "SEW", "REPAIR", "ADDFUEL", "FERTILIZE", "READ"}) do
    ACTIONS[name] = {id = name}
end
function BufferedAction(doer, target, action, item, point)
    local a = {doer = doer, target = target, action = action, invobject = item, point = point, successes = {}, failures = {}}
    function a:AddSuccessAction(fn) self.successes[#self.successes + 1] = fn end
    function a:AddFailAction(fn) self.failures[#self.failures + 1] = fn end
    function a:IsValid() return self.validfn == nil or self.validfn(self) end
    function a:GetActionPoint() return self.point end
    function a:Fail() for _, fn in ipairs(self.failures) do fn() end end
    return a
end
local function Entity(prefab, x)
    serial = serial + 1
    local e = {GUID = serial, prefab = prefab, components = {}, x = x or 0, z = 0, valid = true, tags = {}, events = {}, tasks = {}}
    objects[e.GUID] = e
    e.Transform = {GetWorldPosition = function() return e.x, 0, e.z end,
        SetPosition = function(_, px, _, pz) e.x, e.z = px, pz end}
    function e:IsValid() return self.valid end
    function e:GetDisplayName() return self.prefab end
    function e:HasTag(tag) return self.tags[tag] == true end
    function e:HasAnyTag(...) for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end; return false end
    function e:IsInLimbo() return false end
    function e:GetPosition() return Vector3(self.x, 0, self.z) end
    function e:GetDistanceSqToInst(other) return (self.x - other.x)^2 + (self.z - other.z)^2 end
    function e:GetCurrentPlatform() return nil end
    function e:ListenForEvent(event, fn, source)
        local origin = source or self
        origin.events[event] = origin.events[event] or {}; table.insert(origin.events[event], {owner = self, fn = fn})
    end
    function e:RemoveEventCallback(event, fn, source)
        local list = (source or self).events[event] or {}
        for i = #list, 1, -1 do if list[i].fn == fn and list[i].owner == self then table.remove(list, i) end end
    end
    function e:PushEvent(event, data)
        local copy = {}; for i, record in ipairs(self.events[event] or {}) do copy[i] = record end
        for _, record in ipairs(copy) do record.fn(record.owner, data) end
    end
    function e:DoStaticTaskInTime(delay, fn)
        local task = {delay = delay, fn = fn}; function task:Cancel() self.cancelled = true end
        self.tasks[#self.tasks + 1] = task; return task
    end
    return e
end
local Item
local function Owner(item)
    local owner = item.owner
    while owner ~= nil and owner.components.inventoryitem ~= nil and owner.owner ~= nil do owner = owner.owner end
    return owner
end
Item = function(prefab, owner, size)
    local item = Entity(prefab); item.owner, item.size = owner, size or 1
    local inv = {canbepickedup = true}
    setmetatable(inv, {__index = function(_, k) if k == "owner" then return item.owner end end})
    function inv:GetGrandOwner() return Owner(item) end
    function inv:RemoveFromOwner(whole)
        if not whole and item.size > 1 then return item.components.stackable:Get(1) end
        item.owner = nil; return item
    end
    item.components.inventoryitem = inv
    item.components.stackable = {StackSize = function() return item.size end,
        Get = function(_, n) n = n or 1; assert(n < item.size); item.size = item.size - n; return Item(item.prefab, nil, n) end,
        Put = function(_, other) item.size = item.size + other.size; other.valid = false end}
    return item
end
local function Storage(entity, container)
    local c = {canbeopened = true}
    function c:ReferenceAllItems()
        local items = {}; for _, item in pairs(objects) do if item:IsValid() and Owner(item) == entity and item.components.inventoryitem ~= nil then items[#items + 1] = item end end
        return items
    end
    c.GetAllItems = c.ReferenceAllItems
    function c:GetActiveItem() return nil end
    function c:GetEquippedItem(slot) for _, item in ipairs(self:ReferenceAllItems()) do if item.equipped == slot then return item end end end
    function c:CanAcceptCount(_, n) return self.full and 0 or n end
    function c:IsFull() return self.full == true end
    function c:IsEmpty() return #self:ReferenceAllItems() == 0 end
    function c:IsRestricted() return self.restricted == true end
    function c:IsOpenedByOthers() return self.opened_by_other == true end
    function c:IsOpenedBy(inst) return self.opened == inst end
    function c:Open(inst) self.opened = inst end
    function c:Close() self.opened = nil end
    function c:GiveItem(item)
        if self.full then return false end
        item.owner = entity; return true
    end
    function c:RemoveItem(item) item.owner = nil; return item end
    function c:DropItem(item)
        item.owner = nil; item.x, item.z = entity.x, entity.z; return item
    end
    function c:Equip(item) equip_calls = equip_calls + 1; item.equipped = item.components.equippable.equipslot; return true end
    entity.components[container and "container" or "inventory"] = c
    return c
end
local function Armor(item, slot)
    item.components.equippable = {equipslot = slot, IsEquipped = function() return item.equipped ~= nil end,
        ShouldPreventUnequipping = function() return item.locked == true end}
end
package.loaded.my_friend_food_storage = {ReferenceItems = function(inst) return inst.components.inventory:ReferenceAllItems() end}
package.loaded.my_friend_inventory = {
    CanWithdrawFrom = function(_, e) local c = e.components.container; return c ~= nil and not c.restricted and not c.opened_by_other end,
    GiveCarried = function(inst, item) return inst.components.inventory:GiveItem(item) end,
    IsUsableTool = function(_, item, kind) return item.tool_action == kind end,
}
package.loaded.my_friend_navigation = {IsLand = function() return true end}
package.loaded.my_friend_dialogue = {Reply = function(_, key, text) spoken[#spoken + 1] = {key = key, text = text}; return true end}
package.loaded.my_friend_voice = {StopCustom = function() end}
package.loaded.my_friend_carry_backpack = {Cancel = function() end}
package.loaded.my_friend_recipe_cooking = {Cancel = function() end}
package.loaded.my_friend_contextual_events = {RecordFollowStarted = function(inst) inst.follow_recorded = true end}
package.loaded.my_friend_ghost_commands = {Cancel = function() end}
package.loaded.my_friend_riding = {AllowAutoRide = function(inst) inst.auto_ride_allowed = true end}
do
    local file = assert(io.open("scripts/my_friend_commands.lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
    local body = assert(source:match("function M.Clear%(friend, preserving_session, player_request%)(.-)\nend"))
    package.loaded.my_friend_commands = {Clear = assert(loadstring(
        "return function(friend, preserving_session, player_request)" .. body .. "\nend"))()}
    local aliases = assert(source:match("local ALIASES = ({.-\n})"))
    local address = assert(source:match("local function AddressedMessage%(friend, message%)(.-)\nend\n"))
    package.loaded.my_friend_commands.AddressedMessage = assert(loadstring("local ALIASES=" .. aliases
        .. "\nreturn function(friend,message)" .. address .. "\nend"))()
end
package.loaded.my_friend_food_ai = {IsForbiddenFood = function(item) return item.prefab == "charcoal" end,
    CanSafelyEat = function(inst, item) return inst.components.health.currenthealth + (item.hp or 0) > 0 end}
package.loaded.my_friend_food_rules = {CountStaleMeat = function() return 0 end}
package.loaded.my_friend_crafting_tech = {CanBuild = function(inst) return inst.technology ~= false end,
    OnBuilt = function() return function() end end}
package.loaded.my_friend_combat_rules = {DisengageForFollow = function(inst) inst.components.combat:SetTarget(nil) end}
package.loaded.my_friend_behavior_ai = {CanCounterAttack = function() return true end, CanContinueCombat = function() return true end}
package.loaded.cooking = {recipes = {cookpot = {frogglebunwich = {}}}}
package.loaded.my_friend_recipe_planner = {
    Available = function() return true end, Pool = function(inst) return inst.components.inventory:ReferenceAllItems() end,
    Find = function(_, _, pool)
        local count = {}; for _, item in ipairs(pool) do count[item.prefab] = (count[item.prefab] or 0) + item.size end
        if (count.froglegs or 0) >= 1 and (count.carrot or 0) >= 1 and (count.ice or 0) >= 2 then
            return {prefabs = {"froglegs", "carrot", "ice", "ice"}}, false
        end
    end,
    EvaluateSpecific = function(_, _, prefabs) return #prefabs == 4 and 1 or nil end,
}
local recipes = {spear = {name = "spear", numtogive = 1}}
function GetValidRecipe(name) return recipes[name] end
local API = require("my_friend_body_api")
local Actions = require("my_friend_body_actions")
ACTIONS.MY_FRIEND_BODY.fn = Actions.Operate
ACTIONS.WALKTO.fn = function(a)
    local p = a.target ~= nil and a.target:GetPosition() or a.point
    a.doer.x, a.doer.z = p.x, p.z; return true
end
ACTIONS.PICKUP.fn = function(a) return a.doer.components.inventory:GiveItem(a.target) end
ACTIONS.EQUIP.fn = function(a) return a.doer.components.inventory:Equip(a.invobject) end
ACTIONS.UNEQUIP.fn = function(a) a.invobject.equipped = nil; return true end
ACTIONS.MY_FRIEND_BUILD.fn = function() builds = builds + 1; return true end
ACTIONS.CHOP.fn = function(a) a.target.left = a.target.left - 1; return true end
ACTIONS.EAT.fn = function(a)
    a.doer.components.health.currenthealth = a.doer.components.health.currenthealth + (a.invobject.hp or 0)
    a.doer.components.hunger.current = a.doer.components.hunger.current + 10
    a.invobject.valid = false; return true
end
ACTIONS.HEAL.fn = function(a) a.target.components.health.currenthealth = a.target.components.health.currenthealth + 5; return true end
ACTIONS.COOK.fn = function(a) a.target.cooking = true; for _, item in ipairs(a.target.components.container:GetAllItems()) do item.valid = false end; return true end
ACTIONS.HARVEST.fn = function(a) Item(a.target.product, a.doer); a.target.done = false; return true end
local function Setup()
    now, serial, objects, spoken, equip_calls, builds = 100, 0, {}, {}, 0, 0
    Ents = objects
    local inst, player = Entity("wendy"), Entity("wilson")
    inst.tags.my_friend, inst.isplayer, player.isplayer, player.userid = true, true, true, "KU_body_test"
    inst._my_friend_model_enabled = true
    inst.components.my_friend_affinity = {value = 100, Get = function(self) return self.value end,
        CanCommandWork = function(self) return self.value > 50 end,
        RequestFollow = function(_, target) return target == player end}
    inst.components.follower = {GetLeader = function() return player end}
    inst.components.health = {currenthealth = 100, IsDead = function() return false end}
    inst.components.hunger, inst.components.sanity = {current = 100}, {current = 100}
    inst.components.combat = {SetTarget = function(self, target) self.target = target end}
    inst.components.eater = {CanEat = function() return true end, PrefersToEat = function() return true end}
    inst.components.builder = {HasIngredients = function() return inst.materials ~= false end}
    inst.sg = {HasStateTag = function(_, tag) return tag == "busy" and inst.busy == true end,
        currentstate = {name = "idle"}}
    Storage(inst)
    TheWorld = Entity("world"); TheWorld.ismastersim, TheWorld.ismastershard, TheWorld._my_friend = true, true, inst
    AllPlayers = {player}
    STRINGS = {CHARACTER_TITLES = {}}
    TheSim = {FindEntities = function(_, x, _, z, radius, must, cant)
        local found = {}
        for _, e in pairs(objects) do
            local matches = e:IsValid() and not (e.owner ~= nil and e.components.inventoryitem ~= nil)
                and (e.x - x)^2 + (e.z - z)^2 <= radius^2
            for _, tag in ipairs(must or {}) do matches = matches and e:HasTag(tag) end
            for _, tag in ipairs(cant or {}) do matches = matches and not e:HasTag(tag) end
            if matches then found[#found + 1] = e end
        end
        return found
    end}
    API.Configure(inst)
    local state = assert(API.Open(inst, player))
    return inst, player, state
end
local request = 0
local function Call(inst, player, skill, args)
    request = request + 1
    return API.Call(inst, player, "r" .. request, skill, args or {})
end
local function Perform(inst)
    local action = API.GetAction(inst)
    if action == nil then return end
    if action.target ~= nil and action.action ~= ACTIONS.WALKTO and inst:GetDistanceSqToInst(action.target) > 2^2 then
        inst.x, inst.z = action.target.x - 1.5, action.target.z
    end
    if not action:IsValid() then action:Fail(); return end
    if action.action.fn(action) then for _, fn in ipairs(action.successes) do fn() end else action:Fail() end
    return action
end
local function Handle(state, e) return API.Observation.Handle(state, e) end
local passed = 0
local function Test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end

Test("model mode gate and model work permissions are independent of native affinity and following", function()
    local inst, player = Setup()
    local affinity = inst.components.my_friend_affinity
    inst._my_friend_model_enabled = false
    assert(not API.Authorize(inst, player))
    inst._my_friend_model_enabled = true
    affinity.value = 19.99; assert(API.Authorize(inst, player))
    affinity.value = 20; assert(API.Authorize(inst, player) and not affinity:CanCommandWork(player))
    assert(Call(inst, player, "move_to", {position = {x = 4, z = 0}}).status == "accepted")
    affinity.RequestFollow = function() return false end
    assert(not require("my_friend_follow_request").Apply(inst, player, nil))
    affinity.RequestFollow = function() error("model resume must retain its current leader without re-requesting") end
    assert(Call(inst, player, "follow").status == "completed")
    API.Tick(inst)
    assert(inst._my_friend_body.active == nil)
    inst.components.follower.GetLeader = function() return nil end
    assert(API.Authorize(inst, player) and API.Valid(inst) ~= nil)
end)
Test("owner and nearby players expose character and actual three stats", function()
    local inst, player, state = Setup()
    player.components.health = {currenthealth = 31, maxhealth = 150, IsDead = function() return false end}
    player.components.hunger = {current = 12, max = 150}
    player.components.sanity = {current = 42, max = 200}
    local owner = API.Observation.Snapshot(inst, state).owner
    assert(owner.character.id == "wilson" and owner.name == player:GetDisplayName())
    assert(owner.health == 31 and owner.hunger == 12 and owner.sanity == 42)
    assert(owner.health_max == 150 and owner.hunger_max == 150 and owner.sanity_max == 200)
    API.Observation.RefreshEnvironment(inst, state)
    local nearby = state.environment.players[1]
    assert(nearby.character.id == "wilson" and nearby.hunger == 12 and nearby.sanity == 42)
end)

Test("permissions, absent companion, legacy work and replaceable action ownership", function()
    local inst, player = Setup()
    assert(not API.Authorize(nil, player))
    assert(API.AllowLocal(inst, "recipe_cooking", {hunger = 1}) and API.Score(inst, {}) == 0)
    assert(API.AllowLocal(inst, "eat", {hunger = .1}))
    local stranger = Entity("wilson"); stranger.userid = "other"; AllPlayers[#AllPlayers + 1] = stranger
    assert(Call(inst, stranger, "observe").status == "completed")
    assert(Call(inst, stranger, "move_to", {position = {x = 2, z = 0}}).reason == "leader_only_work")
    assert(Call(inst, player, "move_to", {position = {x = 4, z = 0}}).status == "accepted")
    assert(not API.AllowLocal(inst, "recipe_cooking", {hunger = 1}))
    assert(Call(inst, player, "craft", {recipe = "spear"}).status == "accepted")
    inst._my_friend_command = {id = "chop"}
    now = now + .31
    assert(Call(inst, player, "observe").status == "completed" and inst._my_friend_body ~= nil)
end)
Test("observe discovers named structures and restricted containers do not leak contents", function()
    local inst, p, state = Setup()
    local lab = Entity("researchlab3", 9); lab.tags.structure = true
    local box = Entity("treasurechest", 4); Storage(box, true).restricted = true; Item("gears", box)
    local result = Call(inst, p, "observe", {scope = "structures", filter = "researchlab3"})
    assert(result.status == "completed" and result.result.entities[1].prefab == "researchlab3")
    assert(API.Observation.Resolve(state, result.result.entities[1].handle) == lab)
    now = now + 1
    result = Call(inst, p, "observe", {scope = "containers", contents = true})
    assert(result.result.entities[1].contents == nil)
end)
Test("move runs once, returns actual position and deduplicates request ids", function()
    local inst, p = Setup()
    local result = API.Call(inst, p, "same", "move_to", {position = {x = 8, z = 2}, gait = "run"})
    local action = assert(API.GetAction(inst)); assert(action._my_friend_body_action == result.action_id)
    Perform(inst)
    local final = API.Call(inst, p, "same", "move_to", {position = {x = 9999, z = 0}})
    assert(final.status == "completed" and final.result.position.x == 8 and inst.x == 8)
    assert(inst._my_friend_body.active == nil)
end)
Test("unreachable route reports failure instead of arrival", function()
    local inst, p, state = Setup()
    local accepted = Call(inst, p, "move_to", {position = {x = 8, z = 0}})
    local a = assert(API.GetAction(inst)); a._my_friend_path_failed = true; a:Fail()
    local result = state.jobs[accepted.action_id]
    assert(result.status == "failed" and result.reason == "unreachable" and inst.x == 0)
end)
Test("pickup/drop/transfer honor stack portions and inventory ownership", function()
    local inst, p, state = Setup()
    local silk = Item("silk", nil, 8)
    local result = Call(inst, p, "pickup", {target = Handle(state, silk), count = 3}); Perform(inst)
    assert(state.jobs[result.action_id].result.count == 3 and silk.size == 5)
    local carried; for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do carried = item end
    local box = Entity("treasurechest", 2); Storage(box, true)
    result = Call(inst, p, "transfer", {item = Handle(state, carried), destination = Handle(state, box), count = 2}); Perform(inst); Perform(inst)
    assert(state.jobs[result.action_id].result.count == 2 and carried.size == 1)
    result = Call(inst, p, "drop", {item = Handle(state, carried), count = 1}); Perform(inst)
    assert(state.jobs[result.action_id].status == "completed" and carried.owner == nil)
end)
Test("custom inventory operations recheck physical reach after routing", function()
    local inst, p, state = Setup(); local item = Item("gears", nil); item.x = 10
    Call(inst, p, "pickup", {target = Handle(state, item)})
    local action = assert(API.GetAction(inst))
    assert(not Actions.Operate(action) and item.owner == nil)
    Perform(inst); assert(item.owner == inst)
end)
Test("equipping an already equipped item is idempotent and unequip preserves it", function()
    local inst, p, state = Setup(); local hat = Item("footballhat", inst); Armor(hat, "head")
    Call(inst, p, "equip", {item = Handle(state, hat)}); Perform(inst)
    assert(equip_calls == 1)
    local again = Call(inst, p, "equip", {item = Handle(state, hat)}); API.GetAction(inst)
    assert(state.jobs[again.action_id].status == "completed" and equip_calls == 1)
    Call(inst, p, "unequip", {slot = "head"}); Perform(inst); assert(hat.owner == inst and hat.equipped == nil)
end)
Test("exhausted hand equipment can still be unequipped and dropped", function()
    local inst, p, state = Setup(); local axe = Item("axe", inst); Armor(axe, "hands"); axe.equipped = "hands"
    axe.components.finiteuses = {GetPercent = function() return 0 end}
    local result = Call(inst, p, "unequip", {slot = "hands"}); Perform(inst)
    assert(state.jobs[result.action_id].status == "completed")
    result = Call(inst, p, "drop", {item = Handle(state, axe)}); Perform(inst)
    assert(state.jobs[result.action_id].status == "completed" and axe.owner == nil)
end)
Test("craft loops native builds and reports missing materials/technology", function()
    local inst, p, state = Setup()
    local result = Call(inst, p, "craft", {recipe = "spear", count = 2}); Perform(inst); Perform(inst)
    assert(builds == 2 and state.jobs[result.action_id].result.operations == 2)
    inst.materials = false; result = Call(inst, p, "craft", {recipe = "spear"}); API.GetAction(inst)
    -- This fixture recipe has no ingredient rows: a native HasIngredients
    -- rejection is a recipe condition, not an observed material deficit.
    assert(state.jobs[result.action_id].reason == "native_recipe_condition_unmet")
    inst.materials, inst.technology = true, false
    result = Call(inst, p, "craft", {recipe = "spear"}); API.GetAction(inst)
    assert(state.jobs[result.action_id].reason == "missing_technology")
end)
Test("work equips the actual carried tool then counts real work units", function()
    local inst, p, state = Setup()
    local tree = Entity("evergreen", 5); tree.left = 3
    tree.components.workable = {CanBeWorked = function() return tree.left > 0 end, GetWorkAction = function() return ACTIONS.CHOP end}
    local axe = Item("axe", inst); Armor(axe, "hands"); axe.tool_action = ACTIONS.CHOP
    local result = Call(inst, p, "work", {target = Handle(state, tree), action = "CHOP", amount = 2})
    Perform(inst)
    assert(API.GetAction(inst).invobject == axe)
    Perform(inst); Perform(inst)
    assert(tree.left == 1 and equip_calls == 1 and state.jobs[result.action_id].result.work_units == 2)
end)
Test("eat returns actual deltas and rechecks lethal food and ownership at execution", function()
    local inst, p, state = Setup(); local food = Item("carrot", inst); food.hp = 5
    local result = Call(inst, p, "eat", {item = Handle(state, food)}); Perform(inst)
    assert(state.jobs[result.action_id].result.health_delta == 5 and state.jobs[result.action_id].result.hunger_delta == 10)
    food = Item("monstermeat", inst); food.hp = -3
    result = Call(inst, p, "eat", {item = Handle(state, food)})
    local action = assert(API.GetAction(inst)); inst.components.health.currenthealth = 2
    assert(not action:IsValid()); action:Fail(); assert(food:IsValid())
    food = Item("charcoal", inst); assert(Call(inst, p, "eat", {item = Handle(state, food)}).reason == "cannot_eat")
end)
Test("cook fills four real slots, starts once, waits and verifies the harvested product", function()
    local inst, p, state = Setup(); local pot = Entity("cookpot", 3); Storage(pot, true)
    pot.components.stewer = {IsCooking = function() return pot.cooking == true end, IsDone = function() return pot.done == true end}
    Item("froglegs", inst); Item("carrot", inst); Item("ice", inst, 2)
    local result = Call(inst, p, "cook", {recipe = "frogglebunwich", station = Handle(state, pot)})
    for i = 1, 6 do Perform(inst) end
    assert(pot.cooking and state.active ~= nil and API.GetAction(inst) == nil)
    pot.cooking, pot.done, pot.product = false, true, "frogglebunwich"
    pot.components.stewer.product = pot.product
    Perform(inst)
    assert(state.jobs[result.action_id].status == "completed" and state.jobs[result.action_id].result.count == 1)
    assert(pot._my_friend_body_cook == nil)
end)
Test("native item use reports completion and cannot consume an item moved elsewhere", function()
    local inst, p, state = Setup(); local salve = Item("healingsalve", inst); salve.components.healer = {}
    local result = Call(inst, p, "use_item", {item = Handle(state, salve)})
    Perform(inst); assert(state.jobs[result.action_id].status == "completed" and inst.components.health.currenthealth == 105)
    Call(inst, p, "use_item", {item = Handle(state, salve)})
    local a = assert(API.GetAction(inst)); salve.owner = p; assert(not a:IsValid()); a:Fail()
end)
Test("engage confirms death; follow resumes legacy mode without owning or cancelling subsequent work", function()
    local inst, p, state = Setup(); local frog = Entity("frog", 4)
    frog.components.combat = {}
    frog.components.health = {IsDead = function() return false end}
    local result = Call(inst, p, "engage", {target = Handle(state, frog)})
    assert(Actions.CombatTarget(inst, state.active) == frog)
    inst.components.combat:SetTarget(frog); frog:PushEvent("death")
    assert(state.jobs[result.action_id].result.defeated and inst.components.combat.target == nil)
    result = Call(inst, p, "follow", {player = Handle(state, p), distance = 3})
    assert(result.status == "completed" and result.result.mode == "legacy" and state.active == nil)
    assert(inst.follow_recorded and inst.auto_ride_allowed and inst._my_friend_follow_requested_until == now + 30)
    assert(API.Score(inst, {}) == 0 and API.AllowLocal(inst, "sit", {}) and API.AllowLocal(inst, "follow", {}))
    local twigs = Item("twigs", nil)
    assert(Call(inst, p, "pickup", {target = Handle(state, twigs)}).status == "accepted")
    Perform(inst)
    assert(twigs.owner == inst and inst.components.follower:GetLeader() == p and inst._my_friend_body == state)
    assert(Call(inst, p, "cancel", {action_id = result.action_id}).status == "completed")
    assert(Call(inst, p, "disengage").status == "completed")
end)
Test("busy cancellation waits, statuses are queryable and death cleans the session", function()
    local inst, p, state = Setup(); local result = Call(inst, p, "move_to", {position = {x = 5, z = 0}})
    inst.busy = true; assert(Call(inst, p, "cancel", {action_id = result.action_id}).status == "accepted")
    assert(Call(inst, p, "get_action_status", {action_id = result.action_id}).status == "accepted")
    inst.busy = false; API.Tick(inst); assert(state.jobs[result.action_id].status == "cancelled")
    inst:PushEvent("death"); assert(inst._my_friend_body == nil)
end)
Test("say uses one dynamic template and receives external speech state", function()
    local inst, p, state = Setup()
    local result = Call(inst, p, "say", {text = "我已经到旁边了。"})
    assert(spoken[1].key == "ai_dynamic" and result.status == "completed")
    API.Playback(inst, result.action_id, "playing"); assert(state.jobs[result.action_id].result.speech == "playing")
    API.Playback(inst, result.action_id, "completed"); assert(inst._my_friend_body_speaking == nil)
end)
Test("observation and chatting during movement do not replan or cancel the body owner", function()
    local inst, p, state = Setup()
    local accepted = Call(inst, p, "move_to", {position = {x = 9, z = 0}})
    local active = state.active
    inst._my_friend_replan_requested = nil
    Call(inst, p, "observe", {scope = "inventory"})
    Call(inst, p, "say", {text = "我还在走。", speak = false})
    assert(state.active == active and inst._my_friend_replan_requested == nil)
    Perform(inst); assert(state.jobs[accepted.action_id].status == "completed")
end)
Test("long-running action stays in bounded history and is evicted normally after completion", function()
    local inst, p, state = Setup()
    local accepted = Call(inst, p, "move_to", {position = {x = 10, z = 0}})
    for i = 1, 80 do Call(inst, p, "say", {text = "test", speak = false}) end
    assert(state.jobs[accepted.action_id] ~= nil and #state.order == 40)
    Call(inst, p, "cancel", {action_id = accepted.action_id})
    for i = 1, 40 do Call(inst, p, "say", {text = "test", speak = false}) end
    assert(state.jobs[accepted.action_id] == nil)
    local count = 0; for _ in pairs(state.jobs) do count = count + 1 end
    assert(count <= 40)
end)
Test("actual command-clear boundary interrupts the body and releases future control", function()
    local inst, p, state = Setup(); local result = Call(inst, p, "move_to", {position = {x = 5, z = 0}})
    package.loaded.my_friend_carry_backpack = {Cancel = function() end}
    package.loaded.my_friend_recipe_cooking = {Cancel = function() end}
    local f = assert(io.open("scripts/my_friend_commands.lua", "rb")); local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
    local body = assert(source:match("function M.Clear%(friend, preserving_session, player_request%)(.-)\nend"))
    local clear = assert(loadstring("return function(friend, preserving_session, player_request)" .. body .. "\nend"))()
    clear(inst, nil, true)
    assert(inst._my_friend_body == state and state.jobs[result.action_id].status == "interrupted" and state.revision == 1)
end)
Test("ordinary inventory capture preserves control; destructive transfer closes before its snapshot", function()
    local inst, p = Setup()
    local transfer = require("my_friend_inventory_transfer")
    inst.components.inventory.OnSave = function() return {connected = inst._my_friend_body ~= nil, restored = inst.restored} end
    local saved = transfer.Capture(inst)
    assert(saved.connected and inst._my_friend_body ~= nil)
    inst._my_friend_body.cleanup = function() inst.restored = true end
    saved = transfer.SaveAndClear(inst)
    assert(not saved.connected and saved.restored and inst._my_friend_body == nil)
end)
Test("handles, event logs, result history, invalid arguments and stale replies stay bounded", function()
    local inst, p, state = Setup()
    for i = 1, 2200 do Handle(state, Entity("rock", 2)) end
    assert(#state.handle_order == 2048 and API.Observation.Resolve(state, "e1") == nil)
    for i = 1, 70 do Call(inst, p, "say", {text = "test", speak = false}) end
    assert(#state.order <= 40 and #state.events <= 64)
    assert(Call(inst, p, "move_to", {position = {x = math.huge, z = 0}}).status == "failed")
    local nav = require("my_friend_navigation")
    local land = nav.IsLand
    nav.IsLand = function(point) return point.x < 1024 end
    assert(Call(inst, p, "move_to", {position = {x = 9999, z = 0}}).reason == "invalid_terrain")
    local far = Call(inst, p, "move_to", {position = {x = 300, z = 0}})
    assert(far.status == "accepted")
    nav.IsLand = land
    assert(Call(inst, p, "craft", {recipe = "spear", count = -1}).status == "failed")
    assert(Call(inst, p, "unknown", {}).status == "failed")
end)
Test("a ghost cannot receive inventory transfers but can request a native heart revival", function()
    local inst, p, state = Setup()
    p.tags.playerghost = true
    local heart = Item("reviver", inst)
    heart.tags.reviver = true
    local old_rescue = package.loaded.my_friend_rescue
    local old_give = ACTIONS.GIVETOPLAYER
    package.loaded.my_friend_rescue = {CanRevivePlayer = function(target) return target == p and p.tags.playerghost end}
    ACTIONS.GIVETOPLAYER = {fn = function(act)
        assert(act.target == p and act.invobject == heart and heart.owner == inst)
        heart.owner, heart.valid, p.tags.reviving = nil, false, true
        return true
    end}
    local args = {item = Handle(state, heart), target = Handle(state, p)}
    local transfer = Call(inst, p, "transfer", {item = args.item, destination = args.target})
    assert(transfer.reason == "recipient_ghost_use_revive" and heart.owner == inst)
    local result = Call(inst, p, "revive", args)
    Perform(inst)
    assert(state.jobs[result.action_id].result.revive_started and p.tags.reviving and not heart.valid)
    package.loaded.my_friend_rescue, ACTIONS.GIVETOPLAYER = old_rescue, old_give
end)
Test("model task safely replaces legacy work; emergency priority and busy animations remain protected", function()
    local inst, p, state = Setup()
    inst._my_friend_command = {id = "chop", player = p}
    inst.busy = true
    local next_job = Call(inst, p, "craft", {recipe = "spear"})
    assert(next_job.status == "accepted" and state.pending ~= nil and inst._my_friend_command.id == "chop"
        and inst._my_friend_replan_requested and inst.busy)
    inst.busy = false
    API.Score(inst, {hurt_evade = true})
    assert(state.pending ~= nil and state.active == nil and inst._my_friend_command.id == "chop")
    inst._my_friend_replan_requested = nil
    API.Score(inst, {})
    assert(state.pending == nil and state.active.skill == "craft" and inst._my_friend_command == nil)
    assert(inst._my_friend_replan_requested == nil)
    Perform(inst)
    assert(state.jobs[next_job.action_id].status == "completed" and inst.components.follower:GetLeader() == p)
end)
Test("legacy takeover keeps the connection and rejects late old-revision commands", function()
    local inst, p, state = Setup()
    local old = Call(inst, p, "move_to", {position = {x = 9, z = 0}})
    inst.busy = true
    package.loaded.my_friend_commands.Clear(inst, nil, true)
    inst._my_friend_command = {id = "chop", player = p}
    assert(inst._my_friend_body == state and state.active.cancel_requested and state.revision == 1)
    assert(API.Call(inst, p, "stale", "move_to", {position = {x = 8, z = 0}}, 0, "user").reason == "superseded")
    inst.busy = false; API.Tick(inst)
    assert(state.jobs[old.action_id].status == "interrupted" and inst._my_friend_command.id == "chop")
    assert(API.Call(inst, p, "new", "move_to", {position = {x = 4, z = 0}}, 1, "user").status == "accepted")
    Perform(inst); assert(state.requests.new.status == "completed" and inst._my_friend_command == nil)
end)
Test("new model tasks replace busy model work at the safe boundary and pending/history stay bounded", function()
    local inst, p, state = Setup()
    local old = Call(inst, p, "move_to", {position = {x = 9, z = 0}})
    inst.busy = true
    local next_job = Call(inst, p, "move_to", {position = {x = 3, z = 0}})
    for i = 1, 70 do Call(inst, p, "say", {text = "x", speak = false}) end
    assert(state.active.id == old.action_id and state.pending.id == next_job.action_id and #state.order == 40)
    inst.busy = false; API.Tick(inst); Perform(inst)
    assert(state.jobs[old.action_id].status == "cancelled" and inst.x == 3)
    assert(state.jobs[next_job.action_id].status == "completed")
    assert(API.Call(inst, p, "ambient-work", "craft", {recipe = "spear"}, state.revision, "ambient").reason == "ambient_chat_only")
    API.Score(inst, {dark = true})
    assert(API.Call(inst, p, "ambient-talk", "say", {text = "x"}, state.revision, "ambient").reason == "unsafe_for_idle_chat")
    inst._my_friend_replan_requested = nil
    Call(inst, p, "move_to", {position = {x = 7, z = 0}})
    assert(state.pending ~= nil and state.active == nil and inst._my_friend_replan_requested == nil)
end)
Test("connecting while legacy work runs preserves that work until a real model task arrives", function()
    local inst, p = Setup(); API.Close(inst, "setup")
    inst._my_friend_command = {id = "chop", player = p}; inst._my_friend_replan_requested = nil
    local state = assert(API.Open(inst, p))
    assert(inst._my_friend_command.id == "chop" and inst._my_friend_replan_requested == nil)
    TheWorld.state = {cycles = 8, season = "winter", temperature = -5}
    API.Observation.RefreshEnvironment(inst, state)
    local snapshot = API.Observation.Snapshot(inst, state)
    assert(snapshot.world.day == 9 and snapshot.world.season == "winter" and snapshot.character.id == "wendy")
    assert(snapshot.environment.players[1].name == p.prefab)
end)
Test("world kind and shard follow the companion even without weather or map data", function()
    local inst, _, state = Setup()
    local previous_shard = TheShard
    local shard = 1
    TheShard = {GetShardId = function() return shard end}
    TheWorld.prefab, TheWorld.state = "forest", nil
    local surface = API.Observation.Snapshot(inst, state).world
    assert(surface.kind == "surface" and surface.prefab == "forest" and surface.shard_id == "1" and surface.day == nil)
    TheWorld.prefab, shard = "cave", 2
    local caves = API.Observation.Snapshot(inst, state).world
    assert(caves.kind == "caves" and caves.prefab == "cave" and caves.shard_id == "2")
    TheWorld.prefab = "modded_world"
    local unknown = API.Observation.Snapshot(inst, state).world
    assert(unknown.kind == "unknown" and unknown.prefab == "modded_world")
    TheShard = previous_shard
end)
Test("natural command cleanup does not replace conversation; stopping a busy body node preserves manual interruption reason", function()
    local inst, p, state = Setup()
    inst._my_friend_command = {id = "chop", player = p}
    package.loaded.my_friend_commands.Clear(inst)
    assert(state.revision == 0 and inst._my_friend_body == state)
    local result = Call(inst, p, "move_to", {position = {x = 3, z = 0}})
    local job = state.active; inst.busy = true
    package.loaded.my_friend_commands.Clear(inst, nil, true)
    local file = assert(io.open("scripts/behaviours/my_friend_body.lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
    local body = assert(source:match("function Body:OnStop%(%)(.-)\nend"))
    local stop = assert(loadstring("local API=require('my_friend_body_api'); return function(self)" .. body .. "\nend"))()
    stop({inst = inst, job = job, Release = function() end})
    assert(state.jobs[result.action_id].status == "interrupted" and job.reason == "manual_command")
end)
print(string.format("%d body API tests passed", passed))
