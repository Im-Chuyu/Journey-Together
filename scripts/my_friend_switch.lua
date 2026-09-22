-- Replaces the companion with a different playable character.
--
-- The new companion is a genuinely fresh one: no inherited name, inventory,
-- affinity, personal memories or leader. The old friend leaves for good and a
-- stranger arrives, exactly like meeting the very first companion.
--
-- The shared base and free character-change allowance survive the change.
local Characters = require("my_friend_characters")

local M = {}

local function StopActions(friend)
    require("my_friend_commands").Clear(friend)
    local root = friend.brain ~= nil and friend.brain.bt ~= nil and friend.brain.bt.root or nil
    if root ~= nil and root.CancelActive ~= nil then root:CancelActive() end
    local action = friend:GetBufferedAction()
    if action ~= nil then action._my_friend_cancelled = true end
    friend:ClearBufferedAction()
    if friend.components.locomotor ~= nil then
        friend.components.locomotor:Clear()
        friend.components.locomotor:Stop()
    end
end

local function DropItem(friend, item, position)
    if item == nil or not item:IsValid() then return end
    local invitem = item.components.inventoryitem
    if invitem == nil or invitem.islockedinslot or invitem:GetGrandOwner() ~= friend then return end
    -- Removing an item runs inventory/equipment callbacks. They may consume,
    -- replace or transfer it before the engine can position the dropped item.
    local dropped = invitem:RemoveFromOwner(true)
    if dropped == nil or not dropped:IsValid() or dropped.Transform == nil then return end
    invitem = dropped.components.inventoryitem
    if invitem == nil or invitem.owner ~= nil then return end
    if dropped.Physics ~= nil then dropped.Physics:Teleport(position:Get())
    else dropped.Transform:SetPosition(position:Get()) end
    invitem:OnDropped(true)
    if dropped:IsValid() then
        dropped.prevcontainer, dropped.prevslot = nil, nil
        friend:PushEvent("dropitem", {item = dropped})
    end
end

-- Puts everything down right where the companion is standing. Used at the
-- start of the goodbye so the pile is left at the player's feet, instead of
-- wherever the farewell walk happened to end.
function M.DropBelongings(friend)
    local inventory = friend ~= nil and friend.components ~= nil
        and friend.components.inventory or nil
    if inventory == nil or not friend:IsValid() then return end
    StopActions(friend)
    inventory:CloseAllChestContainers()
    local position = friend:GetPosition()
    local items, seen = {}, {}
    local function Add(item)
        if item ~= nil and item:IsValid() and not seen[item] then
            seen[item] = true
            items[#items + 1] = item
        end
    end
    Add(inventory:GetActiveItem())
    for _, item in pairs(inventory.itemslots or {}) do
        if item ~= nil and item:IsValid() and item.components ~= nil
            and not item.components.curseditem then
            local invitem = item.components.inventoryitem
            if invitem ~= nil and invitem.islockedinslot then
                local container = item.components.container
                if container ~= nil then
                    for _, stored in pairs(container.slots) do Add(stored) end
                end
            else Add(item) end
        end
    end
    if friend.EmptyBeard ~= nil then friend:EmptyBeard() end
    for _, item in pairs(inventory.equipslots or {}) do Add(item) end
    -- Only top-level items are dropped: a backpack or sack keeps its contents.
    for _, item in ipairs(items) do DropItem(friend, item, position) end
    require("my_friend_revive_ai").ReleaseBelongings(friend)
end

-- The "带走吧" goodbye. The items have to be destroyed explicitly: an
-- inventory is not parented to its owner, so removing the body on its own
-- would strand every item in limbo instead of actually clearing it. Vanilla's
-- DestroyContents already walks the active item, both grids and the contents
-- of an equipped backpack.
function M.TakeBelongings(friend)
    local inventory = friend ~= nil and friend.components ~= nil
        and friend.components.inventory or nil
    if inventory == nil or not friend:IsValid() then return end
    StopActions(friend)
    inventory:CloseAllChestContainers()
    inventory:DestroyContents()
    require("my_friend_revive_ai").ReleaseBelongings(friend)
end

function M.CanSwitch(friend, character)
    return friend ~= nil and friend:IsValid() and friend:HasTag("my_friend")
        and not friend:HasTag("playerghost")
        and friend.components ~= nil and friend.components.health ~= nil
        and not friend.components.health:IsDead()
        and Characters.CanBecome(character) and friend.prefab ~= character
end

-- Returns the new companion entity, or nil with a reason.
--
-- keep_items is the "带走吧" goodbye: the player told it to take its things,
-- so whatever is still on the body leaves the world with the body. Otherwise
-- the belongings were already dropped where the goodbye was said, back in
-- Farewell.Begin, and this only sweeps up anything picked up on the way out.
function M.Switch(friend, character, configure, keep_items)
    if not M.CanSwitch(friend, character) then return nil, "invalid" end
    if type(configure) ~= "function" then return nil, "unconfigured" end

    local position = friend:GetPosition()
    local switch_used = friend._my_friend_switch_used
    local base_data = {}
    local Base = require("my_friend_base_ai")
    Base.OnSave(friend, base_data)

    if keep_items then
        M.TakeBelongings(friend)
    else
        -- Deleting it with the old body would quietly destroy gear the players
        -- had handed over.
        M.DropBelongings(friend)
    end

    require("my_friend_abigail").RemoveSource(friend)
    TheWorld._my_friend = nil
    friend:Remove()

    local replacement = SpawnPrefab(character)
    if replacement == nil then
        print("[MyFriends] Character switch failed: could not spawn " .. tostring(character))
        return nil, "spawnfailed"
    end
    replacement.Transform:SetPosition(position:Get())
    configure(replacement)
    if base_data.my_friend_base ~= nil or base_data.my_friend_home ~= nil then
        Base.OnLoad(replacement, base_data)
    end
    replacement._my_friend_switch_used = switch_used
    replacement._my_friend_replan_requested = true
    TheWorld._my_friend = replacement
    TheWorld._my_friend_saved = true
    print("[MyFriends] Companion switched to " .. tostring(character)
        .. (keep_items and " (fresh start, previous belongings taken away)"
            or " (fresh start, previous belongings dropped)"))
    return replacement
end

return M
