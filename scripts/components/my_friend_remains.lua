local MyFriendRemains = Class(function(self, inst)
    self.inst = inst
    inst._my_friend_remains = true
    inst:AddTag("my_friend_remains")
    self.onloot = function(_, data)
        local loot = data ~= nil and data.loot or nil
        if loot ~= nil and loot:IsValid() and loot.prefab == "boneshard"
            and loot.components.my_friend_death_drop == nil then
            loot:AddComponent("my_friend_death_drop")
        end
    end
    inst:ListenForEvent("loot_prefab_spawned", self.onloot)
end)

-- No OnSave here. The marker is persisted by the skeleton_player prefab hook
-- in modmain, because add_component_if_missing made worlds saved with this
-- mod fail to start once the mod was removed.

function MyFriendRemains:OnRemoveFromEntity()
    self.inst._my_friend_remains = nil
    self.inst:RemoveTag("my_friend_remains")
    self.inst:RemoveEventCallback("loot_prefab_spawned", self.onloot)
end

return MyFriendRemains
