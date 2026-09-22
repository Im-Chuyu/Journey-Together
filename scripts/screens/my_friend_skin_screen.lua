local Widget = require "widgets/widget"
local Screen = require "widgets/screen"
local Menu = require "widgets/menu"
local Image = require "widgets/image"
local LoadoutSelect = require "widgets/redux/loadoutselect"

local FriendSkinScreen = Class(Screen, function(self, friend, owner)
    Screen._ctor(self, "MyFriendSkinScreen")
    self.friend = friend
    self.owner = owner
    self.proot = self:AddChild(Widget("ROOT"))
    self.proot:SetHAnchor(ANCHOR_MIDDLE)
    self.proot:SetVAnchor(ANCHOR_MIDDLE)
    self.proot:SetScaleMode(SCALEMODE_PROPORTIONAL)

    self.background = self.proot:AddChild(Image(
        "images/bg_redux_wardrobe_bg.xml", "wardrobe_bg.tex"))
    self.background:SetScale(.8)
    self.background:SetPosition(-200, 0)
    self.background:SetTint(1, 1, 1, .96)

    -- The wardrobe always follows whichever character the companion is now.
    local character = friend ~= nil and friend.prefab
        or require("my_friend_characters").DEFAULT
    local initial = { base = character .. "_none", body = "", hand = "", legs = "", feet = "" }
    local raw = friend._my_friend_skin_net ~= nil and friend._my_friend_skin_net:value() or ""
    local base, body, hand, legs, feet = raw:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
    if base ~= nil and base ~= "" then initial.base = base end
    initial.body, initial.hand = body or "", hand or ""
    initial.legs, initial.feet = legs or "", feet or ""

    self.loadout = self.proot:AddChild(LoadoutSelect(
        Profile, character, nil, true, nil, true, initial
    ))
    self.character = character
    self.loadout:SetPosition(-306, 0)
    self.loadout:SetDefaultMenuOption()

    self.menu = self.proot:AddChild(Menu({
        { text = STRINGS.UI.WARDROBE_POPUP.CANCEL, cb = function() self:Cancel() end },
        { text = STRINGS.UI.WARDROBE_POPUP.SET, cb = function() self:Apply() end },
    }, 70, false, "carny_long", nil, 30))
    self.menu:SetPosition(493, -260, 0)
    self.default_focus = self.loadout
    self.menu:SetFocusChangeDir(MOVE_LEFT, self.loadout)
    self.loadout:SetFocusChangeDir(MOVE_RIGHT, self.menu)
    SetAutopaused(true)
end)

function FriendSkinScreen:OnControl(control, down)
    if FriendSkinScreen._base.OnControl(self, control, down) then
        return true
    end

    if control == CONTROL_CANCEL and not down then
        self:Cancel()
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
        return true
    elseif control == CONTROL_MENU_START and not down then
        self:Apply()
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
        return true
    end
end

function FriendSkinScreen:Cancel()
    TheFrontEnd:PopScreen(self)
end

function FriendSkinScreen:Apply()
    local skins = self.loadout.selected_skins
    if self.friend ~= nil and self.friend:IsValid() and self.friend.prefab == self.character then
        -- Refresh immediately before applying: another report may have replaced
        -- the server's list while this screen was open.
        require("my_friend_skins").Report(self.character)
        SendModRPCToServer(GetModRPC("MyFriends", "SetSkins"),
            self.friend, skins.base or (self.character .. "_none"),
            skins.body or "", skins.hand or "", skins.legs or "", skins.feet or "")
    end
    TheFrontEnd:PopScreen(self)
end

function FriendSkinScreen:OnUpdate(dt)
    self.loadout:OnUpdate(dt)
end

function FriendSkinScreen:OnDestroy()
    SetAutopaused(false)
    self._base.OnDestroy(self)
end

return FriendSkinScreen
