local M = {}
local installed = false

local function CancelTemperatureWait(self)
    if self._my_friend_temperature_wait ~= nil then
        self._my_friend_temperature_wait:Cancel()
        self._my_friend_temperature_wait = nil
    end
end

local function InstallPlayerHearingCleanup()
    local PlayerHearing = require("components/playerhearing")
    local ctor = PlayerHearing._ctor
    if type(ctor) ~= "function" then return end
    local pcall, error = _G.pcall, _G.error
    PlayerHearing._ctor = function(self, inst, ...)
        self._my_friend_hearing_listeners = {}
        self._my_friend_hearing_removed = false
        local schedule = inst.DoTaskInTime
        inst.DoTaskInTime = function(owner, delay, fn, ...)
            local task = schedule(owner, delay, function(entity, ...)
                -- Native OnInit runs later; the component may already be gone.
                if entity.components.playerhearing ~= self then return end
                local listen = entity.ListenForEvent
                entity.ListenForEvent = function(target, event, callback, source)
                    local guarded = function(receiver, ...)
                        if not self._my_friend_hearing_removed
                            and receiver.components.playerhearing == self
                            and receiver.replica.inventory ~= nil then
                            return callback(receiver, ...)
                        end
                    end
                    self._my_friend_hearing_listeners[#self._my_friend_hearing_listeners + 1] = {
                        event = event, callback = guarded, source = source,
                    }
                    return listen(target, event, guarded, source)
                end
                local ok, err = pcall(fn, entity, ...)
                entity.ListenForEvent = listen
                if not ok then error(err, 0) end
            end, ...)
            self._my_friend_hearing_init_task = task
            return task
        end
        local ok, err = pcall(ctor, self, inst, ...)
        inst.DoTaskInTime = schedule
        if not ok then error(err, 0) end
    end
    local onremove = PlayerHearing.OnRemoveFromEntity
    PlayerHearing.OnRemoveFromEntity = function(self, ...)
        self._my_friend_hearing_removed = true
        if self._my_friend_hearing_init_task ~= nil then
            self._my_friend_hearing_init_task:Cancel()
            self._my_friend_hearing_init_task = nil
        end
        for _, listener in ipairs(self._my_friend_hearing_listeners or {}) do
            self.inst:RemoveEventCallback(listener.event, listener.callback, listener.source)
        end
        self._my_friend_hearing_listeners = nil
        for _, dsp in pairs(self.dsptables or {}) do self.inst:PushEvent("popdsp", dsp) end
        self.dsptables = {}
        if onremove ~= nil then return onremove(self, ...) end
    end
end

function M.Install()
    if installed then return end
    installed = true
    InstallPlayerHearingCleanup()

    -- Existing companions can replicate before forest_network/cave_network.
    -- This method is called inside the vanilla constructor, before either a
    -- component post-init or a player post-init could protect the temperature read.
    local FrostyBreather = require("components/frostybreather")
    local ontemperature = FrostyBreather.OnTemperatureChanged
    FrostyBreather.OnTemperatureChanged = function(self, temperature)
        local world = TheWorld
        if world ~= nil and not world.ismastersim and world.net == nil
            and not self.forced_breath then
            if self._my_friend_temperature_wait == nil then
                -- Static tasks also run while a joining client is paused.
                self._my_friend_temperature_wait = self.inst:DoStaticTaskInTime(.1, function(inst)
                    self._my_friend_temperature_wait = nil
                    if inst:IsValid() and inst.components.frostybreather == self
                        and TheWorld == world and not world.isdeactivated then
                        self:OnTemperatureChanged(world.state.temperature)
                    end
                end)
            end
            return
        end
        CancelTemperatureWait(self)
        return ontemperature(self, temperature)
    end

    local onremove = FrostyBreather.OnRemoveFromEntity
    FrostyBreather.OnRemoveFromEntity = function(self, ...)
        CancelTemperatureWait(self)
        return onremove(self, ...)
    end
end

return M
