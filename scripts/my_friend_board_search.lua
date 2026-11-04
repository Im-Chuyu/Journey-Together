-- Cooperative, per-turn search. The service owns scheduling and cancellation.
local M = {}
local Clock = os ~= nil and os.clock or nil
function M.New(search, limit)
    local work = {nodes = 0, limit = limit, exhausted = false}
    function work:Pause()
        self.units = (self.units or 0) + 1
        if self.units % 8 == 0 and (Clock ~= nil and Clock() >= self.until_time
            or Clock == nil and self.units % 64 == 0) then coroutine.yield() end
    end
    function work:Visit()
        self.nodes = self.nodes + 1
        if self.nodes > self.limit then self.exhausted = true; return false end
        self:Pause()
        return true
    end
    local thread = coroutine.create(function() return search(work) end)
    function work:Step()
        if thread == nil then return true end
        self.until_time = Clock ~= nil and Clock() + .006 or 0
        local ok, x, y, from_x, from_y = coroutine.resume(thread)
        if not ok then thread = nil; error(x) end
        if coroutine.status(thread) == "dead" then thread = nil; return true, x, y, from_x, from_y end
        return false
    end
    return work
end
return M
