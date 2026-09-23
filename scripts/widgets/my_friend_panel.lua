local Widget = require "widgets/widget"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local InvSlot = require "widgets/invslot"
local ItemTile = require "widgets/itemtile"
local Text = require "widgets/text"
local ItemSlot = require "widgets/itemslot"
local HealthBadge = require "widgets/healthbadge"
local HungerBadge = require "widgets/hungerbadge"
local SanityBadge = require "widgets/sanitybadge"
local MoistureMeter = require "widgets/moisturemeter"
local TextForLanguage = require("my_friend_strings").Text
local EquipSlots = require("my_friend_equip_slots")

local PANEL_W, PANEL_H = 760, 410
local INFO_X, ACTION_X = -43, 304
local ACTION_STEP = 104

local FriendInvSlot = Class(InvSlot, function(self, num, owner, container, isbackpack)
    InvSlot._ctor(self, num, "images/hud.xml", "inv_slot.tex", owner, container)
    self.isbackpack = isbackpack == true
end)

local FriendEquipSlot = Class(ItemSlot, function(self, slot, owner, friend)
    ItemSlot._ctor(self, slot.atlas, slot.image, owner)
    self.equipslot = slot.name
    self.friend = friend
end)

function FriendEquipSlot:OnControl(control, down)
    if down and control == CONTROL_ACCEPT then
        self:Click()
        return true
    end
    return ItemSlot._base.OnControl(self, control, down)
end

function FriendEquipSlot:Click()
    if self.owner ~= nil and self.owner.HUD ~= nil
        and self.owner.HUD.controls ~= nil
        and self.owner.HUD.controls.my_friend_panel ~= nil then
        local panel = self.owner.HUD.controls.my_friend_panel
        if panel.friend ~= nil and panel.friend:IsValid() then
            SendModRPCToServer(GetModRPC("MyFriends", "EquipSlot"),
                panel.friend, self.equipslot)
        end
    end
end

function FriendInvSlot:GetPanelFriend()
    if self.owner ~= nil and self.owner.HUD ~= nil
        and self.owner.HUD.controls ~= nil
        and self.owner.HUD.controls.my_friend_panel ~= nil then
        local panel = self.owner.HUD.controls.my_friend_panel
        if panel.friend ~= nil and panel.friend:IsValid() then
            return panel.friend
        end
    end
end

function FriendInvSlot:Click(stack_mod)
    local friend = self:GetPanelFriend()
    if friend ~= nil then
        SendModRPCToServer(
            GetModRPC("MyFriends", self.isbackpack and "ClickBackpackSlot" or "ClickSlot"),
            friend,
            self.num,
            stack_mod == true
        )
    end
end

function FriendInvSlot:TradeItem(stack_mod)
    local friend = self:GetPanelFriend()
    if friend ~= nil then
        SendModRPCToServer(GetModRPC("MyFriends", "QuickMoveFriendSlot"),
            friend, self.num, self.isbackpack, stack_mod == true)
    end
end

function FriendInvSlot:CanTradeItem(stack_mod)
    local item = self.tile ~= nil and self.tile.item or nil
    local inventoryitem = item ~= nil and item.replica.inventoryitem or nil
    if inventoryitem == nil or inventoryitem:CanOnlyGoInPocket() then return false end
    if inventoryitem:IsLockedInSlot() then
        return stack_mod == true and item.replica.stackable ~= nil
            and item.replica.stackable:IsStack()
    end
    return true
end

local function ParsePair(value)
    if value == nil then return 0, 0 end
    local a, b = value:match("^([^,]*),([^,]*)$")
    return tonumber(a) or 0, tonumber(b) or 0
end

-- Trailing "|<flags>" field written by PushPanelData. 1 = the shared free
-- character change has not been used yet.
local function ParseFreeSwitch(raw)
    local flags = (raw or ""):match("|([^|]*)$")
    return flags == "1"
end

local function ParseData(raw)
    local hp, hunger, sanity = (raw or ""):match("^([^|]*)|([^|]*)|([^|]*)|")
    local hpc, hpm = ParsePair(hp)
    local huc, hum = ParsePair(hunger)
    local sac, sam = ParsePair(sanity)
    return hpc, hpm, huc, hum, sac, sam
end

local MyFriendPanel = Class(Widget, function(self, owner)
    Widget._ctor(self, "MyFriendPanel")
    self.owner = owner
    self.friend = nil
    self.refresh_timer = 0
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self:SetScale(.8)
    self:StartUpdating()

    self.background = self:AddChild(Image("images/global.xml", "square.tex"))
    self.background:SetSize(PANEL_W, PANEL_H)
    self.background:SetTint(0, 0, 0, 0)
    self.background:SetClickable(false)

    self.info_frame = self:AddChild(Image("images/global.xml", "square.tex"))
    self.info_frame:SetSize(360, 78)
    self.info_frame:SetPosition(INFO_X, 151)
    self.info_frame:SetTint(.035, .045, .055, .88)
    self.info_frame:SetClickable(false)

    self.info_line = self:AddChild(Image("images/global.xml", "square.tex"))
    self.info_line:SetSize(360, 2)
    self.info_line:SetPosition(INFO_X, 119)
    self.info_line:SetTint(1, .72, .28, .8)
    self.info_line:SetClickable(false)

    self.title = self:AddChild(Text(DEFAULTFONT, 30, "Wendy"))
    self.title:SetHAlign(ANCHOR_LEFT)
    self.title:SetPosition(INFO_X - 104, 174)
    self.title:SetColour(1, .85, .45, 1)
    self.affinity = self:AddChild(Text(DEFAULTFONT, 20, TextForLanguage("好感度 20.0", "Affinity 20.0")))
    self.affinity:SetPosition(INFO_X + 65, 174)
    self.affinity:SetColour(1, .85, .45, 1)
    self.stats = self:AddChild(Text(DEFAULTFONT, 16, ""))
    self.stats:SetPosition(INFO_X - 20, 140)
    self.stats:Hide()

    self.slots = {}
    self.equips = EquipSlots.Panel(owner)
    self.backpackslots = {}
    for i = 1, 15 do
        local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
        self.slots[i] = { col = col, row = row }
    end

    self.close = self:AddChild(ImageButton("images/hud.xml", "inv_slot.tex"))
    self.close:SetScale(.48)
    self.close:SetPosition(INFO_X + 201, 169)
    self.close.scale_on_focus = false
    self.close.icon = self.close:AddChild(Text(DEFAULTFONT, 27, "X"))
    self.close.icon:SetColour(1, .82, .42, 1)
    self.close:SetOnClick(function() self:HideFriend() end)

    -- Action row, in the empty band above the backpack grid. Kept out of the
    -- info strip, which the title, affinity and status badges already fill.
    self.actions_frame = self:AddChild(Image("images/global.xml", "square.tex"))
    self.actions_frame:SetSize(322, 52)
    self.actions_frame:SetPosition(ACTION_X + ACTION_STEP, 150)
    self.actions_frame:SetTint(.035, .045, .055, .88)
    self.actions_frame:SetClickable(false)

    local function ActionButton(label, hover, x, onclick)
        local button = self:AddChild(ImageButton("images/global.xml", "square.tex"))
        button:ForceImageSize(96, 36)
        button:SetPosition(x, 150)
        button:SetImageNormalColour(.16, .16, .18, .95)
        button:SetImageFocusColour(.32, .26, .12, 1)
        button:SetImageDisabledColour(.12, .12, .13, .7)
        button.scale_on_focus = false
        button.label = button:AddChild(Text(DEFAULTFONT, 18, label))
        button.label:SetColour(1, .78, .28, 1)
        button.label:SetClickable(false)
        button:SetHoverText(hover)
        button:SetOnClick(onclick)
        return button
    end

    self.switch = ActionButton(TextForLanguage("换伙伴", "Character"),
        TextForLanguage("换伙伴：更换伙伴的角色", "Character: change who your companion is"),
        ACTION_X, function()
            if not self:CanSwitchCharacter() then
                SendModRPCToServer(GetModRPC("MyFriends", "PanelLocked"), self.friend, "switch")
            else
                self:OpenCharacterScreen()
            end
        end)

    self.skin = ActionButton(TextForLanguage("衣柜", "Wardrobe"),
        TextForLanguage("衣柜：好感度达到50可以换装", "Wardrobe: requires 50 affinity"),
        ACTION_X + ACTION_STEP, function()
            if self:GetAffinityScore() < 50 then
                SendModRPCToServer(GetModRPC("MyFriends", "PanelLocked"), self.friend, "skin")
            else
                self:OpenSkinScreen()
            end
        end)

    self.rename = ActionButton(TextForLanguage("改名", "Rename"),
        TextForLanguage("改名：好感度达到100可以改名", "Rename: requires 100 affinity"),
        ACTION_X + ACTION_STEP * 2, function()
            if self:GetAffinityScore() < 100 then
                SendModRPCToServer(GetModRPC("MyFriends", "PanelLocked"), self.friend, "rename")
            else
                self:OpenRenameScreen()
            end
        end)
end)

-- The first change of the whole server is free for anybody standing here;
-- after that it belongs to the player the companion follows, at 100 affinity.
function MyFriendPanel:CanSwitchCharacter()
    local friend = self.friend
    if friend == nil or not friend:IsValid() then return false end
    if self.free_switch then return true end
    local follower = friend.replica ~= nil and friend.replica.follower or nil
    local leader = follower ~= nil and follower:GetLeader() or nil
    if friend.components ~= nil and friend.components.follower ~= nil then
        leader = friend.components.follower:GetLeader()
    end
    return leader == self.owner and self:GetAffinityScore() >= 100
end

function MyFriendPanel:GetAffinityScore()
    local friend = self.friend
    if friend ~= nil and friend.components ~= nil
        and friend.components.my_friend_affinity ~= nil then
        return friend.components.my_friend_affinity:Get(self.owner)
    end
    return self.owner._my_friend_affinity_net ~= nil
        and self.owner._my_friend_affinity_net:value() or 20
end

function MyFriendPanel:OpenRenameScreen()
    local friend = self.friend
    if friend == nil or not friend:IsValid() then return end
    local InputDialog = require "screens/redux/inputdialog"
    local dialog
    local submitted = false
    local function Submit()
        if submitted then return end
        submitted = true
        if friend:IsValid() then
            SendModRPCToServer(GetModRPC("MyFriends", "Rename"), friend, dialog:GetActualString())
        end
        dialog:Close()
    end
    dialog = InputDialog(TextForLanguage("伙伴改名", "Rename Companion"), {
        {text = TextForLanguage("确定", "Confirm"), cb = Submit},
        {text = TextForLanguage("取消", "Cancel"), cb = function() dialog:Close() end},
    }, true, true)
    dialog.edit_text:SetTextLengthLimit(48)
    dialog.edit_text:EnableWordWrap(false)
    dialog.edit_text:EnableScrollEditWindow(true)
    dialog.edit_text.OnTextEntered = Submit
    dialog:OverrideText(friend:GetDisplayName())
    self:HideFriend()
    TheFrontEnd:PushScreen(dialog)
end

function MyFriendPanel:OpenCharacterScreen()
    if self.friend == nil or not self.friend:IsValid() then return end
    local Screen = require "screens/my_friend_character_screen"
    local friend = self.friend
    self:HideFriend()
    TheFrontEnd:PushScreen(Screen(friend, self.owner))
end

function MyFriendPanel:OpenSkinScreen()
    if self.friend == nil or not self.friend:IsValid() then return end
    -- The owned-skin list the server validates against is per character, so
    -- refresh it here in case the companion was switched since login.
    require("my_friend_skins").Report(self.friend.prefab)
    local Screen = require "screens/my_friend_skin_screen"
    local friend = self.friend
    self:HideFriend()
    TheFrontEnd:PushScreen(Screen(friend, self.owner))
end

function MyFriendPanel:ClearSlots()
    for _, slot in ipairs(self.slots) do
        if slot.widget ~= nil then
            slot.widget:Kill()
            slot.widget = nil
        end
    end
    for _, slot in ipairs(self.equips) do
        if slot.widget ~= nil then slot.widget:Kill(); slot.widget = nil end
    end
    for _, slot in ipairs(self.backpackslots or {}) do
        if slot.widget ~= nil then slot.widget:Kill() end
    end
    self.backpackslots = {}
end

function MyFriendPanel:RebuildSlots()
    self:ClearSlots()
    self.equips = EquipSlots.Panel(self.owner)
    local inventory = self.friend ~= nil and self.friend.replica ~= nil
        and self.friend.replica.inventory or nil
    if inventory == nil then return end
    for i, slot in ipairs(self.slots) do
        slot.widget = self:AddChild(FriendInvSlot(i, self.owner, inventory))
        slot.widget:SetPosition((slot.col - 2.6) * 72, 70 - slot.row * 72)
    end
    local inventory = self.friend.replica.inventory
    for _, slot in ipairs(self.equips) do
        slot.widget = self:AddChild(FriendEquipSlot(slot, self.owner, self.friend))
        slot.widget:SetPosition(slot.x, slot.y)
        slot.widget:SetScale(slot.scale or 1)
        local item = inventory:GetEquippedItem(slot.name)
        if item ~= nil then slot.widget:SetTile(ItemTile(item)) end
    end
    local overflow = EquipSlots.BackpackContainer(inventory)
    self.shown_overflow = overflow
    self.shown_overflow_slots = overflow ~= nil and overflow:GetNumSlots() or 0
    if overflow ~= nil then
        for i = 1, overflow:GetNumSlots() do
            local entry = {num = i}
            entry.widget = self:AddChild(FriendInvSlot(i, self.owner, overflow, true))
            entry.widget:SetPosition(276 + ((i - 1) % 5) * 72,
                70 - math.floor((i - 1) / 5) * 72)
            self.backpackslots[i] = entry
        end
    end
end

function MyFriendPanel:ShowFriend(friend)
    if friend == nil or not friend:IsValid() or not friend:HasTag("my_friend") then return end
    self.friend = friend
    SendModRPCToServer(GetModRPC("MyFriends", "PanelOpen"), friend)
    self:CreateStatusBadges()
    self.refresh_timer = 0
    self:RebuildSlots()
    self:Show()
    self:Refresh()
end

function MyFriendPanel:HideFriend()
    SendModRPCToServer(GetModRPC("MyFriends", "PanelClose"))
    self.friend = nil
    if self.moisturebadge ~= nil then
        self.moisturebadge:Kill()
        self.moisturebadge = nil
    end
    if self.statusbadges ~= nil then
        for _, badge in ipairs(self.statusbadges) do badge:Kill() end
        self.statusbadges = nil
    end
    self:ClearSlots()
    self:Hide()
end

function MyFriendPanel:CreateStatusBadges()
    if self.statusbadges ~= nil then return end
    self.statusbadges = {
        self:AddChild(HealthBadge(self.friend)),
        self:AddChild(HungerBadge(self.friend)),
        self:AddChild(SanityBadge(self.friend)),
    }
    for i, badge in ipairs(self.statusbadges) do
        badge:SetScale(.55)
        badge:SetPosition(-145 + (i - 1) * 54, 143)
    end
    self.moisturebadge = self:AddChild(MoistureMeter(self.friend))
    self.moisturebadge:SetScale(.55)
    self.moisturebadge:SetPosition(17, 143)
    self.moisturebadge:Hide()
    self:RefreshStatusBadges()
end

function MyFriendPanel:RefreshStatusBadges(hp, hpmax, hunger, hungermax, sanity, sanitymax)
    if self.statusbadges == nil then return end
    local replica = self.friend ~= nil and self.friend.replica or nil
    local health = replica ~= nil and replica.health or nil
    local sanityreplica = replica ~= nil and replica.sanity or nil
    local healthpenalty = health ~= nil and health:GetPenaltyPercent() or 0
    local sanitypenalty = sanityreplica ~= nil and sanityreplica:GetPenaltyPercent() or 0
    -- Match the vanilla HUD's full SetPercent signature. Uncompromising Mode
    -- compares penaltypercent directly, including during our initial refresh
    -- before the companion's status data has arrived.
    self.statusbadges[1]:SetPercent((hpmax or 0) > 0 and (hp or 0) / hpmax or 0,
        hpmax or 100, healthpenalty)
    self.statusbadges[2]:SetPercent((hungermax or 0) > 0 and (hunger or 0) / hungermax or 0,
        hungermax or 100)
    self.statusbadges[3]:SetPercent((sanitymax or 0) > 0 and (sanity or 0) / sanitymax or 0,
        sanitymax or 100, sanitypenalty)
end

function MyFriendPanel:Refresh()
    local friend = self.friend
    if friend == nil or not friend:IsValid() then self:HideFriend(); return end
    local score = 20
    if friend.components ~= nil and friend.components.my_friend_affinity ~= nil then
        score = friend.components.my_friend_affinity:Get(self.owner)
    elseif self.owner._my_friend_affinity_net ~= nil then
        score = self.owner._my_friend_affinity_net:value()
    end
    self.affinity:SetString(string.format(TextForLanguage("好感度 %.1f", "Affinity %.1f"), score))
    if friend._my_friend_panel_net ~= nil then
        self.free_switch = ParseFreeSwitch(friend._my_friend_panel_net:value())
    end
    local function Dim(button, usable)
        button.label:SetColour(usable and 1 or .5, usable and .78 or .45,
            usable and .28 or .2, 1)
    end
    Dim(self.switch, self:CanSwitchCharacter())
    Dim(self.skin, score >= 50)
    Dim(self.rename, score >= 100)
    local hp, hpmax, hunger, hungermax, sanity, sanitymax
    local moisture, moisturemax = 0, 100
    if friend.components ~= nil and friend.components.health ~= nil then
        local h, hu, sa = friend.components.health, friend.components.hunger, friend.components.sanity
        hp, hpmax = h.currenthealth, h.maxhealth
        hunger, hungermax = hu.current, hu.max
        sanity, sanitymax = sa.current, sa.max
    elseif friend._my_friend_panel_net ~= nil then
        hp, hpmax, hunger, hungermax, sanity, sanitymax = ParseData(friend._my_friend_panel_net:value())
    else
        return
    end
    if friend.components ~= nil and friend.components.moisture ~= nil then
        moisture = friend.components.moisture:GetMoisture()
        moisturemax = friend.components.moisture:GetMaxMoisture()
    elseif friend._my_friend_panel_net ~= nil then
        local raw = friend._my_friend_panel_net:value()
        local wet = raw:match("^[^|]*|[^|]*|[^|]*|(.*)$")
        moisture, moisturemax = ParsePair(wet)
    end
    self.title:SetTruncatedString(require("my_friend_strings").CompanionName(friend), 140, 48, true)
    self.stats:SetString(string.format(TextForLanguage("生命 %d/%d    饥饿 %d/%d    理智 %d/%d    雨水 %d/%d",
        "Health %d/%d    Hunger %d/%d    Sanity %d/%d    Wetness %d/%d"),
        math.floor((hp or 0) + .5), math.floor((hpmax or 0) + .5),
        math.floor((hunger or 0) + .5), math.floor((hungermax or 0) + .5),
        math.floor((sanity or 0) + .5), math.floor((sanitymax or 0) + .5),
        math.floor((moisture or 0) + .5), math.floor((moisturemax or 0) + .5)))

    self:RefreshStatusBadges(hp, hpmax, hunger, hungermax, sanity, sanitymax)
    if self.moisturebadge ~= nil then
        self.moisturebadge:SetValue(moisture, math.max(1, moisturemax), RATE_SCALE.NEUTRAL)
        if moisture > 0 then self.moisturebadge:Show() else self.moisturebadge:Hide() end
    end
    local inventory = friend.replica ~= nil and friend.replica.inventory or nil
    if inventory ~= nil then
        local equip_layout = EquipSlots.Panel(self.owner)
        local changed = #equip_layout ~= #self.equips
        for i, slot in ipairs(equip_layout) do
            local shown = self.equips[i]
            if shown == nil or shown.name ~= slot.name or shown.atlas ~= slot.atlas
                or shown.image ~= slot.image then changed = true break end
        end
        local overflow = EquipSlots.BackpackContainer(inventory)
        local count = overflow ~= nil and overflow:GetNumSlots() or 0
        if changed or overflow ~= self.shown_overflow or count ~= self.shown_overflow_slots
            or self.slots[1].widget == nil then
            self:RebuildSlots()
        end
        for _, slot in ipairs(self.slots) do
            if slot.widget ~= nil then
                local item = inventory:GetItemInSlot(slot.widget.num)
                if item == nil then
                    slot.widget:SetTile(nil)
                elseif slot.widget.tile == nil or slot.widget.tile.item ~= item then
                    slot.widget:SetTile(ItemTile(item))
                else
                    slot.widget.tile:Refresh()
                end
            end
        end
        for _, slot in ipairs(self.equips) do
            if slot.widget ~= nil then
                local item = inventory:GetEquippedItem(slot.name)
                if item == nil then slot.widget:SetTile(nil)
                elseif slot.widget.tile == nil or slot.widget.tile.item ~= item then
                    slot.widget:SetTile(ItemTile(item))
                else slot.widget.tile:Refresh() end
            end
        end
        local overflow = EquipSlots.BackpackContainer(inventory)
        for _, slot in ipairs(self.backpackslots or {}) do
            -- The NPC keeps the backpack open itself, so the local player has
            -- no vanilla container opener. Read the published classified data.
            local item = EquipSlots.ContainerItem(overflow, slot.num)
            if item == nil then
                slot.widget:SetTile(nil)
            elseif slot.widget.tile == nil or slot.widget.tile.item ~= item then
                slot.widget:SetTile(ItemTile(item))
            else
                slot.widget.tile:Refresh()
            end
        end
    end
end

function MyFriendPanel:OnUpdate(dt)
    if not self.shown then return end
    self.refresh_timer = self.refresh_timer + dt
    if self.refresh_timer >= .1 then
        self.refresh_timer = 0
        self:Refresh()
    end
end

return MyFriendPanel
