local Fishing = require("my_friend_fishing")
local Waiting = Class(BehaviourNode, function(self, inst)
    BehaviourNode._ctor(self, "MyFriendFishing")
    self.inst = inst
end)

function Waiting:Visit()
    self.command = self.inst._my_friend_command
    self.status = Fishing.UpdateWaiting(self.inst) and RUNNING or SUCCESS
    self:Sleep(.1)
end

function Waiting:OnStop()
    Fishing.Cancel(self.inst, self.command)
    self.command = nil
end

return Waiting
