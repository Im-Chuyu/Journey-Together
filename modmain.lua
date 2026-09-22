local _G = GLOBAL
local TheNet = _G.TheNet
require("my_friend_client_init").Install()
local InventoryAI = require("my_friend_inventory")
local Language = require("my_friend_strings")
Language.language = GetModConfigData("language") or "zh"
local Text = Language.Text
-- Every companion line is registered in STRINGS on both the server and the
-- clients so the vanilla chatter channel can echo it into nearby chat windows.
local Speech = require("my_friend_speech")
Speech.BuildStrings()
-- Rebuilt once every mod has loaded, so per character dialogue files are also
-- picked up for characters added by mods that load after this one.
AddSimPostInit(function() Speech.BuildStrings() end)
local Home = require("my_friend_home")
local Characters = require("my_friend_characters")

-- The companion is a real vanilla character at runtime, but the world save
-- groups entities by prefab name, so it is written out under a mod owned name
-- ("my_friend_wilson", ...). Without the mod those prefabs do not exist, the
-- loader skips the record, and the companion disappears together with the mod
-- instead of being left behind as a lifeless player.
-- scripts/prefabs/my_friend_characters.lua rebuilds the real character.
PrefabFiles = { "my_friend_characters" }

if _G.SaveGame ~= nil then
    local OldSaveGame = _G.SaveGame
    -- The mod environment is a sandbox: pcall, unpack and error are not
    -- globals here, they have to be reached through GLOBAL.
    local pcall, unpack, error = _G.pcall, _G.unpack, _G.error
    _G.SaveGame = function(...)
        -- SaveGame reads entity.prefab synchronously while building the record
        -- table, so the rename only has to hold for the duration of the call.
        local renamed
        if _G.TheWorld ~= nil and _G.TheWorld.ismastersim then
            for _, entity in pairs(_G.Ents) do
                if entity.persists and entity:IsValid() and entity:HasTag("my_friend")
                    and Characters.IsSupported(entity.prefab) then
                    renamed = renamed or {}
                    renamed[#renamed + 1] = { entity = entity, prefab = entity.prefab }
                    entity.prefab = Characters.SavePrefab(entity.prefab)
                end
            end
        end
        local results = { pcall(OldSaveGame, ...) }
        for _, entry in ipairs(renamed or {}) do
            if entry.entity:IsValid() then entry.entity.prefab = entry.prefab end
        end
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2)
    end
end
local ShardHome = require("my_friend_shard_home")
local FriendReplication = require("my_friend_replication")
local ContainerCompat = require("my_friend_container_compat")
AddClassPostConstruct("components/container_replica", ContainerCompat.WrapReplica)
AddComponentPostInit("teleporter", require("my_friend_wormhole").Configure)
require("my_friend_shadow_compat").Install()

-- A carried light is a separate FX entity.  The normal player interest
-- manager may put that child to sleep when its owner is far from the active
-- player, even though the companion itself is kept awake.  Keep only the
-- small set of light children awake; this preserves normal culling for every
-- other item and effect in the world.
for _, prefab in ipairs({"lanternlight", "minerhatlight", "torchfire", "nightstickfire"}) do
    AddPrefabPostInit(prefab, function(inst)
        if inst ~= nil and inst.entity ~= nil and inst.entity.SetCanSleep ~= nil then
            inst.entity:SetCanSleep(false)
        end
    end)
end
AddShardModRPCHandler("MyFriends", "HomeChunk", ShardHome.ReceiveChunk)
AddShardModRPCHandler("MyFriends", "HomeAck", ShardHome.ReceiveAck)
AddShardModRPCHandler("MyFriends", "PresenceProbe", ShardHome.ReceiveProbe)
AddShardModRPCHandler("MyFriends", "Presence", ShardHome.ReceivePresence)

local function OpenFriendContainer(doer, target, container)
    local leader = doer.components ~= nil and doer.components.follower ~= nil
        and doer.components.follower:GetLeader() or nil
    local opened_by_leader = leader ~= nil and container:IsOpenedBy(leader)
    local own_overflow = target ~= nil and target.prefab == "beargerfur_sack"
        and doer.components ~= nil and doer.components.inventory ~= nil
        and doer.components.inventory:GetOverflowContainer() == container
    if not own_overflow and not opened_by_leader
        and not InventoryAI.CanReachContainer(doer, target) then return false end
    if opened_by_leader then return true end
    if not container:IsOpenedBy(doer) then
        doer:PushEvent("opencontainer", { container = target })
        container:Open(doer)
    end
    return container:IsOpenedBy(doer)
end

local function CloseFriendContainerLater(doer, target, container)
    local action = doer._my_friend_storage_action
    local function Close()
        if doer:IsValid() and target:IsValid() and container:IsOpenedBy(doer) then
            container:Close(doer)
            doer:PushEvent("closecontainer", { container = target })
        end
        if doer:IsValid() and doer._my_friend_storage_action == action then
            doer._my_friend_storage_action = nil
        end
    end
    if action ~= nil and action._my_friend_close_immediately then Close()
    else doer:DoTaskInTime(.6, Close) end
end

local FriendHandOver = AddAction("MY_FRIEND_HANDOVER", Text("递给", "Hand over"), function(act)
    local command = act.doer._my_friend_command
    local player, item = act.target, act.invobject
    if command == nil or player == nil or player ~= command.player or not player:IsValid()
        or player.components.inventory == nil or player:HasTag("playerghost")
        or player.components.health ~= nil and player.components.health:IsDead()
        or require("my_friend_policy").GetLeader(act.doer) ~= player
        or act.doer:GetDistanceSqToInst(player) > 3^2
        or item == nil or not item:IsValid() or item.components.inventoryitem == nil
        or item.components.inventoryitem:GetGrandOwner() ~= act.doer then return false end
    local count = math.max(1, math.floor(act._my_friend_give_count or 1))
    local stack = item.components.stackable
    local moved = stack ~= nil and stack:StackSize() > count and stack:Get(count)
        or item.components.inventoryitem:RemoveFromOwner(true)
    if moved == nil then return false end
    command.delivered = command.delivered or {}
    command.delivered[moved.GUID] = true
    -- GiveItem places overflow by the player; remember it so tidy never
    -- repeatedly picks up a delivery that the player's inventory cannot hold.
    player.components.inventory:GiveItem(moved, nil, player:GetPosition())
    return true
end)
AddStategraphActionHandler("wilson", _G.ActionHandler(FriendHandOver, "doshortaction"))

local FriendLevelSoil = AddAction("MY_FRIEND_LEVELSOIL", Text("平整空坑", "Level soil"), function(act)
    local command = act.doer._my_friend_command
    local soil, tool = act.target, act.invobject
    if command == nil or command.id ~= "hoe" or soil == nil or not soil:IsValid()
        or not soil:HasTag("soil") or soil._plow ~= nil
        or act.doer:GetDistanceSqToInst(soil) > 3^2
        or not require("my_friend_command_work").IsUsableTool(act.doer, tool, _G.ACTIONS.TILL)
        or act.doer.components.inventory:GetEquippedItem(_G.EQUIPSLOTS.HANDS) ~= tool then return false end
    soil:PushEvent("collapsesoil")
    return true
end)
AddStategraphActionHandler("wilson", _G.ActionHandler(FriendLevelSoil, "doshortaction"))

local function IsFriendInventoryItem(doer, item)
    local inventoryitem = item ~= nil and item.components ~= nil
        and item.components.inventoryitem or nil
    if inventoryitem == nil then return false end
    local owner = inventoryitem.owner
    if owner == doer then return true end
    local overflow = doer.components ~= nil and doer.components.inventory ~= nil
        and doer.components.inventory:GetOverflowContainer() or nil
    if overflow ~= nil and (owner == overflow or owner == overflow.inst) then return true end
    for _ = 1, 5 do
        if owner == doer then return true end
        owner = owner ~= nil and owner.entity ~= nil and owner.entity:GetParent() or nil
        if owner == nil then break end
    end
    return false
end

local FriendBuildAction = AddAction("MY_FRIEND_BUILD", Text("制作", "Build"), function(act)
    return _G.ACTIONS.BUILD.fn(act)
end)
FriendBuildAction.mount_valid = true
AddStategraphActionHandler("wilson",
    _G.ActionHandler(FriendBuildAction, "dolongaction"))

local FriendMakeRoom = AddAction("MY_FRIEND_MAKE_ROOM", Text("让出位置", "Make room"), function(act)
    return require("my_friend_bookstation").MakeRoom(act)
end)
AddStategraphActionHandler("wilson", _G.ActionHandler(FriendMakeRoom, "doshortaction"))

local FriendDropSurplus = AddAction("MY_FRIEND_DROP_SURPLUS", Text("放下", "Drop"), function(act)
    local item = act.invobject
    local leader = act.doer.components.follower:GetLeader()
    if leader == nil or not act.doer.components.my_friend_affinity:CanTakeItems(leader)
        or not IsFriendInventoryItem(act.doer, item) then return false end
    local count = math.max(1, math.floor(act._my_friend_drop_count or 1))
    local stack = item.components.stackable
    if stack ~= nil and stack:StackSize() > count then
        item = stack:Get(count)
        item.components.inventoryitem:OnRemoved()
    else
        item = item.components.inventoryitem:RemoveFromOwner(true)
    end
    if item == nil then return false end
    item.Transform:SetPosition(act.doer.Transform:GetWorldPosition())
    item.components.inventoryitem:OnDropped(true)
    return true
end)
AddStategraphActionHandler("wilson", _G.ActionHandler(FriendDropSurplus, "doshortaction"))

local FriendOpenAction = AddAction("MY_FRIEND_OPEN", Text("打开", "Open"), function(act)
    local container = act.target ~= nil and act.target.components.container or nil
    local own_overflow = container ~= nil and act.target.prefab == "beargerfur_sack"
        and act.doer.components ~= nil and act.doer.components.inventory ~= nil
        and act.doer.components.inventory:GetOverflowContainer() == container
    local leader = act.doer.components ~= nil and act.doer.components.follower ~= nil
        and act.doer.components.follower:GetLeader() or nil
    local opened_by_leader = leader ~= nil and container ~= nil
        and container:IsOpenedBy(leader)
    if container == nil or not container.canbeopened or container.readonlycontainer
        or container:IsRestricted(act.doer)
        or container:IsOpenedByOthers(act.doer) and not opened_by_leader and not own_overflow
        or not container:IsOpenedBy(act.doer) and not container:CanOpen()
            and not opened_by_leader and not own_overflow
        or not own_overflow and not opened_by_leader
            and not InventoryAI.CanReachContainer(act.doer, act.target) then return false end
    return OpenFriendContainer(act.doer, act.target, container)
end)
AddStategraphActionHandler("wilson",
    _G.ActionHandler(FriendOpenAction, "doshortaction"))

-- Open carried portable storage without RUMMAGE's drop-on-open branch.
-- Keep Wilson's pocket state so the container does not auto-close each tick.
local FriendPocketRummage = AddAction("MY_FRIEND_POCKET_RUMMAGE",
    Text("翻阅", "Rummage"), function(act)
        local sack = act.invobject
        local inventory = act.doer.components ~= nil
            and act.doer.components.inventory or nil
        local container = sack ~= nil and sack.components ~= nil
            and sack.components.container or nil
        if sack == nil or sack.prefab ~= "beargerfur_sack"
            or inventory == nil or sack.components.inventoryitem == nil
            or sack.components.inventoryitem:GetGrandOwner() ~= act.doer
            or container == nil or container.readonlycontainer
            or container:IsRestricted(act.doer) then return false end
        if not container:IsOpenedBy(act.doer) then
            act.doer:PushEvent("opencontainer", { container = sack })
            container:Open(act.doer)
        end
        return container:IsOpenedBy(act.doer)
    end)
FriendPocketRummage.mount_valid = true
AddStategraphActionHandler("wilson",
    _G.ActionHandler(FriendPocketRummage, "start_pocket_rummage"))

-- Put one ingredient into a cookpot without invoking the player-only
-- inventory UI. Cooking itself still goes through vanilla ACTIONS.COOK.
local FriendCookpotAdd = AddAction("MY_FRIEND_COOKPOT_ADD", Text("放入食材", "Add ingredient"), function(act)
    return require("my_friend_beefalo_cooking").AddIngredient(act)
end)
FriendCookpotAdd.mount_valid = true
AddStategraphActionHandler("wilson", _G.ActionHandler(FriendCookpotAdd, "doshortaction"))
local FriendRecipeAdd = AddAction("MY_FRIEND_RECIPE_ADD", Text("放入食材", "Add ingredient"), function(act)
    return require("my_friend_recipe_cooking").AddIngredient(act)
end)
AddStategraphActionHandler("wilson", _G.ActionHandler(FriendRecipeAdd, "doshortaction"))
for _, prefab in ipairs({"cookpot", "archive_cookpot", "portablecookpot"}) do
    AddPrefabPostInit(prefab, require("my_friend_beefalo_cooking").ConfigurePot)
    AddPrefabPostInit(prefab, require("my_friend_recipe_cooking").ConfigurePot)
end

local FriendSpiceAdd = AddAction("MY_FRIEND_SPICE_ADD", Text("放入调味材料", "Add spice material"), function(act)
    local station, item = act.target, act.invobject
    local c = station ~= nil and station.components.container or nil
    if station == nil or not station:HasTag("spicer") or c == nil or item == nil
        or not c:IsOpenedBy(act.doer) or item.components.inventoryitem == nil
        or item.components.inventoryitem:GetGrandOwner() ~= act.doer
        or c:GetItemInSlot(act._my_friend_spice_slot or 1) ~= nil then return false end
    local moved = item.components.inventoryitem:RemoveFromOwner(false)
    if moved == nil or not moved:IsValid() or moved.components == nil
        or moved.components.inventoryitem == nil then return false end
    moved.prevcontainer, moved.prevslot = nil, nil
    if c:GiveItem(moved, act._my_friend_spice_slot or 1, station:GetPosition(), false) then return true end
    if moved:IsValid() then require("my_friend_inventory").GiveCarried(act.doer, moved, act.doer:GetPosition()) end
    return false
end)
FriendSpiceAdd.mount_valid = true
AddStategraphActionHandler("wilson", _G.ActionHandler(FriendSpiceAdd, "doshortaction"))
AddComponentPostInit("container", function(container)
    require("my_friend_item_reactions").WrapContainer(container)
end)

local FriendReturnFood = AddAction("MY_FRIEND_RETURN_FOOD", Text("放回", "Return"),
    function(act) return require("my_friend_container_ai").ReturnFood(act) end)
AddStategraphActionHandler("wilson", _G.ActionHandler(FriendReturnFood, "domediumaction"))

local FriendStoreAction = AddAction("MY_FRIEND_STORE", Text("存放", "Store"), function(act)
    if act.doer._my_friend_storage_action ~= nil
        and act.doer._my_friend_storage_action ~= act then return false end
    local container = act.target ~= nil and act.target.components.container or nil
    local item = act.invobject
    if container == nil or not InventoryAI.StorageReady(act.doer, act.target)
        or container.readonlycontainer or container:IsRestricted(act.doer)
        or container:IsOpenedByOthers(act.doer) then return false end
    local plan = act._my_friend_store_plan or {{item = item,
        count = math.max(1, math.floor(act._my_friend_store_count or 1))}}
    local can_move = false
    for _, entry in ipairs(plan) do
        if InventoryAI.CanStoreCount(act.doer, act.target, entry.item, entry.count) > 0 then can_move = true break end
    end
    if not can_move then
        InventoryAI.StorageResult(act.doer, act.target, false)
        return false
    end
    act.doer._my_friend_storage_action = act
    if not OpenFriendContainer(act.doer, act.target, container) then
        act.doer._my_friend_storage_action = nil
        return false
    end
    if act._my_friend_transfer ~= nil then
        local moved = require("my_friend_storage").Deposit(act.doer, act)
        InventoryAI.StorageResult(act.doer, act.target, moved)
        CloseFriendContainerLater(act.doer, act.target, container)
        return moved
    end
    local moved_any = InventoryAI.StorePlan(act.doer, act.target, plan)
    InventoryAI.StorageResult(act.doer, act.target, moved_any)
    CloseFriendContainerLater(act.doer, act.target, container)
    return moved_any
end)
AddStategraphActionHandler("wilson",
    _G.ActionHandler(FriendStoreAction, "doshortaction"))

local FriendWithdrawAction = AddAction("MY_FRIEND_WITHDRAW", Text("取出", "Take"), function(act)
    if act.doer._my_friend_storage_action ~= nil
        and act.doer._my_friend_storage_action ~= act then return false end
    local container = act.target ~= nil and act.target.components.container or nil
    local plan = act._my_friend_withdraw_plan
    local item = plan ~= nil and plan[1] ~= nil and plan[1].item or act.invobject
    if container == nil or item == nil or item.components.inventoryitem == nil
        or not InventoryAI.CanWithdrawFrom(act.doer, act.target)
        or item.components.inventoryitem.owner ~= act.target then return false end
    act.doer._my_friend_storage_action = act
    if not OpenFriendContainer(act.doer, act.target, container) then
        act.doer._my_friend_storage_action = nil
        return false
    end
    if act._my_friend_transfer ~= nil then
        local moved = require("my_friend_storage").Withdraw(act.doer, act)
        InventoryAI.StorageResult(act.doer, act.target, moved)
        CloseFriendContainerLater(act.doer, act.target, container)
        return moved
    end
    plan = plan or {{ item = item,
        count = math.max(1, math.floor(act._my_friend_withdraw_count or 1)) }}
    local moved_any = false
    for _, entry in ipairs(plan) do
        local source = entry.item
        local count = math.max(1, math.floor(entry.count or 1))
        if source ~= nil and source:IsValid()
            and source.components ~= nil and source.components.inventoryitem ~= nil
            and not source.components.inventoryitem.islockedinslot
            and source.components.inventoryitem.owner == act.target then
            local inventory = act.doer.components.inventory
            local equip = source.components.equippable
            local tool = source.components.tool
            local work = act._my_friend_equip_tool
            local equip_now = work ~= nil and tool ~= nil and tool:GetEffectiveness(work) > 0
                and equip ~= nil and not equip:IsRestricted(act.doer)
                and require("my_friend_base_ai").CanUseHandToolInCurrentLight(act.doer)
            local direct_equip = equip_now and inventory:GetEquippedItem(equip.equipslot) == nil
            count = direct_equip and 1 or math.min(count, inventory:CanAcceptCount(source, count))
            local moved
            if count <= 0 then
                -- Keep the remainder in storage when carried capacity changed.
            elseif source.components.stackable ~= nil
                and count < source.components.stackable:StackSize() then
                moved = source.components.stackable:Get(count)
            else
                moved = container:RemoveItem(source, true)
            end
            if moved ~= nil and moved:IsValid() and moved.components ~= nil
                and moved.components.inventoryitem ~= nil then
                moved.prevcontainer, moved.prevslot = nil, nil
                local accepted = direct_equip and inventory:Equip(moved) == true
                if not accepted then
                    local can_accept = moved:IsValid() and moved.components ~= nil
                        and moved.components.inventoryitem ~= nil
                        and inventory:CanAcceptCount(moved, count) >= count
                    accepted = can_accept
                        and InventoryAI.GiveCarried(act.doer, moved, act.target:GetPosition())
                    -- GiveItem may merge and remove the split entity. Never
                    -- inspect or equip that stale reference afterward.
                    if accepted and equip_now and moved:IsValid()
                        and moved.components ~= nil and moved.components.equippable ~= nil then
                        inventory:Equip(moved)
                    end
                end
                if accepted then
                    moved_any = true
                    if work ~= nil then
                        act.doer._my_friend_tool_needs = act.doer._my_friend_tool_needs or {}
                        act.doer._my_friend_tool_needs[work.id] = _G.GetTime() + 120
                        act.doer._my_friend_hand_tool_lock_until = _G.GetTime() + 3
                    end
                elseif moved:IsValid() and moved.components ~= nil
                    and moved.components.inventoryitem ~= nil then
                    container:GiveItem(moved, nil, act.target:GetPosition())
                end
            end
        end
    end
    CloseFriendContainerLater(act.doer, act.target, container)
    InventoryAI.StorageResult(act.doer, act.target, moved_any)
    return moved_any
end)
AddStategraphActionHandler("wilson",
    _G.ActionHandler(FriendWithdrawAction, "doshortaction"))

local FriendOrganizeAction = AddAction("MY_FRIEND_ORGANIZE", Text("整理", "Organize"), function(act)
    local container = act.target ~= nil and act.target.components.container or nil
    if container == nil or not InventoryAI.StorageReady(act.doer, act.target)
        or container.readonlycontainer or container:IsRestricted(act.doer)
        or container:IsOpenedByOthers(act.doer)
        or act.doer._my_friend_storage_action ~= nil
            and act.doer._my_friend_storage_action ~= act then return false end
    act.doer._my_friend_storage_action = act
    if not OpenFriendContainer(act.doer, act.target, container) then
        act.doer._my_friend_storage_action = nil
        return false
    end
    local moved = InventoryAI.CompactContainer(container)
    InventoryAI.StorageResult(act.doer, act.target, moved)
    CloseFriendContainerLater(act.doer, act.target, container)
    return moved
end)
AddStategraphActionHandler("wilson",
    _G.ActionHandler(FriendOrganizeAction, "doshortaction"))

local FollowBrain = require("brains/my_friendbrain")
local Feeding = require("my_friend_feeding")
local Backpacks = require("my_friend_backpacks")
local LightAI = require("my_friend_light_ai")
local BaseAI = require("my_friend_base_ai")
local ReviveAI = require("my_friend_revive_ai")
local CoreAI = require("my_friend_core_ai")
local Dialogue = require("my_friend_dialogue")
local Commands = require("my_friend_commands")
local CookingAI = require("my_friend_cooking_ai")
local ResourceMemory = require("my_friend_resource_memory")
AddStategraphPostInit("wilsonghost", Dialogue.ProtectStategraph)

AddStategraphPostInit("wilson", function(sg)
    Dialogue.ProtectStategraph(sg)
    for _, name in ipairs({"eat", "quickeat"}) do
        local state = sg.states[name]
        if state ~= nil then
            local onexit = state.onexit
            state.onexit = function(inst)
                if onexit ~= nil then onexit(inst) end
                Feeding.OnMealExit(inst)
            end
        end
    end
    require("my_friend_work_states").Configure(sg)
end)

for _, prefab in ipairs({
    "researchlab", "researchlab2", "firepit", "coldfirepit", "treasurechest",
}) do
    AddPrefabPostInit(prefab, BaseAI.WrapBaseStructure)
end

AddPrefabPostInitAny(function(inst)
    if inst ~= nil and inst:HasTag("backpack") then Backpacks.WrapBackpack(inst) end
end)

-- The remains marker is stored as a plain flag. Saving it through the
-- component would need add_component_if_missing, and that flag is exactly
-- what stopped a world from starting again after the mod was removed.
AddPrefabPostInit("skeleton_player", function(inst)
    if not _G.TheWorld.ismastersim then return end
    local oldsave, oldload = inst.OnSave, inst.OnLoad
    inst.OnSave = function(self, data)
        local refs = oldsave ~= nil and oldsave(self, data) or nil
        if self._my_friend_remains then data.my_friend_remains = true end
        return refs
    end
    inst.OnLoad = function(self, data, ents)
        if oldload ~= nil then oldload(self, data, ents) end
        if data ~= nil and data.my_friend_remains
            and self.components.my_friend_remains == nil then
            self:AddComponent("my_friend_remains")
        end
    end
end)

-- Server side: which skins each client says it owns, checked by SetSkins.
_G.MyFriendSkinNames = {}

-- SGwilson normally uses its running states for point movement even when the
-- locomotor is moving at walk speed.  These extra states are entered only by
-- the companion brain, so ordinary players and all other Wendy actions keep
-- using the untouched vanilla stategraph.
local function AddFriendWalkState(name, animation, nextstate, looping)
    AddStategraphState("wilson", _G.State{
        name = name,
        tags = { "moving", "canrotate", "overridelocomote", "my_friend_walk" },

        onenter = function(inst, target)
            if target ~= nil then
                inst.components.locomotor:GoToPoint(target, nil, false)
            else
                inst.components.locomotor:SetShouldRun(false)
                inst.components.locomotor:WalkForward()
            end
            inst.AnimState:PlayAnimation(animation, looping == true)
        end,

        onupdate = function(inst)
            inst.components.locomotor:WalkForward()
        end,

        events = {
            _G.EventHandler("animover", function(inst)
                if not looping and inst.AnimState:AnimDone() then
                    inst.sg:GoToState(nextstate)
                end
            end),
        },
    })
end

AddFriendWalkState("my_friend_walk_start", "walk_pre", "my_friend_walk", false)
AddFriendWalkState("my_friend_walk", "walk_loop", nil, true)

AddStategraphState("wilson", _G.State{
    name = "my_friend_walk_stop",
    tags = { "canrotate", "overridelocomote" },

    onenter = function(inst)
        inst.components.locomotor:StopMoving()
        inst.AnimState:PlayAnimation("walk_pst")
    end,

    events = {
        _G.EventHandler("animover", function(inst)
            if inst.AnimState:AnimDone() then inst.sg:GoToState("idle") end
        end),
    },
})

-- Keep legacy prefabs registered so old saves can load, but all new companions
-- are the actual vanilla Wendy prefab.
_G.STRINGS.NAMES.MY_FRIEND = "Wendy"
_G.STRINGS.CHARACTERS.GENERIC.DESCRIBE.MY_FRIEND = Text("这是我的伙伴。", "This is my companion.")

local function PushPanelData(inst)
    if not inst:IsValid() or not inst:HasTag("my_friend")
        or inst._my_friend_panel_net == nil or inst.components == nil then return end
    FriendReplication.Sync(inst)
    local health, hunger, sanity = inst.components.health, inst.components.hunger, inst.components.sanity
    local inv = inst.components.inventory
    -- The trailing field carries panel state the client cannot work out on
    -- its own: whether the shared free character change is still unspent.
    inst._my_friend_panel_net:set(string.format("%.2f,%.2f|%.2f,%.2f|%.2f,%.2f|%s|%d",
        health ~= nil and health.currenthealth or 0, health ~= nil and health.maxhealth or 0,
        hunger ~= nil and hunger.current or 0, hunger ~= nil and hunger.max or 0,
        sanity ~= nil and sanity.current or 0, sanity ~= nil and sanity.max or 0,
        string.format("%.2f,%.2f", inst.components.moisture ~= nil and inst.components.moisture:GetMoisture() or 0,
            inst.components.moisture ~= nil and inst.components.moisture:GetMaxMoisture() or 100),
        require("my_friend_farewell").IsFreeChangeAvailable(inst) and 1 or 0))
    local skinner = inst.components.skinner
    if inst._my_friend_skin_net ~= nil and skinner ~= nil then
        local skins = skinner:GetClothing()
        inst._my_friend_skin_net:set(string.format("%s|%s|%s|%s|%s",
            skins.base or (inst.prefab .. "_none"), skins.body or "", skins.hand or "",
            skins.legs or "", skins.feet or ""))
    end
end

local function RemovePlayerIdentity(inst)
    if inst.jointask ~= nil then
        inst.jointask:Cancel()
        inst.jointask = nil
    end
    for index = #(_G.AllPlayers or {}), 1, -1 do
        if _G.AllPlayers[index] == inst then table.remove(_G.AllPlayers, index) end
    end
    local hud = _G.ThePlayer ~= nil and _G.ThePlayer.HUD or nil
    if hud ~= nil then
        while hud:HasTargetIndicator(inst) do hud:RemoveTargetIndicator(inst) end
    end
end

local function ConfigureFriend(inst)
    if inst == nil or not inst:IsValid() or not Characters.IsCharacter(inst.prefab) then return end
    if inst._my_friend_configured then return inst end
    inst._my_friend_configured = true
    inst._my_friend_is_companion = true
    inst._my_friend_id = inst._my_friend_id or tostring(_G.TheWorld.meta.session_identifier)
        .. ":" .. tostring(_G.TheShard:GetShardId()) .. ":" .. tostring(inst.GUID)
    inst:AddTag("my_friend")
    inst:AddTag("companion")
    inst:AddTag("noplayerindicator")
    RemovePlayerIdentity(inst)
    if inst.components.hudindicatable ~= nil then
        inst.components.hudindicatable:SetShouldTrackFunction(function()
            return false
        end)
    end
    if inst.components.named == nil then inst:AddComponent("named") end
    inst.components.named:SetName(inst._my_friend_custom_name)
    if inst.components.follower == nil then inst:AddComponent("follower") end
    if inst.components.my_friend_affinity == nil then inst:AddComponent("my_friend_affinity") end
    if inst.components.maprevealable == nil then inst:AddComponent("maprevealable") end
    inst.components.maprevealable:AddRevealSource("my_friend_global_map")
    if inst.components.maprevealer == nil then inst:AddComponent("maprevealer") end
    inst.components.maprevealer.revealperiod = 1
    -- Wendy normally gets this from the player prefab. The companion uses the
    -- same SG, but is spawned as an ordinary prefab, so enable platform hopping
    -- explicitly for boats and other walkable platforms.
    if inst.components.embarker == nil then
        inst:AddComponent("embarker")
    end
    inst.components.embarker.embark_speed = inst.components.locomotor ~= nil
        and inst.components.locomotor.runspeed or 6
    if inst.components.locomotor ~= nil then
        inst.components.locomotor:SetAllowPlatformHopping(true)
    end
    ReviveAI.Configure(inst)
    require("my_friend_resource_safety").Configure(inst)
    require("my_friend_gifts").Configure(inst)
    require("my_friend_ghost_commands").Configure(inst)
    require("my_friend_rescue").Configure(inst)
    -- Diagnostics: a companion should only ever become a ghost through real
    -- damage. Log the cause so an unexplained ghost after a reload can be traced.
    inst:ListenForEvent("ms_becameghost", function()
        _G.print(string.format("[MyFriends] Companion became a ghost: cause=%s by=%s pet=%s shard=%s age=%.1fs",
            tostring(inst.deathcause), tostring(inst.deathpkname), tostring(inst.deathbypet),
            tostring(_G.TheShard:GetShardId()), _G.GetTime() - (inst._my_friend_spawn_time or _G.GetTime())))
    end)
    inst._my_friend_spawn_time = inst._my_friend_spawn_time or _G.GetTime()
    inst.components.my_friend_affinity:UpdateLeader()
    for _, player in ipairs(_G.AllPlayers or {}) do
        inst.components.my_friend_affinity:SyncPlayer(player)
    end
    inst.components.follower.keepdeadleader = true
    -- Stops Combat:EngageTarget from unfollowing when the companion ever takes
    -- its own leader as a combat target. The "attacked" handler above covers
    -- the other, unconditional path in Follower itself.
    inst.components.follower.keepleaderonattacked = true
    inst.components.follower.noleashing = true
    inst:SetBrain(FollowBrain)
    inst.entity:SetCanSleep(false)
    inst.persists = true
    -- Wendy's ghostlybond owns Abigail's entity and save lifecycle, and no
    -- other character has one. A companion that is not Wendy registers none of
    -- this: no listener, no cleanup pass and no summon task.
    if require("my_friend_abigail").IsOwner(inst) then
        inst:ListenForEvent("onremove", require("my_friend_abigail").RemoveSource)
        inst:DoTaskInTime(1, require("my_friend_abigail").CleanupDuplicates)
        if inst._my_friend_abigail_task == nil then
            inst._my_friend_abigail_next = inst._my_friend_abigail_next or 0
            inst._my_friend_abigail_task = inst:DoPeriodicTask(1, require("my_friend_abigail").Update)
        end
    end
    if inst._my_friend_save_hooks_added ~= true then
        local oldsave, oldload = inst.OnSave, inst.OnLoad
        inst.OnSave = function(self, data)
            local refs = oldsave ~= nil and oldsave(self, data) or nil
            data.my_friend_companion = true
            data.my_friend_custom_name = self._my_friend_custom_name
            data.my_friend_abigail_resting = self._my_friend_abigail_resting
            data.my_friend_abigail_skin = self._my_friend_abigail_skin
            require("my_friend_farewell").Save(self, data)
            require("my_friend_equipment").Save(self, data)
            data.my_friend_id = self._my_friend_id
            data.my_friend_care = require("my_friend_social_ai").SaveCare(self)
            -- Keep the outfit explicit because shard migration rebuilds the
            -- Wendy entity from a save record and may not run the normal
            -- player skin restore path at the same time as the panel replica.
            if self.components.skinner ~= nil then
                local clothing = self.components.skinner:GetClothing()
                data.my_friend_skin = {
                    skin_name = self.components.skinner.skin_name,
                    clothing = clothing,
                    skin_mode = self.components.skinner.skintype,
                }
            end
            data.my_friend_abigail_next = math.max(0,
                (self._my_friend_abigail_next or 0) - _G.GetTime())
            BaseAI.OnSave(self, data)
            ReviveAI.OnSave(self, data)
            CookingAI.OnSave(self, data)
            require("my_friend_feed_player").OnSave(self, data)
            data.my_friend_resource_memory = ResourceMemory.Save(self, _G.GetTime())
            require("my_friend_migration").SaveWorldMemory(self, data)
            return refs
        end
        inst.OnLoad = function(self, data, ents)
            require("my_friend_migration").SelectWorldMemory(data)
            if oldload ~= nil then oldload(self, data, ents) end
            if data ~= nil and data.my_friend_companion then
                self._my_friend_is_companion = true
                self:AddTag("my_friend")
                self:AddTag("companion")
            end
            BaseAI.OnLoad(self, data)
            ReviveAI.OnLoad(self, data)
            CookingAI.OnLoad(self, data)
            require("my_friend_feed_player").OnLoad(self, data)
            FriendReplication.RestoreSkin(self, data)
            self._my_friend_abigail_resting = data ~= nil and data.my_friend_abigail_resting or nil
            self._my_friend_abigail_skin = data ~= nil and type(data.my_friend_abigail_skin) == "string"
                and data.my_friend_abigail_skin or nil
            require("my_friend_farewell").Load(self, data)
            require("my_friend_equipment").Load(self, data)
            self._my_friend_abigail_next = _G.GetTime()
                + (data ~= nil and data.my_friend_abigail_next or 0)
            ResourceMemory.Load(self, data ~= nil and data.my_friend_resource_memory, _G.GetTime())
            self._my_friend_shard_homes = data ~= nil and data.my_friend_shard_homes or {}
        end
        inst._my_friend_save_hooks_added = true
    end
    PushPanelData(inst)
    inst._my_friend_panel_task = inst:DoPeriodicTask(.25, PushPanelData)
    inst._my_friend_greeting_task = inst:DoPeriodicTask(.5, CoreAI.UpdateGreetings)
    inst._my_friend_inventory_task = inst:DoPeriodicTask(1, CoreAI.MergeOneStack)
    Dialogue.Configure(inst)
    require("my_friend_offscreen").Configure(inst)
    inst._my_friend_platform_task = inst:DoPeriodicTask(.1, require("my_friend_platforms").Observe)
    inst._my_friend_care_task = inst:DoPeriodicTask(2, require("my_friend_social_ai").UpdateCare)
    inst._my_friend_beefalo_leash_task = inst:DoPeriodicTask(3,
        require("my_friend_riding").UpdateLeashing)
    inst._my_friend_permission_task = inst:DoPeriodicTask(3, Home.UpdateAsk)
    inst._my_friend_farewell_task = inst:DoPeriodicTask(1,
        require("my_friend_farewell").Update)
    inst:ListenForEvent("leaderchanged", function(_, data)
        if data ~= nil and data.new ~= nil then
            inst._my_friend_last_leader_userid = data.new.userid
        elseif data ~= nil and data.old ~= nil then
            local old = data.old
            if inst.components.my_friend_affinity.staying then
                inst._my_friend_last_leader_userid = nil
            else
                -- onremove clears followers before ms_playerleft. Preserve the
                -- departing owner until that synchronous removal has finished.
                inst._my_friend_last_leader_userid = old.userid
                inst:DoStaticTaskInTime(0, function()
                    if inst.components.follower:GetLeader() == nil
                        and require("my_friend_policy").IsLocalPlayer(old) then
                        inst._my_friend_last_leader_userid = nil
                    end
                end)
            end
        end
    end)
    local currentleader = inst.components.follower:GetLeader()
    inst._my_friend_last_leader_userid = currentleader ~= nil and currentleader.userid or nil
    inst:ListenForEvent("equip", function(_, data)
        local item = data ~= nil and data.item or nil
        if item ~= nil
            and item:HasTag("backpack")
            and not inst.components.inventory.isloading then
            Backpacks.MarkOwned(inst, item)
        end
    end)
    inst:ListenForEvent("attacked", function(_, data)
        require("my_friend_riding").OnAttacked(inst)
        require("my_friend_equipment").Hurt(inst)
        local attacker = data ~= nil and data.attacker or nil
        -- Combat emits healthdelta before attacked. damageresolved is the
        -- signed health delta and already includes armor and damage modifiers.
        if data ~= nil and ((data.damageresolved or 0) < 0
            or attacker ~= nil and attacker:HasTag("player")) then
            require("my_friend_behavior_ai").StartHurtRetreat(inst, attacker)
        end
        if attacker ~= nil and attacker:IsValid() and attacker.userid ~= nil
            and attacker:HasTag("player") and not attacker:HasTag("my_friend") then
            inst.components.my_friend_affinity:DoDelta(attacker, -10, "player_attack")
        end
        -- Vanilla Follower drops the leader outright on the first hit that
        -- leader lands, on a path that never consults keepleaderonattacked.
        -- The loss is silent and permanent -- UpdateLeader only re-runs when
        -- affinity crosses the follow threshold, which a pinned score never
        -- does -- and every leader-gated command (backpack, work, set_base)
        -- then refuses without a word. The -10 above is the intended cost of
        -- hitting the companion, so let affinity decide whether the follow
        -- actually ends instead of ending it unconditionally.
        if attacker ~= nil and attacker:IsValid() and attacker:HasTag("player")
            and not attacker:HasTag("my_friend")
            and inst.components.follower ~= nil
            and inst.components.follower:GetLeader() == nil then
            inst.components.my_friend_affinity:UpdateLeader()
        end
    end)
    inst:ListenForEvent("healthdelta", function(_, data)
        if data == nil or (data.amount or 0) >= 0 then return end
        require("my_friend_equipment").Hurt(inst)
        -- Hunger, freezing and food penalties need treatment, not random running.
        if data.cause == "fire" or data.cause == "hot" then
            local source = require("my_friend_survival_ai").FindDamagingHeatSource(inst)
            if source ~= nil then
                require("my_friend_behavior_ai").StartHurtRetreat(inst, source)
            end
        end
    end)
    inst:ListenForEvent("buildstructure", function(_, data)
        BaseAI.OnBuildStructure(inst, data ~= nil and data.item or nil)
    end)
    inst:ListenForEvent("builditem", function(_, data)
        local item = data ~= nil and data.item or nil
        LightAI.OnBuildItem(inst, item)
        if item ~= nil and item:HasTag("backpack") then
            Backpacks.MarkOwned(inst, item)
        end
    end)
    if _G.TheWorld ~= nil then _G.TheWorld._my_friend = inst end
    return inst
end

local function FindFriend()
    local actual
    for _, e in pairs(_G.Ents) do
        if e:IsValid() then
            if Characters.IsCharacter(e.prefab)
                and (e._my_friend_is_companion or e:HasTag("my_friend")) then
                if actual == nil then actual = ConfigureFriend(e) else e:Remove() end
            end
        end
    end
    return actual
end

AddPlayerPostInit(function(inst)
    require("my_friend_emotes").ConfigurePlayer(inst)
    inst._my_friend_affinity_net = _G.net_float(inst.GUID,
        "my_friends.affinity", "my_friends_affinity_dirty")
    inst._my_friend_affinity_net:set_local(20)
    if not _G.TheWorld.ismastersim then return end
    inst:ListenForEvent("onattackother", require("my_friend_behavior_ai").RecordPlayerAttack)
    require("my_friend_migration").Attach(inst, ConfigureFriend)
    inst._my_friend_affinity_net:set(20)
    inst:DoPeriodicTask(1, function(player)
        local friend = _G.TheWorld._my_friend
        if friend ~= nil and friend:IsValid() and friend.components.my_friend_affinity ~= nil then
            friend.components.my_friend_affinity:SyncPlayer(player)
        end
    end)
end)

local OldNetworkingSay = _G.Networking_Say
local function IsCommandChat(_, isemote)
    -- Whisper messages still arrive through Networking_Say and should be
    -- understood by the companion. Emotes are kept out because their text is
    -- not ordinary player chat and can otherwise trigger commands accidentally.
    local emote = isemote == true or isemote == 1 or isemote == "emote"
    return not emote
end

_G.Networking_Say = function(guid, userid, name, prefab, message, colour, whisper, isemote, ...)
    if _G.TheWorld ~= nil and _G.TheWorld.ismastersim and IsCommandChat(whisper, isemote)
        and type(message) == "string" then
        local player
        -- Chat's GUID is not guaranteed to be the local player entity GUID.
        for _, online in ipairs(_G.AllPlayers or {}) do
            if online.userid == userid and not online:HasTag("my_friend") then player = online break end
        end
        local friend = _G.TheWorld._my_friend
        if player ~= nil and player:IsValid() and player.userid == userid
            and friend ~= nil and friend:IsValid() and friend.components.my_friend_affinity ~= nil then
            Commands.Dispatch(friend, player, message)
        end
    end
    return OldNetworkingSay(guid, userid, name, prefab, message, colour, whisper, isemote, ...)
end

local OldFeedPlayer = _G.ACTIONS.FEEDPLAYER.fn
_G.ACTIONS.FEEDPLAYER.fn = function(act)
    if act.target ~= nil and act.target:HasTag("my_friend") then return Feeding.Feed(act) end
    return OldFeedPlayer(act)
end
AddComponentPostInit("eater", Feeding.WrapEater)
AddComponentPostInit("health", Feeding.WrapHealth)
AddComponentPostInit("sanity", Feeding.WrapSanity)

AddComponentAction("USEITEM", "edible", function(food, doer, target, actions, right)
    if not right or not target:HasTag("my_friend") or target:HasAnyTag("playerghost", "wereplayer")
        or (target.replica.rider ~= nil and target.replica.rider:IsRiding())
        or (doer.replica.rider ~= nil and doer.replica.rider:IsRiding()) then return end
    local net = doer._my_friend_affinity_net
    local score = net ~= nil and net:value() or 20
    local unsafe = food:HasAnyTag("badfood", "unsafefood", "spoiled")
        or (food.components ~= nil and Feeding.IsUnsafe(food, target))
    if score < 0 or unsafe and score < 90 then
        for i = #actions, 1, -1 do
            if actions[i] == _G.ACTIONS.FEEDPLAYER then table.remove(actions, i) end
        end
        return
    end
    if score < 90 then return end
    for _, action in ipairs(actions) do
        if action == _G.ACTIONS.FEEDPLAYER then return end
    end
    for _, group in pairs(_G.FOODGROUP) do
        if target:HasTag(group.name.."_eater") then
            for _, foodtype in ipairs(group.types) do
                if food:HasTag("edible_"..foodtype) then
                    table.insert(actions, _G.ACTIONS.FEEDPLAYER)
                    return
                end
            end
        end
    end
    for _, foodtype in pairs(_G.FOODTYPE) do
        if food:HasTag("edible_"..foodtype) and target:HasTag(foodtype.."_eater") then
            table.insert(actions, _G.ACTIONS.FEEDPLAYER)
            return
        end
    end
end)

local function SpawnFriend(player, announce)
    local world = _G.TheWorld
    if world == nil or not world.ismastersim or player == nil or not player:IsValid() then return end
    world._my_friend = world._my_friend ~= nil and world._my_friend:IsValid() and world._my_friend or FindFriend()
    if world._my_friend ~= nil then return end
    local friend = _G.SpawnPrefab(Characters.DEFAULT)
    if friend == nil then
        _G.print("[MyFriends] Companion creation failed: SpawnPrefab("
            .. tostring(Characters.DEFAULT) .. ") returned nil")
        return
    end
    ConfigureFriend(friend)
    -- Joining a long running world: live alongside the players instead of
    -- bulldozing a base of our own into their territory.
    if (world.state.cycles or 0) + 1 > Home.LATE_JOIN_DAY then
        friend._my_friend_late_join = true
        require("my_friend_dialogue").Say(friend, "late_join")
    end
    world._my_friend_saved = true
    local portal = _G.TheSim:FindFirstEntityWithTag("multiplayer_portal")
        or _G.TheSim:FindFirstEntityWithTag("moonaltar")
    local px, py, pz = (portal or player).Transform:GetWorldPosition()
    friend.Transform:SetPosition(px + 2, py, pz + 2)
    world._my_friend = friend
    _G.print("[MyFriends] Companion created on shard " .. tostring(_G.TheShard:GetShardId())
        .. " at " .. tostring(px + 2) .. ", " .. tostring(pz + 2))
    if announce then
        TheNet:Announce(friend:GetDisplayName()..Text("已经来到永恒领域，请前去迎接。",
            " has arrived in the Constant. Come and say hello."))
    end
end

local function CanManage(player, friend)
    if player == nil or not player:IsValid() or friend == nil or not friend:IsValid()
        or not Characters.IsCharacter(friend.prefab) or not friend:HasTag("my_friend")
        or friend.components == nil or friend.components.inventory == nil
        or not require("my_friend_policy").IsLocalPlayer(player) then return false end
    local fx, _, fz = friend.Transform:GetWorldPosition()
    local px, _, pz = player.Transform:GetWorldPosition()
    if (fx - px)^2 + (fz - pz)^2 > 100 then return false end
    local leader = friend.components.follower ~= nil and friend.components.follower:GetLeader() or nil
    return leader == nil or leader == player
end

AddModRPCHandler("MyFriends", "Rename", function(player, friend, name)
    if not CanManage(player, friend) then return end
    require("my_friend_commands").Rename(friend, player, name)
end)

AddModRPCHandler("MyFriends", "PanelLocked", function(player, friend, kind)
    if not CanManage(player, friend) or friend.components.my_friend_affinity == nil then return end
    if kind == "switch" then
        -- Either the free change is spent and this is not the leader, or the
        -- leader simply is not liked enough yet.
        if require("my_friend_policy").GetLeader(friend) ~= player then
            Dialogue.Reply(friend, "switch_needs_follow")
        else
            Dialogue.Reply(friend, "affinity_locked", "100")
        end
        return
    end
    local needed = kind == "skin" and 50 or 100
    if friend.components.my_friend_affinity:Get(player) < needed then
        Dialogue.Reply(friend, "affinity_locked", tostring(needed))
    end
end)

-- Replaces the companion with a brand new one of another character. Nothing
-- is inherited except the spent free-change flag. See my_friend_switch.lua.
AddModRPCHandler("MyFriends", "SwitchCharacter", function(player, friend, character)
    if not CanManage(player, friend) or type(character) ~= "string" then return end
    local Farewell = require("my_friend_farewell")
    if not Farewell.CanRequest(friend, player) then
        -- The shared free change is spent, so this is the leader's call only.
        if require("my_friend_policy").GetLeader(friend) ~= player then
            Dialogue.Reply(friend, "switch_needs_follow")
        else
            Dialogue.Reply(friend, "affinity_locked", "100")
        end
        return
    end
    if not Farewell.Begin(friend, character) then return end
    -- Spent as soon as the goodbye starts, so it cannot be used twice while
    -- the old companion is still walking away.
    friend._my_friend_switch_used = true
    PushPanelData(friend)
end)

AddModRPCHandler("MyFriends", "OwnedSkins", function(player, payload)
    if type(payload) ~= "string" then return end
    local owned = {}
    for skin in payload:gmatch("[^,]+") do owned[skin] = true end
    _G.MyFriendSkinNames[player.userid] = owned
end)

AddModRPCHandler("MyFriends", "SetSkins", function(player, friend, base, body, hand, legs, feet)
    if not CanManage(player, friend) then return end
    if friend.components.my_friend_affinity == nil
        or friend.components.my_friend_affinity:Get(player) < 50 then
        Dialogue.Reply(friend, "affinity_skin")
        return
    end
    local owned = _G.MyFriendSkinNames[player.userid] or {}
    local clothing = { body = body, hand = hand, legs = legs, feet = feet }
    local applied, changed = FriendReplication.ApplyWardrobe(friend, player, base, clothing, owned)
    if applied then
        PushPanelData(friend)
        if changed then Dialogue.Say(friend, "skin_changed", player) end
    end
end)

local function GetFriendStorage(friend, isbackpack)
    local finv = friend.components.inventory
    if not isbackpack then return finv, finv.maxslots end
    local container = require("my_friend_equip_slots").BackpackContainer(finv)
    if container == nil then return end
    return container, container:GetNumSlots()
end

local function FriendStorageContainsItem(friend, item)
    if item == nil or item.components.inventoryitem == nil then return false end
    local finv = friend.components ~= nil and friend.components.inventory or nil
    if finv == nil then return false end
    for i = 1, finv.maxslots do
        if finv:GetItemInSlot(i) == item then return true end
    end
    local overflow = require("my_friend_equip_slots").BackpackContainer(finv)
    if overflow ~= nil then
        for i = 1, overflow:GetNumSlots() do
            if overflow:GetItemInSlot(i) == item then return true end
        end
    end
    return false
end

-- Only player inventory transfers reach this gift hook; AI pickups do not.
local function NoteInventoryGift(friend, player, item, count)
    require("my_friend_gifts").Record(friend, player, item, count)
end

local function NotePlayerTake(friend, player, item)
    local reactions = require("my_friend_item_reactions")
    reactions.Say(friend, player, reactions.Kind(item))
end

local function StackSize(item)
    local stackable = item ~= nil and item.components ~= nil
        and item.components.stackable or nil
    return stackable ~= nil and stackable:StackSize() or (item ~= nil and 1 or 0)
end

local function HandleFriendStorageSlot(player, friend, storage, slot, maxslots, stack_mod)
    local inv = player.components.inventory
    slot = math.floor(slot)
    if inv == nil or storage == nil or slot < 1 or slot > maxslots then return end
    local active, target = inv:GetActiveItem(), storage:GetItemInSlot(slot)
    local can_take = friend.components.my_friend_affinity:CanTakeItems(player)
    if active == nil then
        if not can_take then return end
        if target ~= nil then
            local locked = target.components.inventoryitem ~= nil
                and target.components.inventoryitem.islockedinslot
            if stack_mod and target.components.stackable ~= nil
                and target.components.stackable:StackSize() > 1 then
                inv:GiveActiveItem(target.components.stackable:Get(
                    math.floor(target.components.stackable:StackSize() / 2)))
                NotePlayerTake(friend, player, target)
            elseif not locked then
                storage:RemoveItemBySlot(slot, true)
                inv:GiveActiveItem(target)
                NotePlayerTake(friend, player, target)
            else
                return
            end
            PushPanelData(friend)
        end
        return
    end
    if not storage:CanTakeItemInSlot(active, slot) then return end
    if target ~= nil and target.components.stackable ~= nil and active.components.stackable ~= nil
        and target.components.stackable:CanStackWith(active) and storage:AcceptsStacks()
        and not target.components.stackable:IsFull() then
        if stack_mod and active.components.stackable:StackSize() > 1 then
            target.components.stackable:Put(active.components.stackable:Get(1))
            NoteInventoryGift(friend, player, target, 1)
        else
            local given = StackSize(active)
            local leftover = target.components.stackable:Put(active)
            NoteInventoryGift(friend, player, target, given - StackSize(leftover))
            inv:SetActiveItem(leftover)
        end
        PushPanelData(friend)
        return
    end
    if target == nil then
        local moved = stack_mod and active.components.stackable ~= nil
            and active.components.stackable:StackSize() > 1
            and active.components.stackable:Get(1)
            or inv:RemoveItem(active, true)
            if moved ~= nil and moved:IsValid() and moved.components ~= nil
                and moved.components.inventoryitem ~= nil then
            local count = StackSize(moved)
            storage:GiveItem(moved, slot, friend:GetPosition())
            NoteInventoryGift(friend, player, moved, count)
            PushPanelData(friend)
        end
        return
    end
    if not can_take then return end
    if target.components.inventoryitem ~= nil and target.components.inventoryitem.islockedinslot then return end
    if stack_mod and active.components.stackable ~= nil
        and active.components.stackable:StackSize() > 1 then
        local moved = inv:RemoveItem(active, false)
        local old = storage:RemoveItemBySlot(slot, true)
        if moved ~= nil and old ~= nil then
            local count = StackSize(moved)
            storage:GiveItem(moved, slot, friend:GetPosition())
            NoteInventoryGift(friend, player, moved, count)
            NotePlayerTake(friend, player, old)
            inv:GiveItem(old, nil, friend:GetPosition())
            PushPanelData(friend)
        end
        return
    end
    local moved = inv:RemoveItem(active, true)
    local old = storage:RemoveItemBySlot(slot, true)
    if moved ~= nil and old ~= nil then
        local count = StackSize(moved)
        storage:GiveItem(moved, slot, friend:GetPosition())
        NoteInventoryGift(friend, player, moved, count)
        NotePlayerTake(friend, player, old)
        inv:GiveActiveItem(old)
        PushPanelData(friend)
    end
end

AddModRPCHandler("MyFriends", "ClickSlot", function(player, friend, slot, stack_mod)
    if not CanManage(player, friend) or type(slot) ~= "number" then return end
    local storage, maxslots = GetFriendStorage(friend, false)
    HandleFriendStorageSlot(player, friend, storage, slot, maxslots, stack_mod == true)
end)

AddModRPCHandler("MyFriends", "ClickBackpackSlot", function(player, friend, slot, stack_mod)
    if not CanManage(player, friend) or type(slot) ~= "number" then return end
    local storage, maxslots = GetFriendStorage(friend, true)
    HandleFriendStorageSlot(player, friend, storage, slot, maxslots, stack_mod == true)
end)

AddModRPCHandler("MyFriends", "QuickMoveFriendSlot", function(player, friend, slot, isbackpack, stack_mod)
    if not CanManage(player, friend) or type(slot) ~= "number" then return end
    if not friend.components.my_friend_affinity:CanTakeItems(player) then return end
    local storage, maxslots = GetFriendStorage(friend, isbackpack == true)
    slot = math.floor(slot)
    if storage == nil or slot < 1 or slot > maxslots then return end
    local item = storage:GetItemInSlot(slot)
    local inv = player.components.inventory
    if item == nil or inv == nil then return end
    local stackable = item.components.stackable
    local stacksize = stackable ~= nil and stackable:StackSize() or 1
    local count = stack_mod and math.max(math.floor(stacksize / 2), 1) or stacksize
    if item.components.inventoryitem ~= nil and item.components.inventoryitem.islockedinslot then
        count = math.min(count, stacksize - 1)
    end
    count = math.min(count, inv:CanAcceptCount(item, count))
    if count < 1 then return end
    local moved
    if count < stacksize and stackable ~= nil then
        moved = stackable:Get(count)
    else
        moved = storage:RemoveItemBySlot(slot, true)
    end
    if moved ~= nil then
        local reactions = require("my_friend_item_reactions")
        local kind = reactions.Kind(moved)
        moved.prevcontainer, moved.prevslot = nil, nil
        if inv:GiveItem(moved, nil, friend:GetPosition()) then
            reactions.Say(friend, player, kind)
        end
        PushPanelData(friend)
    end
end)

AddModRPCHandler("MyFriends", "PanelOpen", function(player, friend)
    if CanManage(player, friend) then
        player._my_friend_panel_target = friend
        PushPanelData(friend)
    end
end)

AddModRPCHandler("MyFriends", "PanelClose", function(player)
    player._my_friend_panel_target = nil
end)

AddComponentPostInit("inventory", function(self)
    require("my_friend_equipment").Wrap(self)
    local oldCanAccessItem = self.CanAccessItem
    self.CanAccessItem = function(inventory, item)
        local owner = item ~= nil and item.components.inventoryitem ~= nil
            and item.components.inventoryitem:GetGrandOwner() or nil
        if owner ~= nil and owner ~= inventory.inst and owner:HasTag("my_friend")
            and owner.components.my_friend_affinity ~= nil
            and not owner.components.my_friend_affinity:CanTakeItems(inventory.inst) then return false end
        if oldCanAccessItem(inventory, item) then return true end
        local friend = inventory.inst._my_friend_panel_target
        return inventory.isvisible and CanManage(inventory.inst, friend)
            and friend.components.my_friend_affinity:CanTakeItems(inventory.inst)
            and FriendStorageContainsItem(friend, item)
    end
end)

AddModRPCHandler("MyFriends", "EquipSlot", function(player, friend, equipslot)
    if not CanManage(player, friend) then return end
    if not require("my_friend_equip_slots").IsRegistered(equipslot) then return end
    local inv, finv = player.components.inventory, friend.components.inventory
    local active = inv:GetActiveItem()
    local equipped = finv:GetEquippedItem(equipslot)
    if equipped ~= nil and not friend.components.my_friend_affinity:CanTakeItems(player) then return end
    if active ~= nil then
        local equippable = active.components.equippable
        if equippable == nil
            or equippable.equipslot ~= equipslot
            or equippable:IsRestricted(friend)
            or (not active:IsValid())
            or (equipped ~= nil and equipped.components.equippable ~= nil
                and equipped.components.equippable:ShouldPreventUnequipping()) then
            return
        end
        local oldactive = active
        local old = equipped
        LightAI.ClearLightOwnership(old)
        local drop_old_at_friend = old ~= nil and old:HasTag("backpack")
        if drop_old_at_friend then
            finv:DropItem(old, true, false, friend:GetPosition())
        elseif old ~= nil then
            finv:Unequip(equipslot, nil, true)
            inv:GiveActiveItem(old)
        end
        friend._my_friend_player_equipping = true
        local accepted = finv:Equip(oldactive, true, false, true)
        friend._my_friend_player_equipping = nil
        if old ~= nil then require("my_friend_equipment").Removed(friend, equipslot, old) end
        if accepted ~= true then
            inv:GiveActiveItem(oldactive)
            return
        end
        LightAI.MarkPlayerEquipped(finv:GetEquippedItem(equipslot))
        local newitem = finv:GetEquippedItem(equipslot)
        require("my_friend_equipment").MarkPlayerEquipped(friend, newitem)
        if newitem ~= nil and newitem:HasTag("backpack") then Backpacks.MarkOwned(friend, newitem) end
        NoteInventoryGift(friend, player, newitem, 1)
    elseif equipped ~= nil then
        if equipped.components.equippable ~= nil
            and equipped.components.equippable:ShouldPreventUnequipping() then return end
        LightAI.ClearLightOwnership(equipped)
        if equipped:HasTag("backpack") then
            finv:DropItem(equipped, true, false, friend:GetPosition())
        else
            local old = finv:Unequip(equipslot)
            if old ~= nil then inv:GiveActiveItem(old) end
        end
        require("my_friend_equipment").Removed(friend, equipslot, equipped)
    end
    PushPanelData(friend)
end)

-- Runs for every playable character, because the companion can be any of
-- them. AddPrefabPostInit is not used: mod characters register themselves in
-- other mods' modmain, so the name list is not final while this file runs.
AddPrefabPostInitAny(function(inst)
    if not inst.isplayer or not Characters.IsCharacter(inst.prefab) then return end
    if inst._my_friend_panel_net == nil then
        inst._my_friend_panel_net = _G.net_string(inst.GUID, "my_friends.panel", "my_friends_panel_dirty")
    end
    if inst._my_friend_skin_net == nil then
        inst._my_friend_skin_net = _G.net_string(inst.GUID, "my_friends.skin", "my_friends_skin_dirty")
    end
    -- Must run on the server and on every client so the chatter network
    -- variables are created in the same order on each machine.
    Speech.Configure(inst)
    if _G.TheWorld.ismastersim then
        local oldpreload = inst.OnPreLoad
        inst.OnPreLoad = function(self, data, newents)
            -- The affinity data is loaded by the component before inst.OnLoad
            -- runs, so the component has to exist by now. This replaces
            -- add_component_if_missing, which made a world saved with this mod
            -- fail to start once the mod was removed.
            if data ~= nil and data.my_friend_companion == true
                and self.components.my_friend_affinity == nil then
                self:AddComponent("my_friend_affinity")
            end
            if oldpreload ~= nil then return oldpreload(self, data, newents) end
        end
    end
    local oldload = inst.OnLoad
    inst.OnLoad = function(self, data, ents)
        require("my_friend_migration").SelectWorldMemory(data)
        if oldload ~= nil then oldload(self, data, ents) end
        if data ~= nil and data.my_friend_companion == true then
            self._my_friend_custom_name = data.my_friend_custom_name
            self._my_friend_abigail_resting = data.my_friend_abigail_resting
            self._my_friend_abigail_skin = type(data.my_friend_abigail_skin) == "string"
                and data.my_friend_abigail_skin or nil
            require("my_friend_farewell").Load(self, data)
            self._my_friend_id = data.my_friend_id
            require("my_friend_social_ai").LoadCare(self, data.my_friend_care)
            self._my_friend_is_companion = true
            self:AddTag("my_friend")
            self:AddTag("companion")
            self:AddTag("noplayerindicator")
            RemovePlayerIdentity(self)
            BaseAI.OnLoad(self, data)
            ReviveAI.OnLoad(self, data)
            CookingAI.OnLoad(self, data)
            require("my_friend_feed_player").OnLoad(self, data)
            ResourceMemory.Load(self, data ~= nil and data.my_friend_resource_memory, _G.GetTime())
            self._my_friend_shard_homes = data.my_friend_shard_homes or {}
            ConfigureFriend(self)
            require("my_friend_equipment").Load(self, data)
            -- This is the initial SpawnSaveRecord load callback. Hooks added
            -- inside ConfigureFriend do not run retroactively for this load.
            FriendReplication.RestoreSkin(self, data)
            self._my_friend_abigail_next = _G.GetTime() + (data.my_friend_abigail_next or 0)
            PushPanelData(self)
        end
    end
    if not _G.TheWorld.ismastersim then
        inst._my_friend_identity_task = inst:DoPeriodicTask(1, function(self)
            if self:HasTag("my_friend") then
                RemovePlayerIdentity(self)
                if self.components.hudindicatable ~= nil then
                    self.components.hudindicatable:SetShouldTrackFunction(function()
                        return false
                    end)
                end
            end
        end)
        return
    end
end)

-- A client can create an indicator before the companion's tags arrive.
-- Remove those in RemovePlayerIdentity and prevent subsequent HUD re-adds.
AddClassPostConstruct("screens/playerhud", function(self)
    local addindicator = self.AddTargetIndicator
    self.AddTargetIndicator = function(hud, target, ...)
        if target ~= nil and target:HasTag("my_friend") then return end
        return addindicator(hud, target, ...)
    end
end)

-- Clean Sweeper on the companion's Abigail. The vanilla tool refuses pets
-- linked to someone else; the wrapper lends the ghost to the caster for the
-- duration of the call and records the chosen skin for later summons.
AddPrefabPostInit("reskin_tool", function(inst)
    if not _G.TheWorld.ismastersim or inst.components.spellcaster == nil then return end
    local Abigail = require("my_friend_abigail")
    local caster = inst.components.spellcaster
    if caster.spell ~= nil then
        local spell = Abigail.WrapReskin(caster.spell)
        caster.spell = function(tool, target, pos, doer)
            local result = spell(tool, target, pos, doer)
            Abigail.RememberSkin(target, tool)
            return result
        end
    end
    if caster.can_cast_fn ~= nil then
        caster.can_cast_fn = Abigail.WrapReskin(caster.can_cast_fn)
    end
end)

AddPrefabPostInit("abigail", function(inst)
    if not _G.TheWorld.ismastersim then return end
    local link = inst.LinkToPlayer
    inst.LinkToPlayer = function(self, player, ...)
        local result = link(self, player, ...)
        if player ~= nil and player:HasTag("my_friend") then
            require("my_friend_abigail").ConfigureGhost(player, self)
        end
        return result
    end
    local save, load = inst.OnSave, inst.OnLoad
    inst.OnSave = function(self, data)
        local refs = save ~= nil and save(self, data) or nil
        local owner = self._playerlink
        data.my_friend_abigail_owner = self._my_friend_abigail_owner
            or owner ~= nil and owner._my_friend_id or nil
        return refs
    end
    inst.OnLoad = function(self, data, ents)
        if load ~= nil then load(self, data, ents) end
        self._my_friend_abigail_owner = data ~= nil and data.my_friend_abigail_owner or nil
        if self._my_friend_abigail_owner ~= nil then self.reskin_tool_cannot_target_this = true end
    end
end)

AddClassPostConstruct("widgets/targetindicator", function(self)
    local update = self.OnUpdate
    self.OnUpdate = function(widget, ...)
        if widget.target ~= nil and widget.target:HasTag("my_friend") then
            widget:Hide()
            return
        end
        return update(widget, ...)
    end
    -- StartIndicator can call Show after OnUpdate on its deferred first frame.
    local show = self.Show
    self.Show = function(widget, ...)
        if widget.target ~= nil and widget.target:HasTag("my_friend") then
            widget:Hide()
            return
        end
        return show(widget, ...)
    end
end)

AddClassPostConstruct("widgets/controls", function(self)
    local Panel = require("widgets/my_friend_panel")
    self.my_friend_panel = self:AddChild(Panel(self.owner))
    self.my_friend_panel:Hide()
    local Skins = require("my_friend_skins")
    self.owner:DoTaskInTime(2, function() Skins.Report() end)
    self.owner:DoTaskInTime(8, function() Skins.Report() end)
    -- The panel is added after the vanilla cursor item and hover text layers.
    -- Restore their original front-to-back order above the panel.
    if self.mousefollow ~= nil then self.mousefollow:MoveToFront() end
    if self.hover ~= nil then self.hover:MoveToFront() end
end)

AddComponentPostInit("playercontroller", function(self, inst)
    local old = self.OnRightClick
    self.OnRightClick = function(controller, down)
        if not down and controller._my_friend_panel_rmb then controller._my_friend_panel_rmb = nil; return true end
        if down and controller:UsingMouse() and _G.TheInput ~= nil
            and _G.TheInput:IsKeyDown(_G.KEY_ALT) and inst.HUD ~= nil
            and inst.HUD.controls ~= nil and inst.HUD.controls.my_friend_panel ~= nil
            and _G.TheInput:GetHUDEntityUnderMouse() == nil then
            local active = inst.replica.inventory ~= nil and inst.replica.inventory:GetActiveItem() or nil
            local target = _G.TheInput:GetWorldEntityUnderMouse()
            if active == nil and target ~= nil and target:IsValid() and target:HasTag("my_friend") then
                inst.HUD.controls.my_friend_panel:ShowFriend(target)
                controller._my_friend_panel_rmb = true
                return true
            end
        end
        return old(controller, down)
    end
end)

AddClassPostConstruct("components/combat_replica", function(self)
    local validtarget = self.IsValidTarget
    self.IsValidTarget = function(combat, target)
        if target ~= nil and target:HasTag("my_friend") and combat.inst.isplayer
            and not combat.inst:HasTag("my_friend") then
            return target ~= combat.inst and target.entity:IsValid() and target.entity:IsVisible()
                and target.replica.combat ~= nil and not _G.IsEntityDead(target, true)
                and not target:HasAnyTag("playerghost", "spawnprotection")
                and target:GetPosition().y <= combat._attackrange:value()
        end
        return validtarget(combat, target)
    end
    local canbeattacked = self.CanBeAttacked
    self.CanBeAttacked = function(combat, attacker)
        if combat.inst:HasTag("my_friend") and attacker ~= nil
            and attacker.isplayer and not attacker:HasTag("my_friend") then
            return not combat.inst:HasAnyTag("playerghost", "flight", "noattack",
                "invisible", "noplayertarget", "spawnprotection")
                and not _G.IsEntityDead(combat.inst, true)
        end
        return canbeattacked(combat, attacker)
    end
end)

local function ConfigureFriendWorld(world)
    if world == nil or not world.ismastersim or world._my_friend_world_configured then return end
    world._my_friend_world_configured = true
    _G.print("[MyFriends] World lifecycle initialized: " .. tostring(world.prefab)
        .. ", shard=" .. tostring(_G.TheShard:GetShardId()))
    -- DoInitGame replays and removes every snapshot session in the same frame
    -- the world is populated. Those despawns are bookkeeping, not players
    -- leaving, so cave return-home and migration capture stay off until the
    -- first tick after loading.
    world._my_friend_loading = true
    world:DoStaticTaskInTime(0, function() world._my_friend_loading = nil end)
    require("my_friend_migration").ConfigureFriend = ConfigureFriend
    ShardHome.AttachWorld(world)
    local oldsave, oldload = world.OnSave, world.OnLoad
    world.OnSave = function(self, data)
        local refs = oldsave ~= nil and oldsave(self, data) or nil
        data.my_friend_saved = self._my_friend_saved == true
        data.my_friend_initialized = self._my_friend_initialized == true
        data.my_friend_known_shards = self._my_friend_known_shards
        data.my_friend_home_pending = self._my_friend_home_pending
        data.my_friend_home_received = self._my_friend_home_received
        return refs
    end
    world.OnLoad = function(self, data, ents)
        if oldload ~= nil then oldload(self, data, ents) end
        self._my_friend_saved = data ~= nil and data.my_friend_saved == true or false
        self._my_friend_initialized = data ~= nil
            and (data.my_friend_initialized == true or data.my_friend_saved == true) or false
        self._my_friend_known_shards = data ~= nil and data.my_friend_known_shards or {}
        self._my_friend_home_pending = data ~= nil and data.my_friend_home_pending or nil
        self._my_friend_home_received = data ~= nil and data.my_friend_home_received or {}
        -- Generated worlds have no elapsed clock save; an existing world's
        -- clock distinguishes a mid-game mod installation even on day one.
        local clock = data ~= nil and data.clock or nil
        self._my_friend_existing_world = clock ~= nil
            and ((clock.cycles or 0) > 0 or clock.phase ~= nil and clock.phase ~= "day"
                or (clock.remainingtimeinphase or 0) < (clock.totaltimeinphase or 0))
        if self._my_friend_saved then
            self._my_friend_departing_until = _G.GetTime() + 90
        end
    end
    local function EnsureCompanion(player)
        if not world:HasTag("forest") or player == nil or not player:IsValid()
            or player:HasTag("my_friend") or player._despawning then return end
        if not world._my_friend_spawn_check_logged then
            world._my_friend_spawn_check_logged = true
            _G.print("[MyFriends] Checking companion: saved=" .. tostring(world._my_friend_saved)
                .. ", initialized=" .. tostring(world._my_friend_initialized)
                .. ", player=" .. tostring(player.userid))
        end
        world._my_friend = world._my_friend ~= nil and world._my_friend:IsValid()
            and world._my_friend or FindFriend()
        if world._my_friend ~= nil then world._my_friend_initialized = true return end
        local function CreateMissingCompanion()
            if not player:IsValid() then return end
            local announce = world._my_friend_initialized or world._my_friend_existing_world
                or (world.state.cycles or 0) > 0
            SpawnFriend(player, announce)
            if world._my_friend ~= nil then world._my_friend_initialized = true end
        end
        if ShardHome.CanCreateFirstCompanion() then
            -- Fresh worlds have no companion to find in caves. Their first
            -- spawn must not depend on the cave server replying to a probe.
            CreateMissingCompanion()
        else
            ShardHome.CheckMissing(CreateMissingCompanion)
        end
    end
    world._my_friend_ensure_companion = EnsureCompanion
    world:ListenForEvent("ms_playerjoined", function(_, player)
        if player == nil or player:HasTag("my_friend") then return end
        world:DoTaskInTime(4, function()
            EnsureCompanion(player)
        end)
    end)
    world:DoPeriodicTask(30, function()
        for _, player in ipairs(_G.AllPlayers or {}) do
            if player:IsValid() and not player:HasTag("my_friend") then
                EnsureCompanion(player)
                break
            end
        end
    end)
    world:DoPeriodicTask(2, function()
        if world._my_friend == nil or not world._my_friend:IsValid() then
            if _G.GetTime() >= (world._my_friend_find_after or 0) then
                world._my_friend_find_after = _G.GetTime() + 15
                world._my_friend = FindFriend()
            end
        end
        local friend = world._my_friend
        if friend ~= nil and friend:IsValid() and friend.components.my_friend_affinity ~= nil then
            friend.components.my_friend_affinity:UpdateLeader()
        end
    end)
end
AddPrefabPostInit("forest", ConfigureFriendWorld)
AddPrefabPostInit("cave", ConfigureFriendWorld)
AddPrefabPostInitAny(function(inst)
    if inst == _G.TheWorld then
        ContainerCompat.ConfigureWorld(inst)
        ConfigureFriendWorld(inst)
    end
end)

-- Also initialize from a real server-side player. This does not depend on
-- cached world prefab postinit callbacks or the timing of ms_playerjoined.
AddPlayerPostInit(function(inst)
    local world = _G.TheWorld
    if world == nil or not world.ismastersim then return end
    inst:DoTaskInTime(4, function(player)
        if not player:IsValid() or player:HasTag("my_friend")
            or player.userid == nil or player._despawning then return end
        ConfigureFriendWorld(world)
        _G.print("[MyFriends] Player spawn initialization: " .. tostring(player.userid)
            .. ", world=" .. tostring(world.prefab))
        if world._my_friend_ensure_companion ~= nil then
            world._my_friend_ensure_companion(player)
        end
    end)
end)
