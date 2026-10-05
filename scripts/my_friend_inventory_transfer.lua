local M = {}

local function GetInventory(inst)
    return inst ~= nil and inst.components ~= nil and inst.components.inventory or nil
end

local function GetLinkedBeefalo(bell)
    if bell == nil or not bell:IsValid() or not bell:HasTag("bell")
        or bell.GetBeefalo == nil then return nil end
    local ok, beefalo = pcall(bell.GetBeefalo, bell)
    return ok and beefalo ~= nil and beefalo:IsValid() and beefalo or nil
end

function M.Clear(inst)
    local inv = GetInventory(inst)
    if inv == nil or inv.ForEachItem == nil then return end
    local items, beefalo, seen = {}, {}, {}
    inv:ForEachItem(function(item)
        items[#items + 1] = item
        local linked = GetLinkedBeefalo(item)
        if linked ~= nil and not seen[linked] then
            seen[linked] = true
            beefalo[#beefalo + 1] = {animal = linked, bell = item}
        end
    end)
    -- Clear the world animal before removing the bell. A removed bell may
    -- release its follower as an independently persistent beefalo.
    for _, pair in ipairs(beefalo) do
        local linked, bell = pair.animal, pair.bell
        if linked:IsValid() then
            local leader = bell.components ~= nil and bell.components.leader or nil
            local onremove = leader ~= nil and leader.onremovefollower or nil
            if leader ~= nil then leader.onremovefollower = nil end
            if linked._BellRemoveCallback ~= nil and linked.RemoveEventCallback ~= nil then
                linked:RemoveEventCallback("onremove", linked._BellRemoveCallback, bell)
            end
            linked.persists = false
            local ok, err = pcall(linked.Remove, linked)
            if leader ~= nil then leader.onremovefollower = onremove end
            if not ok then print("[MyFriends] Linked beefalo cleanup failed: " .. tostring(err)) end
        end
    end
    for _, item in ipairs(items) do
        if item ~= nil and item:IsValid() then item:Remove() end
    end
end

function M.Capture(inst)
    local inv = GetInventory(inst)
    return inv ~= nil and inv.OnSave ~= nil and inv:OnSave() or nil
end

function M.SaveAndClear(inst)
    local data = M.Capture(inst)
    if data ~= nil then M.Clear(inst) end
    return data
end

function M.Load(inst, data)
    local inv = GetInventory(inst)
    if inv == nil then return end
    M.Clear(inst)
    if data ~= nil and inv.OnLoad ~= nil then inv:OnLoad(data, {}) end

    -- Sessions saved by older mod versions kept the animal outside the bell.
    -- Use the native bell callback to restore both the link and its visuals.
    if data ~= nil and type(data.my_friend_beefalo_records) == "table"
        and _G.SpawnSaveRecord ~= nil then
        for _, entry in ipairs(data.my_friend_beefalo_records) do
            local bell = inv.itemslots ~= nil and inv.itemslots[entry.slot] or nil
            if bell ~= nil and GetLinkedBeefalo(bell) == nil and entry.record ~= nil then
                local ok, beefalo = pcall(_G.SpawnSaveRecord, entry.record)
                if ok and beefalo ~= nil and beefalo:IsValid() then
                    local use = bell.components ~= nil
                        and bell.components.useabletargeteditem or nil
                    local bound_ok, bound = false, false
                    if use ~= nil then
                        bound_ok, bound = pcall(use.StartUsingItem, use, beefalo)
                    end
                    if not bound_ok or not bound then
                        beefalo.persists = false
                        beefalo:Remove()
                    end
                end
            end
        end
    end
end

return M
