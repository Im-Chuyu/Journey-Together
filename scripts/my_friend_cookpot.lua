local Policy = require("my_friend_policy")
local M = {RANGE = 20}
M.PREFABS = {cookpot = true, archive_cookpot = true, portablecookpot = true}

function M.IsWarly(inst)
    return inst ~= nil and inst.prefab == "warly"
end

function M.IsAllowed(inst, pot)
    return pot ~= nil and (pot.prefab ~= "portablecookpot" or M.IsWarly(inst))
end

function M.Priority(inst, pot)
    return pot ~= nil and pot.prefab == "portablecookpot" and M.IsWarly(inst) and 0 or 1
end

function M.OwnerID(inst)
    return inst._my_friend_id or tostring(inst.GUID)
end

function M.Accessible(inst, pot, origin)
    if pot == nil or not pot:IsValid() or not M.PREFABS[pot.prefab]
        or not M.IsAllowed(inst, pot)
        or pot:HasAnyTag("INLIMBO", "burnt", "fire") then return false end
    local c = pot.components.container
    return c ~= nil and pot.components.stewer ~= nil
        and not c.readonlycontainer and not c:IsRestricted(inst)
        and not c:IsOpenedByOthers(inst) and Policy.InRange(inst, pot)
        and (origin ~= nil and pot:GetDistanceSqToPoint(origin)
            or inst:GetDistanceSqToInst(pot)) <= M.RANGE^2
        and inst:GetCurrentPlatform() == pot:GetCurrentPlatform()
end

function M.Close(inst, pot)
    if pot ~= nil and pot:IsValid() and pot.components.container ~= nil
        and pot.components.container:IsOpenedBy(inst) then
        pot.components.container:Close(inst)
        inst:PushEvent("closecontainer", {container = pot})
    end
end

return M
