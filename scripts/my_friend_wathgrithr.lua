local Policy = require("my_friend_policy")
local Rules = require("my_friend_combat_rules")
local M = {LUNGE_RANGE = 6, ASK_DAYS = 5, ANSWER_TIME = 30}
local SPEARS = {spear_wathgrithr_lightning = true, spear_wathgrithr_lightning_charged = true}
local SPEAR_RECIPE = "spear_wathgrithr_lightning"

local function OwnItem(inst, item)
    local inventoryitem = item ~= nil and item:IsValid() and item.components.inventoryitem or nil
    return inventoryitem ~= nil and not inventoryitem.islockedinslot
        and inventoryitem:GetGrandOwner() == inst
end

local function CarriedItem(inst, prefab)
    local inventory = inst.components.inventory
    local hand = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if hand ~= nil and hand.prefab == prefab and OwnItem(inst, hand) then return hand end
    local active = inventory:GetActiveItem()
    if active ~= nil and active.prefab == prefab and OwnItem(inst, active) then return active end
    for _, item in ipairs(inventory:ReferenceAllItems()) do
        if item.prefab == prefab and OwnItem(inst, item) then return item end
    end
end

local function SpearCommandValid(inst, command)
    return TheWorld ~= nil and TheWorld.ismastersim and inst ~= nil and inst:IsValid()
        and inst.prefab == "wathgrithr" and inst:HasTag("my_friend")
        and not inst:HasTag("playerghost") and not inst._my_friend_possess_parked
        and inst.components.inventory ~= nil and inst.components.health ~= nil
        and not inst.components.health:IsDead() and inst._my_friend_command == command
        and command ~= nil and command.special == "lightning_spear"
        and require("my_friend_commands").Get(inst) == command
end

local function HasSpearMaterials(inst)
    local recipe, builder = GetValidRecipe(SPEAR_RECIPE), inst.components.builder
    if recipe == nil or builder == nil then return false end
    for _, ingredient in ipairs(recipe.ingredients) do
        local amount = math.max(1, RoundBiasedUp(ingredient.amount * builder.ingredientmod))
        -- false excludes open chests; the main inventory and worn backpack count.
        if not inst.components.inventory:Has(ingredient.type, amount, false) then return false end
    end
    return builder:HasIngredients(recipe)
end

local function FinishSpearCommand(inst, command, reply)
    if inst._my_friend_command ~= command then return end
    require("my_friend_dialogue").Reply(inst, reply)
    require("my_friend_commands").Clear(inst)
end

function M.PerformSpearBuild(act)
    local inst, command = act.doer, act._my_friend_spear_command
    if not SpearCommandValid(inst, command) or command.spear_phase ~= "build"
        or not HasSpearMaterials(inst) then return false end
    command.spear_phase = "charge"
    -- Native crafting also consults opencontainers when consuming materials.
    -- Hide external sources only for this synchronous call and always restore them.
    local inventory = inst.components.inventory
    local containers = inventory.opencontainers
    inventory.opencontainers = {}
    local ok, success, reason = pcall(ACTIONS.BUILD.fn, act)
    inventory.opencontainers = containers
    if not ok then error(success) end
    command.spear_built = success == true
    return success, reason
end

function M.PerformSpearCharge(act)
    local inst, command, spear, static = act.doer, act._my_friend_spear_command,
        act._my_friend_spear, act.invobject
    if not SpearCommandValid(inst, command) or command.spear_phase ~= "charge"
        or not OwnItem(inst, spear) or spear.prefab ~= SPEAR_RECIPE
        or not OwnItem(inst, static) or static.prefab ~= "moonstorm_static_item" then return false end
    local upgradeable, upgrader = spear.components.upgradeable, static.components.upgrader
    if upgradeable == nil or upgrader == nil
        or upgradeable.upgradetype ~= UPGRADETYPES.SPEAR_LIGHTNING
        or upgrader.upgradetype ~= upgradeable.upgradetype then return false end
    local inventory = inst.components.inventory
    local equipped = inventory:GetEquippedItem(EQUIPSLOTS.HANDS) == spear
    local active = inventory:GetActiveItem() == spear
    if equipped or active then
        local free_slot, destination = inventory:GetNextAvailableSlot(spear)
        if free_slot == nil then
            command.spear_failure = "spear_command_no_space"
            return false
        end
        if equipped then
            if inventory:Unequip(EQUIPSLOTS.HANDS) ~= spear then return false end
        else
            if inventory:RemoveItem(spear, true) ~= spear then return false end
        end
        -- Specify the destination: GiveItem without a slot may return an item
        -- to prevcontainer (including an old open chest).
        if destination ~= nil and destination ~= inventory.itemslots then
            destination:GiveItem(spear, free_slot)
        else
            inventory:GiveItem(spear, free_slot)
        end
    end
    -- An active item needs a real slot too: the native replacement uses GiveItem.
    local inventoryitem = spear.components.inventoryitem
    local container, slot = inventoryitem:GetContainer(), inventoryitem:GetSlotNum()
    if slot == nil or container == nil or not upgradeable:CanUpgrade() then
        if equipped then inventory:Equip(spear) end
        return false
    end
    -- This role command grants the companion ability without mutating skill tags.
    -- Upgrade consumes exactly one static and preserves native skin/uses/cooldown.
    local success = upgradeable:Upgrade(static, inst)
    if success and equipped then
        local replacement = container:GetItemInSlot(slot)
        if OwnItem(inst, replacement) and replacement.prefab == "spear_wathgrithr_lightning_charged" then
            inventory:Equip(replacement)
        end
    elseif equipped and spear:IsValid() then
        inventory:Equip(spear)
    end
    return success
end

function M.GetSpearCommandAction(inst, command)
    if not SpearCommandValid(inst, command) then return end
    if command.spear_phase == nil then
        command.spear_phase = HasSpearMaterials(inst) and "build" or "charge"
    end
    if command.spear_phase == "build" then
        local action = BufferedAction(inst, nil, ACTIONS.MY_FRIEND_SPEAR_BUILD, nil,
            inst:GetPosition(), SPEAR_RECIPE)
        action._my_friend_spear_command = command
        action.validfn = function() return SpearCommandValid(inst, command) and HasSpearMaterials(inst) end
        action:AddFailAction(function() command.spear_phase = "charge" end)
        return Policy.GuardAction(inst, action)
    end
    local spear, static = CarriedItem(inst, SPEAR_RECIPE), CarriedItem(inst, "moonstorm_static_item")
    if spear == nil or static == nil then
        FinishSpearCommand(inst, command, command.spear_built and "spear_command_built"
            or "spear_command_missing")
        return
    end
    if (inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS) == spear
        or inst.components.inventory:GetActiveItem() == spear)
        and inst.components.inventory:GetNextAvailableSlot(spear) == nil then
        FinishSpearCommand(inst, command, "spear_command_no_space")
        return
    end
    local action = BufferedAction(inst, nil, ACTIONS.MY_FRIEND_SPEAR_CHARGE, static)
    action._my_friend_spear_command, action._my_friend_spear = command, spear
    action.validfn = function()
        return SpearCommandValid(inst, command) and OwnItem(inst, spear) and OwnItem(inst, static)
    end
    action:AddSuccessAction(function() FinishSpearCommand(inst, command, "spear_command_charged") end)
    action:AddFailAction(function()
        FinishSpearCommand(inst, command, command.spear_failure or "spear_command_missing")
    end)
    return Policy.GuardAction(inst, action)
end

function M.IsSpear(item)
    return item ~= nil and item:IsValid() and SPEARS[item.prefab] == true
end

local function Weapon(inst)
    local inventory = inst.components.inventory
    local item = inventory ~= nil and inventory:GetEquippedItem(EQUIPSLOTS.HANDS) or nil
    return M.IsSpear(item) and item or nil
end

function M.UpdateCycle(inst, weapon)
    if inst._my_friend_lunge_weapon ~= weapon then
        inst._my_friend_lunge_weapon = weapon
        inst._my_friend_spear_hits, inst._my_friend_lunge_only = 0, false
    end
    local uses = weapon.components.finiteuses
    local percent = uses ~= nil and uses:GetPercent() or 1
    if percent < .1 then inst._my_friend_lunge_only = true
    elseif percent > .2 then inst._my_friend_lunge_only = false end
    return inst._my_friend_lunge_only or (inst._my_friend_spear_hits or 0) >= 4
end

function M.CanLunge(inst, target, weapon)
    if inst.prefab ~= "wathgrithr" or not M.IsSpear(weapon)
        or weapon ~= Weapon(inst) or not Rules.CanAttack(target)
        or target.components.health == nil or target.components.health:IsDead()
        or target.components.combat == nil or Rules.BurnsWhenElectrocuted(target)
        or Policy.IsBusy(inst) and (inst.sg == nil or inst.sg.currentstate.name ~= "combat_lunge_start")
        or inst:HasTag("playerghost")
        or inst.components.rider ~= nil and inst.components.rider:IsRiding()
        or weapon.components.aoespell == nil or weapon.components.aoeweapon_lunge == nil
        or weapon.components.rechargeable == nil or not weapon.components.rechargeable:IsCharged()
        or Policy.DistanceSq(inst, target) > M.LUNGE_RANGE^2 then return false end
    local pos = target:GetPosition()
    return TheWorld.Map:CanCastAtPoint(pos, false, false, 0)
end

function M.PerformLunge(act)
    local inst, weapon, target = act.doer, act.invobject, act.target
    if not M.CanLunge(inst, target, weapon) then return false end
    -- SGwilson combat_lunge_start performs this action after lunge_pre. Use
    -- the native spell and damage/repair/cooldown callbacks for both spears.
    local success = weapon.components.aoespell:CastSpell(inst, target:GetPosition())
    if success then inst._my_friend_spear_hits = 0 end
    return success
end

function M.GetCombatAction(inst, target)
    if inst.prefab ~= "wathgrithr" then return end
    local weapon = Weapon(inst)
    if weapon == nil or not M.UpdateCycle(inst, weapon) then return end
    if Rules.BurnsWhenElectrocuted(target) then return nil, inst._my_friend_lunge_only end
    if Policy.DistanceSq(inst, target) > M.LUNGE_RANGE^2 then
        local action = BufferedAction(inst, target, ACTIONS.WALKTO)
        action.arrivedist = M.LUNGE_RANGE - 1
        return action
    end
    if M.CanLunge(inst, target, weapon) then
        local action = BufferedAction(inst, target, ACTIONS.MY_FRIEND_LIGHTNING_LUNGE, weapon)
        action.validfn = function() return M.CanLunge(inst, target, weapon) end
        return action
    end
    -- Low durability never spends another normal attack while cooling down.
    return nil, inst._my_friend_lunge_only or weapon.components.rechargeable ~= nil
        and not weapon.components.rechargeable:IsCharged()
end

function M.Answer(inst, player, text)
    local pending = inst._my_friend_spear_question
    if inst.prefab ~= "wathgrithr" or pending == nil or pending.player ~= player
        or Policy.GetLeader(inst) ~= player or GetTime() >= pending.deadline
        or type(text) ~= "string" then return false end
    local lower = text:lower():match("^%s*(.-)%s*$")
    local refused = false
    for _, word in ipairs({"不行", "不可以", "不给", "没材料", "没有", "不給", "沒材料", "沒有"}) do
        if lower:find(word, 1, true) then refused = true break end
    end
    for _, word in ipairs({"no", "no materials", "can't", "cannot", "нет", "нет материалов"}) do
        if lower == word then refused = true break end
    end
    if not refused then return false end
    inst._my_friend_spear_question = nil
    require("my_friend_dialogue").RandomReply(inst, "spear_request_refused")
    return true
end

function M.UpdateRequest(inst)
    local pending = inst._my_friend_spear_question
    if pending ~= nil and (GetTime() >= pending.deadline or Policy.GetLeader(inst) ~= pending.player) then
        inst._my_friend_spear_question = nil
    end
    if inst.prefab ~= "wathgrithr" or not inst:HasTag("my_friend")
        or inst:HasTag("playerghost") or inst._my_friend_possess_parked
        or inst.components.health:IsDead() or inst._my_friend_under_threat
        or Policy.IsBusy(inst) then return end
    if GetTime() < (inst._my_friend_spear_ask_after or 0) then return end
    local leader = Policy.GetLeader(inst)
    if not Policy.IsLocalPlayer(leader) or leader:HasTag("playerghost")
        or Policy.DistanceSq(inst, leader) > 20^2 then return end
    local name = leader:GetDisplayName()
    if type(name) ~= "string" then return end
    if require("my_friend_dialogue").RandomReply(inst, "spear_request", name) then
        inst._my_friend_spear_ask_after = GetTime() + M.ASK_DAYS * TUNING.TOTAL_DAY_TIME
        inst._my_friend_spear_question = {player = leader, deadline = GetTime() + M.ANSWER_TIME}
    end
end

function M.Save(inst, data)
    if inst.prefab == "wathgrithr" then
        data.my_friend_spear_ask_remaining = math.max(0,
            (inst._my_friend_spear_ask_after or GetTime() + M.ASK_DAYS * TUNING.TOTAL_DAY_TIME) - GetTime())
    end
end

function M.Load(inst, data)
    if inst.prefab ~= "wathgrithr" then return end
    local remaining = data ~= nil and data.my_friend_spear_ask_remaining or nil
    if type(remaining) ~= "number" or remaining ~= remaining then
        remaining = M.ASK_DAYS * TUNING.TOTAL_DAY_TIME
    end
    inst._my_friend_spear_ask_after = GetTime() + math.max(0, math.min(remaining,
        M.ASK_DAYS * TUNING.TOTAL_DAY_TIME))
end

function M.Configure(inst)
    if inst.prefab ~= "wathgrithr" or inst._my_friend_wathgrithr_configured then return end
    inst._my_friend_wathgrithr_configured = true
    if inst._my_friend_spear_ask_after == nil then M.Load(inst) end
    inst:ListenForEvent("onattackother", function(_, data)
        local weapon = Weapon(inst)
        if weapon ~= nil and data ~= nil and (data.weapon == nil or data.weapon == weapon)
            and (inst.sg == nil or not inst.sg:HasStateTag("aoe")) then
            M.UpdateCycle(inst, weapon)
            inst._my_friend_spear_hits = (inst._my_friend_spear_hits or 0) + 1
        end
    end)
    inst:DoPeriodicTask(5, M.UpdateRequest)
end

return M
