local Policy = require("my_friend_policy")
local Inventory = require("my_friend_inventory")
local FoodStorage = require("my_friend_food_storage")
local Pot = require("my_friend_cookpot")
local M = {RANGE = 20, MAX_FOOD = 5}
local POTS = Pot.PREFABS

local function Size(item)
    return item ~= nil and item:IsValid()
        and (item.components.stackable ~= nil and item.components.stackable:StackSize() or 1) or 0
end

function M.Count(inst, prefab)
    local total = 0
    for _, item in ipairs(FoodStorage.ReferenceItems(inst)) do
        if item.prefab == prefab then total = total + Size(item) end
    end
    return total
end

local function Twig(inst)
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        if item:IsValid() and item.prefab == "twigs"
            and not item.components.inventoryitem.islockedinslot then return item end
    end
end

local OwnerID, Accessible, Close = Pot.OwnerID, Pot.Accessible, Pot.Close

local function Forget(inst, pot)
    Close(inst, pot)
    if pot ~= nil and pot:IsValid() and pot._my_friend_beefalo_chef == OwnerID(inst) then
        pot._my_friend_beefalo_chef, pot._my_friend_beefalo_ingredients = nil, nil
    end
    inst._my_friend_beefalo_pot = nil
end

local function IngredientCount(pot)
    local count = 0
    for _, item in pairs(pot.components.container:GetAllItems()) do
        if item.prefab ~= "twigs" or Size(item) ~= 1 then return nil end
        count = count + 1
    end
    return count
end

-- Claims survive a save while a pot is cooking. No item or ingredient is
-- respawned: all progress lives in the original stewer and container.
function M.ConfigurePot(pot)
    if not TheWorld.ismastersim or not POTS[pot.prefab] then return end
    local function ReleaseClaim()
        pot._my_friend_beefalo_chef, pot._my_friend_beefalo_ingredients = nil, nil
    end
    local harvest = pot.components.stewer.onharvest
    pot.components.stewer.onharvest = function(...)
        ReleaseClaim()
        if harvest ~= nil then return harvest(...) end
    end
    pot:ListenForEvent("onopen", function(_, data)
        if data ~= nil and require("my_friend_policy").IsLocalPlayer(data.doer) then ReleaseClaim() end
    end)
    local save, load = pot.OnSave, pot.OnLoad
    pot.OnSave = function(self, data)
        data.my_friend_beefalo_chef = self._my_friend_beefalo_chef
        data.my_friend_beefalo_ingredients = self._my_friend_beefalo_ingredients
        if save ~= nil then return save(self, data) end
    end
    pot.OnLoad = function(self, data, ...)
        if load ~= nil then load(self, data, ...) end
        self._my_friend_beefalo_chef = data ~= nil and data.my_friend_beefalo_chef or nil
        self._my_friend_beefalo_ingredients = data ~= nil and data.my_friend_beefalo_ingredients or nil
    end
end

local function FindPot(inst, start)
    local current = inst._my_friend_beefalo_pot
    if current ~= nil and current:IsValid() then
        if current._my_friend_beefalo_chef == OwnerID(inst) then return current end
        inst._my_friend_beefalo_pot = nil
    end
    local x, y, z = inst.Transform:GetWorldPosition()
    local best, distance, priority
    for _, pot in ipairs(TheSim:FindEntities(x, y, z, M.RANGE, nil, {"INLIMBO", "burnt", "fire"})) do
        if Accessible(inst, pot) then
            if pot._my_friend_beefalo_chef == OwnerID(inst) then return pot end
            local c, s = pot.components.container, pot.components.stewer
            if start and pot._my_friend_beefalo_chef == nil and pot._my_friend_recipe_job == nil
                and not s:IsCooking() and not s:IsDone() and c:CanOpen()
                and IngredientCount(pot) == 0 then
                local d, p = inst:GetDistanceSqToInst(pot), require("my_friend_cookpot").Priority(inst, pot)
                if best == nil or p < priority or p == priority and d < distance then
                    best, distance, priority = pot, d, p
                end
            end
        end
    end
    return best
end

function M.HasWork(inst)
    local current = inst._my_friend_beefalo_pot
    if current ~= nil and current:IsValid()
        and current._my_friend_beefalo_chef == OwnerID(inst) and Accessible(inst, current) then
        local stewer = current.components.stewer
        if stewer:IsCooking() then return false end
        if stewer:IsDone() then
            return M.Count(inst, "beefalofeed") < M.MAX_FOOD
                and not inst.components.inventory:IsFull()
        end
        local count = IngredientCount(current)
        return count ~= nil and count < 4 and M.Count(inst, "beefalofeed") < M.MAX_FOOD
            and M.Count(inst, "twigs") >= 20 + (4 - count)
    end
    return M.Count(inst, "beefalofeed") == 0 and M.Count(inst, "twigs") > 40
        and FindPot(inst, true) ~= nil
end

local function Guard(inst, pot, action, valid)
    action._my_friend_dialogue_kind = action.action == ACTIONS.HARVEST
        and "beefalo_cooked" or "beefalo_cook"
    action.validfn = function()
        return Accessible(inst, pot) and inst._my_friend_command == nil
            and not inst._my_friend_under_threat
            and require("my_friend_riding").GetBoundBeefalo(inst) ~= nil and valid()
    end
    action:AddSuccessAction(function()
        -- A command/combat may interrupt between steps. Do not leave the pot
        -- open indefinitely, even when no further care action gets selected.
        local stamp = {}
        inst._my_friend_beefalo_pot_step = stamp
        inst:DoTaskInTime(2, function()
            if inst._my_friend_beefalo_pot_step == stamp then Close(inst, pot) end
        end)
    end)
    action:AddFailAction(function()
        Close(inst, pot)
        if not action._my_friend_cancelled then inst._my_friend_beefalo_retry = GetTime() + 10 end
    end)
    return Policy.GuardAction(inst, action)
end

function M.AddIngredient(act)
    local inst, pot, item = act.doer, act.target, act.invobject
    if not Accessible(inst, pot) or not Inventory.CanReachContainer(inst, pot)
        or pot._my_friend_beefalo_chef ~= OwnerID(inst) or item == nil or not item:IsValid()
        or item.prefab ~= "twigs" or item.components.inventoryitem:GetGrandOwner() ~= inst
        or item.components.inventoryitem.islockedinslot or M.Count(inst, "twigs") <= 20 then return false end
    local c, s = pot.components.container, pot.components.stewer
    local count = IngredientCount(pot)
    if s:IsCooking() or s:IsDone() or not c:IsOpenedBy(inst) or count == nil or count >= 4
        or count ~= pot._my_friend_beefalo_ingredients or not c:CanTakeItemInSlot(item) then return false end
    local moved = item.components.inventoryitem:RemoveFromOwner(false)
    if moved == nil or not moved:IsValid() or moved.components.inventoryitem == nil then return false end
    moved.prevcontainer, moved.prevslot = nil, nil
    if c:GiveItem(moved, nil, pot:GetPosition(), false) then
        pot._my_friend_beefalo_ingredients = count + 1
        return true
    end
    if moved:IsValid() then Inventory.GiveCarried(inst, moved, inst:GetPosition()) end
    return false
end

function M.GetAction(inst, start)
    local food = M.Count(inst, "beefalofeed")
    if start and (food > 0 or M.Count(inst, "twigs") <= 40) then return end
    local pot = FindPot(inst, start)
    if pot == nil then return end
    if not Accessible(inst, pot) then Close(inst, pot) return end
    local c, s = pot.components.container, pot.components.stewer
    local owned = pot._my_friend_beefalo_chef == OwnerID(inst)
    if not owned and not start then return end
    inst._my_friend_beefalo_pot = pot
    if s:IsCooking() then
        if not owned or s.product ~= "beefalofeed" then Forget(inst, pot) end
        return
    elseif s:IsDone() then
        if not owned or s.product ~= "beefalofeed" then Forget(inst, pot) return end
        if food >= M.MAX_FOOD or inst.components.inventory:IsFull() then return end
        local action = BufferedAction(inst, pot, ACTIONS.HARVEST)
        action:AddSuccessAction(function() Forget(inst, pot) end)
        return Guard(inst, pot, action, function()
            return s:IsDone() and s.product == "beefalofeed"
                and M.Count(inst, "beefalofeed") < M.MAX_FOOD
                and not inst.components.inventory:IsFull()
        end)
    end
    local count = IngredientCount(pot)
    if count == nil or count ~= (owned and pot._my_friend_beefalo_ingredients or 0) then
        Forget(inst, pot)
        return
    end
    if food >= M.MAX_FOOD or M.Count(inst, "twigs") < 20 + (4 - count) then Close(inst, pot) return end
    local function Unchanged()
        return not s:IsCooking() and not s:IsDone() and IngredientCount(pot) == count
            and (owned and pot._my_friend_beefalo_chef == OwnerID(inst)
                or not owned and pot._my_friend_beefalo_chef == nil)
            and M.Count(inst, "beefalofeed") < M.MAX_FOOD
            and M.Count(inst, "twigs") >= 20 + (4 - count)
    end
    if not c:IsOpenedBy(inst) then
        if not c.canbeopened or not c:CanOpen() then return end
        local action = BufferedAction(inst, pot, ACTIONS.MY_FRIEND_OPEN)
        action.arrivedist = Inventory.ContainerReach(inst, pot)
        action:AddSuccessAction(function()
            pot._my_friend_beefalo_chef = OwnerID(inst)
            pot._my_friend_beefalo_ingredients = count
        end)
        return Guard(inst, pot, action, Unchanged)
    elseif count < 4 then
        local twig = Twig(inst)
        if twig == nil then return end
        return Guard(inst, pot, BufferedAction(inst, pot, ACTIONS.MY_FRIEND_COOKPOT_ADD, twig), Unchanged)
    end
    return Guard(inst, pot, BufferedAction(inst, pot, ACTIONS.COOK), function()
        return Unchanged() and s:CanCook()
    end)
end

return M
