local Traveller = Class(function(self, inst)
    self.inst = inst
end)

function Traveller:Capture()
    local friend = TheWorld._my_friend
    if self.record ~= nil or friend == nil or not friend:IsValid()
        or friend.components.follower:GetLeader() ~= self.inst then return end
    require("my_friend_commands").Clear(friend)
    local root = friend.brain ~= nil and friend.brain.bt ~= nil and friend.brain.bt.root or nil
    if root ~= nil and root.CancelActive ~= nil then root:CancelActive() end
    if friend.sg ~= nil and friend.sg.statemem.feed ~= nil then friend.sg:GoToState("idle") end
    friend.components.locomotor:Clear()
    friend.components.inventory:CloseAllChestContainers()
    local record = friend:GetSaveRecord()
    if record == nil then return end
    self.record = record
    self.userid = self.inst.userid
    require("my_friend_shard_home").MarkDeparture()
    -- The record travels in the player's normal migration session. Remove
    -- the source entity only after the complete carried inventory is captured.
    TheWorld._my_friend_saved = true
    TheWorld._my_friend = nil
    require("my_friend_abigail").RemoveSource(friend)
    friend:Remove()
end

function Traveller:OnSave()
    if self.record ~= nil then
        -- The component is attached by AddPlayerPostInit before the save data
        -- is applied, so add_component_if_missing is neither needed nor safe.
        return {record = self.record, userid = self.userid}
    end
end

function Traveller:Restore()
    if self.record == nil or self.inst:HasTag("my_friend") then return end
    local existing = TheWorld._my_friend
    if existing ~= nil and existing:IsValid() then
        -- The live companion is the truth. Keeping the record around used to
        -- spawn a stale duplicate later, whenever the live one was away.
        print("[MyFriends] Dropping a travelling record: a companion is already here")
        self.record, self.userid = nil, nil
        return
    end
    local migration = require("my_friend_migration")
    if migration.ConfigureFriend == nil then return end
    migration.SelectWorldMemory(self.record.data)
    local friend = SpawnSaveRecord(self.record)
    if friend == nil then return end
    migration.ConfigureFriend(friend)
    self.record = nil
    TheWorld._my_friend_saved = true
    if self.inst.migrationpets ~= nil then
        self.inst.migrationpets[#self.inst.migrationpets + 1] = friend
    end
    self.inst:DoTaskInTime(0, function(player)
        if not friend:IsValid() or not player:IsValid() then return end
        local point = player:GetPosition()
        local offset = FindWalkableOffset(point, math.random() * 2 * math.pi, 2, 8, true, false)
        point = offset ~= nil and point + offset or point
        friend.Physics:Teleport(point:Get())
        require("my_friend_abigail").Place(friend)
        friend.components.my_friend_affinity.staying = false
        friend.components.my_friend_affinity:RequestFollow(player)
        friend._my_friend_follow_requested_until = GetTime() + 30
        friend._my_friend_replan_requested = true
    end)
end

function Traveller:OnLoad(data)
    if data == nil or type(data.record) ~= "table"
        or not require("my_friend_characters").IsCharacter(data.record.prefab)
        or data.record.data == nil or data.record.data.my_friend_companion ~= true then return end
    self.record, self.userid = data.record, data.userid
    -- Snapshot sessions replayed during world load are removed again right
    -- away; the real join runs OnLoad a second time and restores then.
    if TheWorld._my_friend_loading then return end
    self:Restore()
    if self.record ~= nil then self.inst:DoTaskInTime(1, function() self:Restore() end) end
end

return Traveller
