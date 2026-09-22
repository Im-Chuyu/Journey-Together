local M = {}

M.FOLLOW_TARGETS = {
    cutgrass = 10,
    twigs = 10,
    log = 10,
    flint = 4,
    rocks = 10,
    goldnugget = 10,
}

function M.FollowingKeep()
    -- Tidying must never remove resources that following immediately refills.
    local keep = {cutgrass = 20, twigs = 20, log = 20}
    for prefab, count in pairs(M.FOLLOW_TARGETS) do
        keep[prefab] = math.max(keep[prefab] or 0, count)
    end
    return keep
end

return M
