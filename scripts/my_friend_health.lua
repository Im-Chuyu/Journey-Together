-- Shared eligibility for ordinary healing, independent of character prefab.
local M = {}

function M.CanReceiveHealing(inst)
    local components = inst ~= nil and inst.components or nil
    local health = components ~= nil and components.health or nil
    -- Wanda and compatible mod characters advertise time-based health through
    -- oldager/health_as_oldage or the native ordinary-healing disable flags.
    -- Do not infer semantics from max health, prefab names or redirect hooks.
    return health ~= nil and components.oldager == nil
        and not inst:HasTag("health_as_oldage") and not inst:HasTag("cannotheal")
        and not inst._no_healing and health.canheal ~= false
end

return M
