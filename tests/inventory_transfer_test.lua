-- Run from the mod root: lua tests/inventory_transfer_test.lua
package.path = "scripts/?.lua;" .. package.path

local Transfer = require("my_friend_inventory_transfer")
local animals = {}
local drops = 0
local function animal(dead)
    local cow = {dead = dead}
    function cow:IsValid() return not self.removed end
    function cow:Remove()
        local leader = self.bell ~= nil and self.bell.components.leader or nil
        if leader ~= nil and leader.onremovefollower ~= nil then
            leader.onremovefollower(self.bell, self)
        end
        self.removed = true
    end
    function cow:GetSaveRecord() return {prefab = "beefalo", dead = self.dead} end
    animals[#animals + 1] = cow
    return cow
end

local function bell(cow)
    local item = {cow = cow, components = {leader = {
        onremovefollower = function() drops = drops + 1 end,
    }}}
    if cow ~= nil then cow.bell = item end
    function item:IsValid() return not self.removed end
    function item:HasTag(tag) return tag == "bell" end
    function item:GetBeefalo() return self.cow ~= nil and self.cow:IsValid() and self.cow or nil end
    function item:Remove() self.removed = true end
    item.components.useabletargeteditem = {
        StartUsingItem = function(_, target)
            if target.bound then return false end
            target.bound = true
            item.cow = target
            target.bell = item
            item.linked_image = true
            return true
        end,
    }
    return item
end

SpawnSaveRecord = function(record)
    if record == nil then return nil end
    return animal(record.dead)
end
local function inventory(items)
    local inv = {itemslots = items or {}}
    function inv:ForEachItem(fn)
        for _, item in pairs(self.itemslots) do fn(item) end
    end
    function inv:OnSave()
        local data = {items = {}}
        for slot, item in pairs(self.itemslots) do
            data.items[slot] = {beef_record = item:GetBeefalo()
                and item:GetBeefalo():GetSaveRecord() or nil}
        end
        return data
    end
    function inv:OnLoad(data)
        self.itemslots = {}
        for slot, record in pairs(data.items or {}) do
            local item = bell()
            self.itemslots[slot] = item
            if record.beef_record ~= nil then
                assert(item.components.useabletargeteditem:StartUsingItem(
                    SpawnSaveRecord(record.beef_record)))
            end
        end
    end
    return {components = {inventory = inv}}, inv
end

for _, dead in ipairs({false, true}) do
    local original = animal(dead)
    local owner = inventory({[1] = bell(original)})
    local saved = Transfer.SaveAndClear(owner)
    assert(saved.items[1].beef_record.dead == dead)
    assert(original.removed, "old linked animal must be removed after saving")
    assert(drops == 0, "handover must not run manual unbind/drop callbacks")
    local target, inv = inventory({[2] = bell(animal(false))})
    local native = inv.itemslots[2]:GetBeefalo()
    Transfer.Load(target, saved)
    assert(native.removed, "native swap animal must not survive inventory replacement")
    assert(drops == 0)
    assert(inv.itemslots[1]:GetBeefalo() ~= nil)
    assert(inv.itemslots[1].linked_image)
end

local old = {items = {[1] = {}}, my_friend_beefalo_records = {
    {slot = 1, record = {prefab = "beefalo", dead = true}},
}}
local target, inv = inventory()
Transfer.Load(target, old)
assert(inv.itemslots[1]:GetBeefalo() ~= nil and inv.itemslots[1].linked_image)
local count = #animals
old.items[1].beef_record = {prefab = "beefalo", dead = true}
Transfer.Load(target, old)
assert(#animals == count + 1, "old sidecar must not duplicate a bell-owned animal")

local missing = animal(false)
missing.removed = true
local source = inventory({[1] = bell(missing)})
local missing_data = Transfer.SaveAndClear(source)
assert(missing_data.items[1].beef_record == nil)
local destination, destination_inv = inventory()
Transfer.Load(destination, missing_data)
assert(destination_inv.itemslots[1]:GetBeefalo() == nil)
print("PASS: linked bell save, replacement, shadow corpse, missing animal, and legacy sessions")
