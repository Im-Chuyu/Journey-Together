local M = {}
local Policy = require("my_friend_policy")

M.HEAL_THRESHOLD = .90
M.HEAL_SCAN_INTERVAL = 3

function M.NeedsHeal(inst)
    local health = inst ~= nil and inst.components ~= nil and inst.components.health or nil
    return inst ~= nil and inst:IsValid() and inst.prefab == "wormwood"
        and not inst:HasTag("playerghost") and health ~= nil
        and not health:IsDead() and health.canheal ~= false
        and health:GetPercent() < M.HEAL_THRESHOLD
end

function M.GetHealScore(inst)
    if not M.NeedsHeal(inst) then return 0 end
    return inst.components.health:GetPercent() <= .35 and 132 or 90
end

local function HealingAmount(inst, item)
    if item == nil or not item:IsValid() or item.components == nil then return end
    local invitem, healer = item.components.inventoryitem, item.components.healer
    if invitem == nil or invitem.islockedinslot or invitem:GetGrandOwner() ~= inst
        or healer == nil or type(healer.health) ~= "number" or healer.health <= 0 then return end
    if healer.canhealfn ~= nil and not healer.canhealfn(item, inst, inst) then return end
    local efficient = inst.components.efficientuser
    local multiplier = efficient ~= nil and efficient:GetMultiplier(ACTIONS.HEAL) or 1
    return healer.health * multiplier
end

function M.GetHealAction(inst)
    if not M.NeedsHeal(inst) or Policy.IsBusy(inst) or inst.components.inventory == nil
        or inst._my_friend_container_action or inst._my_friend_storage_action
        or GetTime() < (inst._my_friend_wormwood_heal_after or 0) then return end
    -- Only inspect carried medicine while injured; no ground/container scans.
    inst._my_friend_wormwood_heal_after = GetTime() + M.HEAL_SCAN_INTERVAL
    local health = inst.components.health
    local deficit = health:GetMaxWithPenalty() - health.currenthealth
    local best, bestgain, bestamount
    for _, item in ipairs(inst.components.inventory:ReferenceAllItems()) do
        local amount = HealingAmount(inst, item)
        if amount ~= nil and amount > 0 then
            local gain = math.min(deficit, amount)
            if best == nil or gain > bestgain or gain == bestgain and amount < bestamount then
                best, bestgain, bestamount = item, gain, amount
            end
        end
    end
    if best == nil then return end
    local action = BufferedAction(inst, nil, ACTIONS.HEAL, best)
    action.validfn = function()
        local amount = M.NeedsHeal(inst) and HealingAmount(inst, best) or nil
        return amount ~= nil and amount > 0
    end
    action:AddSuccessAction(function()
        if not inst:IsValid() then return end
        inst._my_friend_wormwood_heal_after = GetTime() + M.HEAL_SCAN_INTERVAL
        require("my_friend_dialogue").Say(inst, "activity_wormwood_heal")
    end)
    action:AddFailAction(function()
        if inst:IsValid() then
            inst._my_friend_wormwood_heal_after = GetTime() + M.HEAL_SCAN_INTERVAL
        end
    end)
    return action
end

return M
