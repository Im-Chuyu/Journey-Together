local M = {}
local installed = false

local function CancelTemperatureWait(self)
    if self._my_friend_temperature_wait ~= nil then
        self._my_friend_temperature_wait:Cancel()
        self._my_friend_temperature_wait = nil
    end
end

function M.Install()
    if installed then return end
    installed = true

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
