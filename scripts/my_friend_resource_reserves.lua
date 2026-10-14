local M = {}
M.LATE_WORLD_DAY = 150
M.LATE_MINIMUM_SCORE = 12

function M.IsLateWorld()
    local cycles = TheWorld ~= nil and TheWorld.state ~= nil and TheWorld.state.cycles or nil
    -- cycles is zero-based: cycle 149 displays day 150; cycle 150 is day 151.
    return type(cycles) == "number" and cycles + 1 > M.LATE_WORLD_DAY
end

function M.MinimumKeep() return {cutgrass = 10, twigs = 10} end

M.FOLLOW_TARGETS = {
    cutgrass = 10,
    twigs = 10,
    log = 10,
    flint = 4,
    rocks = 10,
    goldnugget = 10,
}

function M.FollowingKeep()
    if M.IsLateWorld() then return M.MinimumKeep() end
    -- Tidying must never remove resources that following immediately refills.
    local keep = {cutgrass = 20, twigs = 20, log = 20}
    for prefab, count in pairs(M.FOLLOW_TARGETS) do
        keep[prefab] = math.max(keep[prefab] or 0, count)
    end
    return keep
end

return M
