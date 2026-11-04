-- Local-player retry controller. No game tasks or callbacks survive removal.
local M = {}
local function Cancel(task) if task ~= nil then task:Cancel() end end
function M.New(player, code, connect, on_retry)
    local self = {player = player, code = code, connect = connect, failures = 0, enabled = true, serial = 0, world = TheWorld, on_retry = on_retry}
    function self:Valid() return self.player:IsValid() and (self.world == nil or self.world == TheWorld) end
    function self:Schedule(delay)
        Cancel(self.retry)
        if not self.enabled or self.failures >= 30 or not self:Valid() then return end
        self.retry = self.player:DoStaticTaskInTime(delay, function()
            self.retry = nil
            if not self.enabled or not self:Valid() then self:Stop(); return end
            self.connecting = true
            self.serial = self.serial + 1
            local attempt = self.serial
            self.timeout = self.player:DoStaticTaskInTime(15, function() self:Result("failed", "timeout", attempt) end)
            local ok, result = pcall(self.connect, self.code, attempt)
            if not ok or result == false then self:Result("failed", "request_failed", attempt) end
        end)
    end
    function self:Result(status, reason, attempt)
        if not self.enabled or not self:Valid() then return end
        if attempt ~= nil and attempt ~= self.serial then return end
        if reason == "pairing_code_mismatch" then
            self:Stop()
        elseif status == "connected" then
            Cancel(self.retry); Cancel(self.timeout)
            self.retry, self.timeout, self.connecting, self.connected, self.failures = nil, nil, false, true, 0
        elseif status == "disconnected" and self.connected then
            self.connected, self.connecting = false, false
            self:Schedule(0)
        elseif (status == "failed" or status == "disconnected") and self.connecting then
            Cancel(self.timeout); self.timeout, self.connecting, self.connected = nil, false, false
            self.failures = self.failures + 1
            if self.on_retry ~= nil then self.on_retry(self.failures, self.failures < 30 and self.failures * 5 or nil) end
            self:Schedule(self.failures * 5)
        end
    end
    function self:Stop()
        self.enabled = false
        self.connecting, self.connected = false, false
        Cancel(self.retry); Cancel(self.timeout)
        self.retry, self.timeout = nil, nil
    end
    player:ListenForEvent("onremove", function() self:Stop() end)
    self:Schedule(1)
    return self
end
return M
