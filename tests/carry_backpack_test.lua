-- Run from the mod root: lua tests/carry_backpack_test.lua
-- Simulates DST entities/actions; no game runtime or world changes required.
package.path = "scripts/?.lua;" .. package.path
local now, replies, entities = 0, {}, {}
GetTime = function() return now end
EQUIPSLOTS = {HEAD = "head", BODY = "body", HANDS = "hands", BACK = "back"}
ACTIONS = {PICKUP = {}, WALKTO = {}, MOUNT = {}}
STRINGS = {CHARACTER_TITLES = {}}
Ents = {}
TheSim = {FindEntities = function() return entities end}
local function point(x)
    return {x = x or 0, y = 0, z = 0, Get = function(p) return p.x, p.y, p.z end}
end
Vector3 = function(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
local function entity(tags, x)
    local e = {tags = tags or {}, components = {}, pos = point(x), events = {}, tasks = {}}
    function e:IsValid() return not self.removed end
    function e:HasTag(tag) return self.tags[tag] == true end
    function e:AddTag(tag) self.tags[tag] = true end
    function e:RemoveTag(tag) self.tags[tag] = nil end
    function e:IsInLimbo() return self.limbo == true end
    function e:GetPosition() return self.pos end
    function e:GetDistanceSqToInst(other) return (self.pos.x - other.pos.x)^2 end
    function e:GetDisplayName() return self.name or "温蒂" end
    function e:ListenForEvent(event, fn)
        self.events[event] = self.events[event] or {}
        table.insert(self.events[event], fn)
    end
    function e:PushEvent(event, data)
        for _, fn in ipairs(self.events[event] or {}) do fn(self, data) end
    end
    function e:DoTaskInTime(_, fn) table.insert(self.tasks, fn) end
    function e:Flush()
        local tasks = self.tasks
        self.tasks = {}
        for _, fn in ipairs(tasks) do fn() end
    end
    function e:GetBufferedAction() end
    e.Transform = {GetWorldPosition = function() return e.pos:Get() end}
    return e
end
local function item(tags, slot)
    local e = entity(tags)
    e.components.inventoryitem = {canbepickedup = true,
        GetGrandOwner = function(ii) return ii.owner end}
    e.components.equippable = {equipslot = slot or EQUIPSLOTS.BODY,
        IsRestricted = function(eq) return eq.restricted == true end,
        ShouldPreventUnequipping = function(eq) return eq.locked == true end}
    return e
end
BufferedAction = function(inst, target, action)
    local a = {doer = inst, target = target, action = action, success = {}, failure = {}}
    function a:AddSuccessAction(fn) table.insert(self.success, fn) end
    function a:AddFailAction(fn) table.insert(self.failure, fn) end
    function a:IsValid() return self.validfn == nil or self.validfn(self) end
    function a:Succeed() for _, fn in ipairs(self.success) do fn() end end
    function a:Fail() for _, fn in ipairs(self.failure) do fn() end end
    return a
end
package.loaded.my_friend_dialogue = {
    Reply = function(_, key) replies[#replies + 1] = key end,
    RandomReply = function(_, key) replies[#replies + 1] = key end,
}
package.loaded.my_friend_recovery_safety = {IsSafe = function() return true end}
local riding = {
    GetBeefalo = function(inst) return not inst.riding and inst.beefalo or nil end,
    IsAvailableBeefalo = function(_, beefalo) return beefalo ~= nil and not beefalo.removed end,
    GetMountAction = function(inst, beefalo) return BufferedAction(inst, beefalo, ACTIONS.MOUNT) end,
}
package.loaded.my_friend_riding = riding
package.loaded.my_friend_beefalo = {Riding = riding}
package.loaded.my_friend_home = {IsAskPending = function() return false end}
package.loaded.my_friend_special_commands = {Parse = function() end}
package.loaded.my_friend_pets = {Parse = function() end}
package.loaded.my_friend_recipe_cooking = {Cancel = function() end}
local Slots = require("my_friend_equip_slots")
local Bags = require("my_friend_backpacks")
local Trip = require("my_friend_carry_backpack")
local Equipment = require("my_friend_equipment")
local Commands = require("my_friend_commands")
local Policy = require("my_friend_policy")
local Navigation = require("my_friend_navigation")
local Carry = require("my_friend_command_carry")
local Language = require("my_friend_strings")

local function fixture(extra_slot)
    now, replies, Ents = 0, {}, {}
    local leader, inst = entity({}, 80), entity({my_friend = true, player = true})
    inst.prefab, inst.leader = "wendy", leader
    AllPlayers = {leader}
    inst.components.health = {IsDead = function() return false end}
    inst.components.follower = {GetLeader = function() return inst.leader end}
    inst.components.rider = {IsRiding = function() return inst.riding == true end}
    local inventory = {inst = inst, slots = {}}
    function inventory:GetEquippedItem(slot) return self.slots[slot] end
    function inventory:ReferenceAllItems()
        local result = {}
        for _, obj in pairs(self.slots) do table.insert(result, obj) end
        return result
    end
    function inventory:Equip(obj)
        self.slots[obj.components.equippable.equipslot] = obj
        obj.components.inventoryitem.owner = inst
        inst:PushEvent("equip", {item = obj})
        return true
    end
    inst.components.inventory = inventory
    Equipment.Wrap(inventory)
    Trip.Configure(inst)
    local bag = item({backpack = true}, extra_slot and EQUIPSLOTS.BACK or EQUIPSLOTS.BODY)
    local heavy = item({heavy = true})
    Ents[1], Ents[2] = bag, heavy
    inventory:Equip(bag)
    Bags.MarkOwned(inst, bag)
    return inst, leader, bag, heavy, inventory
end
local function lift(inst, bag, heavy, inventory)
    inst:PushEvent("onpickupitem", {item = heavy})
    if bag.components.equippable.equipslot == heavy.components.equippable.equipslot then
        inventory.slots[bag.components.equippable.equipslot] = nil
        bag.components.inventoryitem.owner = nil
    end
    inventory:Equip(heavy)
    inst:Flush()
end
local function putdown(inst, heavy, inventory)
    inventory.slots[heavy.components.equippable.equipslot] = nil
    heavy.components.inventoryitem.owner = nil
    Trip.Update(inst)
end
local function ready()
    local inst, leader, bag, heavy, inv = fixture()
    lift(inst, bag, heavy, inv)
    putdown(inst, heavy, inv)
    now = 5.1
    Trip.Update(inst)
    assert(replies[#replies] == "carry_backpack_ask")
    return inst, leader, bag, heavy, inv
end

-- No automatic equip loop; light overrides cannot replace the heavy slot.
do
    local inst, leader, bag, heavy, inv = fixture()
    lift(inst, bag, heavy, inv)
    assert(Trip.BlocksRecovery(inst))
    now = 20
    assert(Trip.Score(inst) == 0 and #replies == 0)
    Bags.Update(inst)
    assert(Bags.GetAction(inst) == nil and inv:GetEquippedItem(EQUIPSLOTS.BODY) == heavy)
    inst._my_friend_light_equip_override = true
    assert(not inv:Equip(bag))
    putdown(inst, heavy, inv)
    now = 25
    Trip.Update(inst)
    assert(#replies == 0, "must wait more than five seconds")
    inv:Equip(heavy) -- Restart the continuous empty-hands timer.
    now = 30
    putdown(inst, heavy, inv)
    now = 35.1
    Trip.Update(inst)
    assert(#replies == 1)
    now = 90
    Trip.Update(inst)
    assert(#replies == 1 and Trip.GetAction(inst) == nil)
end

-- Multiple equipment slots keep both items; no retrieval question/trip.
do
    local inst, _, bag, heavy, inv = fixture(true)
    lift(inst, bag, heavy, inv)
    assert(Slots.IsEquipped(inv, bag) and Slots.GetHeavy(inv) == heavy)
    assert(not Trip.BlocksRecovery(inst))
    putdown(inst, heavy, inv)
    now = 10
    Trip.Update(inst)
    assert(#replies == 0 and inst._my_friend_carry_backpack == nil)
end

-- Actual chat dispatch: bare/addressed agreement, correct leader, no negatives.
for _, answer in ipairs({"可以", "行", "没问题", "好", "好的", "yes", "no problem", "Wendy, okay!"}) do
    local inst, leader = ready()
    assert(not Trip.Answer(inst, entity(), answer))
    assert(not Commands.Dispatch(inst, leader, "不可以"))
    assert(not Commands.Dispatch(inst, leader, "not okay"))
    assert(Commands.Dispatch(inst, leader, answer), answer)
    assert(Trip.Score(inst) == 117)
end

-- Authorized long-distance pickup then explicit return to the moving leader.
do
    local inst, leader, bag, heavy, inv = ready()
    assert(Trip.Answer(inst, leader, "好"))
    local pickup = Policy.GuardAction(inst, Trip.GetAction(inst))
    assert(pickup.action == ACTIONS.PICKUP and pickup.target == bag and pickup:IsValid())
    inst._my_friend_navigation_action = pickup
    assert(Navigation.InTravelRange(inst, point(-100)))
    inv:Equip(bag)
    pickup:Succeed()
    local back = Trip.GetAction(inst)
    assert(back.action == ACTIONS.WALKTO and back.target == leader)
    leader.pos.x = 120
    assert(back.target:GetPosition().x == 120)
    inst.pos.x = 118
    assert(Trip.Score(inst) == 0)
    assert(replies[#replies] == "carry_backpack_done")
    assert(not Trip.IsTravelAction(inst, pickup))
end

-- Ride when possible, including a bell left inside the dropped backpack.
for _, bell_in_bag in ipairs({false, true}) do
    local inst, leader, bag = ready()
    local cow = entity()
    if bell_in_bag then
        local bell = entity({bell = true})
        bell.GetBeefalo = function() return cow end
        bag.components.container = {slots = {bell}}
    else inst.beefalo = cow end
    assert(Trip.Answer(inst, leader, "可以"))
    local mount = Trip.GetAction(inst)
    assert(mount.action == ACTIONS.MOUNT and mount.target == cow)
    inst.riding = true
    mount:Fail() -- Native mount transition may clear a successful action.
    assert(Trip.GetAction(inst).action == ACTIONS.PICKUP)
end

-- Reload retains permission requirement, not permission from a previous trip.
do
    local inst, _, bag = ready()
    local data = {}
    bag:OnSave(data)
    bag._my_friend_heavy_left, inst._my_friend_carry_backpack = nil, nil
    bag:OnLoad(data)
    assert(Trip.BlocksRecovery(inst) and Trip.GetAction(inst) == nil)
    bag.components.inventoryitem.owner = entity()
    Trip.Update(inst)
    assert(inst._my_friend_carry_backpack == nil, "do not fetch a bag taken by someone else")
end

-- Interrupted trips lose travel permission; failed trips don't retry endlessly.
do
    local inst, leader = ready()
    Trip.Answer(inst, leader, "好")
    local action = Trip.GetAction(inst)
    Commands.Clear(inst)
    assert(not action:IsValid() and Trip.GetAction(inst) == nil)
    now = now + 6
    Trip.Update(inst)
    assert(Trip.Answer(inst, leader, "好"))
    assert(not action:IsValid(), "old trip must stay cancelled after a new approval")
    action:Fail()
    assert(Trip.Score(inst) == 117, "stale failure must not cancel the new trip")
    inst, leader = ready()
    Trip.Answer(inst, leader, "好")
    Trip.GetAction(inst):Fail()
    assert(Trip.Score(inst) == 0 and Trip.GetAction(inst) == nil)
end
assert(Bags.GetAction(nil) == nil)

-- Real carry selector accepts special heavy items and rejects unliftable ones.
do
    local inst, leader = fixture()
    local special = item({heavy = true})
    special.prefab = "moon_altar_glass"
    local invalid = item({heavy = true})
    invalid.components.equippable.restricted = true
    entities = {invalid, special, item({statue = true})}
    local command = {player = leader, origin = point(), phase = "find"}
    inst._my_friend_command = command
    local action = Carry.GetAction(inst, command)
    assert(action ~= nil and action.target == special)
    inst.components.inventory.noheavylifting = true
    assert(not action:IsValid())
end

-- Panel localization follows actual character, preserving replicated nicknames.
do
    local inst = entity()
    inst.prefab = "wathgrithr"
    Language.language = "en"
    assert(Language.CompanionName(inst) == "Wigfrid")
    inst.prefab = "waxwell"
    assert(Language.CompanionName(inst) == "Maxwell")
    inst.replica = {named = {_name = {value = function() return "My friend" end}}}
    inst.name = "My friend"
    assert(Language.CompanionName(inst) == "My friend")
    inst.replica, inst.name = nil, nil
    Language.language = "zh"
    assert(Language.CompanionName(inst) == "温蒂")
end
print("PASS: carry backpack, permission, slots, travel, targets, and panel names")
