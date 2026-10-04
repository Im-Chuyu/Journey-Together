-- Circuits and skill-unlocked implants belong to the WX-78 body.
local M = {}

local function SocketHolder(inst)
    return inst ~= nil and inst.prefab == "wx78" and inst.components ~= nil
        and inst.components.socketholder or nil
end

function M.TakeSockets(inst)
    local holder = SocketHolder(inst)
    if holder == nil then return end
    -- Copy before unsocketing: OnSave returns the live socketdata table.
    local data = deepcopy(holder:OnSave())
    for position in pairs(data or {}) do
        local item = holder:UnsocketPosition(position)
        if item ~= nil and item:IsValid() then item:Remove() end
    end
    return data
end

function M.LoadSockets(inst, data)
    local holder = SocketHolder(inst)
    if holder == nil or data == nil then return end
    M.TakeSockets(inst)
    -- Restore through native callbacks, including quality-specific buffs.
    -- Skill selections must already be applied before loading these sockets.
    holder:DoLoadingOfSockets(deepcopy(data))
end

function M.Save(inst)
    local owner = inst ~= nil and inst.prefab == "wx78" and inst.components ~= nil
        and inst.components.upgrademoduleowner or nil
    if owner == nil then return end
    if inst._my_friend_pending_wx78 ~= nil then return inst._my_friend_pending_wx78 end
    local holder = SocketHolder(inst)
    return {modules = owner:OnSave(), max_charge = owner:GetMaxChargeLevel(),
        sockets = holder ~= nil and deepcopy(holder:OnSave()) or nil}
end

local function LoadNow(inst, data, onloaded)
    if not inst:IsValid() or inst._my_friend_pending_wx78 ~= data then return end
    local owner = inst.components.upgrademoduleowner
    -- A restored user session may already contain circuits. Replace them
    -- without returning extra copies to the inventory or charging an unplug fee.
    if #owner:GetAllModules() > 0 then
        local swapping = owner.is_swapping
        owner.is_swapping = true
        local old_modules = owner:PopAllModules()
        owner.is_swapping = swapping
        for _, module in ipairs(old_modules) do
            if module:IsValid() then module:Remove() end
        end
    end
    if data.max_charge ~= nil then owner:SetMaxCharge(data.max_charge) end
    owner:OnLoad(data.modules, {})
    owner:UpdateActivatedModules(true)
    M.LoadSockets(inst, data.sockets)
    inst._my_friend_pending_wx78 = nil
    -- Circuits can change maximum health, hunger and sanity. Restore the
    -- saved percentages only after those effects have been installed.
    if onloaded ~= nil then onloaded() end
end

function M.Load(inst, data, onloaded)
    if data == nil or inst == nil or inst.prefab ~= "wx78"
        or inst.components == nil or inst.components.upgrademoduleowner == nil then return end
    if inst._my_friend_wx78_initialized ~= nil then
        inst:RemoveEventCallback("ms_skilltreeinitialized", inst._my_friend_wx78_initialized)
        inst._my_friend_wx78_initialized = nil
    end
    inst._my_friend_pending_wx78 = data
    if inst._my_friend_pending_skills ~= nil then
        -- The login handshake applies slot-expansion skills. Wait for its
        -- handlers to finish so they cannot eject the restored extra slots.
        local initialized
        initialized = function()
            inst:RemoveEventCallback("ms_skilltreeinitialized", initialized)
            inst._my_friend_wx78_initialized = nil
            inst:DoTaskInTime(0, function() LoadNow(inst, data, onloaded) end)
        end
        inst._my_friend_wx78_initialized = initialized
        inst:ListenForEvent("ms_skilltreeinitialized", initialized)
    else
        LoadNow(inst, data, onloaded)
    end
end

return M
