local MyFriendDeathDrop = Class(function(self, inst)
    self.inst = inst
    inst._my_friend_death_drop = true
    inst:AddTag("my_friend_death_drop")
end)

-- No OnSave: the marker only matters between a death and the recovery trip.
-- Persisting it needed add_component_if_missing, which made worlds saved with
-- this mod fail to start once the mod was removed.

function MyFriendDeathDrop:OnRemoveFromEntity()
    self.inst._my_friend_death_drop = nil
    self.inst:RemoveTag("my_friend_death_drop")
end

return MyFriendDeathDrop
