-- Run from the mod root: lua tests/wathgrithr_command_test.lua
package.path = "scripts/?.lua;" .. package.path
local now, leader = 10, nil
GetTime = function() return now end
RoundBiasedUp = function(value) return math.floor(value + .5) end
EQUIPSLOTS = {HANDS = "hands"}
UPGRADETYPES = {SPEAR_LIGHTNING = "spear_lightning"}
STRINGS = {CHARACTER_TITLES = {}, NAMES = {}}
TheWorld = {ismastersim = true}
TheSim = {FindEntities = function() error("the spear command must not scan external materials") end}
package.loaded.cooking = {recipes = {}}
package.loaded.my_friend_strings = {language = "zh", Text = function(_, text) return text end}
package.loaded.my_friend_equip_slots = {}
package.loaded.my_friend_backpacks = {}
package.loaded.my_friend_policy = {
    IsLocalPlayer = function(p) return p ~= nil and p.userid ~= nil end,
    GetLeader = function() return leader end,
    GuardAction = function(_, action) return action end,
}
package.loaded.my_friend_home = {IsAskPending = function() return false end}
package.loaded.my_friend_beefalo = {Riding = {}}
package.loaded.my_friend_characters = {List = function() return {} end}
package.loaded.my_friend_carry_backpack = {Answer = function() return false end, Cancel = function() end}
package.loaded.my_friend_pets = {Parse = function() end}
package.loaded.my_friend_recipe_cooking = {Cancel = function() end}
local replies = {}
package.loaded.my_friend_dialogue = {Reply = function(_, key) replies[#replies + 1] = key end}
local recipe = {name = "spear_wathgrithr_lightning", ingredients = {
    {type = "twigs", amount = 2}, {type = "lightninggoathorn", amount = 2}, {type = "beefalowool", amount = 1},
}}
GetValidRecipe = function(name) return name == recipe.name and recipe or nil end
BufferedAction = function(inst, target, action, item, point, name)
    local value = {doer = inst, target = target, action = action, invobject = item, recipe = name,
        success = {}, failure = {}}
    function value:AddSuccessAction(fn) self.success[#self.success + 1] = fn end
    function value:AddFailAction(fn) self.failure[#self.failure + 1] = fn end
    return value
end
ACTIONS = {MY_FRIEND_SPEAR_BUILD = {}, MY_FRIEND_SPEAR_CHARGE = {}, BUILD = {}}
local function companion(prefab)
    local inst = {prefab = prefab or "wathgrithr", components = {}, _my_friend_custom_name = "小薇"}
    function inst:IsValid() return not self.removed end
    function inst:HasTag(tag) return tag == "my_friend" or tag == "playerghost" and self.ghost == true end
    function inst:GetDisplayName() return self._my_friend_custom_name end
    function inst:GetPosition() return {x = 0, y = 0, z = 0} end
    inst.components.health = {IsDead = function() return inst.dead == true end}
    local inventory = {slots = {}, opencontainers = {external = true}, materials = {}, external_materials = {}}
    inst.components.inventory = inventory
    function inventory:GetEquippedItem() return self.hand end
    function inventory:GetActiveItem() return self.active end
    function inventory:GetNextAvailableSlot()
        if self.full then return nil end
        for slot = 1, 20 do if self.slots[slot] == nil then return slot end end
    end
    function inventory:ReferenceAllItems()
        local result = {}
        for _, item in pairs(self.slots) do result[#result + 1] = item end
        if self.hand ~= nil then result[#result + 1] = self.hand end
        return result
    end
    function inventory:GiveItem(item, slot)
        assert(not item.require_explicit_slot or slot ~= nil, "an old chest must not receive the spear")
        slot = slot or self:GetNextAvailableSlot(item)
        assert(slot ~= nil and self.slots[slot] == nil, "items must not be dropped on overflow")
        self.slots[slot], item.slot, item.owner = item, slot, inst
    end
    function inventory:GetItemInSlot(slot) return self.slots[slot] end
    function inventory:Unequip() local item = self.hand; self.hand = nil; return item end
    function inventory:RemoveItem(item)
        if self.active == item then self.active = nil end
        if item.slot ~= nil then self.slots[item.slot] = nil; item.slot = nil end
        return item
    end
    function inventory:Equip(item)
        self:RemoveItem(item)
        self.hand = item
    end
    function inventory:Has(prefab, amount, external)
        local count = self.materials[prefab] or 0
        if external and next(self.opencontainers) ~= nil then count = count + (self.external_materials[prefab] or 0) end
        return count >= amount
    end
    inst.components.builder = {ingredientmod = 1, HasIngredients = function()
        for _, ingredient in ipairs(recipe.ingredients) do
            if not inventory:Has(ingredient.type, ingredient.amount, true) then return false end
        end
        return true
    end}
    return inst
end
local function item(inst, prefab, count)
    local inventory = inst.components.inventory
    local value = {prefab = prefab, owner = inst, count = count or 1, components = {}, skin = "skin", uses = .37, cooldown = .25}
    function value:IsValid() return not self.removed end
    function value:Remove()
        inventory:RemoveItem(self); self.removed = true
    end
    value.components.inventoryitem = {
        GetGrandOwner = function() return value.owner end,
        GetContainer = function() return inventory end,
        GetSlotNum = function() return value.slot end,
    }
    if prefab == "moonstorm_static_item" then
        value.components.upgrader = {upgradetype = UPGRADETYPES.SPEAR_LIGHTNING}
    end
    return value
end
local upgraded = 0
local function spear(inst)
    local value = item(inst, recipe.name)
    value.components.upgradeable = {upgradetype = UPGRADETYPES.SPEAR_LIGHTNING,
        CanUpgrade = function() return inst.components.inventory.hand ~= value end,
        Upgrade = function(_, static, doer)
            assert(doer == inst and static.owner == inst and value.slot ~= nil)
            static.count = static.count - 1
            if static.count == 0 then static:Remove() end
            local slot = value.slot
            value:Remove()
            local replacement = item(inst, "spear_wathgrithr_lightning_charged")
            replacement.skin, replacement.uses, replacement.cooldown = value.skin, value.uses, value.cooldown
            inst.components.inventory:GiveItem(replacement, slot)
            upgraded = upgraded + 1
            return true
        end}
    return value
end
local built, build_error = 0, false
ACTIONS.BUILD.fn = function(act)
    local inventory = act.doer.components.inventory
    assert(next(inventory.opencontainers) == nil, "native crafting must ignore open chests")
    if build_error then error("native build failure") end
    for _, ingredient in ipairs(recipe.ingredients) do
        assert(inventory.materials[ingredient.type] >= ingredient.amount)
        inventory.materials[ingredient.type] = inventory.materials[ingredient.type] - ingredient.amount
    end
    inventory:GiveItem(spear(act.doer))
    built = built + 1
    return true
end
local Commands = require("my_friend_commands")
local Wigfrid = require("my_friend_wathgrithr")
local player = {userid = "B"}
local inst = companion()
-- Always accept this explicit role command, even during the generic refusal roll.
math.random = function() return 0 end
for _, message in ipairs({"小薇，奔雷矛", "准备奔雷矛，小薇", "请小薇准备奔雷矛"}) do
    assert(Commands.Dispatch(inst, player, message), message)
    assert(Commands.Get(inst).special == "lightning_spear", "works without a leader")
end
assert(not Commands.Dispatch(inst, player, "准备奔雷矛"), "address is required")
assert(not Commands.Dispatch(inst, player, "小明准备奔雷矛"))
local other = companion("wilson")
assert(not Commands.Dispatch(other, player, "小薇，奔雷矛"), "other characters must not craft it")
assert(not Commands.DispatchWheel(other, player, "wathgrithr_lightning_spear"))
inst._my_friend_custom_name = "雷歌"
assert(not Commands.Dispatch(inst, player, "小薇奔雷矛"))
assert(Commands.Dispatch(inst, player, "奔雷矛拜托雷歌了"))
leader = {userid = "A"}
assert(Commands.Get(inst) ~= nil, "another player's follow ownership must not cancel the command")
assert(Commands.DispatchWheel(inst, player, "wathgrithr_lightning_spear"))
local function request(actor)
    assert(Commands.DispatchWheel(actor, player, "wathgrithr_lightning_spear"))
    return actor._my_friend_command
end
local function perform(action)
    assert(action.validfn(action))
    local success
    if action.action == ACTIONS.MY_FRIEND_SPEAR_BUILD then success = Wigfrid.PerformSpearBuild(action)
    else success = Wigfrid.PerformSpearCharge(action) end
    for _, fn in ipairs(success and action.success or action.failure) do fn() end
    return success
end
local inventory = inst.components.inventory
inventory.materials = {twigs = 6, lightninggoathorn = 6, beefalowool = 3}
local static = item(inst, "moonstorm_static_item", 3)
inventory:GiveItem(static)
local command = request(inst)
local containers = inventory.opencontainers
assert(perform(Wigfrid.GetSpearCommandAction(inst, command)))
assert(built == 1 and inventory.materials.twigs == 4 and inventory.opencontainers == containers)
assert(perform(Wigfrid.GetSpearCommandAction(inst, command)))
assert(upgraded == 1 and static.count == 2 and inst._my_friend_command == nil)
assert(Wigfrid.GetSpearCommandAction(inst, command) == nil and built == 1, "no repeated batch crafting")
-- Crafting materials missing: upgrade the equipped spear and leave stored spears alone.
local equipped = spear(inst)
equipped.require_explicit_slot = true
inventory.hand = equipped
local stored = spear(inst); inventory:GiveItem(stored)
inventory.materials = {}
command = request(inst)
assert(perform(Wigfrid.GetSpearCommandAction(inst, command)))
assert(inventory.hand.prefab == "spear_wathgrithr_lightning_charged" and equipped.removed and not stored.removed)
assert(inventory.hand.skin == "skin" and inventory.hand.uses == .37 and inventory.hand.cooldown == .25)
assert(static.count == 1 and built == 1)
-- Full inventory leaves the equipped spear and static untouched.
inventory.hand, inventory.full = spear(inst), true
equipped = inventory.hand
command = request(inst)
assert(Wigfrid.GetSpearCommandAction(inst, command) == nil)
assert(inventory.hand == equipped and not equipped.removed and static.count == 1)
assert(replies[#replies] == "spear_command_no_space")
inventory.full = false
-- Cancellation, lost item ownership and slot races cannot consume materials.
command = request(inst)
local action = Wigfrid.GetSpearCommandAction(inst, command)
Commands.Clear(inst)
assert(not Wigfrid.PerformSpearCharge(action) and static.count == 1)
command = request(inst); action = Wigfrid.GetSpearCommandAction(inst, command)
static.owner = player
assert(not Wigfrid.PerformSpearCharge(action) and static.count == 1)
static.owner = inst
command = request(inst); action = Wigfrid.GetSpearCommandAction(inst, command)
inventory.full = true
assert(not perform(action) and inventory.hand == equipped and static.count == 1)
inventory.full = false
-- External/chest materials and foreign-owned static do not count.
inst = companion(); inventory = inst.components.inventory
inventory.external_materials = {twigs = 2, lightninggoathorn = 2, beefalowool = 1}
command = request(inst)
assert(Wigfrid.GetSpearCommandAction(inst, command) == nil and built == 1)
assert(replies[#replies] == "spear_command_missing")
-- No static: report a successful single craft and stop.
inventory.materials = {twigs = 4, lightninggoathorn = 4, beefalowool = 2}
command = request(inst)
assert(perform(Wigfrid.GetSpearCommandAction(inst, command)))
assert(Wigfrid.GetSpearCommandAction(inst, command) == nil and replies[#replies] == "spear_command_built")
assert(built == 2)
-- An active spear is safely moved into a real slot before native replacement.
inst = companion(); inventory = inst.components.inventory
inventory.active = spear(inst)
static = item(inst, "moonstorm_static_item", 2); inventory:GiveItem(static)
command = request(inst)
assert(perform(Wigfrid.GetSpearCommandAction(inst, command)))
assert(inventory.active == nil and static.count == 1)
local found = false
for _, value in ipairs(inventory:ReferenceAllItems()) do
    if value.prefab == "spear_wathgrithr_lightning_charged" then found = true end
end
assert(found, "active spear replacement remains in carried inventory")
-- Native exceptions must restore access to the original containers.
inventory.materials = {twigs = 2, lightninggoathorn = 2, beefalowool = 1}
command = request(inst); action = Wigfrid.GetSpearCommandAction(inst, command)
containers, build_error = inventory.opencontainers, true
assert(not pcall(Wigfrid.PerformSpearBuild, action))
assert(inventory.opencontainers == containers)
build_error = false
-- All localized catalogues route only to Wigfrid with the same stable ID.
local Language = require("my_friend_strings")
for _, language in ipairs({"zh", "zh_tw", "en", "ru"}) do
    Language.language = language
    package.loaded.my_friend_commands, package.loaded.my_friend_special_commands = nil, nil
    Commands = require("my_friend_commands")
    assert(Commands.DispatchWheel(inst, player, "wathgrithr_lightning_spear"), language)
end
print("PASS: named role command, wheel/locales, public ownership, single carried-material craft/charge, equipped priority, safe overflow/cancellation and native state preservation")
