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

function M.CanReceiveHarvest(inst, pot)
    local product = pot.components.stewer.product
    local inv = inst.components.inventory
    if not product or not inv then return false end
    if not inv:IsFull() then return true end
    local recipe = require("cooking").GetRecipe(pot.prefab, product)
    local count = recipe and recipe.stacksize or 1
    for _, item in ipairs(inv:ReferenceAllItems()) do
        if item.prefab == product then return inv:CanAcceptCount(item, count) >= count end
    end
    local pack = inv:GetOverflowContainer()
    if not pack or pack:IsFull() or pack.readonlycontainer or pack:IsRestricted(inst) then return false end
    -- An empty backpack slot can accept a new dish. Ask the native capacity
    -- check about that product, including custom slot filters and recipe yield.
    local cache = inst._my_friend_harvest_room
    local revision = inst._my_friend_discovery_inventory
    if cache and cache.product == product and cache.count == count and cache.pack == pack.inst.GUID
        and cache.revision == revision and GetTime() < cache.untiltime then return cache.fits end
    local sample = SpawnPrefab(product)
    if sample == nil then return false end
    local ok, capacity = pcall(inv.CanAcceptCount, inv, sample, count)
    sample:Remove()
    if not ok then error(capacity, 0) end
    local fits = capacity >= count
    inst._my_friend_harvest_room = {product = product, count = count, pack = pack.inst.GUID,
        revision = revision, untiltime = GetTime() + 1, fits = fits}
    return fits
end

function M.Accessible(inst, pot, origin, radius)
    if pot == nil or not pot:IsValid() or not M.PREFABS[pot.prefab]
        or not M.IsAllowed(inst, pot)
        or pot:HasAnyTag("INLIMBO", "burnt", "fire") then return false end
    local c = pot.components.container
    return c ~= nil and pot.components.stewer ~= nil
        and not c.readonlycontainer and not c:IsRestricted(inst)
        and not c:IsOpenedByOthers(inst) and Policy.InRange(inst, pot)
        and (origin ~= nil and pot:GetDistanceSqToPoint(origin)
            or inst:GetDistanceSqToInst(pot)) <= (radius or M.RANGE)^2
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
