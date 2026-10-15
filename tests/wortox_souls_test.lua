-- Run from the mod root: lua tests/wortox_souls_test.lua
package.path = "scripts/?.lua;" .. package.path
package.loaded.my_friend_policy = {IsBusy = function() return false end}
package.loaded.my_friend_dialogue = {}
TheWorld = {ismastersim = true}
local Wortox = require("my_friend_wortox")
local function soul(count, owner)
    local value = {prefab = "wortox_soul", components = {}, count = count, owner = owner}
    function value:IsValid() return not self.removed end
    value.components.inventoryitem = {GetGrandOwner = function() return value.owner end,
        RemoveFromOwner = function()
            if value.owner ~= nil then value.owner:Remove(value) end
            value.owner = nil
            return value
        end}
    value.components.stackable = {maxsize = 40, StackSize = function() return value.count end,
        CanStackWith = function(_, item) return item.prefab == "wortox_soul" end,
        RoomLeft = function() return 40 - value.count end,
        Get = function(_, amount) value.count = value.count - amount; return soul(amount) end}
    return value
end
local pocket, stored, space, jar_capacity = nil, nil, true, 40
local jar = {prefab = "wortox_souljar", components = {}}
function jar:IsValid() return true end
local c = {readonlycontainer = false, IsRestricted = function() return false end,
    IsOpenedByOthers = function() return false end,
    FindItem = function() return stored end,
    CanAcceptCount = function(_, _, count) return math.min(count, jar_capacity - (stored and stored.count or 0)) end}
function c:Remove(item) if stored == item then stored = nil end end
function c:GiveItem(item)
    if stored then stored.count = stored.count + item.count; item.removed = true
    else stored = item; item.owner = self end
    return true
end
jar.components.container = c
local inv = {itemslots = {}, maxslots = 1, ignoreoverflow = false, ignorespoverflow = false}
function inv:GetItemInSlot() return pocket end
function inv:ReferenceAllItems() return pocket and {pocket, jar} or {jar} end
function inv:Remove(item) if pocket == item then pocket, self.itemslots[1] = nil, nil end end
function inv:GiveItem(item)
    assert(self.ignoreoverflow and self.ignorespoverflow, "souls must bypass all backpacks")
    if pocket then pocket.count = pocket.count + item.count; item.removed = true
    elseif space then pocket = item; item.owner = self; self.itemslots[1] = item
    else return false end
    return 1
end
local inst = {prefab = "wortox", components = {inventory = inv, eater = {CanEat = function() return true end},
    hunger = {GetPercent = function() return .3 end}}}
function inst:IsValid() return true end
function inst:HasTag(tag) return tag == "my_friend" end
function inst:ListenForEvent() end
function inst:DoPeriodicTask() return {Cancel = function() end} end
function inst:GetPosition() return {x = 0, y = 0, z = 0} end
Wortox.Configure(inst)
pocket = soul(25, inv); inv.itemslots[1] = pocket
assert(Wortox.BalanceSouls(inst))
assert(pocket.count == 18 and stored.count == 7)
stored.count, pocket.count = 40, 23
assert(not Wortox.BalanceSouls(inst) and pocket.count == 23 and stored.count == 40)
pocket.count = 12
assert(Wortox.BalanceSouls(inst) and pocket.count == 18 and stored.count == 34)
assert(not inv.ignoreoverflow and not inv.ignorespoverflow, "temporary placement flags must restore")
assert(Wortox.FindHungerSoul(inst) == pocket)
pocket.count = 10; assert(Wortox.FindHungerSoul(inst) == nil)
pocket, inv.itemslots[1], space = nil, {prefab = "rocks", IsValid = function() return true end}, false
assert(not Wortox.BalanceSouls(inst) and stored.count == 34, "no pocket space must leave jar souls untouched")
print("PASS: souls balance to 18, full jars stop transfers, pockets only, and eating threshold exceeds 10")
