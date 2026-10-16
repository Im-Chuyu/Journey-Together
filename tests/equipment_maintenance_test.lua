package.path = "scripts/?.lua;" .. package.path
local now, guid, scans, registrations = 0, 0, 0, 0
GetTime = function() return now end
EQUIPSLOTS = {HANDS = "hands", HEAD = "head", BODY = "body"}
FUELTYPE = {NIGHTMARE = "NIGHTMARE", MAGIC = "MAGIC", USAGE = "USAGE"}
ACTIONS = {SEW = {}, REPAIR = {}, ADDFUEL = {}}
TheWorld = {ismastersim = true}
TheSim = {FindEntities = function() error("equipment maintenance must not search the world") end}
package.loaded.my_friend_policy = {IsBusy = function(inst) return inst.busy == true end}
BufferedAction = function(inst, target, action, kit)
    local value = {doer = inst, target = target, action = action, invobject = kit}
    function value:AddSuccessAction(callback) self.success = callback end
    function value:AddFailAction(callback) self.failure = callback end
    return value
end
local Entity = {}
function Entity:IsValid() return not self.removed end
function Entity:HasTag(tag) return self.tags[tag] == true end
function Entity:ListenForEvent() registrations = registrations + 1 end
function Entity:PushEvent_Internal() end
function Entity:PushEvent(event, data) self:PushEvent_Internal(event, data) end
local function entity(prefab)
    guid = guid + 1
    local value = setmetatable({prefab = prefab, GUID = guid, components = {}, tags = {}}, {__index = Entity})
    value.Transform = {GetWorldPosition = function() return 0, 0, 0 end}
    return value
end
local Discovery = require("my_friend_discovery")
Discovery.Install(Entity, {pickable = {}, crop = {}, dryer = {}})
local Equipment = require("my_friend_equipment")
local function companion()
    local inst = entity("wendy")
    local inventory = {items = {}, equipslots = {}}
    function inventory:ReferenceAllItems() scans = scans + 1; return self.items end
    function inventory:GetEquippedItem(slot) return self.equipslots[slot] end
    inst.components.inventory = inventory
    return inst
end
local function item(inst, prefab)
    local value = entity(prefab)
    value.components.inventoryitem = {owner = inst}
    function value.components.inventoryitem:GetGrandOwner() return self.owner end
    inst.components.inventory.items[#inst.components.inventory.items + 1] = value
    value:PushEvent("onputininventory")
    return value
end
local function durability(value, component, percent)
    local state = {percent = percent}
    function state:GetPercent() return self.percent end
    function state:GetUses() return self.percent * 100 end
    function state:IsEmpty() return self.percent <= 0 end
    function state:SetPercent(number)
        self.percent = math.min(1, number)
        value:PushEvent("percentusedchange", {percent = self.percent})
    end
    value.components[component] = state
    return state
end
local function sewing(inst)
    local kit = item(inst, "sewing_kit")
    kit.components.sewing = {}
    durability(kit, "finiteuses", 1)
    return kit
end
local function forge(inst, material)
    local kit = item(inst, material .. "_kit")
    kit.components.forgerepair = {repairmaterial = material}
    durability(kit, "finiteuses", 1)
    return kit
end
local function change(value, component, percent)
    now = now + 2.1
    value.components[component]:SetPercent(percent)
end
local function execute(action)
    assert(action.validfn())
    local target, kit = action.target, action.invobject
    if action.action == ACTIONS.ADDFUEL then
        assert(target.components.fueled:CanAcceptFuelItem(kit))
        target.components.fueled:SetPercent(target.components.fueled:GetPercent() + .25)
        kit.count = kit.count - 1
        kit:PushEvent("stacksizechange")
        if kit.count == 0 then
            kit.components.inventoryitem.owner, kit.removed = nil, true
            kit:PushEvent("onremove")
            Discovery.InventoryChanged(action.doer)
        end
    elseif action.action == ACTIONS.REPAIR then
        assert(target.components.forgerepairable.repairmaterial == kit.components.forgerepair.repairmaterial)
        local state = target.components.armor or target.components.finiteuses or target.components.fueled
        state:SetPercent(1)
    else
        assert(action.action == ACTIONS.SEW and target:HasTag("needssewing"))
        target.components.fueled:SetPercent(1)
    end
    action.success()
    now = now + 2.1
end

for _, prefab in ipairs({"eyebrellahat", "heatrock", "mod_sewable"}) do
    local inst = companion()
    local target = item(inst, prefab)
    target.tags.needssewing = true
    durability(target, "fueled", .14)
    local kit = sewing(inst)
    assert(Equipment.GetRepairStatus(inst))
    local action = assert(Equipment.GetRepairAction(inst))
    assert(action.action == ACTIONS.SEW and action.target == target and action.invobject == kit)
    execute(action)
    assert(not Equipment.GetRepairStatus(inst))
end

for _, example in ipairs({{"voidcloth_umbrella", "fueled", "voidcloth"},
    {"armor_voidcloth", "armor", "voidcloth"}, {"lunarplant_sword", "finiteuses", "lunarplant"},
    {"mod_armor", "armor", "custom_material"}}) do
    local inst = companion()
    local target = item(inst, example[1])
    durability(target, example[2], .8)
    target.components.forgerepairable = {repairmaterial = example[3], repairable = true}
    local wrong = forge(inst, "wrong_material")
    local kit = forge(inst, example[3])
    assert(not Equipment.GetRepairStatus(inst))
    local before = scans
    for iteration = 1, 50 do now = now + 10; Equipment.GetRepairStatus(inst) end
    assert(scans == before, "unchanged equipment must not be polled periodically")
    change(target, example[2], .14)
    assert(Equipment.GetRepairStatus(inst), example[1])
    local action = assert(Equipment.GetRepairAction(inst))
    assert(action.action == ACTIONS.REPAIR and action.target == target and action.invobject == kit)
    kit.components.inventoryitem.owner = nil
    assert(not action.validfn(), "a queued repair must not consume a transferred kit")
    kit.components.inventoryitem.owner = inst
    execute(action)
    assert(not Equipment.GetRepairStatus(inst))
    kit.components.finiteuses:SetPercent(0)
    change(target, example[2], .1)
    assert(not Equipment.GetRepairStatus(inst) and Equipment.GetRepairAction(inst) == nil)
    assert(wrong:IsValid())
end

local function bone(inst, prefab, percent)
    local target = item(inst, prefab)
    target.components.equippable = {equipslot = EQUIPSLOTS.BODY}
    local fueled = durability(target, "fueled", percent)
    fueled.fueltype, fueled.accepting = FUELTYPE.NIGHTMARE, true
    function fueled:CanAcceptFuelItem(fuel)
        return self.accepting and fuel.components.fuel.fueltype == self.fueltype
    end
    inst.components.inventory.equipslots.body = target
    return target
end
local function fuel(inst, count)
    local value = item(inst, "nightmarefuel")
    value.components.fuel, value.count = {fueltype = FUELTYPE.NIGHTMARE}, count
    return value
end
local inst = companion()
local target = bone(inst, "armorskeleton", .1)
local material = fuel(inst, 10)
assert(not Equipment.GetRepairStatus(inst), "10% itself does not start refuelling")
change(target, "fueled", .09)
local has, urgent = Equipment.GetRepairStatus(inst)
assert(has and urgent)
inst.busy = true
assert(not Equipment.GetRepairStatus(inst) and Equipment.GetRepairAction(inst) == nil)
inst.busy = false
for iteration = 1, 4 do
    local action = assert(Equipment.GetRepairAction(inst))
    assert(action.action == ACTIONS.ADDFUEL and action.target == target and action.invobject == material)
    execute(action)
end
assert(target.components.fueled:GetPercent() == 1 and material.count == 6)
assert(not Equipment.GetRepairStatus(inst) and inst._my_friend_equipment_refuel_guid == nil)
change(target, "fueled", .5)
assert(not Equipment.GetRepairStatus(inst) and Equipment.GetRepairAction(inst) == nil,
    "the next refuel cycle waits until below 10%, rather than topping up at 50%")

inst = companion()
target = bone(inst, "armorskeleton", .05)
assert(not Equipment.GetRepairStatus(inst) and Equipment.GetRepairAction(inst) == nil)
local before = scans
for iteration = 1, 50 do now = now + 10; Equipment.GetRepairStatus(inst) end
assert(scans == before, "missing fuel must not cause repeated inventory searches")
material = fuel(inst, 1)
assert(Equipment.GetRepairStatus(inst), "arrival of fuel must wake the cached negative result")
execute(assert(Equipment.GetRepairAction(inst)))
assert(not Equipment.GetRepairStatus(inst))
material = fuel(inst, 4)
now = now + 2.1
assert(Equipment.GetRepairStatus(inst), "a paused refuel cycle must resume above 10% when fuel arrives")
change(target, "fueled", .9)
assert(Equipment.GetRepairAction(inst) ~= nil, "90% itself must still accept one more fuel")
change(target, "fueled", .91)
assert(Equipment.GetRepairAction(inst) == nil and inst._my_friend_equipment_refuel_guid == nil)
change(target, "fueled", .05)
local action = assert(Equipment.GetRepairAction(inst))
target.components.inventoryitem.owner = nil
assert(not action.validfn())
assert(Equipment.GetRepairAction(inst) == nil and inst._my_friend_equipment_refuel_guid == nil)

inst = companion()
target = bone(inst, "mod_nightmare_armor", .05)
material = fuel(inst, 4)
assert(Equipment.GetRepairAction(inst).target == target, "matching components support mod equipment too")
target.components.pocketwatch = {}
assert(Equipment.GetRepairAction(inst) == nil, "pocket watches retain their character-specific maintenance")
assert(registrations == 0, "maintenance must reuse shared events without adding per-item listeners")
print("PASS: event-cached sewing and forge repair, native material compatibility, low-fuel hysteresis, missing-fuel wakeup, ownership validation and no periodic searches")
